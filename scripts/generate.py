#!/usr/bin/env python3
"""
Camp Comics — Stage 2 generation script.

Generates the 12 narrative panels + 1 cover image for a single camper, using
Gemini 2.5 Flash Image (Nano Banana) on Vertex AI.

Usage:
    python scripts/generate.py --camper camper_042 --class druid

Prerequisites:
    - GCP project set up with Vertex AI enabled
    - `gcloud auth application-default login` completed
    - Env vars GCP_PROJECT, GCP_LOCATION set (or edit constants below)
    - `pip install google-genai pyyaml pillow`

Reads:
    intake/{camper_id}/photo.jpg
    intake/{camper_id}/tokens.json   (must contain *_translated fields you
                                      filled in mid-week from raw camper input)
    templates/{class}.yaml
    templates/refs/{class}_hero.png

Writes:
    outputs/{camper_id}/panel_{NN}.png    (12 panels)
    outputs/{camper_id}/cover.png         (1 cover)
    outputs/{camper_id}/manifest.json     (consumed by Stage 3 layout)
"""

import argparse
import json
import os
import random
import subprocess
import sys
import time
from pathlib import Path

import yaml
from google import genai
from google.genai import types

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

PROJECT_ID = os.environ.get("GCP_PROJECT", "your-gcp-project-id")
MODEL = "gemini-2.5-flash-image"
MAX_ATTEMPTS = 4

# Per-region quotas are non-adjustable for image-input models. Rotating across
# regions multiplies the effective rate limit. Set as comma-separated list:
#   export GCP_LOCATIONS=us-central1,us-east4,us-west1,europe-west4
LOCATIONS = [
    r.strip() for r in os.environ.get(
        "GCP_LOCATIONS", os.environ.get("GCP_LOCATION", "us-central1"),
    ).split(",")
    if r.strip()
]

# Reference protocol:
#   1st image — camper photo (canonical identity, must match exactly)
#   2nd image — class hero card (costume + painted style, faceless by design)
#   3rd image — most-recent approved panel (continuity for face + clothes)
# Face-fidelity language stays at the END of the prompt (recency matters).
STYLE_SUFFIX = (
    "painted digital fantasy illustration, in the style of a Dungeons & "
    "Dragons 5th Edition sourcebook, cinematic lighting, painterly "
    "brushwork, high detail on face. No text or letters anywhere in the image. "
    "ENSURE FACE MATCHES THE ORIGINAL SOURCE PHOTO — the first reference image "
    "is the canonical identity. Preserve facial structure, eye color and shape, "
    "nose, jawline, mouth, skin tone, hair color and hairstyle exactly. The "
    "camper must be instantly recognizable as the same specific person across "
    "every panel. "
    "ENSURE CLOTHES MATCH THE PREVIOUS PICTURE — the costume, armor, props, "
    "and accessories must be identical to those shown in the second reference "
    "(costume/style anchor) and the third reference if present (the most "
    "recent approved panel). Do not invent new clothing details, swap colors, "
    "or restyle existing gear between panels."
)

# Per-panel aspect ratios are role-driven (panel beat), not class-driven —
# all 6 classes share this mapping. The CSS layout in layout/comic.css uses
# matching grid cell shapes so the model's composition fits the printed cell.
#
# Page 2 (Act I)  — small / tall / small / wide-splash:    P1 P2 P3 P4
# Page 3 (Act II) — wide-splash / small / tall / small:    P5 P6 P7 P8
# Page 4 (Act III) — wide-splash / small / small / wide:   P9 P10 P11 P12
PANEL_ASPECT_RATIOS = {
    "01": "1:1",    # intimate establishing (Tuesday afternoon)
    "02": "3:4",    # tall — mystical figure looming
    "03": "1:1",    # macro close-up — transformation detail
    "04": "16:9",   # wide cinematic hero splash
    "05": "16:9",   # wide bird's-eye world establishing
    "06": "1:1",    # intimate two-shot with mentor
    "07": "3:4",    # tall — towering obstacle
    "08": "1:1",    # action close — failed attempt
    "09": "16:9",   # wide cinematic emotional climax
    # P10 + P11 are combined into a single wide diagonal-pair container in
    # the layout — 16:9 (was 1:1) so each fills its trapezoid half without
    # horizontal stretching.
    "10": "16:9",   # triumph walking (diagonal pair left)
    "11": "16:9",   # tight ceremony close (diagonal pair right)
    "12": "16:9",   # wide return mirror
}
COVER_ASPECT = "3:4"

REPO_ROOT = Path(__file__).resolve().parent.parent

# -----------------------------------------------------------------------------
# Prompt assembly
# -----------------------------------------------------------------------------

