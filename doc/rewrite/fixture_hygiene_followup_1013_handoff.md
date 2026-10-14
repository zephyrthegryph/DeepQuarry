# Fixture hygiene follow-up, October 13

This branch scopes the incoming values of construction coalescing telemetry, door-walk and arrival act counters, the hit producer reply scratch value, canister test prompts, and the two NIFsoft catalog references before creating fixtures. Test override teardown restores the exact borrowed global identities.

Three nutrition-heal fixtures use a private contagion archive and end only newly created templates through END_SCOPE. Borrowed templates survive. No observer index is restored to conceal live observers.

Current master already covers dview warm-up. The pending full hygiene branch covers the deliberate midnight-counter fixture. A GC warning needs an identified leaked key and owner before a correction; this branch does not mask its unregister assertions.

Focused verification is pending. Selectors: dq_requirement_protocol_pin, dq_conversion_pin, dq_construction_floor, dq_construction_wall_plain, dq_atmos_m/canister_welder, dq_hit_pin, dq_gameplay/arrival_spawn, dq_gameplay/walk_through_door, dq_p2_vending/nifsoft_shop_hides_its_contraband_from_wires, dq_p2_vending/nifsoft_shop_throws_nothing, dq_timed_pin_w7/v_nutrition_heal, dq_timed_pin_w7/v_nutrition_heal_cancel_on_move, dq_timed_pin_w7/v_nutrition_heal_too_hungry.

STATE LEAK will become a hard failure only after remaining fixture and producer leaks are repaired. No baseline, golden or production behavior changes are included here.

The acceptance run at 17829fb399 subsequently proved dq_gc_sweep leaks only latency_last_ineligible and latency_last_pin_reason diagnostic strings. Both are now scoped at fixture entry; live holder, pin and watch indexes and their assertions are unchanged. Include dq_gc_sweep in the focused gate.

Both appearance producers scope Nar-Sie's one-time round flag, the queen birth/death counter, and their private contagion archive. Standalone tree runs are covered. Captures and goldens are untouched; newly archived templates end through their real lifecycle, so watch registrations disappear normally. Conversion pins also scope the two lazy NIFsoft catalog identities. Global explosion queues remain untouched.
