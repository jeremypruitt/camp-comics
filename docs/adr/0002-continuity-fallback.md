# Continuity reference: strict YAML-override fallback (no-continuity, not default)

> **Superseded by [ADR-0009](./0009-batch-generate-swipe-review.md) (2026-05-30).** Under the swipe-review redesign, continuity is anchored on panel 1 for every panel 2..15 + cover — the chained "most recent accepted panel" default is gone. The YAML-override escape hatch is retained (with the same missing-panel = absent semantics this ADR established), but the default rule below no longer applies.

A non-cover panel N's third Vertex reference (the **continuity reference**) defaults to the most recent accepted `panel_MM.png` with `m < N`, skipping over skipped panels. A `PanelSpec.reference_panel = M` override forces use of `panel_MM.png` — and **if that specific panel is missing on disk, no continuity reference is sent at all**, rather than silently falling back to the default rule.

This is deliberate. The only override case in the templates today is `druid.yaml` panel 12, which points back at panel 01 for the "return home" beat. The override exists *because* the default rule would otherwise drag druid regalia into a scene meant to mirror the everyday-clothes opener; falling back to the default on a missing override would silently produce the wrong image — exactly the failure the override is designed to prevent. The rule applies uniformly to any future class that adds a `reference_panel` override.

The complete set of no-continuity cases: panel 1 (nothing precedes it), the cover (uses `[photo, hero]` only), out-of-order acceptance (operator jumped ahead; chip warns "Continuity reference: none — earlier panels not yet approved"), and missing-override (this ADR's main case).
