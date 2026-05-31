# Camp Comics

Personalized 15-panel D&D-style comic generator for ~60 summer-camp **players** per week. Native iPhone app (in-progress migration) replaces the legacy Python pipeline; each player ends up with a printed comic by Day 5.

## Language

### Comic structure

**Panel**:
A numbered slot in the comic from 1 to 15. May be empty, in-progress, or filled. "Panel 7" refers to the slot, not the image.
_Avoid_: "panel" as the artifact (say "panel 7's accepted image" or `panel_NN.png`).

**PanelSpec**:
The YAML script entry for one panel — `caption`, `emotion`, `position`, optional `reference_panel`. Lives in `templates/{class}.yaml`. Describes what should fill the slot.
_Avoid_: "panel script", "panel definition".

**Cover**:
The 16th generated artifact, sibling to (not a kind of) panel. Has its own prompt skeleton and uses `[photo, hero]` references only.
_Avoid_: "panel 16", "cover panel".

**PanelTarget**:
Code-level discriminator for the shared review surface: `panel(n: Int, spec: PanelSpec) | cover(spec: CoverSpec)`. Parameterizes `PanelReviewView`, `PromptBuilder`, and `PhotoReferenceResolver` so panels and the cover share one code path. On-disk identity is a sibling enum `PanelTargetID` (`.panel(Int) | .cover`) — serialized as the string discriminator `"panel_07"` / `"cover"` in `_attempts.json` and used by `PlayerStore` to address files.

### Print layout

**Comic**:
The final printable artifact for one player — a PDF assembled from the player's 15 accepted panels + cover. On-disk: `Documents/players/player_NNN/comic.pdf`. Distinct from the *story* (the narrative encoded in the class template) and from any individual *panel* or *cover* (the source images that fill it).
_Avoid_: "book" (informal), "PDF" (technical artifact, not the named thing).

**Page**:
One of the page-sized sections of the printed comic. v1 ships four pages — cover (page 1) and three interior pages (pages 2–4). A fifth back-cover **cohort roster** page is deferred until cohorts ship. Page size is 6.625" × 10.25" (comic standard), declared via CSS `@page` and read by `WKWebView.createPDF(configuration:)`.
_Avoid_: "panel" (a panel is one cell on a page, not the whole page).

**Act**:
One of the three interior pages, each carrying a narrative beat from the class template — Act I (Ordinary → Call, panels 1–6, page 2), Act II (The Quest, panels 7–11, page 3), Act III (The Return, panels 12–15, page 4). Each act has its own asymmetric grid declared in CSS. Act I and Act III each contain one **transition triptych** that bookends the quest.
_Avoid_: "interior page" when you mean the narrative beat ("Act II" reads as story; "page 3" reads as the third sheet).

