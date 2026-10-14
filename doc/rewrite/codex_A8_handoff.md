# A8 init sweep handoff

Worktree E:/projects/dq-wt/codex-A8; branch codex/A8; base 219f9ef940.

Offline baseline inventory: 223 -> 124 (init_lines 209 -> 120; world_reads 14 -> 4). Root analyzer confirmation remains required. No baseline was edited. Exact retained identities are in residual-fingerprints.txt.

19 real setup jobs in 14 production files:
- Mining crate: existing generate_loot; original RNG and child constructor order unchanged.
- Trailblazer: existing set_color, dispatched to subtype implementation.
- Survival fridge: stock existing mapped contents, no deferred timer.
- Fans: existing tile-update helper.
- Processing/stacking/unloading: existing catalog enumeration, cardinal marker discovery and input watch; consoles link actual machines, preserve missing-machine diagnostics and discard via spent.
- Resonance crush: original scale followed by original animation, same duration.
- Fuel port: selected subtype tank, then existing loaded setter.
- Helm: existing sector catalog helper; navigation: hook declared module to existing linked ship.
- Disperser: link parts, then calibration reset, in original order.
- Gas thruster: tile update, then original immediate ship ownership walk and direction break.
- Overmap event: hazard refresh after accepted construction.
- Ship: vector creation/flags then flight registration. Its two actual map-configured speed normalization writes remain in Initialize. Tree-wide audit found no ship descendant Initialize consumer; no move of the overmap/visitable parent prerequisites.

Residuals, all exact rows in accompanying fingerprint file:
- machine_silo (4): mapload-only station-z selection and first-default service pointer; setup cannot receive mapload.
- mine_items (1): flag captures mapped icon_state as instance base_state.
- mine_turfs (10): resource flags and blank-substrate/map controls govern per-tile ore/random decoration; keep original draws/mapper behavior, not seeded overwrite semantics.
- mineral_effect (11): owner-location type and ore guards, per-instance ore/name/reagent/layer copied from the real containing turf.
- overmap_object (17): base Initialize camera prerequisites consumed through visitable/ship construction and init queues; setup runs after descendant Initialize, not at this parent boundary.
- sectors (30): synchronous z discovery/registration and nullspace transition consumed by temporary-sector post-parent initialization; appearance/map template normalization stays at that boundary.
- ship (2): round actual map-configured min_speed/max_speed.
- spacetravel (9): pre-parent loc/map coordinates and new-z allocation, followed by actual-result verification.
- turfs (24): pre-parent map-coordinate/mapping boundary and marks derived from actual world icon/map dimensions; root turf initialization consumes these facts.
- landmarks (16): automatic subtype pre-parent name/tag/random-id; actual mapped area/turf normalization and synchronous registration underpin shuttle construction. No delayed registration.

New include for root: code/modules/unit_tests/dq_a8_world_init.dm.
Focused selectors:
/datum/unit_test/dq_a8_world_init/mining_markers
/datum/unit_test/dq_a8_world_init/console_binding
/datum/unit_test/dq_a8_world_init/invalid_console
/datum/unit_test/dq_a8_world_init/fuel_ports
/datum/unit_test/dq_a8_world_init/trail_colors
/datum/unit_test/dq_a8_world_init/mapped_supplies
Plus task-required dq_look_pin, narrowed by root as appropriate.

Tests are real constructors and assert marker relations, catalog zero values, console backlinks, rejected-holder deletion, subtype tank contents/state, subtype color dispatch, and actual map-stock removal. Parent fixture warms dview/status policies outside per-test leak windows; each run snapshots coalesce_runs through the fixture's managed globals. No new fixtures add base types or production registries.

Read-only checks: git diff --check passes. No builds/tests/gen/manifest/baseline edits/commits/pushes were run by the subagent. Existing tracked lines, setter calls and ownership/reference declarations remain unchanged. Existing setter calls inside moved jobs stay in original order; no new raw tracked field assignments were moved except the resonance transform, which has no registered /atom transform setter or TRACKED declaration at this base.
