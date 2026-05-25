# PRD: Camp Comics iPhone App

**Status:** ready-for-agent
**Created:** 2026-05-24 (revised same day)
**Owner:** Jeremy

This PRD describes the migration of Camp Comics from a Python/Flask web pipeline
running on a Mac to a self-contained iPhone (SwiftUI) app that runs the entire
camp-week workflow on one device, calling Vertex AI (via Firebase) or the public
Gemini API directly from the phone.

## Glossary

- **Player** — the person whose photos and tokens become a personalized comic book. Formerly "camper"; renamed project-wide 2026-05-24.
- **Class** — one of six character classes (druid, warrior, wizard, bard, healer, trickster). Each class has a template.
- **Template** — the class YAML file (`templates/{class}.yaml`) that declares the 12 panels of the story arc, their captions, scenes, and now their **photo requirements** (an `(emotion, position)` pair per panel — see Implementation Decisions §4).
- **Capture plan** — the deduplicated set of `(emotion, position)` pairs the chosen class's template requires. The capture plan is *derived* from the template, not fixed.
- **Cohort** — a group of players who play together as a party. Replaces the older `cabin` (where they sleep) and the never-introduced `table` (D&D group) concepts with one abstract term. A player belongs to exactly one cohort.
- **Cohort assignment** — distributing players across cohorts to give each cohort a healthy class mix. Classes are not changed during cohort assignment; if 30 of 60 players picked wizard, some cohorts will simply have multiple wizards. Done in a dedicated screen, not at intake.

## Problem Statement

The current Camp Comics pipeline only runs on the staffer's Mac. A player walks
up to a laptop + tripod photo station, then the staffer translates raw tokens,
generates panels, and renders PDFs back at the laptop. This is:

- **Fragile in practice** — the Mac is a single point of failure; setup at an
  actual camp (LAN, tripod, lighting, monitor) is fiddly. Jeremy already lost
  a working session to a crash.
- **Awkward as a UX** — a tripod-mounted laptop is a much worse camera than
  any modern phone; the player has to stand in one spot and trust an interface
  they can't see.
- **Hard to share** — Jeremy wants to try it with a friend before the actual
  camp. "Install Python, set up a venv, install WeasyPrint, configure
  gcloud, run the Flask server" is not a try-out experience.
- **Single-photo bottleneck** — the pipeline uses one photo per player as the
  canonical reference for all 13 generations. That photo's expression bleeds
  into every panel, flattening the emotional range of the story arc.

## Solution

A native iPhone app (SwiftUI) that owns the entire player workflow end-to-end,
needs only an internet connection (no Mac, no laptop, no LAN setup), and can
be sideloaded onto another person's phone for try-out.

