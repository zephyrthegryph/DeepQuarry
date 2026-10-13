# Fixture hygiene handoff, 2026-10-13

Branch: `codex/fixture-hygiene-1013`.
Lane-ready commit: `4056f2a0fb`, tested code `396ebd1ca5`, master `d3f6b22332`.

The floor-construction fixture restores `GLOB.coalesce_runs`; the canister
fixture replaces and restores its prompt recorder; arrival-spawn restores
`GLOB.act_taken`. These scope cumulative framework/test counters without
changing production behavior or suppressing the leak audit.

Master's automatic setter conversion (`e1141671e5`) changed the card-hand
parity fixture to a nonexistent `add_cards()` call. The repair uses the same
implicit relation API as production card moves: `rel_add()`.

The first gate failed compilation before any tests ran. After reading both
compile logs and repairing that call, the complete lane-ready retry passed:
50 tests, zero failures; production zero errors; DreamChecker clean; ratchets
and analyze clean. Both mandatory pins and the lane's incremental look checks
ran. No full suite ran, baseline increased, allowance was added, or behavior
pin was re-blessed.

Focused selectors: `dq_requirement_protocol_pin`, `dq_conversion_pin`,
`dq_construction_floor`, `dq_atmos_m/canister_welder`,
`dq_gameplay/arrival_spawn`. Lane-ready expanded its normal smoke/client and
incremental pin coverage. Evidence: `data/test-runs/20261013T174450_396ebd1ca5.json`.

This is a bounded hygiene landing. During the run, separate wall-construction
and door-walk fixtures reported cumulative-counter leaks; their repairs are
prepared separately. The broader validated fault-injection contract and
STATE LEAK enforcement remain outstanding.
