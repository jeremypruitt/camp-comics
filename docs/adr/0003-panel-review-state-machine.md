# `PanelReviewStateMachine`: Throttled and MissingPhoto are first-class states

The 7-state machine is `Unstarted / Generating / Throttled / Failed / Reviewing / Accepted / MissingPhoto`. Five are obvious for any "generate, review, accept" loop; the two deliberate ones are:

- **Throttled** (split from Failed): Vertex 429s are expected under cohort load (~60 players × 13 generations against a per-region per-minute quota). Surfacing throttling with a countdown pill + single auto-retry lets the operator route work around throttled panels instead of waiting silently like the legacy `with_backoff()`.
- **MissingPhoto** (split from Failed): recovery is structurally different — deep-link to a scoped `CaptureFlowView` for the one missing `(emotion, position)`, then transition to `Unstarted`. Modeling as a state keeps the recovery affordance attached to the panel where the operator needs it.

## Amendment 2026-05-27 (slice 11a)

`Skipped` was the eighth state in the original machine. It was removed wholesale: the affordance was confusing in the UX (operators reached for it as "I don't want this" but the panel still counted toward done), and once cover lands in 11b there's no flow where deliberately skipping a slot makes sense. The state machine now has 7 phases; `_skipped_NN` markers from earlier camp runs are ignored on disk (hard cutover, no migration).
