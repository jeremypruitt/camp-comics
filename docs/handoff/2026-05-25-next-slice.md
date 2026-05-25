# Handoff — 2026-05-25 (late) — wire up the real camera

**For the next Claude session that picks up this project.**
**Author:** the 2026-05-25 Claude session that landed the Variant B UI.

## Your goal

Ship **slice 1: real camera capture.** Jeremy ran the first slice on his
physical iPhone 16 Pro Max at the end of this session, confirmed the mock
behavior works (tap an uncaptured row = silent record, tap a captured row =
review sheet with retake / "looks good"), and explicitly chose camera capture
as the next tracer bullet.

Three other slices are queued and listed below; don't start on them unless
Jeremy redirects.

## What got built this session (don't repeat)

Two commits, both on `main`, local only:

- `b9ddcc6` — `templates/druid.yaml` tagged with `emotion:` + `position:`
  per panel + cover; Yams 5.4.0 added to `CampComicsCore`; `TemplateLoader`
  + `PromptCopyBook` + 8 new tests. Suite is 24 green.
- `c351af7` — SwiftUI app: `IntakeFormView` → `CaptureFlowView` (Variant B
  Checklist) via `NavigationStack`. Mock `CapturedPhoto` on tap; submit gated
  by `CaptureState.isReadyToSubmit`. Also patches the pbxproj to actually
  link `CampComicsCore` as a product dependency on the app target.

The visual proof lives in the simulator screenshots Jeremy already has;
re-screenshot via `xcrun simctl io <udid> screenshot /tmp/foo.png` if needed.

## Slice 1 — the work to do

Replace the mock `CapturedPhoto()` in `CaptureFlowView.handleTap` with a
real camera capture and surface the resulting image bytes in the UI:

- **Capture mechanism.** `UIImagePickerController` with `sourceType =
  .camera` (rear, by default — PRD calls out rear as the default for
  staff-driven shots) is the smallest path. `PhotosPicker` is fallback for
  the simulator (which has no camera). Long-term we may move to
  `AVCaptureSession` for finer composition control, but for the tracer
  bullet the standard picker is enough.
- **Storage.** First cut: an in-memory `[UUID: Data]` keyed off
  `CapturedPhoto.id`, owned by `CaptureFlowView` (or a small wrapper
  observable around `CaptureState`). Persistence to disk + filename
  convention (`photos/{emotion}_{position}.jpg` per the PRD) is a
  follow-up — don't roll it in.
- **UI changes.** `ChecklistRow`'s thumbnail and `ReviewSheet`'s big
  preview should both show the actual image (using `Image(uiImage:)`)
  when bytes exist; fall back to the prompt emoji when not.
- **Permissions.** Add `NSCameraUsageDescription` (and
  `NSPhotoLibraryUsageDescription` if you wire the photo-library
  fallback) to the app target's Info.plist. The Xcode project uses the
  modern flat-list `Info.plist` keys under build settings — check
  `INFOPLIST_KEY_*` in `project.pbxproj` rather than expecting a
  standalone Info.plist file.
- **Simulator caveat.** The iOS Simulator has no camera. If you wire
  only `UIImagePickerController` with `sourceType = .camera`, the
  simulator will hard-crash or no-op the present. Either gate on
  `isSourceTypeAvailable(.camera)` and fall back to `.photoLibrary`,
  or default to `PhotosPicker` and only branch to the camera when on a
  real device. Build for Jeremy's iPhone (see "Running on Jeremy's
  iPhone" below) before declaring this done — the simulator is not
  enough.

## The other three queued slices (don't start unless Jeremy redirects)

2. **YAML → Bundle loading.** Right now `BundledTemplates.druid` is a
   hardcoded `ClassTemplate` literal. The loader already works
   (`TemplateLoader.load(yaml:)`), but the YAML isn't shipped in the app
   bundle. Decide where the canonical YAML lives:
   - (a) Symlink `CampComicsCore/Sources/CampComicsCore/Resources/templates`
     → `../../../../templates`, declare via `.process()` in `Package.swift`.
     Single source of truth, one risky symlink.
   - (b) Add `templates/*.yaml` as a folder reference in the iOS app's
     Xcode project. Lives outside the SPM package.
   - (c) Copy YAML into the package's `Resources/` and accept a sync step
     between the legacy Python's `templates/` and the SwiftPM copy.

3. **The other five class templates.** Jeremy chose "just druid" for the
   tracer bullet. Warrior, wizard, bard, healer, trickster still need
   `emotion:` + `position:` per panel + cover. Wizard's mapping is
   already drafted in `prototype/intake-mobile/index.html` (`TEMPLATES.wizard`);
   the other four need new hand-tagging using the `neutral|joy|surprise|fear`
   × `front|profile` vocabulary. Mechanical work, low risk.

4. **Firebase / Gemini test-generation on submit.** Currently the submit
   button just shows an alert. The next real step is a Vertex-AI-in-Firebase
   call that takes the captured `neutral|front` photo and tries a single
   test panel generation, mirroring the legacy `_legacy/scripts/intake_server.py`
   QA gate. Firebase AI is already initialized in `CampComicsApp.init`.

## Running on Jeremy's iPhone

Jeremy's iPhone 16 Pro Max (UDID
`EE8B5F99-92C8-537B-BEC2-2670AFDCE6D7`) is paired and signing is wired
up under his free Personal Team. The full sideload sequence that worked
at the end of this session:

