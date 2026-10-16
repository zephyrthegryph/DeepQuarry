# Object initializer migration: non-item cohort, 2026-10-16

Branch/worktree: `codex/init-burndown-objects`, `E:/projects/dq-wt/codex-init-burndown-objects`, based on master `c3cb037784`. Items are owned by the separate source partition, except the two artstuff item initializers explicitly reassigned to this cohort.

## Source result; verification pending

The path cohort began with **368 init baseline rows**. The exact non-item portion is **365**; three further identities belong to the two artstuff item initializers now explicitly assigned here. This source cohort replaces **58 Initialize overrides**, matching **180 baseline identities**, prospectively **368 → 188 path-cohort rows**. The non-item-only change remains 56 overrides / 177 identities. These are source comparisons, not analyzer output. No baseline was hand-edited or updated, no generator/build/test was run, and no stamp is claimed.

The supported conversions use existing `setup()` and, for catwalk duplicate admission and anomaly area validation, pure `keeps_if()`. Existing single CAPABILITIES blocks were extended. Owned children and relation policies remain; anomaly impact_area is explicitly a non-owning area reference. The mine/combifan callbacks use the actual defining ancestors in TYPE_PROC_REF. Retained constructor parameters keep their existing lifetime. Parent/child spawner and fading setup retain ancestor-first order. No new ALLOW or framework form was added.

## Converted types

