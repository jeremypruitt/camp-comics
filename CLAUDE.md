# Camp Comics — Claude working notes

Personalized 12-panel D&D-style comic generator for ~60 summer camp participants
per week. Vertex AI / Gemini 2.5 Flash Image for art, Flask intake UI, WeasyPrint
for PDF, local-print delivery on Day 5.

**Read first:** `spec/design.md` (canonical design) and `README.md` (how to run).
This file is just Claude's working context.

## Repo orientation

| Path | What lives there |
|---|---|
| `spec/design.md` | Source of truth for product decisions. Do not contradict without flagging. |
| `templates/{class}.yaml` × 6 | Per-class panel scripts (druid, warrior, wizard, bard, healer, trickster). |
| `templates/refs/{class}_hero.png` | Pre-generated class hero-card style anchors. |
| `scripts/intake_server.py` | Flask app — intake, QA gate, finalize, translate, generate, render. Stages 1–3 all drive through here. |
| `scripts/generate.py` | Vertex AI panel/cover generation. Imported by intake_server. |
| `scripts/render.py` | Jinja2 + WeasyPrint → comic.pdf. |
| `scripts/make_hero_card.py` | Pre-camp utility to (re)build hero refs. |
| `intake_ui/templates/` | Flask Jinja templates for the web UI. |
| `layout/comic.html.j2` + `comic.css` | Print layout (6.625×10.25", D&D book aesthetic). |
| `intake/camper_NNN/` | Per-camper photo + tokens.json + QA artifacts (auto-assigned IDs). |
| `outputs/camper_NNN/` | Generated panels, manifest.json, comic.pdf. |

## Running it

Always activate the venv first: `source .venv/bin/activate`.

```bash
# Day 1–4 intake + generation UI (port 5001 — macOS AirPlay hogs 5000):
python scripts/intake_server.py
# → http://localhost:5001

# Stage 2/3 also runnable from CLI:
python scripts/generate.py --camper camper_001 --class druid
python scripts/render.py --all
```

Required env: `GCP_PROJECT`, plus `gcloud auth application-default login`.
`GCP_LOCATIONS` (comma-sep) cycles regions to dodge per-region image-gen quotas.

## Things that bite

- **Not a git repo.** No version history → no recovery if a file is clobbered. Initialize git before any risky change.
- **macOS Python is PEP 668**: must use the `.venv`, don't `pip install` globally.
- **WeasyPrint native deps**: `brew install pango` before `pip install -r requirements-render.txt`.
- **Quota**: `gemini-2.5-flash-image` per-minute quota is per-region and non-adjustable. Use `GCP_LOCATIONS` rotation if running a full cohort.
- **Caption ≤12 words**: hard cap. CSS layout breaks if exceeded.
- **Panel 12 mirrors Panel 1**: the YAML `reference_panel` override on panel 12 points back at panel 1 so the continuity anchor doesn't drag druid regalia into the "return home" beat. Don't remove without thought.

## State convention

- `intake/camper_NNN/qa_passed` (zero-byte marker) = photo QA gate cleared.
- `outputs/camper_NNN/_pending_{panel}.png` = unaccepted generation; gets renamed to `panel_NN.png` on accept.
- `outputs/camper_NNN/_skipped_{panel}` (marker) = operator skipped this panel.
- `outputs/camper_NNN/_attempts.json` = per-panel attempt counter + last prompt.
- The dashboard shows status pills derived from these files — no DB.

## Style

- Edit existing files; this repo is small enough that adding new modules usually means I'm over-engineering.
- No comments unless a constraint is non-obvious (e.g. the panel-12 reference override above earns a comment; ordinary control flow does not).
- Match the existing terse-but-pointed docstring style.
