# Optional phased-melee state

Source-only; three `base_var` rows removed, verification pending. The swing-active,
hit-resolution and monotonic serial values now use declared native sparse slots.
All actual click/attack guards, starts, completion, cancellation and stale-safety
consumers use these values. The increment still returns the new serial before the
same timer is armed; false active flags release storage. The monotonic serial
remains after a swing. Existing debug text and all effect/timer order are retained.

Focused selectors: `dq_melee_swing_sparse_safety`, `dq_melee_swing_hits_occupied_tile`,
`dq_melee_swing_kitchen_knife`, `dq_melee_swing_dodge_by_moving`,
`dq_melee_swing_sets_recovery_cooldown`, and existing timed pins `dq_timed_pin_w7/h_melee_swing`,
`dq_timed_pin_w7/h_melee_swing_dodge`,
`dq_timed_pin_w7/h_melee_swing_cancel_on_move`,
`dq_timed_pin_w7/h_melee_swing_cancel_on_drop`. The real hit/recovery/movement assertions are retained;
the new safety leaf exercises actual stale and matching callbacks and asserts
state reclamation plus serial persistence.