- `/obj/structure/timer_door` — `code/game/objects/micro_event.dm`.
- `/obj/structure/micro_tunnel` — `code/game/objects/micro_structures.dm`.
- `/obj/structure/mob_spawner` — `code/game/objects/mob_spawner.dm`.
- `/obj/effect/bspawner` — `code/game/objects/effects/bluespace_spawner.dm`.
- `/obj/effect/countdown` — `code/game/objects/effects/countdown.dm`.
- `/obj/effect/dark` — `code/game/objects/effects/dark_growth.dm`.
- `/obj/effect/effect/sparks` — `code/game/objects/effects/effect_system.dm`.
- `/obj/effect/mine` — `code/game/objects/effects/mines.dm`.
- `/obj/effect/temporary_effect/cleave_attack` — `code/game/objects/effects/misc.dm`.
- `/obj/effect/abstract/directional_lighting` — `code/game/objects/effects/misc.dm`.
- `/obj/effect/overlay/light_cone` — `code/game/objects/effects/overlays.dm`.
- `/obj/effect/abstract/shared_particle_holder` — `code/game/objects/effects/shared_particle_holder.dm`.
- `/obj/effect/step_trigger/teleporter/landmark` — `code/game/objects/effects/step_triggers.dm`.
- `/obj/structure/catwalk` — `code/game/objects/structures/catwalk.dm`.
- `/obj/structure/grille/broken` — `code/game/objects/structures/grille.dm`.
- `/obj/structure/holosign/barrier/combifan` — `code/game/objects/structures/holosign.dm`.
- `/obj/structure/inflatable` — `code/game/objects/structures/inflatable.dm`.
- `/obj/structure/foodcart` — `code/game/objects/structures/kitchen_foodcart.dm`.
- `/obj/structure/mirror` — `code/game/objects/structures/mirror.dm`.
- `/obj/structure/bed/pillowpile` — `code/game/objects/structures/pillows.dm`.
- `/obj/structure/railing` — `code/game/objects/structures/railing.dm`.
- `/obj/structure/reflector` — `code/game/objects/structures/reflectors.dm`.
- `/obj/machinery/portable_atmospherics/canister/phoron/cold` — `code/game/objects/structures/reflectors.dm`.
- `/obj/structure/safe/floor` — `code/game/objects/structures/safe.dm`.
- `/obj/structure/salvageable/personal` — `code/game/objects/structures/salvageable.dm`.
- `/obj/structure/stasis_cage` — `code/game/objects/structures/stasis_cage.dm`.
- `/obj/structure/transit_tube_pod` — `code/game/objects/structures/transit_tubes.dm`.
- `/obj/structure/transit_tube` — `code/game/objects/structures/transit_tubes.dm`.
- `/obj/structure/mob_spawner/mouse_nest` — `code/game/objects/structures/trash_pile.dm`.
- `/obj/structure/toilet` — `code/game/objects/structures/watercloset.dm`.
- `/obj/structure/windoor_assembly` — `code/game/objects/structures/windoor_assembly.dm`.
- `/obj/structure/window` — `code/game/objects/structures/window.dm`.
- `/obj/effect/anomaly/bioscrambler` — `code/game/objects/effects/anomalies/anomalies_bioscrambler.dm`.
- `/obj/effect/anomaly/dimensional` — `code/game/objects/effects/anomalies/anomalies_dimensional.dm`.
- `/obj/effect/anomaly/dust` — `code/game/objects/effects/anomalies/anomalies_dust.dm`.
- `/obj/effect/anomaly/flux` — `code/game/objects/effects/anomalies/anomalies_flux.dm`.
- `/obj/effect/anomaly/hallucination` — `code/game/objects/effects/anomalies/anomalies_hallucination.dm`.
- `/obj/effect/anomaly/weather` — `code/game/objects/effects/anomalies/anomalies_weather.dm`.
- `/obj/effect/anomaly` — `code/game/objects/effects/anomalies/_anomalies.dm`.
- `/obj/effect/decal/cleanable/chemcoating` — `code/game/objects/effects/chem/coating.dm`.
- `/obj/effect/effect/foam` — `code/game/objects/effects/chem/foam.dm`.
- `/obj/structure/foamedmetal` — `code/game/objects/effects/chem/foam.dm`.
- `/obj/effect/map_effect/interval/effect_emitter` — `code/game/objects/effects/map_effects/effect_emitter.dm`.
- `/obj/effect/temporary_effect/eruption` — `code/game/objects/effects/prop/columnblast.dm`.
- `/obj/effect/temp_visual/decoy/fading` — `code/game/objects/effects/temporary_visuals/miscellaneous.dm`.
- `/obj/effect/decal/cleanable/blood/drip` — `code/game/objects/effects/decals/Cleanable/humans.dm`.
- `/obj/effect/decal/cleanable/blood/old` — `code/game/objects/effects/decals/Cleanable/misc.dm`.
- `/obj/structure/largecrate` — `code/game/objects/structures/crates_lockers/largecrate.dm`.
- `/obj/structure/vehiclecage` — `code/game/objects/structures/crates_lockers/vehiclecage.dm`.
- `/obj/structure/ghost_pod/ghost_activated/swarm_drone/event` — `code/game/objects/structures/ghost_pods/silicon.dm`.
- `/obj/structure/prop/prism` — `code/game/objects/structures/props/beam_prism.dm`.
- `/obj/structure/prop/prismcontrol` — `code/game/objects/structures/props/beam_prism.dm`.
- `/obj/structure/prop/nest` — `code/game/objects/structures/props/nest.dm`.
- `/obj/machinery/door/blast/puzzle` — `code/game/objects/structures/props/puzzledoor.dm`.
- `/obj/structure/prop/transmitter` — `code/game/objects/structures/props/transmitter.dm`.
- `/obj/structure/closet/secure_closet/mind` — `code/game/objects/structures/crates_lockers/closets/secure/secure_closets.dm`.

- `/obj/item/canvas` — `code/game/objects/structures/artstuff.dm` (existing `reset_grid()` setup).
- `/obj/item/paint_brush` — `code/game/objects/structures/artstuff.dm` (per-instance color-image setup).

## Exact remaining contracts

The 23 retained overrides are not claimed converted or verified. This partition does not invent missing phase/context forms; in particular the declaration lane’s with_params extension is not on this base.

