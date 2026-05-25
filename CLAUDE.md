# Camp Comics — Claude working notes

Personalized 12-panel D&D-style comic generator for ~60 summer camp **players**
per week. Vertex AI / Gemini 2.5 Flash Image for art, Flask intake UI (legacy),
WeasyPrint for PDF, local-print delivery on Day 5.

**Read first:** `spec/design.md` (canonical design), `README.md` (how to run),
and `docs/prd/iphone-intake.md` (the in-progress migration to a native iPhone
app that replaces the Python pipeline). This file is just Claude's working context.

## Terminology

Use **player** (not "camper") in all new code, docs, and conversation. The legacy
Python code in `scripts/` still uses "camper" in variables and on-disk paths
(`intake/camper_NNN/`, `outputs/camper_NNN/`, `--camper` CLI flag); that code is
moving to `_legacy/` and doesn't need to be sweep-renamed. New iOS code uses
`players/player_NNN/`.

## Repo orientation

| Path | What lives there |
|---|---|
| `spec/design.md` | Source of truth for product decisions. Do not contradict without flagging. |
| `docs/prd/iphone-intake.md` | The active migration plan: iPhone (SwiftUI) app replaces the Python pipeline. |
| `templates/{class}.yaml` × 6 | Per-class panel scripts (druid, warrior, wizard, bard, healer, trickster). Will gain `emotion:` + `position:` fields per panel as part of the iPhone migration. |
| `templates/refs/{class}_hero.png` | Pre-generated class hero-card style anchors. |
| `_legacy/scripts/intake_server.py` | Legacy Flask app — intake, QA gate, finalize, translate, generate, render. Kept runnable as Jeremy's prompt-iteration sandbox; not on the production path anymore. |
| `_legacy/scripts/generate.py` | Legacy Vertex AI panel/cover generation. Imported by intake_server. |
| `_legacy/scripts/render.py` | Legacy Jinja2 + WeasyPrint → comic.pdf. |
| `_legacy/scripts/make_hero_card.py` | Pre-camp utility to (re)build hero refs in `templates/refs/`. |
| `_legacy/intake_ui/templates/` | Legacy Flask Jinja templates for the web UI. |
| `_legacy/layout/comic.html.j2` + `comic.css` | Print layout (6.625×10.25", D&D book aesthetic). Will be ported (mostly as-is) to the iOS app's `WKWebView` PDF renderer. |
| `_legacy/intake/camper_NNN/` | Per-player photo + tokens.json + QA artifacts (legacy layout — IDs and dir names keep "camper" prefix). |
| `_legacy/outputs/camper_NNN/` | Generated panels, manifest.json, comic.pdf (legacy layout). |

## Running it (legacy Python sandbox)

The legacy pipeline lives under `_legacy/` but still runs end-to-end from
the repo root. Always activate the venv first: `source .venv/bin/activate`.

```bash
# Day 1–4 intake + generation UI (port 5001 — macOS AirPlay hogs 5000):
python _legacy/scripts/intake_server.py
# → http://localhost:5001

# Stage 2/3 also runnable from CLI:
python _legacy/scripts/generate.py --camper camper_001 --class druid
python _legacy/scripts/render.py --all
```

`templates/` stays at the repo root (shared with the new iOS app). Everything
else legacy — scripts, intake_ui, layout, intake, outputs, requirements*.txt —
moved under `_legacy/`.

Required env: `GCP_PROJECT`, plus `gcloud auth application-default login`.
`GCP_LOCATIONS` (comma-sep) cycles regions to dodge per-region image-gen quotas.

## Things that bite

- **macOS Python is PEP 668**: must use the `.venv`, don't `pip install` globally.
- **WeasyPrint native deps**: `brew install pango` before `pip install -r requirements-render.txt`.
- **Quota**: `gemini-2.5-flash-image` per-minute quota is per-region and non-adjustable. Use `GCP_LOCATIONS` rotation if running a full cohort.
- **Caption ≤12 words**: hard cap. CSS layout breaks if exceeded.
- **Panel 12 mirrors Panel 1**: the YAML `reference_panel` override on panel 12 points back at panel 1 so the continuity anchor doesn't drag druid regalia into the "return home" beat. Don't remove without thought.

## State convention (legacy)

- `intake/camper_NNN/qa_passed` (zero-byte marker) = photo QA gate cleared.
- `outputs/camper_NNN/_pending_{panel}.png` = unaccepted generation; gets renamed to `panel_NN.png` on accept.
- `outputs/camper_NNN/_skipped_{panel}` (marker) = operator skipped this panel.
- `outputs/camper_NNN/_attempts.json` = per-panel attempt counter + last prompt.
- The dashboard shows status pills derived from these files — no DB.

## Style

- Edit existing files; this repo is small enough that adding new modules usually means I'm over-engineering.
- No comments unless a constraint is non-obvious (e.g. the panel-12 reference override above earns a comment; ordinary control flow does not).
- Match the existing terse-but-pointed docstring style.
- This is a git repo as of `81ed9bc` (initialized 2026-05-24). Commit small, named, often.

## Agent skills

### Issue tracker

GitHub Issues via the `gh` CLI. Repo has no remote yet — run `gh repo create` once before any skill that publishes to issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` + `docs/adr/` at the repo root. Neither exists yet; `/grill-with-docs` will create them lazily. See `docs/agents/domain.md`.
