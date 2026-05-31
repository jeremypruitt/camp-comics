# `PanelReviewStateMachine`: Throttled and MissingPhoto are first-class states

> **Superseded by [ADR-0009](./0009-batch-generate-swipe-review.md) (2026-05-30).** The 7-state per-panel review machine is replaced by the batch-generate + swipe-review model. The `Throttled` distinction is retained inside the new [[Generation queue]] (same auto-retry-then-surface semantics applied to the head of the stack); `MissingPhoto` recovery is folded into the QA-gate flow upstream of phase 1. Skipped (removed in slice 11a per the amendment below) is NOT reintroduced — see ADR-0009 for the `Failed` + `Defer` vocabulary that replaces operator-driven slot abandonment.

The 7-state machine is `Unstarted / Generating / Throttled / Failed / Reviewing / Accepted / MissingPhoto`. Five are obvious for any "generate, review, accept" loop; the two deliberate ones are:

- **Throttled** (split from Failed): Vertex 429s are expected under cohort load (~60 players × 13 generations against a per-region per-minute quota). Surfacing throttling with a countdown pill + single auto-retry lets the operator route work around throttled panels instead of waiting silently like the legacy `with_backoff()`.
- **MissingPhoto** (split from Failed): recovery is structurally different — deep-link to a scoped `CaptureFlowView` for the one missing `(emotion, position)`, then transition to `Unstarted`. Modeling as a state keeps the recovery affordance attached to the panel where the operator needs it.

## Amendment 2026-05-27 (slice 11a)

`Skipped` was the eighth state in the original machine. It was removed wholesale: the affordance was confusing in the UX (operators reached for it as "I don't want this" but the panel still counted toward done), and once cover lands in 11b there's no flow where deliberately skipping a slot makes sense. The state machine now has 7 phases; `_skipped_NN` markers from earlier camp runs are ignored on disk (hard cutover, no migration).
