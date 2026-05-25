# Handoff — 2026-05-25 — build the Variant B capture UI

**For the next Claude session that picks up this project.**
**Author:** the 2026-05-25 Claude session, written for cold-start consumption.

## Your goal

Build the **Variant B "Checklist" capture UI** in SwiftUI, wired against the
existing `CampComicsCore` types. The first vertical slice is the per-player
checklist screen — see the spirit of `prototype/intake-mobile/index.html`'s
Variant B (commit `63f6fac`). No camera yet; start with the screen shape
backed by mock photos so the layout and state-machine bindings land first.

## What got built today (don't repeat)

Everything is captured in commits and code; this is just the index:

- `9309a7b` — Moved the Python pipeline under `_legacy/` (sandbox only;
  still runnable from `_legacy/scripts/intake_server.py`). `templates/`
  stayed at the root because the iOS app and the legacy code both read it.
- `4a14255` — Added the `CampComicsCore` Swift Package with `CapturePlanner`
  + `CaptureStateMachine` and 16 passing Swift Testing cases. Pure Swift,
  no UI/Firebase coupling.
- `5e15c95` — Gitignore cleanup (stopped tracking `.build/`).
- `fd1a09a` — Scaffolded the SwiftUI app at `CampComics/`, wired Firebase
  (FirebaseAI + FirebaseAnalytics via SwiftPM), dropped in the plist,
  called `FirebaseApp.configure()` in the App init. `xcodebuild` clean.

The Variant B winner decision, bundle ID, Firebase setup details, etc. all
live in commit messages and `~/.claude/projects/-Volumes-MacMiniDock-dev-camp-comics/memory/`.
Read those, not summaries here.

## What's still open

Three things worth deciding before you start writing UI:

1. **YAML extension scope.** Templates need per-panel `emotion:` + `position:`
   fields before `CapturePlanner` can resolve real-world plans. Druid's
   mapping is already hand-tagged in `prototype/intake-mobile/index.html`.
   The other five (warrior, wizard, bard, healer, trickster) need the
   same. Decide: tag all 6 now, or just druid for the first vertical slice
   and tag the rest opportunistically? **Ask Jeremy.**
2. **Template parsing strategy.** Three viable approaches:
   (a) bundle Yams (a SwiftPM YAML lib) and parse `templates/*.yaml` at runtime;
   (b) convert YAML → JSON at build time and bundle JSON;
   (c) hand-port the 6 templates to Swift static data inside the app.
   (a) is the cleanest "single source of truth" but adds a dependency.
   (c) is zero-dep but means YAML and Swift can drift. **Ask Jeremy.**
3. **First vertical slice.** Pick a tracer bullet: probably
   *intake form → class picker → CaptureFlowView (Variant B) with mock
   photos*. No camera, no Firebase calls yet. Validates the model end-to-end
   before adding I/O. Then a second slice adds the camera, a third adds
   the actual AI call.

## The load-bearing context you need to read

In rough priority order:

1. `CLAUDE.md` — orientation, terminology, gotchas, paths.
2. `docs/prd/iphone-intake.md` — the PRD. Still authoritative.
3. `docs/handoff/2026-05-24-start-swift-app.md` — the previous handoff.
   Read it for the decisions taken on day 1 of the iPhone pivot.
4. **This document.**
5. `prototype/intake-mobile/index.html` — the visual model. Variant B is
   the chosen UX; the other two are reference only. Look at how the prompt
   copy in `PROMPTS` maps `(emotion, position)` → user-facing copy + emoji —
   the SwiftUI port should reuse the spirit of that vocabulary.
6. `CampComicsCore/Sources/CampComicsCore/` — the types you'll bind UI to.
   `CaptureState` is the model your SwiftUI view watches.
7. `templates/druid.yaml` — the canonical template; you'll need to add
   `emotion:`/`position:` per panel before `CapturePlanner` resolves anything
   meaningful for a real player.
8. Memory store at `~/.claude/projects/-Volumes-MacMiniDock-dev-camp-comics/memory/` —
   `MEMORY.md` is the index. The `user-jeremy`, `feedback-*`, `glossary-player`,
   and `project-variant-winner` memories are the ones most likely to bite if
   ignored.

## First three things to do

1. **Ask Jeremy the two open questions above** (YAML scope + parsing
   strategy). Don't speculate.
2. **Tag whatever templates Jeremy agrees to extend** with `emotion:`/
   `position:` per panel. The druid mapping is already in the prototype —
   port it verbatim. For other classes, use the same `(neutral, joy,
   surprise, fear) × (front, profile)` vocabulary.
