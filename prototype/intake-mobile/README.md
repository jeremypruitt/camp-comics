# Prototype — Camp Comics iPhone intake (mobile-web)

**Throwaway. Delete or absorb once the winning variant is folded into the real SwiftUI app.**

## What this is for

Answers the question: *does the (intake form → template-derived capture plan → guided multi-shot capture) UX actually feel right on a phone?*

Three radically different variants of the capture flow, switchable from the bottom bar:

- **A — Story cards**: full-bleed, one shot per card, Instagram-Reels-like. Accept/retake advances.
- **B — Checklist**: utilitarian list of required shots, tap any to capture, tap a done row to review. See all progress at once.
- **C — Coach**: gentle one-at-a-time, big emoji + prompt, progress dots, encouragement copy.

All three share the same intake form, the same template-derived capture plan, and the same "done" screen.

## Run

```bash
# From the repo root:
python3 -m http.server -d prototype/intake-mobile 8000
```

Then on your phone (same WiFi as the Mac):

1. Find the Mac's LAN IP: `ipconfig getifaddr en0` (or System Settings → Network).
2. In iOS Safari open `http://<that-ip>:8000`.
3. Tap to take photos — uses the iOS native camera via `<input capture>`. No `getUserMedia`, no HTTPS needed.

In a desktop browser, the camera button still works but opens a file picker.

## Variant switching

- Floating pill at the bottom-center: ← / variant label / →.
- Keyboard `←` / `→` (when focus isn't in an input).
- URL `?variant=A|B|C` is shareable and reload-stable.

## State

- Everything in memory. **Reload = wipe.** That's intentional — persistence is what the real iOS app will solve.
- Setup screen has a `Skip capture` link in small text at the bottom for jumping straight to the done screen with the photos blank.

## What's NOT in the prototype

- No real Gemini / Firebase / Vertex AI calls. The done screen lists what *would* happen next.
- No QA gate, translation, generation, or render.
- No cohort assignment screen.
- Only two class templates (druid, wizard) — and wizard is sketched, not the real `templates/wizard.yaml`. Just enough variety to see the capture plan visibly change when class changes.
- No accessibility beyond defaults; no localization.

## Wins to look for

- Which variant makes the *capture plan size changing per class* feel natural vs. confusing?
- Which variant feels best for a player who's nervous about being photographed?
- Which variant feels best for a staffer running 60 players through the same flow in a day?
- The interesting answer is usually "I want the dots from A with the progress bar from B" — write that down.

## Cleanup

When a variant wins, write down which and why in the commit message that absorbs it, then **delete this whole `prototype/intake-mobile/` directory**.
