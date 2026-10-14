# Fixture hygiene follow-up, October 13

This branch scopes the incoming values of construction coalescing telemetry, door-walk and arrival act counters, the hit producer reply scratch value, canister test prompts, and the two NIFsoft catalog references before creating fixtures. Test override teardown restores the exact borrowed global identities.

Three nutrition-heal fixtures use a private contagion archive and end only newly created templates through END_SCOPE. Borrowed templates survive. No observer index is restored to conceal live observers.

Current master already covers dview warm-up. The pending full hygiene branch covers the deliberate midnight-counter fixture. A GC warning needs an identified leaked key and owner before a correction; this branch does not mask its unregister assertions.

Focused verification is pending. Selectors: dq_requirement_protocol_pin, dq_conversion_pin, dq_construction_floor, dq_construction_wall_plain, dq_atmos_m/canister_welder, dq_hit_pin, dq_gameplay/arrival_spawn, dq_gameplay/walk_through_door, dq_p2_vending/nifsoft_shop_hides_its_contraband_from_wires, dq_p2_vending/nifsoft_shop_throws_nothing, dq_timed_pin_w7/v_nutrition_heal, dq_timed_pin_w7/v_nutrition_heal_cancel_on_move, dq_timed_pin_w7/v_nutrition_heal_too_hungry.

STATE LEAK will become a hard failure only after remaining fixture and producer leaks are repaired. No baseline, golden or production behavior changes are included here.

The acceptance run at 17829fb399 subsequently proved dq_gc_sweep leaks only latency_last_ineligible and latency_last_pin_reason diagnostic strings. Both are now scoped at fixture entry; live holder, pin and watch indexes and their assertions are unchanged. Include dq_gc_sweep in the focused gate.

Both appearance producers scope Nar-Sie's one-time round flag, the queen birth/death counter, and their private contagion archive. Standalone tree runs are covered. Captures and goldens are untouched; newly archived templates end through their real lifecycle, so watch registrations disappear normally. Conversion pins also scope the two lazy NIFsoft catalog identities. Global explosion queues remain untouched.

The test runner now performs its existing staleness-start hook before capturing fixture leak baselines. This prevents the deliberate boot-backlog parked flag from being reported as a fixture mutation, while retaining all fixture mutations in the snapshots. No exemption, index reset or fixture flag restoration was added. Verification remains pending.

First gate a6816f6309 passed compile/DreamChecker and ratchets but failed three tests: the hit producer recorded two generated chameleon-list versions, and the look entry checks detected supermatter explosion work left by the hit fixture. It also logged canister prompt/counter leaks. The repair preserves immediate hit rows, then waits a bounded real epoch before cleanup; it neither clears the service nor blesses runtime output. The version exclusion has master cause e1141671e5 and a new public EMP regression. Canister coalesce is scoped; prompt restoration is instrumented because its existing private scope did not explain the leak. No stamp exists yet.

Source trace identified the prompt leak: dq_atmos_m/Run() invokes p2cl_capture_prompts() before the child run_gate() scope. The child therefore saved the helper's new list rather than the runner's original null. The base now records the original value before that helper; restoration diagnostics remain. Explosion settling runs once after every immediate hit row and target deletion, then restores gravity and owns only its fixture block, avoiding real-time changes between pin triggers.
Repair batch 53912af3d0 passed all three tests (20261014T080501_53912af3d0.json), including unchanged hit goldens and the real EMP regression. Prompt restoration is proven. Its remaining warnings identify first-use dview cache creation and two hit-fixture latency diagnostic strings; the fixture now warms dview in New(), following existing test harnesses, and scopes those strings. The complete lane-ready gate remains required.
