#!/usr/bin/env python3
"""
Camp Comics — intake + translation web UI.

A small Flask app that replaces manual folder/JSON editing for Stages 1–2.

What it owns:
  - Day 1 intake form (photo upload + universal raw tokens + class top-3)
  - Day 1 photo QA gate (single Gemini test gen, accept/retake inline)
  - Day 1 evening class finalization (assign class + collect class-specific token)
  - Mid-week translation (raw camper input → fantasy prompt fragments)
  - Dashboard with status per camper

What it does NOT own (for now):
  - Generation (still `python scripts/generate.py --camper X --class Y` in terminal)
  - Render (still `python scripts/render.py --all`)

Run:
    pip install -r requirements.txt
    export GCP_PROJECT=your-project-id
    gcloud auth application-default login
    python scripts/intake_server.py

Then open http://localhost:5001
(Override with PORT=5002 python scripts/intake_server.py if 5001 is also taken.
 Default 5000 is avoided because macOS AirPlay Receiver hogs it.)
"""

import json
import os
import re
import sys
from pathlib import Path

# Make sibling modules (generate.py, render.py) importable regardless of how
# this server is launched (`python scripts/intake_server.py` or import-as-module).
_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

import yaml
from flask import (
    Flask, abort, jsonify, redirect, render_template, request,
    send_from_directory, url_for,
)
from google import genai
from google.genai import types
from PIL import Image

from generate import (  # noqa: E402
    assemble_panel_prompt, assemble_cover_prompt, call_gemini,
    build_manifest_dict, with_backoff,
)

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------

LEGACY_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = LEGACY_ROOT.parent
INTAKE_DIR = LEGACY_ROOT / "intake"
OUTPUTS_DIR = LEGACY_ROOT / "outputs"
# templates/ stays at the actual repo root, shared with the new iOS app.
TEMPLATES_DIR = REPO_ROOT / "templates"

PROJECT_ID = os.environ.get("GCP_PROJECT", "your-gcp-project-id")
MODEL = "gemini-2.5-flash-image"
TEXT_MODEL = "gemini-2.5-flash"  # for suggest_translations (cheap, fast)

# Region rotation: gemini-2.5-flash-image's per-minute quota is non-adjustable
# AND per-region. Cycling across N regions multiplies the effective rate
# limit by N. Set GCP_LOCATIONS as a comma-separated list, e.g.:
#   export GCP_LOCATIONS=us-central1,us-east4,us-west1,europe-west4
# (Falls back to GCP_LOCATION for single-region setups.)
LOCATIONS = [
    r.strip() for r in os.environ.get(
        "GCP_LOCATIONS",
        os.environ.get("GCP_LOCATION", "us-central1"),
    ).split(",")
    if r.strip()
]

CLASSES = ["druid", "warrior", "wizard", "bard", "healer", "trickster"]

# 12 narrative panels + cover, in the order the generation UI walks through them.
PANEL_ORDER = [f"{n:02d}" for n in range(1, 13)] + ["cover"]

CLASS_SPECIFIC_TOKEN_PROMPTS = {
    "druid":     ("animal_companion", "An animal companion that fits you (wolf, hawk, otter, fox, ...)"),
    "warrior":   ("someone_to_protect", "Someone or something you'd stand up to protect"),
    "wizard":    ("question_to_answer", "A real question you'd want answered"),
    "bard":      ("art_form", "An art form you love (instrument, writing, drawing, dance, ...)"),
    "healer":    ("mentor_figure", "Someone in your life you look up to"),
    "trickster": ("world_problem", "A problem you think the world has"),
}

INTAKE_DIR.mkdir(parents=True, exist_ok=True)
OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)

app = Flask(
    __name__,
    template_folder=str(LEGACY_ROOT / "intake_ui" / "templates"),
    static_folder=str(LEGACY_ROOT / "intake_ui" / "static"),
)
app.config["MAX_CONTENT_LENGTH"] = 25 * 1024 * 1024  # 25 MB upload cap


# -----------------------------------------------------------------------------
# Camper record helpers
# -----------------------------------------------------------------------------

_ID_RE = re.compile(r"^camper_(\d{3,})$")


def next_camper_id() -> str:
    max_n = 0
    for p in INTAKE_DIR.iterdir():
        if p.is_dir() and (m := _ID_RE.match(p.name)):
            max_n = max(max_n, int(m.group(1)))
    return f"camper_{max_n + 1:03d}"


