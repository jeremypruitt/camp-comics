# Handoff — 2026-05-25 (very late, third session of the day) — slice 4 shipped

**For the next Claude session that picks up this project.**
**Author:** the 2026-05-25 Claude session that shipped slice 4
(Firebase Gemini QA-gate on submit).

## Where we are

**Slice 4 is shipped and verified end-to-end on Jeremy's iPhone 16 Pro
Max.** The full loop now runs: take 6 staff captures → tap Submit →
spinner runs ~5–15s → real Gemini-generated test panel appears in a
zoomable sheet. Jeremy walked the loop, confirmed the likeness transfer
works, and tested both Re-roll (regenerate from the same photo) and
Retake (re-shoot the gate photo).

Two commits on `main`, both pushed:

- `8df428f` — slice 4 core: `QAGatePrompt` + `PanelGenerator` protocol
  in `CampComicsCore` (5 new tests, suite at 29), `FirebaseAIPanelGenerator`
  in the app target, `CaptureFlowView.submit()` is now async with a
  `SubmissionState` enum driving the spinner / result sheet / error
  alert.
- `d4e03cd` — polish from device testing: swapped `FirebaseAI.firebaseAI()`
  to `FirebaseAI.firebaseAI(backend: .vertexAI())` (the default googleAI
  backend needed a Gemini Developer API key we don't have; Vertex runs
  through the GCP project Firebase is already wired to). Added a
  UIScrollView-backed `ZoomableImage` (pinch / drag / double-tap to
  toggle 1×/2.5×) and a three-button row on the result sheet:
  Retake / Re-roll / Done.

`origin/main` is now at `d4e03cd`. No uncommitted work.

## Issues on GitHub

Three `ready-for-agent` issues exist after `/to-issues` ran earlier today:

- **#1** — Load class templates from app bundle (slice 2)
  https://github.com/jeremypruitt/camp-comics/issues/1
- **#2** — Tag remaining five class templates with (emotion, position)
  (slice 3)
  https://github.com/jeremypruitt/camp-comics/issues/2
- **#3** — Firebase Gemini QA-gate on submit (slice 4) — **done; close it**
  https://github.com/jeremypruitt/camp-comics/issues/3

Issue #3 hasn't been closed yet. Run `gh issue close 3 --comment
"Shipped in 8df428f + d4e03cd; verified end-to-end on iPhone."` at the
top of the next session.

## Recommended next slice

**Two reasonable options. Ask Jeremy which.**

**(a) Issue #2 — tag the other 5 class templates** (warrior, wizard,
bard, healer, trickster). Mechanical low-risk YAML editing. Wizard
already has a draft mapping in `prototype/intake-mobile/index.html`
(`TEMPLATES.wizard`). Becomes user-visible only after #1 lands, but the
tagging work is independent. Tracer-bullet-able: tag one class, add a
parsing test, repeat.

**(b) Filesystem photo persistence.** The PRD calls for
`photos/{emotion}_{position}.jpg` per player. Right now everything is
in-memory — close the app and you lose the captures. This is the next
obvious vertical slice for the iPhone app and unlocks multi-player work.
Not yet on GitHub as an issue; could be filed via `/to-issues`.

Either is fine. **(b) feels more visible and product-relevant**; **(a)
is shorter and unblocks #1.** Don't start without confirming.

## What got built this session (don't repeat)

Four new files, two modified:

- `CampComicsCore/Sources/CampComicsCore/QAGatePrompt.swift` —
  pure-function string assembler. Ports the legacy Python
  `run_qa_gate` prompt verbatim into Swift.
- `CampComicsCore/Sources/CampComicsCore/PanelGenerator.swift` —
  `Sendable` protocol + `PanelGeneratorError` enum. The view depends
  on this, not on FirebaseAI directly.
- `CampComicsCore/Tests/CampComicsCoreTests/QAGatePromptTests.swift` —
  five tracer-bullet tests (display name, D&D style, face-match
  instruction, no-text-in-image, determinism).
- `CampComics/CampComics/FirebaseAIPanelGenerator.swift` — concrete
  impl: `FirebaseAI.firebaseAI(backend: .vertexAI()).generativeModel(...)`
  + `InlineDataPart` for the photo. Maps `quota` / `PERMISSION_DENIED`
  errors to human-readable strings.
- `CampComics/CampComics/CaptureFlowView.swift` — async submit handler,
  `SubmissionState` enum, `QAResultSheet` with Retake/Re-roll/Done,
  embedded `ZoomableImage` (UIViewRepresentable around UIScrollView).

Reference commits + diffs:
- `git show 8df428f`
- `git show d4e03cd`

## Firebase / Vertex AI gotchas worth knowing

- The default backend in `FirebaseAI.firebaseAI()` is `.googleAI()`,
  which needs a Gemini Developer API key. We use `.vertexAI()` because
  the existing Firebase project is wired to a GCP project with Vertex
  AI enabled. **Don't revert this** without a plan.
- `gemini-2.5-flash-image` is the model. Quota is per-region and
  non-adjustable; the legacy CLI rotated regions, but the iOS app
  doesn't (yet). One submit = one Gemini call = one quota slot.
  Re-roll burns another. Be aware during a 60-player cohort.
- Errors surface via `PanelGeneratorError.underlying(String)` —
  `FirebaseAILogic.BackendError` strings are passed through. The
  human-readable mapping in `FirebaseAIPanelGenerator.humanReadable`
  catches the common ones (quota, permission denied) but most
  failures will surface raw text in the alert.

## Running on Jeremy's iPhone

No changes — same 3-step sequence from the prior handoffs. Trust is
cached for ~7 days; first install of the week needs the
Settings → General → VPN & Device Management → Trust tap.

```bash
cd /Volumes/MacMiniDock/dev/camp-comics/CampComics