def assemble_panel_prompt(panel: dict, class_data: dict, tokens: dict) -> str:
    """Fill a panel's scene template with tokens; assemble the full prompt.

    Per-panel YAML overrides (optional):
      costume_override: replaces the class-level costume for this panel only.
                        Used by panel 12 to switch back to everyday clothes.
      style_override:   appended after STYLE_SUFFIX so it wins on recency.
                        Used by panel 12 to override the "match previous
                        costume" instruction, which would otherwise leak
                        the druid regalia into the return-home scene.
    """
    scene = panel["scene"].format(**tokens)
    palette = class_data["palette"]
    n = f"{panel['n']:02d}"
    aspect = PANEL_ASPECT_RATIOS.get(n, "4:3")

    costume = panel.get("costume_override", class_data["costume"])
    style_block = STYLE_SUFFIX
    if panel.get("style_override"):
        style_block = f"{STYLE_SUFFIX} {panel['style_override']}"

    return (
        f"{scene}. {panel['composition']}. "
        f"Costume: {costume}. "
        f"Lighting and color: {palette['lighting']}, {palette['colors']}. "
        f"Style: {style_block} "
        f"Image aspect ratio: {aspect}."
    )


def assemble_cover_prompt(class_data: dict, tokens: dict) -> str:
    """Cover is a dedicated 13th call — portrait orientation, title headroom."""
    palette = class_data["palette"]
    pose = class_data["cover"]["pose_directive"]
    return (
        f"{pose}, depicting {tokens['camper_name']} as a "
        f"{class_data['display_name']}. "
        f"Costume: {class_data['costume']}. "
        f"Lighting and color: {palette['lighting']}, {palette['colors']}. "
        f"Style: {STYLE_SUFFIX} "
        f"Image aspect ratio: {COVER_ASPECT}."
    )


# -----------------------------------------------------------------------------
# Gemini call
# -----------------------------------------------------------------------------

def _mime(path: Path) -> str:
    return "image/jpeg" if path.suffix.lower() in (".jpg", ".jpeg") else "image/png"


# Backoff schedule: 2s, 4s, 8s, 16s, 32s (+jitter) — ~62s total of patient
# waiting before giving up. Vertex per-minute quotas refill within a minute,
# so the schedule covers two refill windows.
_BACKOFF_BASE = 2.0
_BACKOFF_MAX_RETRIES = 5


def _is_rate_limit_error(exc: Exception) -> bool:
    msg = str(exc)
    return "429" in msg or "RESOURCE_EXHAUSTED" in msg


def with_backoff(fn, *, on_retry=None):
    """Run fn() with exponential backoff on 429 / RESOURCE_EXHAUSTED errors.

    fn        — zero-arg callable that performs the API call.
    on_retry  — optional callback(attempt, delay, exc) called before each
                sleep, e.g. for terminal logging or UI status.
    """
    for attempt in range(_BACKOFF_MAX_RETRIES + 1):
        try:
            return fn()
        except Exception as exc:
            if not _is_rate_limit_error(exc) or attempt == _BACKOFF_MAX_RETRIES:
                raise
            delay = _BACKOFF_BASE * (2 ** attempt) + random.uniform(0, 1)
            if on_retry:
                on_retry(attempt + 1, delay, exc)
            else:
                print(f"  rate-limited (attempt {attempt + 1}/{_BACKOFF_MAX_RETRIES + 1}); "
                      f"waiting {delay:.1f}s before retry...", flush=True)
            time.sleep(delay)


def call_gemini(client, prompt: str, reference_images: list[Path]) -> bytes | None:
    """Single API call (with auto-retry on 429). Returns PNG bytes or None."""
    parts = [
        types.Part.from_bytes(data=p.read_bytes(), mime_type=_mime(p))
        for p in reference_images
    ]
    parts.append(prompt)

    response = with_backoff(lambda: client.models.generate_content(model=MODEL, contents=parts))

    for part in response.candidates[0].content.parts:
        if getattr(part, "inline_data", None):
            return part.inline_data.data
    return None


# -----------------------------------------------------------------------------
# Terminal review loop
# -----------------------------------------------------------------------------

def open_image(path: Path) -> None:
    """macOS quicklook. On Linux, swap for `xdg-open`."""
    subprocess.run(["open", str(path)], check=False)


def review_panel(image_bytes: bytes, label: str) -> str:
    """Show image, prompt for accept/re-roll/tweak/skip. Returns the choice."""
    tmp = Path(f"/tmp/camp_review_{label}.png")
    tmp.write_bytes(image_bytes)
    open_image(tmp)

    while True:
        choice = input(
            f"[{label}] (a)ccept / (r)e-roll / (t)weak prompt / (s)kip → "
        ).strip().lower()
        if choice in ("a", "r", "t", "s"):
            return choice
        print("  invalid input — pick a/r/t/s")