def load_tokens(camper_id: str) -> dict:
    path = INTAKE_DIR / camper_id / "tokens.json"
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def save_tokens(camper_id: str, tokens: dict) -> None:
    path = INTAKE_DIR / camper_id / "tokens.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(tokens, indent=2))


def list_campers() -> list[dict]:
    rows = []
    for p in sorted(INTAKE_DIR.iterdir()):
        if not p.is_dir() or not _ID_RE.match(p.name):
            continue
        cid = p.name
        t = load_tokens(cid)
        rows.append({
            "id": cid,
            "name": t.get("camper_name", "—"),
            "character_name": t.get("character_name", ""),
            "cabin": t.get("cabin", ""),
            "class": t.get("class") or "(not assigned)",
            "class_top_3": t.get("class_top_3", []),
            "qa_passed": (p / "qa_passed").exists(),
            "finalized": bool(t.get("class")),
            "translated": all(
                k in t for k in ("hometown_landmark", "fear_image", "quality_symbol")
            ),
            "generated": (OUTPUTS_DIR / cid / "manifest.json").exists(),
            "rendered": (OUTPUTS_DIR / cid / "comic.pdf").exists(),
        })
    return rows


# -----------------------------------------------------------------------------
# Gemini client + QA gate
# -----------------------------------------------------------------------------

_clients: dict[str, genai.Client] = {}
_location_idx = 0


def gemini() -> genai.Client:
    """Return a Vertex AI client, round-robin across configured regions.

    Each call advances the index so consecutive API calls land on different
    region buckets. When with_backoff() retries on a 429, the retry naturally
    hits the next region — automatic regional fail-over for free.
    """
    global _location_idx
    location = LOCATIONS[_location_idx % len(LOCATIONS)]
    _location_idx += 1
    if location not in _clients:
        _clients[location] = genai.Client(
            vertexai=True, project=PROJECT_ID, location=location,
        )
    return _clients[location]


def run_qa_gate(photo_path: Path, class_name: str) -> bytes:
    """Single test generation to verify the camper's likeness transfers cleanly."""
    prompt = (
        f"This person as a generic {class_name} hero in painted Dungeons & "
        f"Dragons 5th Edition sourcebook style, full body, cinematic lighting. "
        f"The character's face must match the reference photo exactly. "
        f"No text or letters in the image."
    )
    parts = [
        types.Part.from_bytes(data=photo_path.read_bytes(), mime_type="image/jpeg"),
        prompt,
    ]
    response = with_backoff(lambda: gemini().models.generate_content(model=MODEL, contents=parts))
    for part in response.candidates[0].content.parts:
        if getattr(part, "inline_data", None):
            return part.inline_data.data
    raise RuntimeError("QA test generation returned no image")


def suggest_translations(tokens: dict, only_field: str | None = None) -> dict:
    """Ask Gemini for 3 candidate fantasy fragments per raw token, flavored by class."""
    cls = tokens["class"]
    class_data = yaml.safe_load((TEMPLATES_DIR / f"{cls}.yaml").read_text())
    palette = class_data["palette"]

    field_specs = {
        "hometown_landmark": {
            "raw": tokens.get("hometown_landmark_raw", ""),
            "use": "the panel where an otherworldly magical thing intrudes in this place. The fragment is a visual scene fragment showing this familiar place transformed into a fantasy setting.",
        },
        "fear_image": {
            "raw": tokens.get("fear_raw", ""),
            "use": "the obstacle panel. The fear must become a visual, physical, drawable obstacle the hero can face. Abstract fears (e.g. 'political polarization', 'imposter syndrome') must be made concrete (e.g. a cracked bridge over a chasm with two crowds on opposite sides shouting through fog).",
        },
        "quality_symbol": {
            "raw": tokens.get("quality_raw", ""),
            "use": "the ceremonial reward panel. The fragment depicts this quality as a small symbolic object being handed to the hero.",
        },
    }
    if only_field:
        field_specs = {only_field: field_specs[only_field]}

    fields_yaml = "\n".join(
        f'  - field "{name}"\n    raw: "{spec["raw"]}"\n    used in: {spec["use"]}'
        for name, spec in field_specs.items()
    )

    prompt = f"""You are a worldbuilding assistant for a personalized D&D-themed comic project.

A camper has picked the {class_data['display_name']} class. Their painted-fantasy panels use:
  Lighting: {palette['lighting']}
  Colors:   {palette['colors']}

For each of the camper's raw inputs below, generate THREE alternative short fantasy fragments. Each fragment MUST be:
  - A single visual scene fragment (not a sentence)
  - 8 to 18 words
  - Concrete and drawable — no abstractions
  - Stylistically matched to the {class_data['display_name']} aesthetic above
  - Will be inserted directly into an image-generation prompt

Inputs:
{fields_yaml}

Output ONLY this JSON (no markdown fences, no commentary):
{json.dumps({k: ["...", "...", "..."] for k in field_specs}, indent=2)}
"""

    response = with_backoff(lambda: gemini().models.generate_content(
        model=TEXT_MODEL,
        contents=prompt,
        config=types.GenerateContentConfig(response_mime_type="application/json"),
    ))
    return json.loads(response.text)