- `/obj` (`code/game/objects/micro_structures.dm:397`): The instance helper also runs from table_initialize(). An ordinary setup hook would miss the fast path or duplicate work; its position before descendant constructor work must remain explicit.
- `/obj/effect/landmark` (`code/game/objects/effects/landmarks.dm:86`): Coordinate registration must occur before descendant constructors can consume the landmark (corpse, shell and other loaders). Completion setup would skip deleted instances and lose those records.
- `/obj/effect/landmark/poi_loader` (`code/game/objects/effects/landmarks_poi.dm:10`): SSpois.enqueue(src) runs before the parent landmark initializer/registration; ordinary completion setup reverses that boundary.
- `/obj/effect/temporary_effect/lightning_strike` (`code/game/objects/effects/misc.dm:64`): Fade animation starts before the parent initializes its lifespan/presentation. Moving it after the parent changes the animation boundary.
- `/obj/effect/abstract/particle_holder` (`code/game/objects/effects/particle_holder.dm:26`): Invalid loc currently emits a stack_trace then returns QDEL. keeps_if(warn=) changes diagnostic severity; valid setup also changes parent vis_contents, observes lifetime/movement, and nullspaces the holder. Preserve validation/diagnostic ordering rather than conceal it.
- `/obj/structure/cliff` (`code/game/objects/structures/cliff.dm:52`): Registers danger after parent, but refreshes turf edges only when !mapload. Existing setup callbacks have no mapload context.
- `/obj/structure/drop_pod` (`code/game/objects/structures/droppod.dm:29`): cargo_at_make is keep=FALSE and is dropped before current setup_run. Needs the pending with_params constructor-completion form; retaining the transient parameter permanently would change lifetime.
- `/obj/structure/fence` (`code/game/objects/structures/fence.dm:26`): update_cut_status() changes density and sprite before the parent chain. Native completion setup would move those writes after parent initialization.
- `/obj/structure/fence/door` (`code/game/objects/structures/fence.dm:183`): update_door_status() runs before the fence parent, whose cut-state update then runs before its own parent. Preserve both ordered pre-parent boundaries.
- `/obj/structure/lattice` (`code/game/objects/structures/lattice.dm:11`): Validation and duplicate rejection precede smoothing. mapload redraws immediately without neighbor timers; runtime construction schedules its own and neighboring redraws. No mapload-aware setup exists here.
- `/obj/structure/biowaste_tank` (`code/game/objects/structures/watercloset.dm:1253`): Links the crusher before parent construction, then names/configures the owned muffin monster after parent construction. A single setup cannot preserve both boundaries.
- `/obj/effect/alien/weeds/node` (`code/game/objects/effects/alien/aliens.dm:73`): Peer replacement and self linked_node must precede inherited weeds setup/fullUpdateWeedOverlays. Ordinary ancestor-first setup would reverse that relationship.
- `/obj/effect/decal/cleanable` (`code/game/objects/effects/decals/cleanable.dm:41`): Persistence registration is conditional on mapload/config and runs before the parent, including before descendant merge/rejection behavior. Needs explicit context and phase.
- `/obj/effect/map_effect/beam_point` (`code/game/objects/effects/map_effects/beam_point.dm:46`): Creates initial beams and sets next_beam_delay before parent periodic initialization. A completion hook changes first-arm ordering.
- `/obj/effect/map_effect/portal/master` (`code/game/objects/effects/map_effects/portal.dm:143`): find_lines() runs before the parent initialization, while pair_up remains after_init. Preserve that split rather than run both after construction.
- `/obj/effect/temp_visual/decoy` (`code/game/objects/effects/temporary_visuals/miscellaneous.dm:13`): mimiced_atom and customappearance are keep=FALSE. Current InitAtom drops them before setup; needs pending with_params completion, not a shadow stored reference.
- `/obj/effect/temp_visual/circle_wave` (`code/game/objects/effects/temporary_visuals/miscellaneous.dm:139`): Initial transform, parallel animations and filters are all established before the parent lifetime/presentation initializer.
- `/obj/effect/decal/cleanable/liquid_fuel` (`code/game/objects/effects/decals/Cleanable/fuel.dm:20`): Rejects invalid loc, emits existing admin/game logs and merges into another spill before parent initialization; conditionally spreads afterward. Cannot flatten this two-sided boundary without changing behavior.
- `/obj/effect/decal/cleanable/liquid_fuel/flamethrower_fuel` (`code/game/objects/effects/decals/Cleanable/fuel.dm:67`): Ignites the actual simulated turf before entering the fuel parent chain (and its merge/spread work).
- `/obj/effect/decal/cleanable/blood` (`code/game/objects/effects/decals/Cleanable/humans.dm:50`): Mapload controls drying delay; duplicate DNA merging and pending-map-instance deletion flags occur before descendant work. Existing setup lacks mapload context.
- `/obj/effect/decal/cleanable/dirt` (`code/game/objects/effects/decals/Cleanable/misc.dm:80`): Mapload controls a random dirt seed; merging sets peer alpha and deletion flags and can return QDEL. Preserve RNG/duplicate ordering and mapload context.
- `/obj/structure/prop/machine/nt_pod` (`code/game/objects/structures/props/machines.dm:593`): Builds actual mask/visual references and adopts a map occupant only when mapload. Existing setup has no mapload context; no extra persistent flag was invented.
- `/obj/structure/closet/statue` (`code/game/objects/structures/crates_lockers/closets/statue.dm:29`): statue_of is keep=FALSE; current setup cannot see it after params_drop. Also preserves actual unbuckling/stasis/integrity and portrait ordering; needs pending with_params completion.

