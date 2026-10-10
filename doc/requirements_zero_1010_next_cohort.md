# Next requirement_bool cohort: read-only audit

Snapshot: current 425 baseline; excludes the four D draft file sets (machines, atmos, player-effects and storage/food/hydro). Counts are baseline fingerprints, not constructor instances. No production file, baseline, generator, build or test was changed/run.

Candidate next landing: **118 rows**, **60 files**. The three machinery.dm remote/menu/display rows are kept out because the silicon/resolver owner is resolving those semantics on master. Equipment-fit/rules REQ_* tables are explicitly excluded.

| Subsystem | Fingerprint rows | Files |
|---|---:|---:|
| Machinery and power | 49 | 25 |
| Clothing native ops (not fit tables) | 11 | 5 |
| Industrial, reagents, food and research | 36 | 20 |
| Mobs and silicon equipment | 22 | 10 |

## Ten semantic samples for coordinator review

1. **Portable atmos inherited status**: portable_atmospherics.dm `/obj/machinery/portable_atmospherics/not_destroyed` feeds port_connect and canister.dm ui_open. Preserve portable/wrecked at both callers. `port_free` already connected returns TRUE immediately; all branches need null/reason. `is_off` feeds huge pump anchor; `never` feeds huge pump and scrubber anchors with a different fixed bolted reason. Convert the shared holder family together.
2. **PACMAN and large Altevian fuel**: port_gen.dm has two separate holder implementations of sheet_match and has_room (`/pacman` and `/large_altevian`). Add-fuel selection is a when requirement; capacity rejection is pacman/full. A name-only codemod must not miss the second implementation or convert unrelated has_room methods.
3. **Pipe tile blocking**: construction.dm `/obj/item/pipe/tile_free` is isnull(tile_blocker()), separate tile_refusal returns that same dynamic value. Collapse to one checked callback preserving every tile_blocker reason. Do not return TRUE for null or introduce a fixed generic reason. Existing fasten(user) is an ordinary effect and must stay distinct.
4. **VR passenger entry**: vr_console.dm vr_entry_ready is already isnull(vr_entry_reason(A)). Both drag insertion and self-climb consume it. The existing reason callback checks actor/patient reachability only for drag, then operability, human-only and occupied slot in order. Use the reason directly and remove the redundant Boolean wrapper; preserve key-dependent ordering.
5. **Voidsuit attachment variants**: void.dm root has_removable_component permits hood/boots/tank, but autolok and ert.dm responseteam overrides permit boots/tank/cooler. Change all three implementations; a cooler-only root suit must still refuse, cooler-only variants must still allow. This is a native component-removal op, not an equipment-fit table.
6. **Holobadge credential imprint**: badges.dm imprint_credentials_holds wraps imprint_credentials_refusal, which is already null-or-text and handles ID vs PDA, missing ID, valid_access and emag bypass. An unrelated held item returns null deliberately so the effect can decline it. Preserve that path; do not blanket refuse non-ID items.
7. **Weaver site and silk**: weaver.dm five button rows each contain two Boolean requirements. weave_site_free wraps weave_site_text; weave_site_refusal adds fallback only for failed checks. Reuse site text with no_room/already_there reasons. Silk requirements use per-product costs; capture all five insufficient/sufficient boundaries and the shared occupied-tile branch.
8. **Ghost join**: simple_mob.dm declarations delegate to methods defined in game/objects/items/devices/denecrotizer.dm. can_ghost_join wraps ghost_join_refusal and ghost_join_reason returns it. Preserve banned roles, existing ckey and capture preference checks. Genuine client/preferences are needed for complete allow/deny coverage; do not fabricate a ckey or stub rights.
9. **Robot tongue mixed presentation**: dog_modules.dm tongue_thirsty is shared by sink (silent) and toilet (tongue/full). One callback can return tongue/full with sink silent flag retained, or generic reason with explicit per-use because overrides. Keep the two presentation contracts distinct, and test full/partially-empty battery through real charge setters.
10. **Appliance and furnace paired adapters**: _appliance.dm and material_machines.dm currently call an old TRUE-or-text helper twice through separate holds/refusal procs. Collapse into one callback that invokes the helper once, returns null only for the old truthy non-text success, preserves text including empty-text refusal, and returns req_failed for false/non-text. Appliance power has a mixer override in _mixer.dm; migrate that override and its ordinary callers together if changing the underlying helper protocol. Do not merely rename the adapter.

## Inheritance and cross-file consumer traps

