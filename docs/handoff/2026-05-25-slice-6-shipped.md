# Handoff — 2026-05-25 (fifth session of the day) — slice 6 shipped

**For the next Claude session that picks up this project.**
**Author:** the 2026-05-25 Claude session that shipped slice 6
(QA-gate avatar persistence).

## Where we are

**Slice 6 is shipped and verified on Jeremy's iPhone 16 Pro Max.**
The QA-gate avatar (the "test panel" the Gemini submit produces) now
survives kill/restart and is accessible from both surfaces the user
ever sees a player in: the players list and the capture flow.

One commit pushed to `origin/main`:

- `bd05b8d` — slice 6: `PlayerStore` gains a panels API
  (`saveQAPanel` / `loadQAPanel` / `deleteQAPanel` / `hasQAPanel`)
  storing at `players/player_NNN/panels/qa_avatar.png`.
  `CaptureFlowView` persists on submit success, deletes on gate-photo
  retake, and surfaces a tap-to-view "Test panel ready" chip in the
  summary when an avatar exists (reuses the existing `QAResultSheet`
  with re-roll / retake / done — same UX as the post-generation sheet).
  `ContentView.PlayerRow` swaps the initials circle for the avatar
  thumbnail when present; the list re-loads avatars on pop back from
  the capture flow via `onChange(of: activePlayer)`. Six new tests
  (round-trip, overwrite, absent, delete, no-op-delete, hasQAPanel) —
  full suite 48/48 green.

Closes issue #5.

## Issues on GitHub

After this session:

- **#1** — Load class templates from app bundle (slice 2) —
  https://github.com/jeremypruitt/camp-comics/issues/1 — `ready-for-agent`
- **#2** — Tag remaining five class templates with `(emotion, position)`
  (slice 3) — https://github.com/jeremypruitt/camp-comics/issues/2 —
  `ready-for-agent`
- **#3** — closed (Gemini QA-gate, slice 4)
- **#4** — closed (filesystem persistence, slice 5)
- **#5** — closed (avatar persistence, slice 6)

