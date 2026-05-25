# Handoff — 2026-05-25 (sixth session of the day) — slice 7 shipped

**For the next Claude session that picks up this project.**
**Author:** the 2026-05-25 Claude session that shipped slice 7
(bundle the YAMLs + tag the five non-druid classes).

## Where we are

**Slice 7 is shipped and verified on Jeremy's iPhone 16 Pro Max.**
All six character classes (druid, warrior, wizard, bard, healer,
trickster) now have full `(emotion, position)` panel + cover tags,
load from on-bundle YAML at runtime, and are selectable in the
intake picker.

This slice closed issues **#1** and **#2** in one go.

## What got built

Five YAML files modified, two Swift files rewritten, one Swift
file modified, one symlink created, eleven new tests:

- **MODIFIED** `templates/{warrior,wizard,bard,healer,trickster}.yaml`
  — added `emotion:` + `position:` to every panel and to the
  `cover:` block. All five clone the druid arc shape
  (neutral/front, surprise/front, neutral/front, joy/front,
  **neutral/profile**, neutral/front, fear/front, fear/front,
  neutral/front, **joy/profile**, neutral/front, joy/front +
  cover neutral/profile) because the class YAMLs are literal
  clones of druid.yaml with prose swapped per class.

- **MODIFIED** `CampComics/CampComics/BundledTemplates.swift` —
  rewrote from the hardcoded druid `ClassTemplate` literal to a
  `Bundle.main`-backed loader. `template(forClassKey:)` resolves
  `Templates/{key}.yaml`, reads it, runs it through
  `TemplateLoader.load`, and caches the result. New
  `allClassKeys: [String]` exposes the canonical six. The static
  `druid` constant is gone — replaced everywhere it was used.

- **MODIFIED** `CampComics/CampComics/IntakeFormView.swift` —
  picker now iterates a `ClassChoice.all` array with all six
  classes (with hand-written subtitles drawn from the YAML
  `value:` lines). Old "only Druid is wired up" footnote removed.

- **MODIFIED** `CampComics/CampComics/CaptureFlowView.swift` —
  the SwiftUI preview swapped `BundledTemplates.druid` for
  `BundledTemplates.template(forClassKey: "druid")`.

- **MODIFIED** `CampComicsCore/Tests/CampComicsCoreTests/TemplateLoaderTests.swift`
  — added six new tests (one per class, including druid) that
  load the actual on-disk YAMLs via `#filePath`-relative path
  resolution and verify the canonical 12-panel arc. Plus added
  `Foundation` import. Full suite: 54/54 green (was 48/48).

- **NEW** `CampComics/CampComics/Templates` — a **symlink** to
  the repo-root `templates/`. The Xcode 16
  `PBXFileSystemSynchronizedRootGroup` mechanism follows it and
  auto-includes all `*.yaml` files as bundle resources, so the
  templates land in `CampComics.app/Templates/`. The legacy
  Python pipeline still reads from the same files via the
  canonical `templates/` path. Single source of truth.

Reference: the slice-7 commit (run `git log --oneline -1`).

## Verified on device

Jeremy tapped through on the iPhone:

- ✅ App launches with no crash
- ✅ Tap **+** → picker shows all six classes with subtitles
- ✅ Selecting a non-druid class + starting capture opens the
  capture flow without crashing (the YAML loads through
  `BundledTemplates.template(forClassKey:)`)

The full per-class capture/QA round-trip for non-druid classes
was not exhaustively walked through (e.g., we didn't generate a
QA avatar for each of the five new classes), but the code path
is the same one slice 4–6 verified — only the template changed.

## Issues on GitHub

After this session:

- **#1** — closed (bundle templates from app bundle, this slice)
- **#2** — closed (tag five class templates, this slice)
- **#3** — closed (Gemini QA-gate, slice 4)
- **#4** — closed (filesystem persistence, slice 5)
- **#5** — closed (avatar persistence, slice 6)

**No open `ready-for-agent` issues.** The next significant
piece of v1 work is the 12-panel storyboard generation loop —
big enough that it needs its own PRD pass or `/to-issues` cut
before starting (see option (c) in the slice-6 handoff).

## Recommended next slice

**Two reasonable options. Ask Jeremy which.**

**(a) Scope the numbered-panel generation loop.** PRD §169
reserves `panels/panel_NN.png` for the 12-panel storyboard. This
is the per-panel review screen (`PanelReviewView`, module 10) —
accept / re-roll / re-prompt / skip with a 4-attempt budget per
panel. Use `/to-issues` (or `/grill-me`) to break it into
tracer-bullet slices first.