- `/obj/item::kit_goes_first/kit_goes_last` are defined in game/objects/items/paintkit.dm, not component.dm. kit_goes_first uses Boolean `!kit_goes_last(A)`; converting the leaf without that inverse breaks precedence. Their consumers here are two robot-component customization when gates. Leave resolver/keybinding code untouched.
- `/obj/item/reagent_containers::blood_test_fits` is defined in reagent_containers/_reagent_containers.dm but used by food.dm and glass.dm; convert both when consumers together.
- `/obj/machinery/door/blast` and `/door/firedoor` have independent same-named wielded_if_axe/pry_free helpers and different MSG namespaces. Keep both families exact.
- Three eye_switch_allowed methods in glasses/hud.dm belong to three distinct eyepatch types. RIG *_holds/refusal adapters live in rig.dm; their underlying helpers live in rig_verbs.dm.
- Syndicate beacon topic_usable refers to /obj in objects/objs.dm and overlaps the coordinator's interaction-boundary work. Either use the existing final req_topic_ok with identical topic-gate semantics or coordinate the shared callback conversion; do not quietly mutate the shared API.
- `dq_actor_can_act_holds/refusal` in drill/filter is shared legacy actor logic. Compare actual actor restrictions against req_capable before replacing; preserve text or keep a direct null/reason helper if stronger restrictions remain.
- Scope counts exclude new small-form/rules and ratchet framework work. These candidates do not authorize broad rewrites of their neighbors.

## File and callback inventory

### Machinery and power

| File | Rows | Boolean callback references |
|---|---:|---|
| code/game/machinery/airconditioner.dm | 1 | `bolted` |
| code/game/machinery/atmoalter/canister.dm | 4 | `can_relabel`, `drained_for_liner`, `empty_or_wrecked`, `no_liner`, `not_destroyed` |
| code/game/machinery/atmoalter/clamp.dm | 2 | `dragged_by_self`, `pipe_free`, `released` |
| code/game/machinery/atmoalter/meter.dm | 1 | `pipe_here` |
| code/game/machinery/atmoalter/portable_atmospherics.dm | 2 | `has_cell`, `not_destroyed`, `port_free`, `port_reachable` |
| code/game/machinery/atmoalter/pump.dm | 2 | `/obj/machinery/portable_atmospherics/powered, is_off`, `/obj/machinery/portable_atmospherics/powered, never` |
| code/game/machinery/atmoalter/scrubber.dm | 1 | `/obj/machinery/portable_atmospherics/powered, never` |
| code/game/machinery/cryo.dm | 2 | `actor_outside`, `piped` |
| code/game/machinery/doors/airlock.dm | 3 | `backup_carries`, `power_systems_on` |
| code/game/machinery/doors/blast_door.dm | 2 | `pry_free`, `wielded_if_axe` |
| code/game/machinery/doors/firedoor.dm | 2 | `pry_free`, `wielded_if_axe` |
| code/game/machinery/doors/windowdoor.dm | 1 | `damaged_now` |
| code/game/machinery/nuclear_bomb.dm | 1 | `bomb_reachable` |
| code/game/machinery/pipe/construction.dm | 3 | `actor_able`, `on_floor`, `pipe_here`, `tile_free` |
| code/game/machinery/pipe/pipe_dispenser.dm | 2 | `dispenser_usable`, `loose_and_near` |
| code/game/machinery/pipe/pipelayer.dm | 2 | `can_run`, `pipe_has_steel`, `room_for_pipe` |
| code/game/machinery/portable_turret.dm | 4 | `intact`, `not_anchoring_in_space`, `uncontrolled` |
| code/game/machinery/recharger.dm | 2 | `takes_device` |
| code/game/machinery/syndicatebeacon.dm | 2 | `topic_usable` |
| code/game/machinery/virtual_reality/vr_console.dm | 2 | `vr_entry_ready` |
| code/game/machinery/wall_frames.dm | 1 | `mount_facing` |
| code/modules/power/apc.dm | 1 | `/obj/machinery/power/apc, floor_exposed` |
| code/modules/power/cable.dm | 1 | `alien_coil_inactive` |
| code/modules/power/port_gen.dm | 4 | `has_room`, `not_broken`, `sheet_match` |
| code/modules/power/solar.dm | 1 | `held_is_glass` |
### Clothing native ops (not fit tables)

| File | Rows | Boolean callback references |
|---|---:|---|
| code/modules/clothing/accessories/badges.dm | 1 | `imprint_credentials_holds` |
| code/modules/clothing/clothing.dm | 2 | `pred_has_holster_holds`, `pred_holding_knife_holds` |
| code/modules/clothing/glasses/hud.dm | 3 | `eye_switch_allowed` |
| code/modules/clothing/spacesuits/rig/rig.dm | 4 | `pred_has_boots_holds`, `pred_has_chest_holds`, `pred_has_gauntlets_holds`, `pred_has_helmet_holds` |
| code/modules/clothing/spacesuits/void/void.dm | 1 | `has_removable_component` |
### Industrial, reagents, food and research

