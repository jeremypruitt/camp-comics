# Camp Comics

Pipeline for generating personalized 12-panel D&D-style comic books for
summer camp participants.

**See `spec/design.md` for the full design.**

## Quick map

The legacy Python pipeline has moved under `_legacy/` (sandbox / prompt-iteration
only — not the production path). The native iPhone app under `docs/prd/iphone-intake.md`
is the path forward. `templates/` stays at the repo root because the new iOS
app and the legacy pipeline both consume it.

```
camp-comics/
├── spec/design.md             ← design source of truth (read first)
├── docs/prd/iphone-intake.md  ← active migration plan (iPhone SwiftUI app)
├── templates/
│   ├── {class}.yaml × 6       ← class arc templates (druid, warrior, wizard, bard, healer, trickster)
│   └── refs/                  ← class hero-card reference PNGs (you generate pre-camp)
├── prototype/intake-mobile/   ← mobile-web prototype (Variant B "Checklist" is the chosen capture UX)
└── _legacy/                   ← Python sandbox (still runnable, kept for prompt iteration)
    ├── scripts/
    │   ├── intake_server.py   ← Stages 1 (intake + QA + finalize) + mid-week translation
    │   ├── generate.py        ← Stage 2: image gen via Vertex AI
    │   └── render.py          ← Stage 3: HTML+CSS → PDF via WeasyPrint
    ├── intake_ui/templates/   ← Flask templates for the intake app
    ├── layout/
    │   ├── comic.html.j2      ← 5-page comic template
    │   └── comic.css          ← print layout (6.625×10.25", D&D book aesthetic)
    ├── intake/camper_NNN/     ← photo + tokens.json + QA artifacts
    └── outputs/camper_NNN/    ← panels, manifest.json, comic.pdf
```

## Setup

macOS Python is externally managed (PEP 668), so install into a venv:

```bash
cd camp-comics
python3 -m venv .venv
source .venv/bin/activate

# Core deps (intake app + generation):
pip install -r _legacy/requirements.txt

# Stage 3 render deps (separate because WeasyPrint needs native libs):
brew install pango     # macOS only; Debian: sudo apt install libpango-1.0-0 libpangoft2-1.0-0
pip install -r _legacy/requirements-render.txt

# Auth to Vertex AI:
gcloud auth application-default login
export GCP_PROJECT=your-project-id
export GCP_LOCATION=us-central1
```

Every session, activate the venv first: `source .venv/bin/activate`.

## Pre-camp (Stage 0, one weekend)

1. Generate the 6 class hero-card reference PNGs in the Gemini UI;
   save to `templates/refs/{class}_hero.png`.
2. End-to-end test with one fake camper through the intake app.

## During camp

```bash
# Start the intake app (Days 1–4 — leave running on a laptop at the photo station):
python _legacy/scripts/intake_server.py
# → open http://localhost:5001
# (Port defaults to 5001 because macOS AirPlay Receiver hogs 5000.
#  Override with: PORT=5002 python _legacy/scripts/intake_server.py)
```

The intake app handles:

- **Day 1 — Photo station** — `+ New camper intake` form takes the camper's name,
  cabin, top-3 class ranking, photo, and three short raw-word answers (landmark,
  fear, quality). On submit it runs the day-1 **QA gate** (single Gemini test
  generation) and shows the source photo and test image side by side. *Accept*
  marks the photo gate passed; *retake* loops back to upload another shot.
- **Day 1 evening — Class finalization** — `Finalize class` button per camper
  on the dashboard. Pick the assigned class (defaults to their #1 choice) and
  collect the class-specific token in their own words.
- **Mid-week — Translation** — `Translate` button per camper. Their raw words
  are shown alongside textareas for fantasy-fragment translation; on save the
  `_translated` fields are written into `tokens.json` and the camper is ready
  to generate.

The dashboard shows status pills per camper:
`photo • class • translated • generated • rendered`. Once a camper is fully
translated, the dashboard shows the exact `generate.py` command to run for
them.

```bash
# Stage 2 — generation (Days 3–4 evenings, terminal):
python _legacy/scripts/generate.py --camper camper_001 --class druid

# Stage 3 — render (Day 5 morning):
python _legacy/scripts/render.py --all
```

## `tokens.json` shape (managed by the app, not by hand)

```json
{
  "camper_name": "Riley",
  "character_name": "Thornroot the Patient",
  "cabin": "Oakhaven",
  "class_top_3": ["druid", "bard", "healer"],
  "class": "druid",

  "hometown_landmark_raw": "the old lighthouse",
  "fear_raw": "fear of letting my family down",
  "quality_raw": "patience",
  "animal_companion": "river otter",

  "hometown_landmark": "a lighthouse glowing on a windswept cliff above gray waves",
  "fear_image": "a translucent ghostly figure of an elder looking on with sorrowful eyes",
  "quality_symbol": "a small lit torch handed to them by unseen hands"
}
```

The three `_raw` fields are captured by the intake form; the three matching
translated fields are filled mid-week in the translation form. `class` is set
in the finalize step. The class-specific token (`animal_companion` here)
is also set in finalize.