# -----------------------------------------------------------------------------
# Routes
# -----------------------------------------------------------------------------

@app.route("/")
def dashboard():
    return render_template(
        "dashboard.html",
        campers=list_campers(),
        classes=CLASSES,
    )


@app.route("/intake/new", methods=["GET"])
def intake_new():
    return render_template("intake_new.html", classes=CLASSES)


@app.route("/intake", methods=["POST"])
def intake_create():
    photo = request.files.get("photo")
    if not photo or not photo.filename:
        return "Photo is required", 400

    cid = next_camper_id()
    cdir = INTAKE_DIR / cid
    cdir.mkdir(parents=True, exist_ok=True)

    # Normalize photo to JPEG; downstream tools assume photo.jpg.
    img = Image.open(photo.stream).convert("RGB")
    img.save(cdir / "photo.jpg", "JPEG", quality=92)

    tokens = {
        "camper_name": request.form["camper_name"].strip(),
        "character_name": request.form.get("character_name", "").strip(),
        "cabin": request.form["cabin"].strip(),
        "class_top_3": [
            request.form.get(f"class_choice_{i}", "") for i in (1, 2, 3)
        ],
        "hometown_landmark_raw": request.form["hometown_landmark_raw"].strip(),
        "fear_raw": request.form["fear_raw"].strip(),
        "quality_raw": request.form["quality_raw"].strip(),
    }
    save_tokens(cid, tokens)

    return redirect(url_for("qa", camper_id=cid))


@app.route("/camper/<camper_id>/photo.jpg")
def camper_photo(camper_id: str):
    cdir = INTAKE_DIR / camper_id
    if not cdir.exists():
        abort(404)
    return send_from_directory(cdir, "photo.jpg")


@app.route("/camper/<camper_id>/qa", methods=["GET", "POST"])
def qa(camper_id: str):
    cdir = INTAKE_DIR / camper_id
    if not cdir.exists():
        abort(404)
    photo_path = cdir / "photo.jpg"
    qa_image_path = cdir / "qa_test.png"

    if request.method == "POST":
        action = request.form.get("action")
        if action == "accept":
            (cdir / "qa_passed").touch()
            return redirect(url_for("dashboard"))
        if action == "regen":
            qa_image_path.unlink(missing_ok=True)
            return redirect(url_for("qa", camper_id=camper_id))
        if action == "retake":
            # Send back to intake form for photo re-upload only.
            return redirect(url_for("retake_photo", camper_id=camper_id))

    # Run QA gate if no test image yet.
    if not qa_image_path.exists():
        tokens = load_tokens(camper_id)
        # Use the top-ranked class choice for the test render.
        test_class = (tokens.get("class_top_3") or ["druid"])[0] or "druid"
        try:
            img_bytes = run_qa_gate(photo_path, test_class)
            qa_image_path.write_bytes(img_bytes)
        except Exception as exc:
            return render_template("qa.html", camper_id=camper_id, error=str(exc)), 502

    return render_template("qa.html", camper_id=camper_id, error=None)


@app.route("/camper/<camper_id>/qa_test.png")
def qa_image(camper_id: str):
    return send_from_directory(INTAKE_DIR / camper_id, "qa_test.png")


@app.route("/camper/<camper_id>/retake-photo", methods=["GET", "POST"])
def retake_photo(camper_id: str):
    cdir = INTAKE_DIR / camper_id
    if not cdir.exists():
        abort(404)

    if request.method == "POST":
        photo = request.files.get("photo")
        if not photo or not photo.filename:
            return "Photo is required", 400
        img = Image.open(photo.stream).convert("RGB")
        img.save(cdir / "photo.jpg", "JPEG", quality=92)
        # Invalidate prior QA result.
        (cdir / "qa_test.png").unlink(missing_ok=True)
        (cdir / "qa_passed").unlink(missing_ok=True)
        return redirect(url_for("qa", camper_id=camper_id))

    return render_template("retake_photo.html", camper_id=camper_id)