**Transition triptych**:
A three-panel row sharing one figure container with constant-width cream gaps along diagonal seams. Two per comic, symmetrically placed: **P-in** on page 2 (panels 3–5, transition INTO fantasy, parallelogram middle + trapezoid bookends, //// slashes) and **H-out** on page 4 (panels 12–14, transition BACK to everyday, hexagonal diamond-middle + pentagon bookends). The middle cell is a face-out-of-frame close-up on the **prop**; the bookends frame it narratively. Triptych panels emit no `<figcaption>` (Watchmen-style); adjacent on-page panels carry the captions. See ADR-0007. In the review surface, a triptych is reviewed as **one super-card** (see [[Review card]]) — Accept/Re-roll/Re-prompt apply to all three sub-panels atomically; Re-prompt edits a single shared addendum string appended to each sub-panel's assembled prompt (the per-panel `caption`/`emotion`/`position` stay intact). A triptych Re-roll or Re-prompt spends 3 calls against the per-comic generation budget.
_Avoid_: "diagonal pair" (the OLD page-3 two-cell shape, superseded), "transition row" (loses the geometric "triptych" signal), "split panel" (suggests one panel was split, when these are three distinct `PanelSpec`s).

**Prop / through-line**:
The class-specific object that carries visual continuity through the second half of the comic. Handed over glowing at new-P8 (mentor gift, act-2 introduction), it appears glowing in the H-out left bookend (new-P12), visibly dims in the H-out middle close-up (new-P13), and lands mundane in the right bookend (new-P14) and the kitchen return splash (new-P15). Per-class props: druid sprig+pendant, warrior shield-pin, wizard notebook+crescent, bard music-note pendant, healer wooden symbol, trickster brass key.
_Avoid_: "gift" (only describes the handoff moment, not the through-line role), "souvenir" (only describes the final mundane form).

### Generation loop

**Candidate**:
An in-flight image contender for a panel slot or the cover, produced by one call to Vertex. Lives in `_candidates/NN/{nnn}.png` until either promoted (Accept) or deleted (Accept of a sibling, or session abandon).
_Avoid_: "attempt" (overlaps with the retry counter), "draft" (suggests a non-final form rather than a competitor).

**Gallery**:
The live set of candidates for one panel during a review session. Empty after Accept. Re-populated when Re-roll-after-accept demotes the prior winner back in. Surfaced as the filmstrip at the bottom of `PanelReviewView`.
_Avoid_: "candidates" (the directory) when you mean the set being reviewed.

**Accepted image**:
The single committed image for a panel or the cover — `panel_NN.png` or `cover.png`. The moment Accept fires (swipe-right on a review card), the **currently-visible** candidate is promoted out of the gallery and becomes the accepted image; the rest of that gallery is deleted.
_Avoid_: "the panel" (the panel is the slot), "winner" (only meaningful mid-review).

### Review surface

**Review stack**:
The full-screen card stack the operator works through to finalize a comic. Cards are ordered by [[PanelTarget]] in story order (panel 2, panel 3, ..., panel 15, cover); under the [[Generation queue]]'s panel-1-first batch shape, the stack only begins populating after panel 1 is generated and accepted in a separate phase. One card at a time is the head; swipe gestures act on the head. Replaces the legacy `PanelReviewView` + filmstrip + grid navigation as the single review surface.
_Avoid_: "swipe deck" (less specific), "review queue" (queue refers to the generation backlog, not the review surface).

**Review card**:
A single card in the [[Review stack]] representing one [[PanelTarget]]. For ordinary panels and the cover, renders the head of that panel's [[Gallery]] full-screen. For a [[Transition triptych]], renders as a **super-card** showing all three sub-panels in the print-faithful triptych composition; Accept/Re-roll/Re-prompt act atomically on all three. While the underlying generation is in flight (or throttled per [[Throttled]]), the head card renders as a **placeholder card** with a spinner and the panel number; behind-head in-flight panels are invisible.
_Avoid_: "swipe card", "panel card" (panel is the slot, not the visual element).

**Swipe vocabulary**:
The gesture set on a [[Review card]]:
- **Swipe right** = Accept → promote currently-visible candidate, delete the rest of the gallery, advance the stack.
- **Swipe left** = [[Re-roll]] → append a new candidate to this panel's gallery; new candidate becomes the head; gallery accumulates.
- **Swipe up / down** = cycle through this panel's gallery (zero API calls); newest on top.
- **Long-press** = [[Re-prompt]] → opens the shared-addendum editor; result lands in the gallery like a Re-roll.
The review surface must be a full-screen NavigationStack root, never a sheet (swipe-down on a sheet dismisses it, colliding with gallery navigation).
_Avoid_: "swipe action" (too generic — name the gesture).

**Panel grid**:
The 4×4 thumbnail sheet showing all 15 panels + cover with their [[PanelGridCellStatus]] (Empty / Generating / Filled / Accepted). Two entry points from the [[Review stack]]: a toolbar grid-icon button (always available — escape hatch for re-opening accepted panels) and auto-presentation when the last unaccepted panel reaches Accept (pre-finalize confirmation, with prominent "Generate PDF" CTA). Tapping an Accepted cell triggers a Re-roll-after-accept confirm and jumps the stack back to that panel. Reuses the existing `PanelGridView` from slice 11d.
_Avoid_: "grid sheet" (sheet is a presentation style, not the thing), "thumbnail grid" (less specific).

**Generation queue**:
The producer side of the [[Review stack]]. A worker pool with `K` concurrent workers pulling from a FIFO of [[PanelTarget]]s in story order. Phase 1 is single-target (panel 1, sequential). Phase 2 enqueues panels 2..15 + cover after panel 1 is accepted. Throughput is adaptive: `K` starts at 3, decrements on any 429 ([[Throttled]] absorbs single auto-retry per ADR-0003), increments after 5 consecutive successes; floor 1, ceiling 8. Per-session state, not persisted across launches. Results land into the gallery of their target panel; the review stack head re-renders whenever its gallery gains a candidate or completes generation.
_Avoid_: "batch" (the queue isn't a fire-and-forget batch — it's a live producer), "background worker" (overloaded term).

### References (anti-drift)

**Photo reference**:
The original player photo — slot 1 in every Vertex call. Anchors canonical identity. Never absent.

**Hero reference**:
The pre-generated class hero card at `templates/refs/{class}_hero.png` — slot 2 in every call. Anchors costume + painted style. Never absent. Faceless by design.

**Continuity reference**:
Slot 3, optional. The **accepted `panel_01.png`** for panel N's generation (N ≥ 2). Anchoring everything on panel 1 instead of the most recent accepted panel stops the "telephone game" — drift no longer compounds panel-by-panel; the late-comic look stays locked to the look established at panel 1. Absent for: panel 1 itself, and any panel generated before panel 1 has been accepted (out-of-order generation; chip warns "Continuity reference: none — panel 1 not yet approved"). A `PanelSpec.reference_panel = M` override is still honored as an escape hatch for special cases (e.g., a panel that needs to anchor on a different earlier panel); if the named panel is missing on disk, the continuity reference is **absent**, not silently fallen back. Whether the cover takes a continuity reference is covered separately under [[Cover]].
_Avoid_: "previous panel reference" (was true under the prior chained model; under the panel-1 anchor model the only "previous" panel that matters is panel 1).

**STYLE_SUFFIX**:
The canonical prompt tail enforcing face-fidelity (to slot 1) and costume continuity (to slots 2 + 3). Load-bearing — it's the primary anti-drift mechanism on this project. Ported verbatim from `_legacy/scripts/generate.py:66–80`.
_Avoid_: "style block" (suggests it's just decorative).

### Generation states

**Throttled**:
Vertex 429 (per-minute quota exhausted). Its own state in `PanelReviewStateMachine`, distinct from Failed. The state shows a countdown and auto-retries **once**; if the retry also 429s, holds at Throttled until the operator taps Retry. Expected under cohort load; not an error.
_Avoid_: treating throttled as a flavor of Failed.

**Failed**:
Vertex returned a non-retryable error, or [[Throttled]] busted through its single auto-retry budget. Operator-driven recovery — Retry button does not auto-fire. On a [[Review card]], a Failed head shows three affordances: Retry (re-enqueue at head), long-press = [[Re-prompt]] (content-policy recovery — edit prompt before retry), and **Defer** (secondary pill — advance the stack; the panel's gallery stays empty; the [[Panel grid]] cell becomes the `Failed` status). A comic with one or more Failed-Deferred panels finalizes after a confirm warning ("Panel N has no image — your comic will have an empty cell. Generate anyway?").
_Avoid_: lumping rate-limit retries in here; "skip" (Skip was removed wholesale in slice 11a per ADR-0003 amendment — Defer is the new vocabulary).

### Operator actions

**Re-roll**:
Generate a new candidate against the same prompt and **add** it to the panel's gallery — prior candidates are not discarded; the new candidate becomes the gallery's head (newest on top). Gesture: swipe-left on a review card. On an already-Accepted panel ("Re-roll-after-accept"), demotes the prior accepted image back to candidate #1 and re-opens the gallery; downstream accepted panels are **not** regenerated. Same UI label in both contexts. Spends 1 call against the per-comic generation budget (3 for a triptych, since all three sub-panels regenerate together). **Panel 1 special case**: Accept fires on a new panel-1 candidate that differs from the prior accepted one AND at least one downstream panel is already accepted — a warn-only confirm surfaces ("Panel 1 anchors the continuity of every other panel. The new look won't auto-propagate. Re-roll downstream panels from the grid if anything looks off."). No auto-cascade — the operator chooses what to re-roll.
_Avoid_: separate "Regenerate" and "Re-roll" verbs; "discard the current candidate" (older swipe-loop terminology — under the swipe model nothing is discarded until Accept fires).

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

### Billing

**BillingMode**:
The "who pays Google" axis. Two cases: `.sponsored` (the `comic-harness` Firebase project pays — Jeremy's card, capped per-install + capped globally by Google Cloud budget) and `.byo` (the user provides their own Gemini Developer API key — bills against their own Google account, uncapped). User-facing copy may say "free" / "use your own key"; the glossary term names the axis. Stored per-app in `UserDefaults` (the BYO key itself lives in Keychain). Not recorded per-player; flipping mid-comic is supported because both modes call the same model with the same `STYLE_SUFFIX`.
_Avoid_: "Default" (describes UX, not who's paying), "paid mode" (ambiguous about which side is paying).

**Sponsored trial**:
The 2-comic free allotment each install gets on `.sponsored`. "Comic" here means *finalized* (PDF generated); incomplete comics don't decrement the install counter. Surfaced upfront on first launch ("Try 2 free, then bring your own key") so the App Store reviewer sees the BYO model immediately. Per-install counter keyed on the Firebase Auth anonymous UID, server-side in Firestore.
_Avoid_: "free tier" (suggests an ongoing tier, not a finite trial).

**Generation budget**:
Per-comic ceiling of `(panel_count + 1) × 2` Vertex calls — i.e., one initial generation per slot + one full re-roll pass. For the current 15-panel template that's 32 calls (15 panels + 1 cover). The formula is **template-dynamic** so future shorter templates (a 9-panel trial template, a 5-panel demo) scale proportionally without code changes. Every `gemini-2.5-flash-image` call on this comic decrements it uniformly — initial generations, Re-rolls, Re-prompts, and Re-roll-after-accept. The **QA-gate** generation does NOT count (it gates whether the comic even starts). Visible mid-flight as a low-key chip ("23 re-rolls left"). On exhaustion, the swipe surface disables swipe-left (Re-roll) and long-press (Re-prompt); only swipe-right (Accept) and swipe-up/down (gallery cycle, 0 calls) remain. The exhaustion modal offers "accept current candidates and finalize" or "paste a Gemini key to continue in BYO." Per-comic budget exists only in `.sponsored`; `.byo` is uncapped.
_Avoid_: "panel budget" (it's shared across all slots, not per-panel), "re-roll budget" (re-rolls are one consumer; initial generations and re-prompts also draw); "32-call cap" as a fixed phrase (it's the current 15-panel template's value, not the formula).

**Global budget cap**:
Google Cloud hard budget limit on the `comic-harness` project. The actual liability ceiling — per-install caps and per-comic budgets are friction controls layered on top, but only the GCP cap stops billing in extremis. Load-bearing. Must be configured before any Sponsored code ships.