```bash
# 1. Build a signed device-arch app
cd CampComics
xcodebuild -project CampComics.xcodeproj -scheme CampComics \
  -destination 'platform=iOS,id=EE8B5F99-92C8-537B-BEC2-2670AFDCE6D7' \
  -derivedDataPath build-device build

# 2. Install it
xcrun devicectl device install app \
  --device EE8B5F99-92C8-537B-BEC2-2670AFDCE6D7 \
  build-device/Build/Products/Debug-iphoneos/CampComics.app

# 3. Launch it
xcrun devicectl device process launch \
  --device EE8B5F99-92C8-537B-BEC2-2670AFDCE6D7 \
  me.jeremypruitt.CampComics
```

**First-install trust gate.** After step 2, the first `process launch`
will fail with `FBSOpenApplicationServiceErrorDomain error 1
("inadequate entitlements or its profile has not been explicitly
trusted by the user")`. That's not a bug. Jeremy must go to **Settings
→ General → VPN & Device Management → Developer App → Apple
Development: jeremypruitt@mac.com → Trust** on the iPhone, then re-run
step 3. **You can't do step 3 for him from the CLI — he must tap the
trust confirmation on the device.** Pause and ask.

**7-day trust expiry.** Free-tier provisioning profiles expire after 7
days. After expiry the app silently refuses to launch. Re-running the
three steps above (with another trust step) refreshes the profile. A
paid Apple Developer Program account ($99/yr) removes this; Jeremy is
staying on the free tier for now.

## Load-bearing context to read

1. `CLAUDE.md` — orientation, gotchas, terminology.
2. The two new commits' diffs (`git show b9ddcc6 c351af7`).
3. `docs/prd/iphone-intake.md` — still authoritative; check the
   data-flow + Firebase notes before doing slice 4.
4. `docs/handoff/2026-05-25-build-the-ui.md` — the prior handoff. Reads
   like a prequel to this one.
5. `CampComicsCore/Sources/CampComicsCore/*.swift` — six files, all
   pure-Swift, small. Read in order: `CapturePlanner.swift`,
   `CaptureStateMachine.swift`, `TemplateLoader.swift`, `PromptCopy.swift`.
6. `CampComics/CampComics/*.swift` — the SwiftUI side.
7. Memory at `~/.claude/projects/-Volumes-MacMiniDock-dev-camp-comics/memory/`
   — `project_capture_ui_landed.md` is new; the rest stand.

## How to verify the current state

```bash
# Core tests (24 green expected):
cd CampComicsCore && swift test

# iOS build for any booted simulator:
xcrun simctl list devices booted  # find the UDID
cd CampComics
xcodebuild -project CampComics.xcodeproj -scheme CampComics \
  -destination "platform=iOS Simulator,id=<UDID>" \
  -derivedDataPath build build

# Install + launch:
xcrun simctl install <UDID> \
  build/Build/Products/Debug-iphonesimulator/CampComics.app
xcrun simctl launch <UDID> me.jeremypruitt.CampComics
```

If you want to see the checklist screen without typing on the simulator,
temporarily set `activePlayer` in `ContentView.swift` to a non-nil
`PlayerProfile(playerName: "Alex", ...)`, rebuild, screenshot, **revert**.
That hack was used + reverted this session.

## Don't break

Carry over the "Don't break" list from the previous handoff verbatim —
nothing in it has changed. In particular:

- `_legacy/` Python still renders end-to-end; don't touch its naming.
- Bundle ID stays `me.jeremypruitt.CampComics` (capital C/C).
- SSH commit signing needs `ssh-add ~/.ssh/github_ed` first
  (Jeremy already did it once this session, but ssh-agent is per-shell).
- The `@retroactive` conformance on `PanelRequirement: Identifiable` in
  `CampComics/CampComics/PanelRequirement+Identifiable.swift` is required —
  removing the annotation re-introduces a build warning.

One new gotcha: SourceKit in Claude's environment lags badly behind
`xcodebuild` after pbxproj edits or new SPM dependencies. Ignore "No such
module" / "Cannot find type" diagnostics from SourceKit if `xcodebuild`
succeeds. The actual compiler is the source of truth.

## Open questions for Jeremy

1. **Photo-library fallback?** Wire `PhotosPicker` as a secondary path for
   the simulator, or device-only?
2. **In-memory photo storage OK for this slice?** Or does Jeremy want
   filesystem persistence rolled in (per the PRD's
   `photos/{emotion}_{position}.jpg` convention)?
3. **Push the local commits?** 7 commits ahead of `origin/main` as of this
   handoff. Jeremy may want to push, or keep accumulating.
4. **GitHub Issues yet?** No issues filed. `/to-issues` against the queued
   slices in this doc is a reasonable move at any point.

## Suggested skills

- **`grill-with-docs`** — early in the session, to stress-test the chosen
  slice against the PRD. `CONTEXT.md` and `docs/adr/` are still both
  absent; the skill will lazily create them.
- **`tdd`** — slice 1 and 2 both have pure-Swift pieces worth driving
  red-green-refactor. The Swift Testing framework is set up.
- **`diagnose`** — for any Xcode/Firebase/simulator weirdness.
  Photo-permissions plumbing in slice 1 is a likely source of "why
  doesn't the camera open" head-scratchers.
- **`to-issues`** — break the remaining three queued slices into tracer
  bullets in the GitHub repo once the first one is in motion.
- **`verify`** — confirm the chosen slice actually works in the simulator
  before declaring it done. The handoff convention requires it.
- **`caveman`** — if Jeremy wants to cut tokens.
- **`handoff`** — at the end. Write to `docs/handoff/YYYY-MM-DD-*.md`,
  not `/tmp`.

## Verdict

Slice 1 is locked in. Open the session by reading the slice-1 description
above, asking the two open questions (photo-library fallback, in-memory
storage), and then start. Don't declare it done until Jeremy has launched
the build on his iPhone 16 Pro Max and captured at least one real photo
end-to-end.
