# Handoff — 2026-05-24 — start the SwiftUI iPhone app

**For the next Claude session that picks up this project.**
**Author:** previous Claude session, written for cold-start consumption.

## Your goal

Build the real iPhone (SwiftUI) app described in `docs/prd/iphone-intake.md`.
This is a sustained, multi-session piece of work — don't expect to finish in one.
This document gives you enough to start without re-interviewing Jeremy.

## What was decided over the previous session (today)

1. **Pivot from Python/Flask to a self-contained iPhone app.** The Mac is out of the production path. The phone calls Vertex AI (via Firebase AI Logic) or the public Gemini API directly, and renders the PDF on-device via WKWebView → UIPrintPageRenderer.
2. **Template-driven 5-ish-shot photo capture.** Each panel in a class YAML declares an `(emotion, position)` requirement. The capture plan is the deduplicated union of those requirements for the chosen class. Resolver is a direct lookup, no fallback.
3. **Class is picked at intake** (the old "finalize" step collapses into the intake form).
4. **Cohort assignment is a separate later screen** and *never* changes a player's class. If 30 players pick wizard, some cohorts simply have multiple wizards.
5. **Manual class change is a rare, separate action** from the player detail screen, with a "needs re-shoot" warning if the new class's template needs photos the player didn't capture.
6. **"Player" replaces "camper"** in all new code and docs. Legacy Python keeps the old name since it's moving to `_legacy/`.
7. **Cloud auth**: Firebase AI Logic primary (preserves the "adult faces not used for training" guarantee), public Gemini API key fallback (for friends sideloading without a Firebase project). Both paths require explicit setup; app never ships with an embedded key.
8. **Tests for v1**: `CaptureStateMachine` (Swift, pure) and `PhotoReferenceResolver` (Swift, pure). Bonus: `CapturePlanner` if quick. No tests for the legacy Python.
9. **iPhone-only target, sideload via Xcode** for v1 (free Apple Developer, 7-day re-sign). TestFlight ($99/yr) deferred.

## What's still open

Three things Jeremy needs to decide before you can build wholeheartedly:

1. **Capture-flow variant.** A mobile-web prototype with three variants (`A` story cards / `B` checklist / `C` coach) is committed at `prototype/intake-mobile/` (commit `63f6fac`). Jeremy looked at all three on his phone and said "looks good" but did not pick a winner. **Ask him which variant won, or which parts of each.** The previous session's last unanswered question to him was exactly this.
2. **Firebase project setup.** The PRD assumes a Firebase project linked to Jeremy's GCP. As of handoff, this isn't done. Jeremy will need to create it himself (web console) and drop `GoogleService-Info.plist` into the Xcode project. Don't try to do this for him.
3. **App name / bundle identifier.** PRD placeholder is `com.jeremypruitt.campcomics`. Confirm or change.

## The load-bearing context you need to read

In rough priority order:

1. **`CLAUDE.md`** at the repo root — orientation, terminology, gotchas, conventions. Already configured with a `## Agent skills` block.
2. **`docs/prd/iphone-intake.md`** — the PRD. Read it end-to-end before designing anything. Glossary, user stories (40 of them), module sketch (15 modules), test targets, open risks.
3. **`spec/design.md`** — canonical product design (12-panel arc, palette, prompt anatomy, failure modes). Pre-dates the iPhone pivot but is still the truth on what the comic *is*.
4. **`templates/druid.yaml`** — the canonical class template; you'll need to add `emotion:` / `position:` per panel (the PRD §"Template-driven capture plan" explains the model). Look at the prototype's `index.html` for the hand-tagged druid mapping I used (panels 1–12 + cover, the dedup → 6 photos).
5. **`prototype/intake-mobile/`** — runnable mobile-web prototype. The three variant components in `index.html` show three takes on the capture UX; pick whichever Jeremy lands on and port the spirit (not the code) into SwiftUI.
6. **Memory store at `~/.claude/projects/-Volumes-MacMiniDock-dev-camp-comics/memory/`** — `MEMORY.md` is the index. Read `user-jeremy`, `project-iphone-pivot`, `glossary-player`, `feedback-persist-context`. Update aggressively as you make decisions.

## First three things to do

1. **Ask Jeremy which variant won** (and his answers to the other two open items above). Don't start Xcode work on speculation.
2. **Move the Python code to `_legacy/`** to make it visible that it's a sandbox, not the production path. The legacy code should *still run* from there (intake_server.py, generate.py, render.py) — useful for prompt iteration. Re-run an end-to-end render of one test camper to confirm nothing broke from the move.
3. **Scaffold the Xcode project.** Single SwiftUI app, iPhone-only target, named per Jeremy's choice. First module to build: `CapturePlanner` (pure, ~30 lines, easy to write the test first). Then `CaptureStateMachine`. These two are testable in isolation and validate the model before any UI work.

## What's already on GitHub

- Repo: https://github.com/jeremypruitt/camp-comics (private, `jeremypruitt` owner).
- 5 git commits on `main`, all already pushed.
- Labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`.
- No issues yet — `/to-issues` against the PRD is a reasonable next step if Jeremy wants to break the SwiftUI build into ticketed tracer-bullet slices.

## Servers / background processes

- Mobile-web prototype is running at `python3 -m http.server -d prototype/intake-mobile 8000`. It may still be running in the previous session's background; if not, Jeremy can restart it himself with that one command. Phone URL: `http://192.168.4.31:8000` (his Mac's LAN IP at handoff time — may have changed).

## How Jeremy likes to be talked to

(From memory `user-jeremy.md`.)

- Terse, direct. Don't repeat his question back at him.
- He'll redirect mid-stream if you go the wrong way — let him; don't ask permission for every choice.
- He's comfortable reading Python and SwiftUI; you don't need to over-explain code. He's *not* a deep iOS expert — explain Xcode-specific quirks if relevant.
- He lost a session to a crash today, so persist context aggressively (CLAUDE.md, memory, this kind of handoff doc).

## Don't break

- The legacy Python pipeline can still render one of the three test campers end-to-end — don't break that during the move to `_legacy/`. It's Jeremy's prompt-iteration sandbox.
- The committed `templates/refs/*_hero.png` files are pre-camp Stage 0 artifacts that took real iteration to produce — never re-generate them carelessly.
- Don't sweep-rename `camper` → `player` in the Python code; that code is moving to `_legacy/` and keeping the old name there is fine (this was an explicit decision — see memory `glossary-player`).

## Verdict from the prototype

**Winner: Variant B — Checklist.** Confirmed 2026-05-24 by Jeremy in the
follow-up session. The SwiftUI capture flow ports the spirit of variant B:
all required shots visible at once on one screen, tappable in any order, a
small per-row preview with retake, and a single "submit" gated on all rows
being green. Variants A (story cards) and C (coach) are not being built.
