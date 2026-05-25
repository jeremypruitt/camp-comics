# Handoff — 2026-05-25 (very late) — pick the next tracer bullet

**For the next Claude session that picks up this project.**
**Author:** the 2026-05-25 late-night Claude session that shipped slice 1
(real camera capture).

## Where we are

**Slice 1 is shipped and verified.** Jeremy walked the full loop on his
iPhone 16 Pro Max end-to-end at the end of this session: tap an empty
row → rear camera opens → take a photo → thumbnail appears in the row;
tap a captured row → review sheet with the real photo + retake/looks
good; tap retake → camera re-opens. The four-tap flow works.

Three queued slices remain (still as described in
[`docs/handoff/2026-05-25-next-slice.md`](2026-05-25-next-slice.md)):

2. **YAML → bundle loading** — plumbing only; not user-visible.
3. **Other five class templates** — mechanical hand-tagging, low risk.
4. **Firebase / Gemini test-generation on submit** — the riskiest
   unknown and the most exciting demo (real photo → real Vertex panel).

**Recommended next slice: #4.** Reason: it's the next *vertical* tracer
bullet that produces a visible end-to-end result, doesn't depend on #2
(the hardcoded druid template still works for one player), and is the
biggest remaining unknown. #2 and #3 are tidy-up work that can wait
until a second player joins or the team wants to ship more than druid.

## ⚠ First thing: commit slice 1

The slice-1 code is **uncommitted on disk** as of this handoff. Don't
start new work on top of dirty trees.

```
modified:   CampComics/CampComics.xcodeproj/project.pbxproj
modified:   CampComics/CampComics/CaptureFlowView.swift
new file:   CampComics/CampComics/ImagePicker.swift
```

Suggested commit message: *"Slice 1: real camera capture via
UIImagePickerController (rear, photo-library fallback)"*. Don't include
`.claude/` — that's a local-only directory.

Local branch is **8 commits ahead of `origin/main`**. Jeremy hasn't
asked to push; ask before doing so.

## What got built this session (don't repeat)

Three files touched, no new tests added (slice 1 is all UIKit
plumbing; CampComicsCore's 24 tests still cover the state machine
unchanged):

- **`CampComics/CampComics/ImagePicker.swift`** (new) —
  `UIViewControllerRepresentable` wrapping `UIImagePickerController`.
  Exposes `ImagePicker.preferredSourceType` which picks `.camera` on
  device, `.photoLibrary` on simulator (via `isSourceTypeAvailable`).
  Rear-cam default per the PRD.
- **`CampComics/CampComics/CaptureFlowView.swift`** — replaced the mock
  `CapturedPhoto()` with a real flow. New `@State` for `capturing:
  PanelRequirement?` drives a `.fullScreenCover` presenting
  `ImagePicker`. In-memory `[UUID: UIImage]` photo store keyed off
  `CapturedPhoto.id`. `ChecklistRow` and `ReviewSheet` now show real
  thumbnails / previews when bytes exist, fall back to the prompt
  emoji otherwise. Retake discards the photo from the store, calls
  `captureState.retake`, dismisses the review sheet, and re-presents
  the camera.
- **`CampComics/CampComics.xcodeproj/project.pbxproj`** — added
  `INFOPLIST_KEY_NSCameraUsageDescription` and
  `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` to both Debug and
  Release configs of the app target.

## Slice 4 — what the work looks like

Replace the "Submitted (mock)" alert in
[`CaptureFlowView.swift`](../../CampComics/CampComics/CaptureFlowView.swift)
with a single-panel Vertex AI in Firebase generation that takes the
**neutral|front** photo and tries to render one panel as a QA gate
(mirroring what `_legacy/scripts/intake_server.py` did at the
`qa_passed` marker).

Things you'll need to figure out, in roughly this order:

- **Which SDK / API surface.** Firebase AI for iOS (`FirebaseAI`) is
  the official path; `FirebaseApp.configure()` is already called in
  `CampComicsApp.init`. Don't reach for Vertex directly. The model is
  `gemini-2.5-flash-image` (matches the legacy Python).
- **Where the request lives.** A small `CampComicsCore` actor or
  service struct is the cleanest place; the SwiftUI side calls it from
  the submit handler. Returns either a `UIImage`/`Data` panel or a
  structured failure ("photo too blurry", "no face detected",
  whatever Vertex tells us).