## Focused coverage prepared

`code/modules/unit_tests/dq_init_objects_nonitems_tests.dm` contains real-constructor assertions for: mine registration/countdown attachment; mapped tunnel offsets/tube directions; pillow ownership/support-table creation; light-cone transform/mirror constructor arguments; foodcart/crate loose contents; actual timer/cooldown initialization; window/windoor constructor arguments; coating reagent transfer/drip identity; real particle allocation; directional-light child lifetime; duplicate catwalk replacement; valid/invalid anomaly areas, core identity and countdown/immortality; actual canvas dimensions/every pixel and independent mutable brush images/colors. Tests own real spawned products and use forced deletion for the intentionally retained light-cone type.

Exact new selectors:

- `/datum/unit_test/dq_init_objects_nonitems/mine_and_countdown`.
- `/datum/unit_test/dq_init_objects_nonitems/tunnel_and_tube`.
- `/datum/unit_test/dq_init_objects_nonitems/pillow_and_salvage`.
- `/datum/unit_test/dq_init_objects_nonitems/light_cone_and_mirror`.
- `/datum/unit_test/dq_init_objects_nonitems/loose_map_contents`.
- `/datum/unit_test/dq_init_objects_nonitems/initial_clocks`.
- `/datum/unit_test/dq_init_objects_nonitems/constructed_frames`.
- `/datum/unit_test/dq_init_objects_nonitems/coating_and_drip`.
- `/datum/unit_test/dq_init_objects_nonitems/shared_particles`.
- `/datum/unit_test/dq_init_objects_nonitems/directional_light_child`.
- `/datum/unit_test/dq_init_objects_nonitems/duplicate_catwalk`.
- `/datum/unit_test/dq_init_objects_nonitems/anomaly_countdown`.

- `/datum/unit_test/dq_init_objects_nonitems/art_constructors`.

Root owns manifest wiring and serialized verification. The eventual focused gate also includes the required requirement/conversion pins and relevant existing construction/look regressions. No old-code capture, compile, runtime pass, DreamChecker result, ratchet result or lane-ready stamp is invented by this handoff. The next step is actual generation/checking and the coordinated focused gate, repairing only diagnosed failures.
