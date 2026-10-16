# Optional drain activity state

Source-only; two eating `base_var` rows removed, final verification pending.
`absorbing_prey` and `drain_finalized` now use declared native sparse booleans,
unset until an actor uses the activity. All human drain/feed starts, stages,
completion, cancellation and the finalization verb use the same zero/boolean
values, comparisons, messages and ordering. Writing zero releases the slot.
These are optional runtime flags, not character configuration or references.

Focused selector: `dq_vore_drain_state_home`. It exercises the actual finalization
verb in both directions and the real cancellation callback, checks the zero
fallback and absence of storage while idle, and verifies independent actors.
