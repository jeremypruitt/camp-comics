# PRD: Camp Comics iPhone App

**Status:** ready-for-agent
**Created:** 2026-05-24
**Owner:** Jeremy

This PRD describes the migration of Camp Comics from a Python/Flask web pipeline
running on a Mac to a self-contained iPhone (SwiftUI) app that runs the entire
camp-week workflow on one device, calling Vertex AI (via Firebase) or the public
Gemini API directly from the phone.

## Problem Statement

The current Camp Comics pipeline only runs on the staffer's Mac. A camper walks
up to a laptop + tripod photo station, then the staffer translates raw tokens,
generates panels, and renders PDFs back at the laptop. This is:

- **Fragile in practice** — the Mac is a single point of failure; setup at an
  actual camp (LAN, tripod, lighting, monitor) is fiddly. Jeremy already lost
  a working session to a crash.
- **Awkward as a UX** — a tripod-mounted laptop is a much worse camera than
  any modern phone; the camper has to stand in one spot and trust an interface
  they can't see.
- **Hard to share** — Jeremy wants to try it with a friend before the actual
  camp. "Install Python, set up a venv, install WeasyPrint, configure
  gcloud, run the Flask server" is not a try-out experience.
- **Single-photo bottleneck** — the pipeline uses one photo per camper as the
  canonical reference for all 13 generations. That photo's expression bleeds
  into every panel, flattening the emotional range of the story arc.

## Solution

A native iPhone app (SwiftUI) that owns the entire camper workflow end-to-end,
needs only an internet connection (no Mac, no laptop, no LAN setup), and can
be sideloaded onto another person's phone for try-out.

The capture step is replaced with a **5-shot guided sequence** — neutral, joy,
fear, surprise, and a 3⁄4-angle profile — and downstream panel generation picks
the expression that fits each story beat. Panel 4 ("wow that's me") uses the
joy shot; panel 7 (the challenge appears) uses the fear shot; panel 1 / 12
(everyday self / return home) use the neutral shot; etc.