| File | Rows | Boolean callback references |
|---|---:|---|
| code/modules/food/food.dm | 5 | `/obj/item/reagent_containers, blood_test_fits`, `can_cook`, `small_self_drag`, `stuffing_free`, `takes_micro` |
| code/modules/food/food/sandwich.dm | 1 | `not_collapsing` |
| code/modules/food/kitchen/cooking_machines/_appliance.dm | 2 | `can_take_item_holds`, `can_toggle_power_verb_holds` |
| code/modules/food/kitchen/cooking_machines/container.dm | 1 | `has_room` |
| code/modules/food/kitchen/smartfridge/smartfridge.dm | 2 | `is_powered_for_stocking_holds`, `ui_gate` |
| code/modules/materials/engineering/material_machines.dm | 3 | `can_eject_contents_holds`, `can_load_stock_holds`, `can_use_furnace_holds` |
| code/modules/mining/drilling/drill.dm | 2 | `can_work_on_holds`, `dq_actor_can_act_holds` |
| code/modules/mining/machinery/machine_processing.dm | 1 | `lets_in_holds` |
| code/modules/mining/mine_items.dm | 2 | `can_plant_holds` |
| code/modules/mining/mine_turfs.dm | 1 | `actor_dexterous_holds` |
| code/modules/mining/resonator.dm | 1 | `resonance_allowed` |
| code/modules/reagents/machinery/chem_master.dm | 4 | `makes_drugs` |
| code/modules/reagents/machinery/dispenser/dispenser2.dm | 2 | `not_broken` |
| code/modules/reagents/machinery/pump.dm | 1 | `battery_panel_open`, `no_cell` |
| code/modules/reagents/reagent_containers/glass.dm | 1 | `/obj/item/reagent_containers, blood_test_fits` |
| code/modules/reagents/reagent_containers/syringes.dm | 1 | `may_stab` |
| code/modules/refinery/core/industrial_reagent_filter.dm | 2 | `dq_actor_can_act_holds` |
| code/modules/refinery/core/industrial_reagent_grinder.dm | 1 | `has_room_holds` |
| code/modules/research/anomaly/anomaly_core.dm | 1 | `releaser_fresh` |
| code/modules/research/tg/machinery/destructive_analyzer.dm | 2 | `idle` |
### Mobs and silicon equipment

| File | Rows | Boolean callback references |
|---|---:|---|
| code/modules/mob/living/bot/medbot.dm | 1 | `arm_is_robotic` |
| code/modules/mob/living/carbon/human/species/lleill/lleill_items.dm | 2 | `has_homunculus_targets`, `ring_connected` |
| code/modules/mob/living/carbon/human/species/station/traits/states/weaver.dm | 5 | `weave_silk_binding`, `weave_silk_floor`, `weave_silk_nest`, `weave_silk_trap`, `weave_silk_wall`, `weave_site_free` |
| code/modules/mob/living/silicon/pai/software_modules.dm | 1 | `ui_pai` |
| code/modules/mob/living/silicon/robot/component.dm | 2 | `kit_goes_first`, `kit_goes_last` |
| code/modules/mob/living/silicon/robot/dogborg/dog_modules.dm | 3 | `has_room`, `tongue_thirsty` |
| code/modules/mob/living/silicon/robot/dogborg/dog_sleeper.dm | 4 | `sleeper_fits`, `sleeper_has_room`, `sleeper_may_ingest`, `sleeper_target_free`, `sleeper_target_loose`, `sleeper_vacant` |
| code/modules/mob/living/silicon/robot/robot_ui_decals.dm | 1 | `ui_gate` |
| code/modules/mob/living/simple_mob/simple_mob.dm | 2 | `can_ghost_join`, `hungry_enough_to_heal` |
| code/modules/mob/mob_defines.dm | 1 | `vv_not_remote_driven` |

## Proof and landing plan

Record old behavior pins before each family. Add compiled requirement boundary tests where menu snapshots cannot reach the important state (occupied VR, cooler-only suit, full tongue battery, silk reserve, client/preferences). Use current existing focused behavior tests plus scoped pin roots; do not use abstract /obj/item or /obj/machinery as whole-subtree pin captures. Compile and run one combined focused batch only after edits; root handles verification. Exact refusal text is a compatibility contract. This inventory is a proposal, not a claim the next 118 rows have been converted.