**(b) Per-class hero card.** The class YAMLs reference
`refs/{class}_hero.png` (already symlinked into the bundle via
`Templates/refs/`). Showing a hero-card thumbnail at intake or
in the player list is a small UX win that uses what's already
shipping. Tracer-bullet: load + display the hero PNG in the
`ClassPickerRow`. Tiny slice, but user-visible.

**Recommendation lean: (a).** It's the biggest remaining hole in
the v1 iPhone app; doing it next moves toward an end-to-end
pipeline replacement. (b) is a nice polish but can land any
time.

## Don't break

Carrying forward, plus slice-7-specific:

- The Vertex AI backend choice in `FirebaseAIPanelGenerator.swift`
  (line 9). Load-bearing.
- The `@retroactive` conformance in
  `PanelRequirement+Identifiable.swift`.
- SourceKit "No such module 'UIKit'" / "No such module
  'FirebaseAI'" / "No such module 'CampComicsCore'" / "No such
  module 'Testing'" warnings are all false positives.
  `xcodebuild` and `swift test` are the source of truth.
- SSH commit signing: `ssh-add ~/.ssh/github_ed` once per shell.
- The legacy `_legacy/` Python pipeline still renders end-to-end.
  Don't touch it.
- **Slice 7 specifics:**
  - `Templates` (capital T) inside `CampComics/CampComics/` is a
    **symlink** to the repo-root `templates/` (lowercase). The
    symlink is what makes Xcode 16's file-system-synchronized
    group pick the YAMLs up as bundle resources. Don't replace
    it with a copy — that breaks the single-source-of-truth
    invariant with the legacy Python pipeline.
  - All six class arcs are literal clones of druid's
    emotion/position pattern. If you ever genuinely want a class
    arc to deviate (e.g., wizard panel 10 = front instead of
    profile), update both the YAML and the
    `assertCanonicalArc` helper in `TemplateLoaderTests.swift` —
    that helper currently asserts every class follows the druid
    pattern exactly, which is the right shape today but won't
    stay right if arcs diverge.
  - `ClassChoice.all` in `IntakeFormView.swift` is the
    authoritative list of classes shown in the picker, with
    hand-written subtitles. If you add a class, add a row to
    `ClassChoice.all` AND a YAML in `templates/` AND a hero PNG
    in `templates/refs/`. The `BundledTemplates.allClassKeys`
    constant is kept in sync by hand — there's no enforcement.

## Load-bearing context to read

1. `CLAUDE.md` — orientation, gotchas, terminology.
2. `docs/handoff/2026-05-25-slice-6-shipped.md` — prior handoff.
3. `docs/prd/iphone-intake.md` — §169 (PlayerStore interface)
   has `qa_avatar.png` ✅ and `tokens.json` ✅; `panel_NN.png`
   and `comic.pdf` remain.
4. `git show $(git log --oneline -1 --format=%H)` — the slice 7
   commit.
5. Memory at
   `~/.claude/projects/-Volumes-MacMiniDock-dev-camp-comics/memory/`
   — `project_slice_7_shipped.md` was added this session.

## Suggested skills

- **`to-issues`** — if Jeremy picks (a), use `/to-issues` to
  break the numbered-panel work into tracer-bullet slices before
  starting. Likely 3–5 issues (state machine for accept /
  re-roll / re-prompt / skip; per-panel attempt budget;
  PanelReviewView UI; integration with `FirebaseAIPanelGenerator`;
  storage at `panels/panel_NN.png` via new `PlayerStore` API).
- **`grill-me`** — `/to-issues` and `/grill-me` pair well for
  the panel-review work. The state machine for the 4-attempt
  budget + retake/skip semantics deserves grilling before any
  code lands.
- **`tdd`** — the per-panel accept/re-roll/skip state is pure
  Swift; natural for red-green-refactor.
- **`verify`** — confirm whatever ships works on Jeremy's
  iPhone. Convention.
- **`handoff`** — at the end of the next session. Write to
  `docs/handoff/YYYY-MM-DD-*.md`, **not** `/tmp` (project
  convention overrides the skill default).

## Verdict

All six classes are real. The intake picker shows them all,
they all parse, the capture flow opens for each. The iPhone app
is now class-flexible: switching characters is a YAML edit, not
a Swift edit. The remaining v1 surfaces are the 12-panel
generation loop (big — needs scoping) and the PDF render.

Open the next session by asking the (a)/(b) question, then
start from there.