xcodebuild -project CampComics.xcodeproj -scheme CampComics \
  -destination 'platform=iOS,id=EE8B5F99-92C8-537B-BEC2-2670AFDCE6D7' \
  -derivedDataPath build-device build

xcrun devicectl device install app \
  --device EE8B5F99-92C8-537B-BEC2-2670AFDCE6D7 \
  build-device/Build/Products/Debug-iphoneos/CampComics.app

xcrun devicectl device process launch \
  --device EE8B5F99-92C8-537B-BEC2-2670AFDCE6D7 \
  me.jeremypruitt.CampComics
```

## Open questions for Jeremy

1. **Close #3?** It's shipped; just need `gh issue close`.
2. **Next slice: issue #2 (tag templates) or photo persistence?**
   Recommendation above leans persistence; reasonable to do either.
3. **File the persistence work as a GitHub issue first?** `/to-issues`
   is set up. Could also just open it inline.
4. **Region rotation for Gemini?** Not urgent until a real cohort runs,
   but worth flagging — the legacy CLI rotates `GCP_LOCATIONS`; the iOS
   app pins to whatever Vertex picks.

## Don't break

Carry forward from the prior handoffs — nothing has materially changed.
Specifically:

- The `@retroactive` conformance on `PanelRequirement: Identifiable`
  in `CampComics/CampComics/PanelRequirement+Identifiable.swift`.
- The Vertex AI backend choice in `FirebaseAIPanelGenerator.swift`
  (line 11). See "Firebase / Vertex AI gotchas" above.
- Slice 1's `[UUID: UIImage]` photo store keyed off `CapturedPhoto.id`
  (not the `PanelRequirement`). Slice 4's submit handler depends on
  this; persistence work (if chosen next) needs to keep the keying.
- The legacy `_legacy/` Python pipeline still renders end-to-end.
  Don't rename or touch it.
- SourceKit's "No such module 'UIKit'" / "No such module 'FirebaseAI'"
  warnings are false positives. `xcodebuild` is the source of truth.
- SSH commit signing needs `ssh-add ~/.ssh/github_ed` once per shell.

## Load-bearing context to read

1. `CLAUDE.md` — orientation, gotchas, terminology.
2. `docs/handoff/2026-05-25-pick-next-tracer-bullet.md` — the prior
   handoff. Reads like a prequel.
3. `docs/prd/iphone-intake.md` — still authoritative for any new slice.
4. `git show 8df428f d4e03cd` — the two slice 4 commits.
5. `_legacy/scripts/intake_server.py` `run_qa_gate` — the prompt this
   slice ports to Swift.
6. Memory at
   `~/.claude/projects/-Volumes-MacMiniDock-dev-camp-comics/memory/` —
   add a `project_slice_4_shipped.md` after this handoff is filed.

## Suggested skills

- **`grill-with-docs`** — if the next slice is photo persistence,
  stress-test the file-layout decision against the PRD before writing
  code. `CONTEXT.md` and `docs/adr/` are both still absent; the skill
  will lazily create them. The Vertex AI backend choice from this
  session is a candidate first ADR.
- **`tdd`** — both candidate slices have pure-Swift pieces worth
  driving red-green-refactor. Photo persistence has a natural
  `PhotoStore` interface; template tagging has YAML parsing tests.
- **`to-issues`** — file photo persistence as a GitHub issue if Jeremy
  picks it as the next slice.
- **`verify`** — confirm the chosen slice works on Jeremy's iPhone
  before declaring it done. Convention requires it.
- **`diagnose`** — Vertex AI quota / permission errors are the most
  likely runtime surprise during a cohort.
- **`handoff`** — at the end. Write to `docs/handoff/YYYY-MM-DD-*.md`,
  not `/tmp` (project convention overrides the skill default).

## Verdict

Slice 4 is in the can. The iPhone app now does: capture → Gemini → real
panel. The "tracer bullet through every layer" goal of the iPhone
migration is met for one player on one class (druid). Everything from
here is broadening (more classes, more players) or hardening
(persistence, multi-region, error UX). Open the next session by closing
issue #3, asking the (a)/(b) question above, and starting from there.