The capture step is **template-driven**: each panel in the chosen class's
template declares the `(emotion, position)` it needs (e.g. panel 7 "the
challenge appears" needs `(fear, front)`; the cover needs `(any, 3⁄4-profile)`).
The app computes the deduplicated set of `(emotion, position)` pairs across
all 12 panels + cover, and that becomes the capture plan for that player.
Simpler templates need fewer photos; richer templates need more.

Class is picked at intake (not in the evening), so the capture plan is known
before the camera opens. Cohort balancing happens later as a separate review
screen, not as a constraint at intake time.

Image generation uses Vertex AI via Firebase AI Logic (Jeremy's primary path,
preserving the spec's "adult faces not used for training" guarantee). A
fallback path uses the public Gemini API with a user-supplied API key for
friends sideloading the app without a Firebase project. Both paths require
explicit setup; the app never ships with an embedded key.

The existing Python/Flask code moves to `_legacy/` as a sandbox for prompt
experimentation; it is not part of the production path.

## User Stories

### Setup and onboarding

1. As Jeremy sideloading the app onto my own phone, I want a one-time setup screen that detects my Firebase config and connects me to my Vertex AI project, so that I don't have to re-authenticate each session.
2. As a friend sideloading the app, I want a setup screen that accepts a public Gemini API key (Jeremy's or my own from aistudio.google.com), so that I can try the app without setting up a GCP/Firebase project.
3. As any user, I want clear inline guidance on how to obtain an API key (with a tappable link to aistudio.google.com), so that I can complete setup without leaving the app to hunt for docs.
4. As a user, I want the app to remember my API key / Firebase config across launches, so that I'm not re-prompted every time.
5. As a user, I want a way to switch between the Firebase path and the public-Gemini path in settings, so that I can fall back if one breaks.

### Day 1 — Player intake at the photo station

6. As a camp staffer, I want to tap "New player" on the main screen, so that I can start a fresh intake without seeing other players' data on the form.
7. As a camp staffer, I want to enter the player's name and character name (optional) in a single short form, so that intake is fast. (Cohort is assigned later in a dedicated screen, not at intake.)
8. As a camp staffer, I want to **pick the class at intake** (defaulting to a list of all six, no top-3 ranking), so that the capture plan is determined before the camera opens.
9. As a camp staffer, I want to capture the player's three raw tokens (hometown landmark, fear, quality) and the class-specific token in a single intake form, so that translation can happen mid-week without a separate "finalize" step.
10. As a camp staffer, I want the form to validate that all required fields are filled before advancing to capture, so that I don't lose a player because a field was missed.

### Day 1 — Template-driven photo capture

11. As a camp staffer, I want the capture flow to derive its shot list from the chosen class's template (deduplicated `(emotion, position)` pairs), so that I capture exactly what that template needs — no more, no less.
12. As a camp staffer, I want the deduplicated capture plan shown up front ("This class needs 4 photos: neutral-front, joy-front, fear-front, neutral-3⁄4"), so that I know how long the session will take.
13. As a camp staffer, I want a guided capture flow that walks the player through each required shot in a sensible order (all front-facing first, then any profile shots), so that the player isn't whipsawed between positions.
14. As a camp staffer, I want each shot to show a clear prompt on screen ("Look neutral, mouth closed" / "Big smile" / "Look scared" / "Look surprised" / "Turn 45° to the side, whichever feels natural"), so that I don't have to remember the script.
15. As a camp staffer, I want a tappable preview after each shot with accept/retake buttons, so that a bad shot is fixed in the moment, not discovered mid-week.
16. As a camp staffer, I want each shot to use the front-facing OR rear camera (configurable, default rear), so that the player can see what they look like during the shot if I want them to.
17. As a camp staffer, I want a single test generation (the existing QA gate, run against the neutral-front shot) before the player leaves the station, so that I catch unusable photo sets at the source.

### Cohort assignment (separate later screen)

18. As a camp staffer, I want a "cohort assignment" screen accessible from the dashboard that shows all submitted players and lets me drag them into named cohorts, so that I can group players into parties.
19. As a camp staffer, I want each cohort row to show its current class composition (e.g. "Cohort A: 2× wizard, 1× druid, 1× bard"), so that I can see imbalance at a glance and try to mix classes within each cohort.
20. As a camp staffer, I want the screen to suggest a starting cohort assignment (round-robin by class, balancing cohort sizes), so that I don't start from a blank slate.
21. As a camp staffer, I want the screen to *not* force class changes — if 30 players pick wizard, the screen just shows me that several cohorts will have multiple wizards, and accepts that as a fact rather than blocking save.
22. As a camp staffer, I want to rename cohorts ("Party of the Sun", "Party of the Tides", etc.) so that the printed output and dashboard use meaningful labels.

### Manual class change (rare, separate from cohort assignment)

23. As a camp staffer, I want to change a player's assigned class from their detail screen (not from the cohort assignment screen), so that the rare case of a player changing their mind has a clear path.
24. As a camp staffer, I want a class change to warn me if it requires capturing photos the player doesn't have (because the new class's template uses `(emotion, position)` pairs that weren't in the original capture), so that I know whether the player needs to come back to the photo station.
25. As a camp staffer, I want a "needs re-shoot" worklist on the dashboard listing any players whose class change left their photo set incomplete, so that I don't lose track of who to pull aside.

### Mid-week — Token translation

26. As a camp staffer, I want a "translate" action per player that shows each raw token alongside a textarea for the fantasy-fragment translation, so that the highest-skill step has a focused screen.
27. As a camp staffer, I want a "suggest" button per token that asks Gemini for 3 candidate fantasy fragments based on the player's class palette, so that I have a starting point instead of a blank textarea.
28. As a camp staffer, I want to edit any suggested fragment before accepting it, so that the player's own voice doesn't get washed out by AI suggestions.

### Days 3–4 evenings — Panel generation

29. As a camp staffer, I want to tap "generate" on a player to enter a per-panel review loop, so that I can drive 13 generations (12 panels + cover) with minimum friction.
30. As a camp staffer, I want each panel to auto-generate when I land on its screen (using the resolved reference photo(s) for that panel's `(emotion, position)` requirement), so that I'm not tapping "generate" twice per panel.
31. As a camp staffer, I want accept / re-roll / re-prompt / skip buttons on each panel, so that I can match the existing 4-attempt re-roll budget.
32. As a camp staffer, I want the per-panel screen to show the attempt count, so that I know when I'm approaching the budget cap.
33. As a camp staffer, I want generation failures (network, API errors, content policy) to show a clear error with a retry button, so that I can recover without losing the player's place.
34. As a camp staffer, I want a per-player progress indicator (X of 13 panels done), so that I know how far I am.

### Day 5 — Render and print

35. As a camp staffer, I want a "render PDF" action per player that produces a final comic.pdf on-device, so that I don't need a Mac running WeasyPrint.
36. As a camp staffer, I want the rendered PDF to match the visual fidelity of the current WeasyPrint output (same layout, same typography, same captions), so that prior layout work is preserved.
37. As a camp staffer, I want to share the rendered PDF via the iOS share sheet (AirDrop, email, save to Files, print via AirPrint), so that I can route it to whatever print path the camp uses.

### Cross-cutting

38. As a camp staffer, I want all player data (photos, tokens, generated panels) to persist locally on the device, so that the app survives crashes and backgrounding.
39. As a camp staffer, I want a way to export all player data (zip of player folders) to the iOS share sheet, so that I have a manual backup option.
40. As a camp staffer, I want the app to work fully offline for *non-generation* tasks (form input, viewing already-generated panels, exporting), so that flaky internet doesn't block intake.

## Implementation Decisions

### App architecture

- **Single SwiftUI app, iPhone-only target.** iPad support is out of scope for v1; SwiftUI can be made universal later without rework.
- **Bundle identifier and app name:** placeholder `com.jeremypruitt.campcomics`.
- **Minimum iOS version:** the lowest version supported by Firebase AI Logic (currently iOS 15 — confirm at implementation time).
- **Distribution:** Xcode sideload to Jeremy's phone (free Apple Developer account, 7-day re-sign cycle); same for a friend's phone. TestFlight ($99/yr Apple Developer Program) deferred until v1 is validated.

### Template-driven capture plan

Each panel in a class template gains two new fields: `emotion` (one of `neutral`, `joy`, `fear`, `surprise`) and `position` (one of `front`, `3-4-profile`). The class hero card and the cover use `(any, 3-4-profile)` or similar.

The capture plan for a player is computed at intake time:

```
capture_plan(class) = unique({ (panel.emotion, panel.position) for panel in class.panels })
                     ∪ { (cover.emotion, cover.position) }
```

Deduplication is essential — if 8 of the 12 panels need `(neutral, front)`, that's still one photo. Goal is fewest photos that cover everything the template needs.

The resolver is a pure function: `resolve(panel) -> Photo`. No fallback — by construction, every `(emotion, position)` the template references was captured at intake time. If the template is later changed (or the class is reassigned via cohort balance), the resolver may raise a "missing photo" error which surfaces in the balance screen (story 20) and the panel-review screen.

### The 11 modules

Modules are organized in two groups: the new iOS app, and the pipeline-contract changes that legacy Python (in `_legacy/`) should mirror so the Python sandbox stays useful for prompt experimentation.

**iOS app (new):**

1. **CaptureStateMachine** (deep, pure Swift, no AVFoundation) — drives the guided capture flow. Initialized from a capture plan (a list of `(emotion, position)` shots in display order). States are "awaiting shot N", events are `shotAccepted`, `shotRetake`, `flowAbandoned`. Testable in isolation.
2. **CameraAdapter** (AVFoundation wrapper) — capture session, photo output, orientation. Driven by the state machine.
3. **IntakeFormView** (shallow) — SwiftUI form: name, character name (optional), **class pick**, three raw tokens, class-specific token. Validates required fields. Produces an `IntakeRecord` that feeds the capture plan. (Cohort is *not* on this form — assigned later via the dedicated screen.)
4. **CapturePlanner** (deep, pure) — `plan(class: ClassTemplate) -> [CaptureShot]`. Computes the deduplicated, display-ordered list of shots from a class template. Testable.
5. **PlayerStore** (deep) — single source of truth for all player data on-device. Encapsulates persistence (file-system layout: `Documents/players/player_NNN/` with `tokens.json` + `photos/{emotion}_{position}.jpg` + `panels/panel_NN.png` + `comic.pdf`). Interface: `create(intake) -> PlayerID`, `load(id)`, `update(id, mutation)`, `delete(id)`, `list()`.
6. **PhotoReferenceResolver** (deep, pure) — `resolve(panel, player) -> Photo`. Direct lookup, no fallback. Raises if photo is missing (only happens after a class reassignment that the balance screen didn't reconcile).
7. **GenerationClient** (deep) — abstract `protocol GenerationClient { func generate(prompt, references) -> Image }` with two implementations: `FirebaseVertexClient` and `PublicGeminiClient`. Caller (PanelReviewView) doesn't know which is in use.
8. **PromptBuilder** (deep, pure) — assembles the panel/cover prompt from the 7-part skeleton in `spec/design.md` §8: scene-with-tokens + composition + costume + palette + style-suffix + aspect-ratio. Mirrors `assemble_panel_prompt()` in legacy `generate.py`.
9. **TranslationClient** (deep) — wraps a text-only Gemini call to suggest 3 fantasy fragments per raw token. Mirrors `suggest_translations()` in legacy `intake_server.py`.
10. **PanelReviewView** (shallow) — per-panel screen: shows pending generation, accept / re-roll / re-prompt / skip buttons, attempt count, error states.
11. **PDFRenderer** (deep) — takes a complete player bundle (12 panels + cover + captions + cover metadata) and produces a `comic.pdf`. Implementation: a `WKWebView` loads an HTML template (ported from `layout/comic.html.j2`), then `viewPrintFormatter` + `UIPrintPageRenderer` → PDFData. Preserves the existing `comic.css` and Jinja-like template structure (Swift will use a minimal mustache-style substitution).
12. **CohortAssignmentView** (shallow) — list of players + named cohorts; drag/drop players into cohorts; round-robin-by-class auto-suggest button; per-cohort class-composition summary. Does **not** change classes. Renaming cohorts ("Party of the Sun") supported.
13. **ClassChangeAction** (in `PlayerStore`, exposed via the player-detail screen) — rare manual change-of-class; warns if the new class's template needs photos the player didn't capture, and adds the player to the "needs re-shoot" worklist if so. Not in the cohort assignment flow.
14. **SettingsView** (shallow) — Firebase config status, public-Gemini API key entry, generation-path toggle, app version, export/import.
15. **AppCoordinator** (shallow) — navigation between Dashboard → Intake → Capture → QA → (Dashboard) → CohortAssignment → Translate → Generate → Render. Each screen pushes/pops; no deep linking for v1.

**Pipeline contract changes (apply to both iOS app and `_legacy/` Python):**

- **Class templates gain photo-requirement fields.** Each panel in `templates/{class}.yaml` gets `emotion: <neutral|joy|fear|surprise>` and `position: <front|3-4-profile>`. The cover entry gets the same.
- **On-disk player layout** (in the iOS app): `Documents/players/player_NNN/photos/{emotion}_{position}.jpg`. Filenames encode the photo metadata; no separate index file needed.
- **`tokens.json`** drops the `class_top_3` field (class is picked directly at intake) and the `cabin` field (replaced by `cohort`, assigned later). The "raw + translated" split stays. Adds a `photos` field listing captured `(emotion, position)` pairs for debug/recovery and a `cohort` field (string label, nullable until cohort assignment runs).
- **Finalize step disappears** as a discrete screen — it's collapsed into intake. The class-specific token (druid's `animal_companion`, etc.) is collected in the same form as the universal raw tokens.
- **`generate.py` reference order changes** (in the legacy sandbox too, for parity): `[resolved_photo_for_panel, class_hero_card, prior_panel_continuity]`. The primary photo is no longer hard-coded.
- **The QA gate runs against the `neutral_front.jpg` shot only.** That shot is always in the capture plan because the everyday-self panels (1 and 12) need it.
- **`spec/design.md` §5 (tokens) updated**: drop top-3 ranking (class is picked at intake); add note that class-specific token is collected at intake.
- **`spec/design.md` §7 (photo collection protocol) updated**: replace single-photo protocol with template-driven multi-shot capture.
- **`spec/design.md` §10 Stage 1 updated**: collapse intake + QA + finalize into a single station flow.

### Cloud auth

- **Primary path: Firebase AI Logic (Vertex AI in Firebase) Swift SDK.** Preserves the "adult faces not used for training" guarantee from `spec/design.md`. Requires a Firebase project linked to Jeremy's GCP project; iOS app embeds `GoogleService-Info.plist`.
- **Fallback path: public Gemini API.** User pastes their own API key in `SettingsView`; key stored in iOS Keychain (not `UserDefaults`). API key may be Jeremy's (shared via DM with a friend) or the friend's own from aistudio.google.com.
- **Both paths require explicit setup** — the app never ships with an embedded API key. First-launch onboarding requires choosing a path and providing credentials.

## Testing Decisions

A test is good if it would still pass after the implementation is rewritten —
i.e. it tests external behavior, not internal structure. Pure modules with
clear inputs and outputs are the highest-value test targets.

**Test targets:**

1. **CaptureStateMachine** (Swift, XCTest) — verifies the N-shot sequence walks correctly: each `shotAccepted` advances to the next shot; `shotRetake` stays in the same shot; `flowAbandoned` from any state ends the flow; final state is `completed` after the last shot. Parameterized on capture plans of varying lengths. No AVFoundation involved.
2. **PhotoReferenceResolver** (Swift, XCTest) — verifies each panel's `(emotion, position)` maps to the expected captured photo filename. Tests the "missing photo" error path explicitly (simulating a post-reassignment class change). Bonus: a property-style test that asserts `resolve(panel)` always succeeds when the panel's requirement is in the player's capture plan.

**Also worth testing (recommended but not promised for v1):**

- **CapturePlanner** (Swift, pure) — same shape as PhotoReferenceResolver, easy to test, asserts dedup correctness. If I have time, write it; it's ~30 lines of test.

**Not tested for v1:**

- `GenerationClient` implementations (involve real network or heavy mocking; defer until a bug shows up).
- `PDFRenderer` (visual fidelity is the success criterion — eyeball the output, don't unit-test it).
- `PlayerStore` (file I/O; integration test would be useful but not load-bearing for v1).
- The Flask `_legacy/` code (it's a sandbox; it doesn't need to ship-quality).

**Prior art:** none — the repo has no test suite today. The Swift tests will be the first.

## Out of Scope

- **iPad support.** The app is iPhone-only for v1.
- **Multi-device sync.** v1 assumes one staffer holds one device for the whole camp week. Cross-device sync (CloudKit) deferred.
- **TestFlight distribution.** Sideload via Xcode for v1.
- **Background generation.** Generation runs while the app is foregrounded.
- **Per-class emotion enums.** All classes use the same emotion vocabulary (`neutral`, `joy`, `fear`, `surprise`) and same position vocabulary (`front`, `3-4-profile`). If a class wants a unique expression later (`mischievous` for trickster?) the type can be extended; for v1 it's a closed set.
- **Multiple 3⁄4-profile shots (left + right).** v1 captures one 3⁄4 profile per player, whichever side the operator picks at the moment. Side isn't a data dimension.
- **Cabin group-shot panel.** Already deferred in `spec/design.md` §13.
- **Lulu Print API integration.** Already deferred in `spec/design.md` §13.
- **Minors handling.** Already deferred in `spec/design.md` §13.
- **Migration of in-progress Python intake records** to the new iOS storage layout. The three test campers (`camper_001`–`003`) can be finished via the `_legacy/` Flask path; no migration tooling.

## Open Risks

- **Post-class-change photo mismatch.** Cohort assignment never changes a player's class, so the photo set always matches the player's template by construction. The only path that breaks this invariant is the rare manual class-change action (story 23), which surfaces a "needs re-shoot" warning (stories 24–25) and adds the player to a worklist. Empirically expected to be rare. If frequent in practice, future v2: have intake capture the union across all 6 classes (~6–7 photos for everyone, eliminates the warning).
- **PDF visual fidelity via WKWebView.** WKWebView's print output may diverge from WeasyPrint in subtle ways (font hinting, page breaks, image scaling). Worth a 30-minute spike *before* committing to the full implementation: render one existing player's manifest into a PDF via WKWebView and compare side-by-side with the WeasyPrint output. If divergence is bad, fallback options: Core Graphics layout code (more work, total control) or a thin server-side render endpoint (reintroduces the Mac for one job).
- **Sideload UX with the 7-day re-sign cycle.** A friend trying the app will lose access after a week. Acceptable for early try-out; will hurt at the actual camp. The fix is paying for an Apple Developer Program ($99/yr) and using TestFlight. Deferred but should be on the radar.

## Further Notes

- **Why this is the right shape now:** Three of the four most painful operational realities of the current pipeline (Mac setup, sharing with friends, photo-station quality) collapse into "the staffer holds an iPhone." The fourth (cloud cost / API quota) is unchanged — the phone calls Vertex AI / Gemini just like the laptop did.
- **What this PRD doesn't do:** It doesn't prescribe specific UI screens beyond naming the views. The screens are best designed against a `/prototype` SwiftUI sketch (next step after this PRD lands).
- **The Python sandbox remains useful for:** prompt iteration (`scripts/generate.py` is the easiest place to A/B prompts), class YAML editing (Python loads YAML cleanly), and the QA-gate test loop. Move to `_legacy/` but don't delete.
- **Reference:** `spec/design.md` is still the canonical design source. This PRD describes the implementation pivot; the spec should be updated in tandem (sections 5, 7, and 10) to reflect the template-driven capture model.
