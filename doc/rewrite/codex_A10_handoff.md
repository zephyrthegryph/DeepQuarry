# A10 init sweep handoff

Worktree E:/projects/dq-wt/codex-A10; branch codex/A10; base d36a5946fb.

Offline inventory 287 -> 128: init_lines 281 -> 127; world_reads 6 -> 1. Exact remaining row identities: residual-fingerprints.txt. Root analyzer must confirm; no baseline edits.

38 declared setup jobs across 28 production files. Covered conveyor observation/direction/start/parts; disposal pipe updates, sorting/tag registration, outlet link/observer and crusher discovery; reagent pump cell/parts, borg hypo catalog, used injector, vial capacity, random zoom dose/dirty syringe infection, cartridges/synthesizer instruction paper/tank sockets; food slicing/crunch coating/bread replacement/glass sounds/fitness look/meat composition; oven/grill insertion lists, cooker/mixer selection, icecream catalog and persistent/paired fridges; wax recipes and tray scratch/connection.

Order proof/traps:
- Whole-tree actual CAPABILITIES declarations (anchored, comments excluded) checked: all changed file types still have one block. No duplicate pump block from the documentation example in hose/connector.dm.
- Spidermeat had two identical Initialize definitions. deepquarry.dme includes snacks.dm at 2817, meat.dm at 2824, so meat.dm is active. Removed the earlier overridden definition and moved only the later active body's six-unit acid removal. The test asserts six acid remains from the actual twelve-unit parent contents, not two removals.
- Cooker and mixer both have distinct setup hook names: inherited reset first, child reset/selection second, preserving both original setter calls (no hook dedup).
- Junction and sortjunction retain both original update() calls: inherited direct setup plus distinct child job that updates again after naming/direction/index work.
- Smartfridge persistence remains ancestor-first, before down-chemvator pairing and read-only item-record aliasing.
- Tray scratch/connection job moved after auditing its only descendant Initialize: invisible soil check_health -> check_level_sanity does not read scratch; invisible soil is nonmechanical and does not need parent's mechanical connect. Param inputs used by other jobs keep=TRUE on this base.
- Vial hypospray copies its already-declared starting child's capacities. Its moved raw icon reset uses existing /atom set_icon_state; no existing setter or TRACKED declaration was modified. Reset still discards mapper icon changes as before.
- Original ordered world RNG calls and interleaved child constructors preserved for zoom pills, old syringes, sliced whole food and rare bread replacement; no RNG algorithm switch to seeded rolls.
- Two obsolete decl ALLOWs were removed because create_reagents/add_reagent moved outside Initialize; no new ALLOW added. All diagnostics/logging preserved.

Residual rows (exact identities in fingerprint file):
- z_custom_food 3: per-instance image objects use actual mapped icon, plus name from actual ingredients; no new stored-reference declarations or draw sweep.
- _cooker_output 1: cooked food capacity from actual instance size.
- grown 30: actual constructor plantname/seed facts, copied name/trash/potency, material/seed-sensitive chemical state; fruit slice uses actual passed seed and its per-instance cached-colored images.
- grown_inedible 5: actual constructor planttype and potency from its seed.
- seed_packets 2: random seed created before parent init; parent consumes seed_type.
- spreading 36: actual passed seed/parent/location, preexisting deletion guard, seed-derived growth/stinging/proximity, world-roll draw, deadline state. Keeping constructor phase, no duplicate seed state.
- tray_soil 8: actual constructor seed, location guard, health/age and cycle stamp depend on that seed.
- distillery 2: base sprite captures actual mapped icon only when mapper did not provide one.
- blood_pack 2: captures actual mapped name/desc before stock-label setup.
- glass 3: captures actual mapped name/desc; beaker suffix follows actual instance volume. Descendant cyborg beaker/bucket initializers elsewhere consume parent state.
- disposal-construction 21: actual constructor ptype/subtype/flipped and mapped direction normalized in original order.
- disposal 1: base_icon_state captures actual mapped icon before subtype updates.
- disposal_machines 14: mapload-only atmosphere priming. Its synchronous link/face/publish sequence precedes that priming; setup cannot take mapload and moving only that prefix would reverse the observation order.

New include: code/modules/unit_tests/dq_a10_content_init.dm.
Nine tests under /datum/unit_test/dq_a10_content_init:
meat_contents, cooking_insertions, mixer_selection, hypo_catalog, tray_scratch, reagent_sockets, wax_recipes, gibber_plate, vial_and_blood.
Tests use actual constructors and actual reagent/child/link state; fixtures warm dview/status policies in New and manage coalesce_runs through set_global per run. Root should include task-required dq_look_pin as appropriate.

Read-only checks: diff whitespace clean, changed-file block uniqueness clean, old setter/declaration line multisets preserved. No builds/tests/cargo/gen/manifest/baseline edits/commits/merges/pushes by subagent. Root serializes all verification.

Root preflight: generated tracked check passed after two insertion-list additions and starting-vial volume were routed through existing setters. Analyzer baseline4115 ->3956 (159removed); decl47unchanged. Runtime gate pending.


Source audit repair (2026-10-15): the newly added setup declarations referenced inherited procs with PROC_REF, which checks a current-type proc path. Changed only these new hook references to TYPE_PROC_REF at the actual defining ancestor: `/obj/item/reagent_containers/food/drinks/drinkingglass/fitnessflask/glucose` → `/obj/item/reagent_containers/food/drinks/drinkingglass/fitnessflask::on_reagent_change`; `/obj/structure/disposalpipe/segment` → `/obj/structure/disposalpipe::update`; `/obj/structure/disposalpipe/up` → `/obj/structure/disposalpipe::update`; `/obj/structure/disposalpipe/down` → `/obj/structure/disposalpipe::update`; `/obj/structure/disposalpipe/junction` → `/obj/structure/disposalpipe::update`. Hook names and dynamic dispatch remain unchanged; no wrappers, declarations, setters or behavior changed. No generation, analyzer, compile or test was run for this source-only repair. Verification remains with the A coordinator.

Read-tracking preflight found one newly moved wax recipe write. prepare_wax_recipes now uses the existing set_recipes(GLOB.wax_recipes), preserving the original table and position while publishing through the registered setter. Existing declarations/setter sites are unchanged. No compile or world ran in the blocked preflight; renewed proof pending.

Compile producer repair: on_reagent_change is declared as /datum/proc/on_reagent_change; fitnessflask only overrides it. The new glucose setup reference now names /datum while retaining dynamic dispatch. All other new plain callback targets have direct /proc declarations; the four typed disposal update targets also match their explicit declaring proc. The failed compile ran no world; original selected fixtures still require first execution.
