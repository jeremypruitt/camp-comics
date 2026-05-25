# Handoff — 2026-05-25 (fourth session of the day) — slice 5 shipped

**For the next Claude session that picks up this project.**
**Author:** the 2026-05-25 Claude session that shipped slice 5
(filesystem photo + profile persistence).

## Where we are

**Slice 5 is shipped and verified on Jeremy's iPhone 16 Pro Max.**
Captures and player profiles now survive app kill / restart. The full
loop works: capture photos → kill app → reopen → players list shows
the player → tap to resume → photos restored → Submit still hits Gemini.

One commit on `main` (local — auto-mode blocked the push, see "Open
items" below):

- `23d0a1a` — slice 5: `PlayerStore` in `CampComicsCore` owning the
  on-disk layout from PRD §169 + §184:

      Documents/players/player_NNN/tokens.json
      Documents/players/player_NNN/photos/{emotion}_{position}.jpg

  ContentView is now a players list with **+ New player**; tapping a
  row resumes the CaptureFlow with photos hydrated from disk.
  `PlayerProfile` (app-only struct) deleted in favor of `PlayerRecord`
  (in core, `Hashable + Codable + Sendable`). 13 new XCTests cover
  sequential numbering (gap-tolerant), tokens.json round-trip, photo
  bytes round-trip + overwrite + delete, filename encoding for every
  `(emotion, position)` pair, and `capturedRequirements` reading from
  disk. Full suite 42/42 green.

Closes issue #4.

## Issues on GitHub

After this session:

- **#1** — Load class templates from app bundle (slice 2) —
  https://github.com/jeremypruitt/camp-comics/issues/1 — `ready-for-agent`
- **#2** — Tag remaining five class templates with `(emotion, position)`
  (slice 3) — https://github.com/jeremypruitt/camp-comics/issues/2 —
  `ready-for-agent`
- **#3** — closed (Gemini QA-gate, slice 4)
- **#4** — closed (filesystem persistence, slice 5)

Plus one candidate that isn't on GitHub yet — **panel persistence**, see
below.

## Recommended next slice

**Three reasonable options. Ask Jeremy which.**

**(a) Panel persistence.** On verify Jeremy said *"I cant get to the
avator thing though"* — meaning the QA-generated test panel isn't
retained across app restart. PRD §169 calls for
`panels/panel_NN.png` per player. Slice would: persist the QA-gate
panel + restore it in the players-list / capture-flow when a player
already has one. Natural extension of slice 5. **Not yet a GitHub
issue** — `/to-issues` it before starting.

**(b) Issue #2 — tag the other 5 class templates.** Mechanical YAML
edits (warrior, wizard, bard, healer, trickster). Wizard already has a
draft mapping in `prototype/intake-mobile/index.html`. Tracer-bullet:
tag one class, add a parsing test, repeat. User-visible only after #1
lands.

**(c) Issue #1 — load class templates from the app bundle.** Today
`BundledTemplates` hardcodes druid only. This slice reads
`templates/{class}.yaml` files via the existing `TemplateLoader`, so
adding a class becomes a YAML edit instead of a Swift edit.

Recommendation lean: **(a)** — it's the most product-visible follow-up
(Jeremy explicitly noticed the gap on verify) and stays in the same
"persist what the app produces" lane as slice 5. **(b)** is shortest;
**(c)** unlocks **(b)**. Don't start without asking.

## What got built this session (don't repeat)

Two new files, four modified, one deleted:

- **NEW** `CampComicsCore/Sources/CampComicsCore/PlayerStore.swift` —
  pure file-backed `struct PlayerStore: Sendable`. Constructor takes an
  injectable root `URL` so tests use a tmpdir and the app uses
  `PlayerStore.documentsRoot()`. `PlayerRecord` value type is the
  `tokens.json` schema (id / playerName / characterName / classKey /
  createdAt). Filename encoding/decoding is a static pair of methods
  on the store so views and tests share them.
- **NEW** `CampComicsCore/Tests/CampComicsCoreTests/PlayerStoreTests.swift`
  — 13 tracer-bullet tests.
- **MODIFIED** `CampComics/CampComics/CampComicsApp.swift` — owns the
  single `PlayerStore` instance, injects into `ContentView`.
- **MODIFIED** `CampComics/CampComics/ContentView.swift` — players list
  + intake sheet + navigation; calls `store.create()` on intake submit
  and `store.list()` on appear.
- **MODIFIED** `CampComics/CampComics/IntakeFormView.swift` — callback
  shape changed to `(name, characterName, classKey) -> Void` so the
  caller (which holds the store) materializes the `PlayerRecord`.
- **MODIFIED** `CampComics/CampComics/CaptureFlowView.swift` — takes a
  `PlayerRecord` + `PlayerStore`, hydrates `photoStore` + `captureState`
  from disk in `init`, calls `store.savePhoto` on capture and
  `store.deletePhoto` on retake/discard.
- **DELETED** `CampComics/CampComics/PlayerProfile.swift` — replaced
  by `PlayerRecord`.

Reference: `git show 23d0a1a`.

## Verified on device

Jeremy walked through the cycle on the iPhone:

- ✅ Take pictures
- ✅ Generate test panel via Gemini (slice 4 unaffected)
- ✅ Leave the app, come back, captured photos restored
- ❌ QA-generated panel ("avatar") not restored — by design (out of
  scope, called out in issue body); becomes candidate slice (a) above

## Open items

1. **Push `23d0a1a` to `origin/main`.** Auto-mode blocked the push (it
   doesn't permit direct-to-`main` without explicit user OK). Jeremy
   needs to either `git push origin main` himself or grant the
   permission. No conflicts expected — clean fast-forward.
2. **File panel persistence as a GitHub issue** if (a) is chosen.
   `/to-issues` works; can also just `gh issue create` inline.

## Don't break

Carrying forward from prior handoffs, plus slice-5-specific:

- The Vertex AI backend choice in `FirebaseAIPanelGenerator.swift`
  (line 11). Still load-bearing.
- The `@retroactive` conformance on `PanelRequirement: Identifiable`
  in `CampComics/CampComics/PanelRequirement+Identifiable.swift`.
- SourceKit's "No such module 'UIKit'" / "No such module 'FirebaseAI'"
  / "No such module 'CampComicsCore'" / "No such module 'Testing'"
  warnings are all false positives. `xcodebuild` and `swift test` are
  the source of truth.
- SSH commit signing needs `ssh-add ~/.ssh/github_ed` once per shell.
- The legacy `_legacy/` Python pipeline still renders end-to-end. Don't
  touch it.
- **Slice 5 specifics:**
  - `PlayerStore` is a `struct` (Sendable for free). If you make it a
    `class`, you'll need to think about isolation.
  - `tokens.json` deliberately does NOT carry the photos list — the
    `photos/` directory listing is the source of truth, and PRD §185's
    "photos field for debug/recovery" hasn't been wired yet (skip
    until concretely needed).
  - Filename encoding is `{emotion}_{position}.jpg` with lowercase raw
    values. Don't change without updating `parseFilename`.
  - `nextId()` picks max-existing + 1. After deletion the ID is not
    reused (tested).

## Load-bearing context to read

1. `CLAUDE.md` — orientation, gotchas, terminology.
2. `docs/handoff/2026-05-25-slice-4-shipped.md` — prior handoff.
3. `docs/prd/iphone-intake.md` — §169 (PlayerStore interface) + §184
   (on-disk layout) + §185 (tokens.json shape) all touched by this
   slice; §169's panel-persistence call is candidate slice (a).
4. `git show 23d0a1a` — the slice 5 commit.
5. Memory at
   `~/.claude/projects/-Volumes-MacMiniDock-dev-camp-comics/memory/`
   — `project_slice_5_shipped.md` was added this session.

## Suggested skills

- **`to-issues`** — file panel persistence as a GitHub issue if Jeremy
  picks slice (a).
- **`tdd`** — both (a) and (b) have pure-Swift pieces worth driving
  red-green-refactor. Panel persistence has a natural extension to
  `PlayerStore` (add `savePanel` / `loadPanel`); template tagging has
  YAML parsing tests already in shape.
- **`verify`** — confirm whatever ships works on Jeremy's iPhone
  before declaring done. Convention requires it.
- **`diagnose`** — Vertex AI quota / permission errors are still the
  most likely runtime surprise during a real cohort.
- **`handoff`** — at the end of the next session. Write to
  `docs/handoff/YYYY-MM-DD-*.md`, **not** `/tmp` (project convention
  overrides the skill default).

## Verdict

Persistence works. The iPhone app now does: capture → save to disk →
Gemini → and survives kill/restart with photos intact. The next
obvious gap (Jeremy noticed it on verify) is that the *generated*
panel doesn't survive — that's slice (a) above. The two stale
GitHub issues (#1, #2) are still good options if Jeremy wants to
broaden classes instead of deepening persistence.

Open the next session by asking the (a)/(b)/(c) question, then start
from there.
