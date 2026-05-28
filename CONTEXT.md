# Camp Comics

Personalized 12-panel D&D-style comic generator for ~60 summer-camp **players** per week. Native iPhone app (in-progress migration) replaces the legacy Python pipeline; each player ends up with a printed comic by Day 5.

## Language

### Comic structure

**Panel**:
A numbered slot in the comic from 1 to 12. May be empty, in-progress, or filled. "Panel 7" refers to the slot, not the image.
_Avoid_: "panel" as the artifact (say "panel 7's accepted image" or `panel_NN.png`).

**PanelSpec**:
The YAML script entry for one panel — `caption`, `emotion`, `position`, optional `reference_panel`. Lives in `templates/{class}.yaml`. Describes what should fill the slot.
_Avoid_: "panel script", "panel definition".

**Cover**:
The 13th generated artifact, sibling to (not a kind of) panel. Has its own prompt skeleton and uses `[photo, hero]` references only.
_Avoid_: "panel 13", "cover panel".

**PanelTarget**:
Code-level discriminator for the shared review surface: `panel(n: Int, spec: PanelSpec) | cover(spec: CoverSpec)`. Parameterizes `PanelReviewView`, `PromptBuilder`, and `PhotoReferenceResolver` so panels and the cover share one code path. On-disk identity is a sibling enum `PanelTargetID` (`.panel(Int) | .cover`) — serialized as the string discriminator `"panel_07"` / `"cover"` in `_attempts.json` and used by `PlayerStore` to address files.

### Generation loop

**Candidate**:
An in-flight image contender for a panel slot or the cover, produced by one call to Vertex. Lives in `_candidates/NN/{nnn}.png` until either promoted (Accept) or deleted (Accept of a sibling, or session abandon).
_Avoid_: "attempt" (overlaps with the retry counter), "draft" (suggests a non-final form rather than a competitor).

**Gallery**:
The live set of candidates for one panel during a review session. Empty after Accept. Re-populated when Re-roll-after-accept demotes the prior winner back in. Surfaced as the filmstrip at the bottom of `PanelReviewView`.
_Avoid_: "candidates" (the directory) when you mean the set being reviewed.

**Accepted image**:
The single committed image for a panel or the cover — `panel_NN.png` or `cover.png`. The moment Accept fires, the chosen candidate is promoted out of the gallery and becomes the accepted image; the rest of that gallery is deleted.
_Avoid_: "the panel" (the panel is the slot), "winner" (only meaningful mid-review).

### References (anti-drift)

**Photo reference**:
The original player photo — slot 1 in every Vertex call. Anchors canonical identity. Never absent.

**Hero reference**:
The pre-generated class hero card at `templates/refs/{class}_hero.png` — slot 2 in every call. Anchors costume + painted style. Never absent. Faceless by design.

**Continuity reference**:
Slot 3, optional. The most recent accepted `panel_MM.png` with `m < N`, for panel N's generation. Absent for: panel 1, the cover, and out-of-order acceptance. If a `PanelSpec.reference_panel = M` override names a missing panel, **also absent** (no fallback to the default-rule panel — preserves YAML intent).
_Avoid_: "previous panel reference" (which previous? skipped ones are skipped over).

**STYLE_SUFFIX**:
The canonical prompt tail enforcing face-fidelity (to slot 1) and costume continuity (to slots 2 + 3). Load-bearing — it's the primary anti-drift mechanism on this project. Ported verbatim from `_legacy/scripts/generate.py:66–80`.
_Avoid_: "style block" (suggests it's just decorative).

### Generation states

**Throttled**:
Vertex 429 (per-minute quota exhausted). Its own state in `PanelReviewStateMachine`, distinct from Failed. The state shows a countdown and auto-retries **once**; if the retry also 429s, holds at Throttled until the operator taps Retry. Expected under cohort load; not an error.
_Avoid_: treating throttled as a flavor of Failed.

**Failed**:
Vertex returned a non-retryable error, or Throttled busted through its single auto-retry budget. Operator-driven recovery — Retry button does not auto-fire.
_Avoid_: lumping rate-limit retries in here.

### Operator actions

**Re-roll**:
Discard the current candidate selection and generate a new one against the same prompt. During review, pulls a new candidate into the gallery. On an already-Accepted panel ("Re-roll-after-accept"), demotes the prior accepted image back to candidate #1 and re-opens the gallery; downstream accepted panels are **not** regenerated. Same UI label in both contexts.
_Avoid_: separate "Regenerate" and "Re-roll" verbs.

**Re-prompt**:
Edit the prompt text, then generate a new candidate against the edited prompt. Distinct from Re-roll because the prompt itself is changing.

**Out-of-order acceptance**:
Accepting panel N when one or more earlier panels (`m < N`) are unapproved. Allowed. The candidate is generated with references = `[photo, hero]` only (no continuity reference), and the review screen shows a chip warning "Continuity reference: none — earlier panels not yet approved."

## Example dialogue

> **Operator:** Panel 7's gallery has three candidates and I don't love any of them — let me re-prompt.
>
> **Engineer:** OK, the Re-prompt button expands the textarea; edit the prompt and tap Generate. That adds a 4th candidate to the gallery without dropping the first three.
>
> **Operator:** Done. Accepting candidate 4. What happens to the others?
>
> **Engineer:** Candidate 4 is promoted to `panel_07.png` — that's now the accepted image. The other three candidates are deleted from `_candidates/07/`. Panel 8's continuity reference will be panel 7 when you generate it next.
>
> **Operator:** And if I re-roll panel 5 later? It's already accepted.
>
> **Engineer:** Re-roll-after-accept. You'll get a confirm because panels 6 and 7 are downstream — they're already generated against the old panel 5 and we don't cascade. If you confirm, the prior `panel_05.png` is demoted back to candidate 1 in a fresh gallery, and the new generation starts.
>
> **Operator:** What's the warning chip on panel 9?
>
> **Engineer:** Out-of-order acceptance — you jumped to panel 9 with panel 8 still unapproved, so it was generated with `[photo, hero]` only, no continuity reference. The chip's a reminder that panel 9 wasn't anchored to panel 8.

### Player

**Player**:
A summer-camp kid who ends up with a printed comic. Project-wide rename of the legacy "camper" term (legacy Python still uses "camper" on disk and in CLI flags).
_Avoid_: "camper" (in any new code or conversation), "user".