3. **Build a `CaptureFlowView` (or whatever you name it) in SwiftUI** that
   takes a `CaptureState` and renders Variant B's checklist. Backed by mock
   `CapturedPhoto` records (no camera). Get the visual right, get the
   submit-button gating right (driven by `CaptureState.isReadyToSubmit`).

## What's already on GitHub

- Repo: <https://github.com/jeremypruitt/camp-comics> (private,
  `jeremypruitt` owner).
- This session's 4 commits are **local only** — Jeremy explicitly chose
  to keep them off the remote for now. Push when you (or Jeremy) decide.
- Labels: `needs-triage`, `needs-info`, `ready-for-agent`,
  `ready-for-human`, `wontfix`.
- No issues yet — `/to-issues` against the PRD or this handoff is a
  reasonable next step once the first slice has shape.

## Servers / background processes

- **Mobile-web prototype** was running on the previous session at
  `http://192.168.4.31:8000`. May not be running now. Restart with
  `python3 -m http.server -d prototype/intake-mobile 8000` if needed.
- **Firebase** project is `camp-harness` (the existing GCP project with
  Firebase added on). AI Logic + AI Monitoring are enabled. Jeremy is the
  sole admin.
- **iPhone code signing** works now — free Apple ID + Personal Team, with
  Jeremy's physical iPhone registered as a provisioned device. Don't try
  to switch teams or change the bundle ID.

## How Jeremy likes to be talked to

(Persisted from previous handoff + `user-jeremy.md`.)

- Terse, direct. Don't repeat his question back at him.
- He'll redirect mid-stream if you go the wrong way — let him; don't ask
  permission for every choice.
- He's comfortable reading Python and Swift but is *not* a deep iOS expert.
  Explain Xcode-specific quirks if relevant; don't over-explain code.
- He lost a session to a crash on 2026-05-23; persist context aggressively
  (memory, this kind of handoff doc, CLAUDE.md updates).
- Use Swift Testing (`@Test` / `#expect`) not XCTest for new unit tests —
  the project picked that already.
- Don't try to commit silently — git commit signing requires the SSH key
  passphrase, which needs an interactive `ssh-add ~/.ssh/github_ed` first.
  If a commit hangs, that's why.

## Don't break

- The legacy Python pipeline still renders end-to-end from `_legacy/`.
  Verified at the end of the previous session. Don't break it; it's
  Jeremy's prompt-iteration sandbox.
- The committed `templates/refs/*_hero.png` files are pre-camp Stage 0
  artifacts; never re-generate them carelessly.
- Don't sweep-rename `camper → player` in `_legacy/` Python code.
- Bundle ID is `me.jeremypruitt.CampComics` (capital C/C). Apple's
  bundle-ID registration won't let us switch to lowercase after the
  capital-case one auto-registered. Don't try.
- `**/intake/*/photo.jpg` and `**/intake/*/qa_test.png` are gitignored on
  purpose — face data stays out of git by default. Don't unignore without
  asking.
- `CampComics/.git/` is **not** wanted — Xcode tried to nest a repo
  despite the wizard checkbox being off. If it reappears, delete it
  (don't accidentally treat it as a submodule).

## Suggested skills for the next session

(Per the `handoff` skill convention.)

- **`prototype`** — if you need to sanity-check a UI question before
  paying SwiftUI's compile-and-run cost.
- **`tdd`** — for new pure-Swift modules added to `CampComicsCore`
  (template loader, prompt copy resolver, etc.). The test framework is
  already set up.
- **`grill-with-docs`** — early in the session, to stress-test the
  planned approach against the PRD's terminology and (once we have them)
  the `CONTEXT.md` + ADRs. Lazily create those if not yet present.
- **`diagnose`** — for any Xcode/Firebase weirdness.
- **`to-issues`** — once the first vertical slice has shape, break the
  remaining work into tracer-bullet issues.
- **`caveman`** — if Jeremy says "be brief" or wants to cut tokens.
- **`handoff`** — at the end of next session. Note that the skill writes
  to `/tmp` by default (ephemeral) — Jeremy's project convention is
  `docs/handoff/YYYY-MM-DD-*.md` (durable, version-controlled). Honour
  the convention.

## Verdict for the next session

There's no single open question carried over (unlike the previous
handoff). The two real decisions waiting are listed under **What's still
open** above. Ask both at the top of the session and don't start coding
templates or UI until Jeremy answers.
