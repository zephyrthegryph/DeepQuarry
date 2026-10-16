# Timed body-effect serial storage

Source-only; one `base_var` row removed, verification pending. The next timed-stack
serial is now a declared native numeric sparse slot. The original zero fallback,
pre-increment value, timer-name format, scheduling position and monotonicity across
removal are unchanged. No body-effect origin, application state, factor table,
stack list or timer lifetime moves.

Focused selectors: `dq_body_effect_serial_home`, `dq_body_effect_stacking_rules`
and `dq_body_effect_expires_on_body_clock`. The new leaf applies two real allowed
effects, asserts separate timer names and one increment per application, then
removes them and checks the serial persists. Existing expiry/stasis and independent
stack behavior remains covered.