@app.route("/camper/<camper_id>/finalize", methods=["GET", "POST"])
def finalize(camper_id: str):
    tokens = load_tokens(camper_id)
    if not tokens:
        abort(404)

    if request.method == "POST":
        cls = request.form["class"]
        if cls not in CLASSES:
            return f"Invalid class: {cls}", 400
        token_key, _ = CLASS_SPECIFIC_TOKEN_PROMPTS[cls]
        tokens["class"] = cls
        tokens[token_key] = request.form["class_token"].strip()
        save_tokens(camper_id, tokens)
        return redirect(url_for("dashboard"))

    # Default the class dropdown to their #1 rank.
    default_class = (tokens.get("class_top_3") or [CLASSES[0]])[0] or CLASSES[0]
    return render_template(
        "finalize.html",
        camper_id=camper_id,
        tokens=tokens,
        classes=CLASSES,
        class_prompts=CLASS_SPECIFIC_TOKEN_PROMPTS,
        default_class=default_class,
    )


# -----------------------------------------------------------------------------
# Stage 2 / 3 helpers — drive the web UI's per-panel generate + render
# -----------------------------------------------------------------------------

def _final_filename(panel: str) -> str:
    return "cover.png" if panel == "cover" else f"panel_{panel}.png"


def _pending_filename(panel: str) -> str:
    return f"_pending_{panel}.png"


def _skipped_marker(panel: str) -> str:
    return f"_skipped_{panel}"


def current_panel(out_dir: Path) -> str | None:
    """Lowest panel slot that hasn't been accepted or skipped. None if all done."""
    for p in PANEL_ORDER:
        if (out_dir / _final_filename(p)).exists():
            continue
        if (out_dir / _skipped_marker(p)).exists():
            continue
        return p
    return None


def load_attempts(out_dir: Path) -> dict:
    f = out_dir / "_attempts.json"
    return json.loads(f.read_text()) if f.exists() else {}


def save_attempts(out_dir: Path, state: dict) -> None:
    (out_dir / "_attempts.json").write_text(json.dumps(state, indent=2))


def panel_caption(class_data: dict, panel: str) -> str:
    if panel == "cover":
        return "Cover image"
    return next(p["caption"] for p in class_data["panels"] if f"{p['n']:02d}" == panel)


def generate_one_panel(camper_id: str, panel: str,
                       custom_prompt: str | None = None) -> None:
    """One Gemini call. Saves to the pending file; bumps the attempts counter.

    References passed to the model (order matters; see STYLE_SUFFIX in generate.py):
      [0] camper photo       — canonical identity
      [1] class hero card    — costume + painted style anchor (faceless)
      [2] most-recent panel  — continuity for face + clothes (only if ≥1 panel approved)
    """
    tokens = load_tokens(camper_id)
    cls = tokens["class"]
    class_data = yaml.safe_load((TEMPLATES_DIR / f"{cls}.yaml").read_text())
    out_dir = OUTPUTS_DIR / camper_id
    out_dir.mkdir(exist_ok=True)

    photo = INTAKE_DIR / camper_id / "photo.jpg"
    hero = TEMPLATES_DIR / "refs" / f"{cls}_hero.png"
    for p in (photo, hero):
        if not p.exists():
            raise RuntimeError(f"Missing required file: {p}")

    # Look up panel dict (if any) so we can honor per-panel reference overrides.
    panel_dict = None
    if panel != "cover":
        panel_dict = next(
            (p for p in class_data["panels"] if f"{p['n']:02d}" == panel), None,
        )

    references = [photo, hero]
    # Continuity anchor (3rd reference). Default: most-recent approved panel.
    # Per-panel YAML override via `reference_panel` — used by panel 12 which
    # mirrors panel 1 (everyday clothes) and would be corrupted by chaining
    # off panel 11's druid regalia.
    continuity_panel = None
    if panel_dict and panel_dict.get("reference_panel"):
        ref = out_dir / f"panel_{panel_dict['reference_panel']}.png"
        if ref.exists():
            continuity_panel = ref
    if continuity_panel is None:
        approved = sorted(out_dir.glob("panel_*.png"))
        if approved:
            continuity_panel = approved[-1]
    if continuity_panel:
        references.append(continuity_panel)

    if custom_prompt:
        prompt = custom_prompt
    elif panel == "cover":
        prompt = assemble_cover_prompt(class_data, tokens)
    else:
        prompt = assemble_panel_prompt(panel_dict, class_data, tokens)

    image_bytes = call_gemini(gemini(), prompt, references)
    if not image_bytes:
        raise RuntimeError("Gemini returned no image")

    (out_dir / _pending_filename(panel)).write_bytes(image_bytes)

    state = load_attempts(out_dir)
    rec = state.get(panel, {"count": 0, "prompt": ""})
    rec["count"] += 1
    rec["prompt"] = prompt
    state[panel] = rec
    save_attempts(out_dir, state)