def generate_with_reroll(
    client,
    prompt: str,
    references: list[Path],
    label: str,
    out_path: Path,
) -> tuple[str, str]:
    """Run the 4-attempt re-roll loop per spec §11. Returns (status, final_prompt)."""
    current_prompt = prompt

    for attempt in range(1, MAX_ATTEMPTS + 1):
        print(f"  attempt {attempt}/{MAX_ATTEMPTS}…")

        try:
            image_bytes = call_gemini(client, current_prompt, references)
        except Exception as exc:
            print(f"  ! API error: {exc}")
            continue

        if not image_bytes:
            print("  ! no image returned")
            continue

        choice = review_panel(image_bytes, label)

        if choice == "a":
            out_path.write_bytes(image_bytes)
            return "ok", current_prompt
        if choice == "s":
            return "skipped", current_prompt
        if choice == "t" or attempt == MAX_ATTEMPTS - 1:
            # Manual prompt edit before the final attempt.
            print(f"\n  current prompt:\n  {current_prompt}\n")
            edited = input("  enter revised prompt (empty = keep current): ").strip()
            if edited:
                current_prompt = edited

    print(f"  ! {label}: failed after {MAX_ATTEMPTS} attempts — use fallback (spec §12 Mode 1)")
    return "failed", current_prompt


# -----------------------------------------------------------------------------
# Manifest construction — shared by CLI and the web app.
# -----------------------------------------------------------------------------

def build_manifest_dict(camper_id: str, class_name: str, class_data: dict,
                        tokens: dict, results: list[dict]) -> dict:
    return {
        "camper_id": camper_id,
        "class": class_name,
        "character_name": tokens.get("character_name") or tokens["camper_name"],
        "cabin": tokens.get("cabin"),
        "captions": [p["caption"] for p in class_data["panels"]],
        "results": results,
    }


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a camper's 13 comic images.")
    parser.add_argument("--camper", required=True, help="Camper ID (matches intake folder name)")
    parser.add_argument("--class", dest="class_name", required=True,
                        help="Class name (druid, wizard, warrior, bard, healer, trickster)")
    args = parser.parse_args()

    # Resolve paths
    intake_dir = REPO_ROOT / "intake" / args.camper
    out_dir = REPO_ROOT / "outputs" / args.camper
    template_path = REPO_ROOT / "templates" / f"{args.class_name}.yaml"
    hero_card_path = REPO_ROOT / "templates" / "refs" / f"{args.class_name}_hero.png"
    photo_path = intake_dir / "photo.jpg"
    tokens_path = intake_dir / "tokens.json"

    for p in (photo_path, tokens_path, template_path, hero_card_path):
        if not p.exists():
            sys.exit(f"Missing required file: {p}")

    out_dir.mkdir(parents=True, exist_ok=True)

    # Load
    class_data = yaml.safe_load(template_path.read_text())
    tokens = json.loads(tokens_path.read_text())

    # Verify human-translation step is done (spec §5).
    required_translated = ("hometown_landmark", "fear_image", "quality_symbol")
    missing = [k for k in required_translated if k not in tokens]
    if missing:
        sys.exit(
            f"tokens.json is missing translated fields: {missing}\n"
            f"You must translate raw camper input into fantasy fragments first."
        )

    # CLI uses the first configured region; the web app rotates automatically.
    # For batch CLI runs spanning many calls, set GCP_LOCATIONS and the script
    # below could be extended to rotate — for now sticks to one region.
    client = genai.Client(vertexai=True, project=PROJECT_ID, location=LOCATIONS[0])

    results = []

    # ---- 12 narrative panels ----
    for panel in class_data["panels"]:
        label = f"panel_{panel['n']:02d}"
        print(f"\n=== {label} — {panel['caption']} ===")
        prompt = assemble_panel_prompt(panel, class_data, tokens)
        out_path = out_dir / f"{label}.png"
        status, final_prompt = generate_with_reroll(
            client, prompt, [photo_path, hero_card_path], label, out_path,
        )
        results.append({
            "panel": panel["n"],
            "status": status,
            "caption": panel["caption"],
            "final_prompt": final_prompt if status != "ok" else None,  # only keep for audit on non-OK
        })

    # ---- Cover (13th call) ----
    print(f"\n=== cover ===")
    cover_prompt = assemble_cover_prompt(class_data, tokens)
    cover_path = out_dir / "cover.png"
    status, _ = generate_with_reroll(
        client, cover_prompt, [photo_path, hero_card_path], "cover", cover_path,
    )
    results.append({"panel": "cover", "status": status})

    # ---- Manifest for Stage 3 ----
    manifest = build_manifest_dict(args.camper, args.class_name, class_data, tokens, results)
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))

    ok_count = sum(1 for r in results if r["status"] == "ok")
    print(f"\nDone: {ok_count}/{len(results)} images approved.")
    print(f"Output: {out_dir}")


if __name__ == "__main__":
    main()
