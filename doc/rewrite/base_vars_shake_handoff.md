# Shake rest-state cohort (source only)

Owner directory `code/modules/mob/living/life/`: dizzy_was_resting and jittery_was_resting move from two /mob vars to existing native sparse boolean slots. They retain nullable initial values and independent status histories. Actual shake tick comparison, status_rate_check ordering, dead-status ending, client effects and random offsets are unchanged. No extra fields or duplicate shadow state are added.

`dq_shake_state_home` calls both real ticks on resting transitions and asserts independent per-status and per-mob state. No generation, compile, tests, baseline update or stamp has run on this cohort.