def accept_pending(out_dir: Path, panel: str) -> None:
    pending = out_dir / _pending_filename(panel)
    if not pending.exists():
        raise RuntimeError("no pending image to accept")
    pending.replace(out_dir / _final_filename(panel))
    _clear_panel_state(out_dir, panel)


def mark_skipped(out_dir: Path, panel: str) -> None:
    (out_dir / _skipped_marker(panel)).touch()
    (out_dir / _pending_filename(panel)).unlink(missing_ok=True)
    _clear_panel_state(out_dir, panel)


def clear_panel(out_dir: Path, panel: str) -> None:
    """Redo: remove approved/skipped/pending for this panel so it's 'current' again."""
    (out_dir / _final_filename(panel)).unlink(missing_ok=True)
    (out_dir / _skipped_marker(panel)).unlink(missing_ok=True)
    (out_dir / _pending_filename(panel)).unlink(missing_ok=True)
    _clear_panel_state(out_dir, panel)


def _clear_panel_state(out_dir: Path, panel: str) -> None:
    state = load_attempts(out_dir)
    state.pop(panel, None)
    save_attempts(out_dir, state)


def build_and_render(camper_id: str) -> Path:
    """Write manifest.json and render comic.pdf via WeasyPrint."""
    tokens = load_tokens(camper_id)
    cls = tokens["class"]
    class_data = yaml.safe_load((TEMPLATES_DIR / f"{cls}.yaml").read_text())
    out_dir = OUTPUTS_DIR / camper_id

    results = []
    for panel_dict in class_data["panels"]:
        n = f"{panel_dict['n']:02d}"
        if (out_dir / _final_filename(n)).exists():
            status = "ok"
        elif (out_dir / _skipped_marker(n)).exists():
            status = "skipped"
        else:
            status = "missing"
        results.append({"panel": panel_dict["n"], "status": status,
                        "caption": panel_dict["caption"]})

    cover_status = (
        "ok" if (out_dir / "cover.png").exists()
        else "skipped" if (out_dir / _skipped_marker("cover")).exists()
        else "missing"
    )
    results.append({"panel": "cover", "status": cover_status})

    manifest = build_manifest_dict(camper_id, cls, class_data, tokens, results)
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))

    # Lazy import — WeasyPrint pulls native libs and isn't needed for intake stages.
    from render import render_camper
    return render_camper(camper_id)


def panel_summary(out_dir: Path) -> list[dict]:
    """Snapshot every panel's state for the dashboard / generate page."""
    rows = []
    for p in PANEL_ORDER:
        final = out_dir / _final_filename(p)
        if final.exists():
            rows.append({"id": p, "status": "ok", "filename": _final_filename(p)})
        elif (out_dir / _skipped_marker(p)).exists():
            rows.append({"id": p, "status": "skipped", "filename": None})
        else:
            rows.append({"id": p, "status": "pending", "filename": None})
    return rows


# -----------------------------------------------------------------------------

@app.route("/camper/<camper_id>/suggest", methods=["POST"])
def suggest(camper_id: str):
    tokens = load_tokens(camper_id)
    if not tokens or not tokens.get("class"):
        return jsonify(error="camper has no class assigned"), 400
    only_field = request.form.get("field") or None
    try:
        return jsonify(suggest_translations(tokens, only_field=only_field))
    except Exception as exc:
        return jsonify(error=str(exc)), 502


@app.route("/camper/<camper_id>/translate", methods=["GET", "POST"])
def translate(camper_id: str):
    tokens = load_tokens(camper_id)
    if not tokens:
        abort(404)
    if not tokens.get("class"):
        # Translation depends on a finalized class for context.
        return redirect(url_for("finalize", camper_id=camper_id))

    if request.method == "POST":
        for k in ("hometown_landmark", "fear_image", "quality_symbol"):
            tokens[k] = request.form[k].strip()
        save_tokens(camper_id, tokens)
        return redirect(url_for("dashboard"))

    return render_template("translate.html", camper_id=camper_id, tokens=tokens)


# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Stage 2 — per-panel generation in the browser
# -----------------------------------------------------------------------------

@app.route("/camper/<camper_id>/generate", methods=["GET"])
def generate_page(camper_id: str):
    tokens = load_tokens(camper_id)
    if not tokens or not tokens.get("class"):
        return redirect(url_for("dashboard"))
    out_dir = OUTPUTS_DIR / camper_id
    out_dir.mkdir(exist_ok=True)

    panel = current_panel(out_dir)
    summary = panel_summary(out_dir)
    done_count = sum(1 for r in summary if r["status"] in ("ok", "skipped"))

    if panel is None:
        return render_template("generate.html", camper_id=camper_id, tokens=tokens,
                               all_done=True, summary=summary, done_count=done_count)

    pending = out_dir / _pending_filename(panel)
    error = None
    if not pending.exists():
        try:
            generate_one_panel(camper_id, panel)
        except Exception as exc:
            error = str(exc)

    class_data = yaml.safe_load((TEMPLATES_DIR / f"{tokens['class']}.yaml").read_text())
    state = load_attempts(out_dir).get(panel, {"count": 0, "prompt": ""})

    return render_template(
        "generate.html",
        camper_id=camper_id, tokens=tokens, all_done=False,
        panel=panel, caption=panel_caption(class_data, panel),
        attempts=state["count"], current_prompt=state["prompt"] or "",
        error=error, pending_url=url_for("output_file", camper_id=camper_id,
                                         filename=_pending_filename(panel)),
        summary=summary, done_count=done_count,
    )


@app.route("/camper/<camper_id>/generate/reroll", methods=["POST"])
def do_reroll(camper_id: str):
    panel = current_panel(OUTPUTS_DIR / camper_id)
    if panel is None:
        return redirect(url_for("generate_page", camper_id=camper_id))
    custom = request.form.get("custom_prompt", "").strip() or None
    # Drop the existing pending so /generate will re-trigger the API call.
    (OUTPUTS_DIR / camper_id / _pending_filename(panel)).unlink(missing_ok=True)
    try:
        generate_one_panel(camper_id, panel, custom_prompt=custom)
    except Exception as exc:
        return f"Generation failed: {exc}", 502
    return redirect(url_for("generate_page", camper_id=camper_id))


@app.route("/camper/<camper_id>/generate/accept", methods=["POST"])
def do_accept(camper_id: str):
    panel = current_panel(OUTPUTS_DIR / camper_id)
    if panel is None:
        return redirect(url_for("generate_page", camper_id=camper_id))
    accept_pending(OUTPUTS_DIR / camper_id, panel)
    return redirect(url_for("generate_page", camper_id=camper_id))


@app.route("/camper/<camper_id>/generate/skip", methods=["POST"])
def do_skip(camper_id: str):
    panel = current_panel(OUTPUTS_DIR / camper_id)
    if panel is None:
        return redirect(url_for("generate_page", camper_id=camper_id))
    mark_skipped(OUTPUTS_DIR / camper_id, panel)
    return redirect(url_for("generate_page", camper_id=camper_id))


@app.route("/camper/<camper_id>/generate/redo/<panel>", methods=["POST"])
def do_redo(camper_id: str, panel: str):
    if panel not in PANEL_ORDER:
        abort(404)
    clear_panel(OUTPUTS_DIR / camper_id, panel)
    return redirect(url_for("generate_page", camper_id=camper_id))


@app.route("/camper/<camper_id>/render", methods=["POST"])
def do_render(camper_id: str):
    try:
        build_and_render(camper_id)
    except Exception as exc:
        return f"Render failed: {exc}<br>Likely cause: WeasyPrint isn't installed yet (pip install -r requirements-render.txt; brew install pango).", 502
    return redirect(url_for("comic_pdf", camper_id=camper_id))


@app.route("/camper/<camper_id>/comic.pdf")
def comic_pdf(camper_id: str):
    return send_from_directory(OUTPUTS_DIR / camper_id, "comic.pdf")


@app.route("/camper/<camper_id>/output/<path:filename>")
def output_file(camper_id: str, filename: str):
    return send_from_directory(OUTPUTS_DIR / camper_id, filename)


# -----------------------------------------------------------------------------

if __name__ == "__main__":
    # Production note: this is the Flask dev server. Fine for camp-week use on a
    # trusted local network; do not expose to the internet.
    port = int(os.environ.get("PORT", "5001"))
    app.run(host="0.0.0.0", port=port, debug=False)