No new issue filed at the close of this session. The two stale
`ready-for-agent` issues (#1 and #2) are the obvious next picks unless
Jeremy wants to push deeper into the avatar story (see below).

## Recommended next slice

**Three reasonable options. Ask Jeremy which.**

**(a) Issue #1 — load class templates from the app bundle.** Today
`BundledTemplates` hardcodes druid only. This slice reads
`templates/{class}.yaml` files via the existing `TemplateLoader`, so
adding a class becomes a YAML edit instead of a Swift edit. Required
before #2 lights anything up for the user.

**(b) Issue #2 — tag the other five class templates.** Mechanical YAML
edits (warrior, wizard, bard, healer, trickster). Wizard already has a
draft mapping in `prototype/intake-mobile/index.html`. Tracer-bullet:
tag one class, add a parsing test, repeat. User-visible only after #1
lands, but you can do them in either order; both can also be done in
one session.

**(c) Numbered panels (`panel_NN.png`).** PRD §169 reserves
`panels/panel_NN.png` for the 12-panel storyboard generation loop
(stories 29–34 in the PRD). This is a much bigger slice — it's the
per-panel review screen (`PanelReviewView`, module 10) with
accept/re-roll/re-prompt/skip and a 4-attempt budget. Big enough that
the existing GitHub issues don't cover it; needs its own PRD pass or
`/to-issues` cut before starting. **Don't start this without scoping
first.**

Recommendation lean: **(a)** — small, unblocks (b), and the next
user-visible thing you'd want to demo is "pick a different class and
see the right capture plan." **(b)** is the natural follow-up. **(c)**
is the biggest remaining piece of the iPhone app, but plan it before
starting.

## What got built this session (don't repeat)

Four modified files, zero new files:

- **MODIFIED** `CampComicsCore/Sources/CampComicsCore/PlayerStore.swift`
  — added `saveQAPanel` / `loadQAPanel` / `deleteQAPanel` / `hasQAPanel`
  and the `panelsDir` / `qaPanelURL` helpers. Doc comment updated to
  mention `panels/qa_avatar.png`.
- **MODIFIED** `CampComicsCore/Tests/CampComicsCoreTests/PlayerStoreTests.swift`
  — six new tracer-bullet tests under a `// MARK: - QA panel
  persistence` section.
- **MODIFIED** `CampComics/CampComics/CaptureFlowView.swift` — `init`
  hydrates a `savedAvatar: UIImage?` from disk; new `SavedAvatarChip`
  view renders above the checklist when one exists; new
  `viewingSavedAvatar` boolean drives a second sheet that reuses
  `QAResultSheet`. `submit()` writes the panel bytes via
  `store.saveQAPanel` on success and sets `savedAvatar`.
  `retakeGatePhoto()` deletes the avatar from disk and clears
  `savedAvatar`.
- **MODIFIED** `CampComics/CampComics/ContentView.swift` — added
  `avatars: [String: UIImage]` state; `refresh()` now loads
  `loadQAPanel` for every listed player and caches the `UIImage`.
  `PlayerRow` takes an `avatar: UIImage?` and renders it (clipped to a
  circle) when present, falling back to the initials circle. Added
  `onChange(of: activePlayer)` so the list refreshes when the capture
  flow pops back.

Reference: `git show bd05b8d`.

## Verified on device

Jeremy walked through the cycle on the iPhone:

- ✅ Take pictures
- ✅ Submit → avatar generated and displayed in the QA sheet
- ✅ Kill the app, reopen → player row shows the avatar (not initials)
- ✅ Tap player → CaptureFlow shows the "Test panel ready" chip → tap
  → sheet reappears with the same image

The two retake/re-roll edge cases (avatar deletes when you retake the
gate photo; avatar overwrites when you re-roll) were not explicitly
walked through on device but the code path is straightforward and
tests cover both `overwrite` and `delete`.

## Open items

None. Slice is shipped, pushed, issue closed.

## Don't break

Carrying forward from prior handoffs, plus slice-6-specific:

- The Vertex AI backend choice in `FirebaseAIPanelGenerator.swift`
  (line 9). Still load-bearing.
- The `@retroactive` conformance on `PanelRequirement: Identifiable`
  in `CampComics/CampComics/PanelRequirement+Identifiable.swift`.
- SourceKit's "No such module 'UIKit'" / "No such module 'FirebaseAI'"
  / "No such module 'CampComicsCore'" / "No such module 'Testing'"
  warnings are all false positives. `xcodebuild` and `swift test` are
  the source of truth.
- SSH commit signing needs `ssh-add ~/.ssh/github_ed` once per shell.
- The legacy `_legacy/` Python pipeline still renders end-to-end.
  Don't touch it.
- **Slice 6 specifics:**
  - The avatar filename is `panels/qa_avatar.png`, deliberately
    distinct from the future `panel_NN.png` files (PRD §169). It's
    the avatar/preview, not part of the 12-panel story arc; don't
    collapse them into one naming scheme without thought.
  - `saveQAPanel` writes the raw bytes returned by Gemini. They're
    PNG today, but the `.png` extension is by convention — the round
    trip is just `Data → UIImage(data:)`. Don't add any re-encoding
    step (it would re-compress).
  - `ContentView` reloads every player's avatar on `refresh()`. With
    ~60 players that's 60 file reads + UIImage decodes; fine at camp
    scale but if the list ever grows past a few hundred, lazy-load
    per-row.

## Load-bearing context to read

1. `CLAUDE.md` — orientation, gotchas, terminology.
2. `docs/handoff/2026-05-25-slice-5-shipped.md` — prior handoff.
3. `docs/prd/iphone-intake.md` — §169 (PlayerStore interface) is now
   partially realized: photos ✅, tokens ✅, qa_avatar ✅, numbered
   panels ❌, comic.pdf ❌.
4. `git show bd05b8d` — the slice 6 commit.
5. Memory at
   `~/.claude/projects/-Volumes-MacMiniDock-dev-camp-comics/memory/`
   — `project_slice_6_shipped.md` was added this session.

## Suggested skills

- **`tdd`** — both (a) and (b) have pure-Swift pieces worth driving
  red-green-refactor. Template loading + parsing has natural test
  shapes.
- **`verify`** — confirm whatever ships works on Jeremy's iPhone
  before declaring done. Convention requires it.
- **`diagnose`** — Vertex AI quota / permission errors are still the
  most likely runtime surprise during a real cohort.
- **`to-issues`** — if Jeremy picks option (c), `/to-issues` the
  numbered-panel work into slices before starting.
- **`handoff`** — at the end of the next session. Write to
  `docs/handoff/YYYY-MM-DD-*.md`, **not** `/tmp` (project convention
  overrides the skill default).

## Verdict

Avatar persistence works end-to-end. The iPhone app now does:
intake → capture → save → Gemini → save avatar → and survives
kill/restart with everything intact and reachable. The remaining
v1 surfaces are: more classes (#1 + #2 — easy), the 12-panel
generation loop (big — needs scoping), and the PDF render.

Open the next session by asking the (a)/(b)/(c) question, then
start from there.