- **Photo selection.** The current `[UUID: UIImage]` map lives in
  `CaptureFlowView`. Slice 4 needs to pluck the **neutral|front** shot
  specifically — that's `PanelRequirement(emotion: .neutral, position:
  .front)`. `CaptureState.capturedPhoto(for:)` plus the UI's store
  lookup gives you it.
- **Prompt assembly.** The druid YAML now has `emotion` + `position`
  per panel, and `PromptCopyBook` has the user-facing strings, but
  there's no Gemini-prompt assembly yet — that's part of this slice.
  Look at the legacy `_legacy/scripts/generate.py` for the
  prompt-building shape (panels + cover) and decide how much to port.
- **UI feedback.** While the call is in flight, the submit button
  needs a spinner state and disable. On success, show the returned
  panel. On failure, surface the error so staff can decide whether to
  re-shoot the gate photo.

**Don't** roll filesystem persistence in at the same time — the
in-memory store works fine for one-shot generation, and disk
persistence (`photos/{emotion}_{position}.jpg` per the PRD) is its own
slice.

## Running on Jeremy's iPhone

No changes from the previous handoff — the three-step `xcodebuild` /
`devicectl install` / `devicectl process launch` sequence still works
verbatim. Trust was cached this session (no Settings tap needed), so
expect the 7-day expiry to bite mid-week.

See [`docs/handoff/2026-05-25-next-slice.md`](2026-05-25-next-slice.md)
"Running on Jeremy's iPhone" section for the exact commands.

## Open questions for Jeremy

1. **Slice 4, or somethng else?** Recommendation above is #4. Confirm
   or redirect.
2. **Push the 8 local commits before more work?** Or keep accumulating.
3. **File GitHub issues?** Still none. `/to-issues` against the queued
   slices is one option; just-keep-coding is another.
4. **Filesystem persistence appetite?** Once #4 lands, the
   `photos/{emotion}_{position}.jpg` slice is the next obvious one.

## Don't break

Same list as the prior handoff — nothing new. In particular:

- The `@retroactive` conformance in
  `CampComics/CampComics/PanelRequirement+Identifiable.swift` is still
  required.
- Slice 1's in-memory `[UUID: UIImage]` store is keyed off
  `CapturedPhoto.id` (a fresh UUID per capture), not off
  `PanelRequirement`. Retakes generate a *new* CapturedPhoto and a new
  key; the old key is cleared. Slice 4 should look up the image via
  `captureState.capturedPhoto(for:)?.id` rather than indexing the
  store directly by requirement.
- SourceKit still lags `xcodebuild`. The "No such module 'UIKit'"
  warning on `ImagePicker.swift` / `CaptureFlowView.swift` is a false
  positive when those files compile via xcodebuild.

## Load-bearing context to read

1. [`docs/handoff/2026-05-25-next-slice.md`](2026-05-25-next-slice.md)
   — the previous handoff. Slice descriptions for 2/3/4 are there,
   not re-pasted here.
2. [`docs/prd/iphone-intake.md`](../prd/iphone-intake.md) — still
   authoritative for slice 4's data flow.
3. `_legacy/scripts/intake_server.py` — the QA gate logic to mirror.
4. `_legacy/scripts/generate.py` — the prompt-assembly logic to port.
5. The new commit, once Jeremy commits it (see top of doc).
6. Memory at
   `~/.claude/projects/-Volumes-MacMiniDock-dev-camp-comics/memory/` —
   add a `project_slice_1_shipped.md` after this handoff is filed.

## Suggested skills

- **`grill-with-docs`** — slice 4 has more unknowns than slice 1 did
  (SDK choice, prompt shape, failure modes). Stress-test the plan
  against the PRD before writing code. `CONTEXT.md` and `docs/adr/`
  are still both absent; the skill will lazily create them.
- **`claude-api`** — Anthropic SDK skill doesn't cover Vertex AI in
  Firebase directly, but its prompt-caching/feature framing is
  relevant if you end up calling Gemini at any scale.
- **`tdd`** — the prompt-assembly + photo-selection logic in
  `CampComicsCore` is pure-Swift and worth driving red-green-refactor.
  Swift Testing is already wired up.
- **`diagnose`** — Firebase AI auth / project-config issues are the
  most likely source of head-scratchers. The
  `GoogleService-Info.plist` is already in the bundle.
- **`verify`** — confirm the chosen slice actually generates a panel
  on Jeremy's iPhone before declaring it done.
- **`handoff`** — at the end. Write to `docs/handoff/YYYY-MM-DD-*.md`,
  not `/tmp` (project convention overrides the skill default).

## Verdict

Slice 1 is in the can. Open the session by:
1. Committing the uncommitted slice 1 changes (see top of doc).
2. Confirming with Jeremy that slice 4 is the next tracer bullet.
3. Reading the previous handoff's slice-4 paragraph + the legacy
   intake_server.py QA-gate section.
4. Sketching the Firebase AI call surface before touching the UI.
