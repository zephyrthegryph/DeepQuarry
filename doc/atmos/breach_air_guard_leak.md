# Fixed: the air guard's leak on a floor taken through space and back

Symptom (2026-11-08): a test that turned a block floor of the test map into space and back ended with the air guard reporting
`gas id 1 +82.1 mol` on that floor, and on it again after every later test.

What the world did (measured through the DM datum and the Rust cell at every step, on the old DM registration path and on the
one-call path alike): the floor read 0 mol before, during and after the change. ChangeTurf carries the previous air, so a floor
built over space starts as vacuum; DM and the arena agreed throughout. The real map is unaffected: 50 random Southern Cross floors
sampled right after boot read 104 mol at 293 K in every room (the ones under 10 mol were all `*/airless` exterior floors).

The cause was the harness, in two places:

1. The guard judged a replaced turf through the mixture handle it captured before the change. `unit_test_air_changed()`
   (code/tests/unit_tests/unit_test_guard.dm) now adds every turf whose air datum is not the captured one
   (`unit_test_air_replaced()`) and judges it through its current air.
2. The block reset (`unit_test_block_reset_turf()`, code/tests/unit_tests/unit_test.dm) wrote standard station air onto every
   block floor after each test. The test map's Unit Test Room boots as vacuum (follow-up below), so the reset injected about 82 mol of
   nitrogen and 22 of oxygen into any floor whose cell kept it (a floor rebuilt by ChangeTurf). The reset now puts back the air the
   guard's session baseline holds for the floor (`unit_test_block_restore_session_air()`); standard air only for a turf the guard does
   not watch.

Tests: `dq_air_guard_judges_a_replaced_turf_by_its_current_air` (no leak on an unchanged replaced floor),
`dq_air_guard_catches_gas_on_a_replaced_turf` (200 mol added to a replaced floor is still caught and put back),
`dq_breach_space_registers_in_one_call`.
