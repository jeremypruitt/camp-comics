# `PanelReviewStateMachine`: Throttled and MissingPhoto are first-class states

The 8-state machine is `Unstarted / Generating / Throttled / Failed / Reviewing / Accepted / Skipped / MissingPhoto`. Six are obvious for any "generate, review, accept/skip" loop; the two deliberate ones are:

- **Throttled** (split from Failed): Vertex 429s are expected under cohort load (~60 players × 13 generations against a per-region per-minute quota). Surfacing throttling with a countdown pill + single auto-retry lets the operator route work around throttled panels instead of waiting silently like the legacy `with_backoff()`.
- **MissingPhoto** (split from Failed): recovery is structurally different — deep-link to a scoped `CaptureFlowView` for the one missing `(emotion, position)`, then transition to `Unstarted`. Modeling as a state keeps the recovery affordance attached to the panel where the operator needs it.
