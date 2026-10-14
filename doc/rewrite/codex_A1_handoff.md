# A1 archaeology initializer migration audit

Baseline inventory: 783 rows; expected supported extraction reduction 746; remaining 37 (root must run analyzer update to confirm).
Before by rule: {'init_lines': 781, 'world_reads': 2}
Remaining by rule: {'init_lines': 37}

## Residual reasons
- artifact.dm: master creation, primary effect trigger selection, appearance and activation happen before machinery parent init. Existing setup is phase 3 after the whole chain; moving this work would reorder it relative to gas-level initialization/power setup. Map predefined_icon_num is per-instance. Preserve all 33 rows until a proven early setup contract exists.
- fossils.dm: breq = rand(6)+3 and derived desc overwrite mapper breq. Native rolls skips mapper override values, so preserve these two genuinely per-instance lines rather than silently change map behavior.
- misc.dm: crystal randomize_color() overwrites map-set state/color before machinery parent init; native rolls preserves map overrides and phase timing differs. Keep the one genuinely per-instance call.
- special.dm: loc_last_process = src.loc remembers the actual constructor/map placement for animated blood; genuine per-instance state. Keep one row.

## Exact remaining baseline fingerprints
```text
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::if
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::make_artifact_master
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::if
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::my_effect
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::if
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::icon_num
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::else
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::icon_num
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::icon_state
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::if
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::name
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::desc
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::expr
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::expr
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::expr
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::expr
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::my_effect.trigger
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::else if
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::name
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::desc
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::my_effect.trigger
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::else if
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::desc
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::my_effect.trigger
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::else if
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::name
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::desc
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::my_effect.trigger
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::else if
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::name
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::desc
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::my_effect.trigger
init_lines	code/modules/xenoarcheaology/artifacts/artifact.dm	@/obj/machinery/artifact::Initialize::artifact_master.do_large_randomization
init_lines	code/modules/xenoarcheaology/finds/fossils.dm	@/obj/skeleton::Initialize::breq
init_lines	code/modules/xenoarcheaology/finds/fossils.dm	@/obj/skeleton::Initialize::desc
init_lines	code/modules/xenoarcheaology/finds/misc.dm	@/obj/machinery/crystal::Initialize::randomize_color
init_lines	code/modules/xenoarcheaology/finds/special.dm	@/obj/effect/decal/cleanable/blood/splatter/animated::Initialize::loc_last_process
```

## Verification ownership
No tests, compilation, cargo, generation or baseline updates run by this agent. Root wires new test file and performs one gate.
New include: code/modules/unit_tests/dq_a1_archaeology_init.dm
New selectors: dq_a1_archaeology_init/replacement, /retained_proxy, /rejected_holder, /rock_contents, /harvester_facing, /container.
Existing focused coverage: interim_strangerock_mining_release, interim_strangerock_welder_cleanup, dq_look_pin.

Source equivalence: no production subclasses of archaeological_find, strangerock, anomaly_container or artifact_harvester override Initialize. Source algorithm bodies unchanged, including RNG/child constructor interleaving, setter/relation calls and diagnostics. All three find INITIALIZE_HINT_QDEL paths now explicitly spent(src) (same END_SPENT path as InitAtom). The setup entry checks discarded/deleted holder before running; a fixture asserts rejected holder creates no child.
No spawns_many declaration fits a proxy replaced by independently placed and decorated subtype-selected objects: it instead constructs owned children with fixed offsets. No finds declaration preserves harvester facing-first then orange-order fallback. Named setup hooks preserve these jobs without inventing APIs.