Image generation uses Vertex AI via Firebase AI Logic (Jeremy's primary path,
preserving the spec's "adult faces not used for training" guarantee). A
fallback path uses the public Gemini API with a user-supplied API key for
friends sideloading the app without a Firebase project.

The existing Python/Flask code moves to `_legacy/` as a sandbox for prompt
experimentation; it is not part of the production path.

## User Stories

### Setup and onboarding

1. As Jeremy sideloading the app onto my own phone, I want a one-time setup screen that detects my Firebase config and connects me to my Vertex AI project, so that I don't have to re-authenticate each session.
2. As a friend sideloading the app, I want a setup screen that accepts a public Gemini API key (Jeremy's or my own from aistudio.google.com), so that I can try the app without setting up a GCP/Firebase project.
3. As any user, I want clear inline guidance on how to obtain an API key (with a tappable link to aistudio.google.com), so that I can complete setup without leaving the app to hunt for docs.
4. As a user, I want the app to remember my API key / Firebase config across launches, so that I'm not re-prompted every time.
5. As a user, I want a way to switch between the Firebase path and the public-Gemini path in settings, so that I can fall back if one breaks.

### Day 1 — Camper intake at the photo station

6. As a camp staffer, I want to tap "New camper" on the main screen, so that I can start a fresh intake without seeing other campers' data on the form.
7. As a camp staffer, I want to enter the camper's name, character name (optional), and cabin in a single short form, so that intake is fast.
8. As a camp staffer, I want to capture the camper's top-3 ranked class choices via tappable chips, so that the cohort-balancing step has the data it needs.
9. As a camp staffer, I want to capture the camper's three raw tokens (hometown landmark, fear, quality) as short freetext, so that translation can happen mid-week.
10. As a camp staffer, I want the form to validate that all required fields are filled before advancing, so that I don't lose a camper because a field was missed.

### Day 1 — 5-shot guided capture

11. As a camp staffer, I want a guided capture flow that walks the camper through 5 shots in a fixed order (neutral → joy → fear → surprise → 3⁄4-profile), so that every camper produces a uniform photo set.
12. As a camp staffer, I want each shot to show a clear prompt on screen ("Look neutral, mouth closed" / "Big smile" / "Look scared" / "Look surprised" / "Turn 45° to the side"), so that I don't have to remember the script.
13. As a camp staffer, I want a tappable preview after each shot with accept/retake buttons, so that a bad shot is fixed in the moment, not discovered mid-week.
14. As a camp staffer, I want to pick whether the 3⁄4-profile shot is left or right (operator's choice per camper, based on which side has better light or whichever feels right), so that I'm not locked into one orientation across all 60 campers.
15. As a camp staffer, I want each shot to use the front-facing OR rear camera (configurable, default rear), so that the camper can see what they look like during the shot if I want them to.
16. As a camp staffer, I want a single test generation (the existing QA gate, run against the neutral shot) before the camper leaves the station, so that I catch unusable photo sets at the source.

### Day 1 evening — Cohort balance and class finalization

17. As a camp staffer, I want a dashboard view listing all campers with their top-3 class choices, so that I can see at a glance whether any class is over-picked.
18. As a camp staffer, I want a "finalize class" action per camper that lets me confirm the assigned class (default = their #1) and collect the class-specific token in their own words, so that mid-week generation has everything it needs.

### Mid-week — Token translation

19. As a camp staffer, I want a "translate" action per camper that shows each raw token alongside a textarea for the fantasy-fragment translation, so that the highest-skill step has a focused screen.
20. As a camp staffer, I want a "suggest" button per token that asks Gemini for 3 candidate fantasy fragments based on the camper's class palette, so that I have a starting point instead of a blank textarea.
21. As a camp staffer, I want to edit any suggested fragment before accepting it, so that the camper's own voice doesn't get washed out by AI suggestions.

### Days 3–4 evenings — Panel generation

22. As a camp staffer, I want to tap "generate" on a camper to enter a per-panel review loop, so that I can drive 13 generations (12 panels + cover) with minimum friction.
23. As a camp staffer, I want each panel to auto-generate when I land on its screen (using the resolved reference photo for that panel beat), so that I'm not tapping "generate" twice per panel.
24. As a camp staffer, I want accept / re-roll / re-prompt / skip buttons on each panel, so that I can match the existing 4-attempt re-roll budget.
25. As a camp staffer, I want the per-panel screen to show the attempt count, so that I know when I'm approaching the budget cap.
26. As a camp staffer, I want generation failures (network, API errors, content policy) to show a clear error with a retry button, so that I can recover without losing the camper's place.
27. As a camp staffer, I want a per-camper progress indicator (X of 13 panels done), so that I know how far I am.

### Day 5 — Render and print

28. As a camp staffer, I want a "render PDF" action per camper that produces a final comic.pdf on-device, so that I don't need a Mac running WeasyPrint.
29. As a camp staffer, I want the rendered PDF to match the visual fidelity of the current WeasyPrint output (same layout, same typography, same captions), so that prior layout work is preserved.
30. As a camp staffer, I want to share the rendered PDF via the iOS share sheet (AirDrop, email, save to Files, print via AirPrint), so that I can route it to whatever print path the camp uses.

### Cross-cutting

31. As a camp staffer, I want all camper data (photos, tokens, generated panels) to persist locally on the device, so that the app survives crashes and backgrounding.
32. As a camp staffer, I want a way to export all camper data (zip of camper folders) to the iOS share sheet, so that I have a manual backup option.
33. As Jeremy, I want the panel→expression mapping to live in a per-class YAML/JSON config bundled in the app, so that I can iterate on it without rewriting Swift code.
34. As Jeremy testing this with a friend, I want the app to work fully offline for *non-generation* tasks (form input, viewing already-generated panels, exporting), so that flaky internet doesn't block intake.

## Implementation Decisions

### App architecture

- **Single SwiftUI app, iPhone-only target.** iPad support is out of scope for v1; SwiftUI can be made universal later without rework.
- **Bundle identifier and app name TBD** — placeholder `com.jeremypruitt.campcomics`.
- **Minimum iOS version:** the lowest version supported by Firebase AI Logic (currently iOS 15 — confirm at implementation time).
- **Distribution:** Xcode sideload to Jeremy's phone (free Apple Developer account, 7-day re-sign cycle); same for a friend's phone. TestFlight ($99/yr Apple Developer Program) deferred until v1 is validated.

### The 11 modules

Modules are organized in two groups: the new iOS app, and the pipeline-contract changes that legacy Python (in `_legacy/`) should mirror so the Python sandbox stays useful for prompt experimentation.

**iOS app (new):**

1. **GuidedCaptureFlow** (deep) — owns the 5-shot guided capture sequence. Internally split into:
   - `CaptureStateMachine` (pure Swift, no AVFoundation) — states are the 5 expressions; events are `shotAccepted`, `shotRetake`, `flowAbandoned`. Testable in isolation.
   - `CameraAdapter` (AVFoundation wrapper) — capture session, photo output, orientation. Driven by the state machine.
2. **IntakeFormView** (shallow) — SwiftUI form for name, character name, cabin, class top-3, three raw tokens. Validates required fields.
3. **CamperStore** (deep) — single source of truth for all camper data on-device. Encapsulates persistence (file-system layout: `Documents/campers/camper_NNN/` with `tokens.json` + `photos/{expression}.jpg` × 5 + `panels/panel_NN.png` + `comic.pdf`). Interface: `create(intake) -> CamperID`, `load(id)`, `update(id, mutation)`, `delete(id)`, `list()`.
4. **PhotoReferenceResolver** (deep, pure) — `pickPhoto(panelID, camperClass) -> ExpressionTag`. Map lives in a class-specific JSON config bundled in the app (one entry per panel: `{panel: 1, expression: "neutral"}`). Testable.
5. **GenerationClient** (deep) — abstract `protocol GenerationClient { func generate(prompt, references) -> Image }` with two implementations: `FirebaseVertexClient` and `PublicGeminiClient`. Caller (PanelReviewView) doesn't know which is in use.
6. **PromptBuilder** (deep, pure) — assembles the panel/cover prompt from the 7-part skeleton in `spec/design.md` §8: scene-with-tokens + composition + costume + palette + style-suffix + aspect-ratio. Mirrors `assemble_panel_prompt()` in legacy `generate.py`.
7. **TranslationClient** (deep) — wraps a text-only Gemini call to suggest 3 fantasy fragments per raw token. Mirrors `suggest_translations()` in legacy `intake_server.py`.
8. **PanelReviewView** (shallow) — per-panel screen: shows pending generation, accept / re-roll / re-prompt / skip buttons, attempt count, error states.
9. **PDFRenderer** (deep) — takes a complete camper bundle (12 panels + cover + captions + cover metadata) and produces a `comic.pdf`. Implementation: a `WKWebView` loads an HTML template (ported from `layout/comic.html.j2`), then `viewPrintFormatter` + `UIPrintPageRenderer` → PDFData. Preserves the existing `comic.css` and Jinja-like template structure (Swift will use a minimal mustache-style substitution).
10. **SettingsView** (shallow) — Firebase config status, public-Gemini API key entry, generation-path toggle, app version, export/import.
11. **AppCoordinator** (shallow) — navigation between Dashboard → Intake → Capture → Finalize → Translate → Generate → Render. Each screen pushes/pops; no deep linking for v1.

**Pipeline contract changes (apply to both iOS app and `_legacy/` Python):**

- On-disk layout: `intake/camper_NNN/photos/{neutral,joy,fear,surprise,profile}.jpg` (5 files) replaces the single `photo.jpg`. `tokens.json` gains a `photos` field: `{"neutral": "neutral.jpg", "joy": "joy.jpg", ...}` and a `profile_side` field (`"left"` or `"right"`).
- `generate.py` reference order changes: `[primary_photo_for_panel, class_hero_card, prior_panel_continuity]` where the primary photo is no longer hard-coded but resolved per panel.
- The QA gate runs against the `neutral.jpg` shot only.
- `spec/design.md` §7 (photo collection protocol) updated to describe 5-shot guided capture; §10 Stage 1 updated to reflect iPhone capture replacing laptop+tripod.

### Cloud auth

- **Primary path: Firebase AI Logic (Vertex AI in Firebase) Swift SDK.** Preserves the "adult faces not used for training" guarantee from `spec/design.md`. Requires a Firebase project linked to Jeremy's GCP project; iOS app embeds `GoogleService-Info.plist`.
- **Fallback path: public Gemini API.** User pastes their own API key in `SettingsView`; key stored in iOS Keychain (not `UserDefaults`). API key may be Jeremy's (shared via DM with a friend) or the friend's own from aistudio.google.com.
- **Both paths require explicit setup** — the app never ships with an embedded API key. First-launch onboarding requires choosing a path and providing credentials.

### Panel → expression mapping (default)

Bundled in `Resources/panel_expression_map.json`, keyed by panel number; same map across all classes for v1 (per-class overrides are an easy follow-up):

| Panel | Expression | Rationale |
|---|---|---|
| 1 | neutral | Everyday self, mirror of panel 12 |
| 2 | surprise | The summons — something otherworldly intrudes |
| 3 | neutral | Mid-transformation, blended expression |
| 4 | joy | "Wow that's me" — the hero shot |
| 5 | neutral | Wide establishing shot, camper small in frame |
| 6 | neutral | Meeting the guide, receptive |
| 7 | fear | The challenge appears |
| 8 | fear | First attempt fails |
| 9 | neutral | Class-specific solution, focused competence |
| 10 | joy | Triumph, quiet competence |
| 11 | neutral | The reward, ceremonial calm |
| 12 | neutral | Return home, changed but composed |
| cover | profile | Hero pose, 3⁄4 angle |

This mapping is the v1 default and will be tuned by hand once Jeremy sees real output.

## Testing Decisions

A test is good if it would still pass after the implementation is rewritten —
i.e. it tests external behavior, not internal structure. Pure modules with
clear inputs and outputs are the highest-value test targets.

**Test targets:**

1. **CaptureStateMachine** (Swift, XCTest) — verifies the 5-shot sequence: `start → neutralAccepted → joyAccepted → fearAccepted → surpriseAccepted → profileAccepted → completed`; retake from any state stays in that state; abandon from any state ends the flow. No AVFoundation involved.
2. **PhotoReferenceResolver** (Swift, XCTest) — verifies each panel ID resolves to the expected expression per the bundled map; missing-panel returns a documented default (likely `neutral`); resolver works for cover.

**Not tested for v1:**

- `GenerationClient` implementations (involve real network or heavy mocking; defer until a bug shows up).
- `PDFRenderer` (visual fidelity is the success criterion — eyeball the output, don't unit-test it).
- `CamperStore` (file I/O; integration test would be useful but not load-bearing for v1).
- The Flask `_legacy/` code (it's a sandbox; it doesn't need to ship-quality).

**Prior art:** none — the repo has no test suite today. The two Swift tests will be the first.

## Out of Scope

- **iPad support.** The app is iPhone-only for v1. SwiftUI's adaptive layout means upgrading to universal later is mostly free, but designing for both now adds review-screen complexity that doesn't justify itself.
- **Multi-device sync.** v1 assumes one staffer holds one device for the whole camp week. Cross-device sync (CloudKit) is deferred until single-device proves painful.
- **TestFlight distribution.** Sideload via Xcode for v1; pay the $99/yr Apple Developer fee only after v1 is validated in real use.
- **Background generation.** Generation runs while the app is foregrounded. iOS background-task scheduling is a known rabbit hole; if generation has to span a phone-in-pocket interval, the staffer plugs the phone in and leaves the app open.
- **Per-class panel→expression overrides.** v1 uses one map across all six classes. Per-class tuning is a config-only change later.
- **Cabin group-shot panel.** Already deferred in `spec/design.md` §13.
- **Lulu Print API integration.** Already deferred in `spec/design.md` §13.
- **Minors handling (under-18 campers).** Already deferred in `spec/design.md` §13. The iPhone pivot does not re-open this — first camp remains 18+.
- **Online translation of the existing 3 test campers.** The Python pipeline at `_legacy/` can still be used to finish them; no migration story for in-progress Python intake records.

## Further Notes

- **Why this is the right shape now:** Three of the four most painful operational realities of the current pipeline (Mac setup, sharing with friends, photo-station quality) collapse into "the staffer holds an iPhone." The fourth (cloud cost / API quota) is unchanged — the phone calls Vertex AI / Gemini just like the laptop did.
- **What this PRD doesn't do:** It doesn't prescribe specific UI screens beyond naming the views. The screens are best designed against a `/prototype` SwiftUI sketch (next step after this PRD lands).
- **Risk to watch:** PDF visual fidelity via WKWebView is the highest-uncertainty piece. If WKWebView's print output diverges from WeasyPrint in subtle ways (font hinting, page breaks, image scaling), Jeremy's 2026-05-23 layout iteration is partially wasted. Worth a 30-minute spike *before* committing to the full PRD: render one existing camper's manifest into a PDF via WKWebView and compare side-by-side with the WeasyPrint output.
- **The Python sandbox remains useful for:** prompt iteration (`scripts/generate.py` is the easiest place to A/B prompts), class YAML editing (Python loads YAML cleanly; Swift will need a port), and the QA-gate test loop. Move to `_legacy/` but don't delete.
- **Reference:** `spec/design.md` is still the canonical design source. This PRD describes the implementation pivot; it does not replace the design.
