# Complete remaining machinery/power legacy inventory
Lexical executable-token audit excluding comments/string literals. Counts are occurrences, not distinct files. Target declaration/watch/field families remain zero.

## `DECLARE_APPEARANCE` — 5
Appearance declaration bridge; separate look/draw conversion, not targeted interaction/emag/damage/repeat sweep.
- `code/game/machinery/jukebox.dm:172` — `DECLARE_APPEARANCE(/obj/machinery/media/jukebox, "appearance_running", list(`
- `code/game/machinery/jukebox.dm:176` — `DECLARE_APPEARANCE(/obj/machinery/media/jukebox, "appearance_panel", list("1" = list(APPEARANCE_OVERLAYS = list("panel_open"))))`
- `code/game/machinery/jukebox.dm:177` — `DECLARE_APPEARANCE(/obj/machinery/media/jukebox/casinojukebox, "appearance_running", list(`
- `code/game/machinery/spaceheater.dm:45` — `DECLARE_APPEARANCE(/obj/machinery/space_heater, "state", list( 	"0" = list(APPEARANCE_ICON_STATE = "sheater0"), 	"1" = list(APPEARANCE_ICON_STATE = "sheater1"), 	"2" = list(APPEARANCE_ICON_STATE = "sheater2"), 	"3" = list(APPEARANCE_ICON_STATE = "sheater3") ))`
- `code/game/machinery/spaceheater.dm:46` — `DECLARE_APPEARANCE(/obj/machinery/space_heater, "panel_open", list("1" = list(APPEARANCE_OVERLAYS = list("sheater-open"))))`

## `DECLARE_APPEARANCE_PROC` — 17
Appearance proc bridge; requires migrating actual overlay dependencies and output parts, not deleting declaration.
- `code/game/machinery/feeder.dm:15` — `DECLARE_APPEARANCE_PROC(/obj/machinery/feeder, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/fire_alarm.dm:99` — `DECLARE_APPEARANCE_PROC(/obj/machinery/firealarm, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/floor_light.dm:155` — `DECLARE_APPEARANCE_PROC(/obj/machinery/floor_light, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/frame.dm:343` — `DECLARE_APPEARANCE_PROC(/obj/structure/frame, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/holoposter.dm:47` — `DECLARE_APPEARANCE_PROC(/obj/machinery/holoposter, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/iv_drip.dm:17` — `DECLARE_APPEARANCE_PROC(/obj/machinery/iv_drip, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/jukebox.dm:385` — `DECLARE_APPEARANCE_PROC(/obj/machinery/media/jukebox/ghost, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/newscaster.dm:202` — `DECLARE_APPEARANCE_PROC(/obj/machinery/newscaster, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/rechargestation.dm:269` — `DECLARE_APPEARANCE_PROC(/obj/machinery/recharge_station, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/rechargestation.dm:379` — `DECLARE_APPEARANCE_PROC(/obj/machinery/recharge_station/ghost_pod_recharger, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/requests_console.dm:117` — `DECLARE_APPEARANCE_PROC(/obj/machinery/requests_console, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/spaceheater.dm:91` — `DECLARE_APPEARANCE_PROC(/obj/machinery/space_heater, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/doors/brigdoors.dm:212` — `DECLARE_APPEARANCE_PROC(/obj/machinery/door_timer, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/embedded_controller/airlock_controllers.dm:93` — `DECLARE_APPEARANCE_PROC(/obj/machinery/embedded_controller/radio/airlock, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/embedded_controller/airlock_controllers.dm:126` — `DECLARE_APPEARANCE_PROC(/obj/machinery/embedded_controller/radio/airlock/access_controller, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/game/machinery/embedded_controller/embedded_controller_base.dm:97` — `DECLARE_APPEARANCE_PROC(/obj/machinery/embedded_controller/radio, TYPE_PROC_REF(/atom, appearance_overlays), list())`
- `code/modules/power/singularity/particle_accelerator/particle_smasher.dm:117` — `DECLARE_APPEARANCE_PROC(/obj/machinery/particle_smasher, TYPE_PROC_REF(/atom, appearance_overlays), list())`

## `DECLARE_LOOT` — 4
Load-time loot registry remains current shared API under AGENTS; separate spawn-table capability migration.
- `code/game/machinery/deployable.dm:326` — `DECLARE_LOOT(/obj/random/cutout, LOOT_TABLE(LOOT_TYPES(1, subtypesof(/obj/structure/barricade/cutout))), LOOT_CHANCE(20)) // Only spawns 20% of the time to avoid being predictable`
- `code/game/machinery/paradox.dm:60` — `DECLARE_LOOT(/obj/random/portalloot, LOOT_TABLE(\`
- `code/game/machinery/paradox.dm:76` — `DECLARE_LOOT(/obj/random/greaterportalloot, LOOT_TABLE(\`
- `code/game/machinery/paradox.dm:107` — `DECLARE_LOOT(/obj/random/mob/interspace, LOOT_TABLE(\`

## `DECLARE_SHARED_CACHE` — 3
Shared appearance/cache registry; separate shared-cache API conversion, preserves cached artifacts.
- `code/game/machinery/floor_light.dm:1` — `DECLARE_SHARED_CACHE(floor_light_overlays, GLOBAL_PROC_REF(build_floor_light_overlay), SC_NEVER)`
- `code/game/machinery/pipe/construction.dm:272` — `DECLARE_SHARED_CACHE(pipe_init_dirs, GLOBAL_PROC_REF(build_pipe_init_dirs), SC_NEVER)`
- `code/modules/power/lighting.dm:10` — `DECLARE_SHARED_CACHE(light_type_instance, GLOBAL_PROC_REF(build_light_type_instance), SC_NEVER)`

## `OM_WORLD` — 1
Doppler explosion notice observes world owner; shared world-context alias, not gas hub.
- `code/game/machinery/doppler_array.dm:26` — `observe(OM_WORLD, /datum/notice/world_explosion, src, then(PROC_REF(sense_explosion)))`

## `REQ_INTERACTION_REACH` — 6
Legacy requirement clauses on six abstract machinery interaction bases and two construction ladder entries; separate compatibility-base/construction retirement.
- `code/game/machinery/machinery_interactions.dm:29` — `requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null))`
- `code/game/machinery/machinery_interactions.dm:34` — `requires = list(REQ_INTERACTION_REACH)`
- `code/game/machinery/machinery_interactions.dm:41` — `requires = list(REQ_INTERACTION_REACH)`
- `code/game/machinery/machinery_interactions.dm:48` — `requires = list(REQ_INTERACTION_REACH)`
- `code/game/machinery/machinery_interactions.dm:54` — `requires = list(REQ_INTERACTION_REACH)`
- `code/game/machinery/machinery_interactions.dm:59` — `requires = list(REQ_INTERACTION_REACH, REQ_PROC(/proc/dq_actor_can_act, "you can't do that right now"))`

## `REQ_ON` — 3
Legacy requirement clauses on six abstract machinery interaction bases and two construction ladder entries; separate compatibility-base/construction retirement.
- `code/game/machinery/frame_construction.dm:130` — `requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/structure/frame/proc/accepts_board, null))`
- `code/game/machinery/frame_construction.dm:305` — `requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/structure/frame/proc/has_all_components, "it is missing components"))`
- `code/game/machinery/machinery_interactions.dm:29` — `requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null))`

## `REQ_PROC` — 1
Legacy requirement clauses on six abstract machinery interaction bases and two construction ladder entries; separate compatibility-base/construction retirement.
- `code/game/machinery/machinery_interactions.dm:59` — `requires = list(REQ_INTERACTION_REACH, REQ_PROC(/proc/dq_actor_can_act, "you can't do that right now"))`

## `REQ_REACH_ADJACENT` — 2
Legacy requirement clauses on six abstract machinery interaction bases and two construction ladder entries; separate compatibility-base/construction retirement.
- `code/game/machinery/frame_construction.dm:130` — `requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/structure/frame/proc/accepts_board, null))`
- `code/game/machinery/frame_construction.dm:305` — `requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/structure/frame/proc/has_all_components, "it is missing components"))`

## `om_native_watch_of` — 1
Machine service generic native-watch lookup through thin alias to kernel_native_native_watch_of; not om_gas_watch_hub.
- `code/game/machinery/machine_service.dm:247` — `var/datum/native_watch/gas/W = om_native_watch_of(observations[record])`

## `om_playsound` — 2
Delayed sound callbacks in atmospheric alert computer; after() scheduling is native but callback name remains compatibility helper.
- `code/game/machinery/computer/atmos_alert.dm:51` — `after(src, 10 SECONDS, TYPE_PROC_REF(/atom, om_playsound), key = "alert_repeat", with = list('sound/effects/comp_alert_major.ogg', 70, 1))`
- `code/game/machinery/computer/atmos_alert.dm:54` — `after(src, 10 SECONDS, TYPE_PROC_REF(/atom, om_playsound), key = "alert_repeat", with = list('sound/effects/comp_alert_minor.ogg', 50, 1))`

## `om_qdel_self` — 1
Transport pod timer disposal callback compatibility helper.
- `code/game/machinery/transportpod.dm:69` — `after(src, 0.2 SECONDS, TYPE_PROC_REF(/datum, om_qdel_self))`

## `om_range` — 2
NOT legacy OM: named argument meaning overmap range in using_map.get_map_levels, two legitimate sites.
- `code/game/machinery/cryopod.dm:512` — `announce.autosay("[to_despawn.real_name][departing_job ? ", [departing_job], " : " "][on_store_message]", "[on_store_name]", announce_channel, using_map.get_map_levels(z, TRUE, om_range = DEFAULT_OVERMAP_RANGE))`
- `code/game/machinery/telecomms/telecomunications.dm:695` — `return src_z in using_map.get_map_levels(dst_z, TRUE, om_range = DEFAULT_OVERMAP_RANGE)`

## `om_step` — 1
Singularity delayed one-step callback compatibility helper.
- `code/modules/power/singularity/singularity.dm:307` — `after(src, 0.1 SECONDS, TYPE_PROC_REF(/atom/movable, om_step), with = list(movement_dir))`

## `own_bring_in` — 6
Ownership helper compatibility path; separate ownership/containment conversion, preserves release/delete/move policy.
- `code/game/machinery/biogenerator.dm:241` — `if(!own_bring_in(src, nameof(contents), G, null, user, TRUE, null, FALSE))`
- `code/game/machinery/biogenerator.dm:261` — `if(!own_bring_in(src, nameof(contents), O, null, user, TRUE, null, FALSE))`
- `code/game/machinery/floorlayer.dm:49` — `if(!own_bring_in(src, nameof(contents), W, null, user, TRUE, null, FALSE))`
- `code/game/machinery/newscaster.dm:675` — `if(!own_bring_in(src, nameof(photo_data), incoming, null, user, TRUE, null, FALSE))`
- `code/game/machinery/nuclear_bomb.dm:83` — `if(!own_bring_in(src, nameof(auth), disk, null, user, TRUE, null, FALSE))`
- `code/game/machinery/washing_machine.dm:158` — `if(!own_bring_in(src, nameof(crayon), W, null, user, TRUE, null, FALSE))`

## `own_clear` — 6
Ownership helper compatibility path; separate ownership/containment conversion, preserves release/delete/move policy.
- `code/game/machinery/newscaster.dm:657` — `own_clear(GLOB.news_network, nameof(/datum/feed_network::wanted_issue_owned), OWN_DELETE)`
- `code/game/machinery/protean_reconstitutor.dm:289` — `own_clear(BR, nameof(BR.stored_mmi), OWN_DELETE) //toss the dummy...`
- `code/game/machinery/rechargestation.dm:147` — `own_clear(rigchest, nameof(rigchest.breaches), OWN_DELETE)`
- `code/game/machinery/computer/message.dm:240` — `own_clear(linkedServer(), nameof(/obj/machinery/message_server::pda_msgs), OWN_DELETE)`
- `code/game/machinery/computer/message.dm:251` — `own_clear(linkedServer(), nameof(/obj/machinery/message_server::rc_msgs), OWN_DELETE)`
- `code/game/machinery/suit_storage/suit_cycler.dm:513` — `own_clear(suit, nameof(suit.breaches), OWN_DELETE)`

## `own_move` — 7
Ownership helper compatibility path; separate ownership/containment conversion, preserves release/delete/move policy.
- `code/game/machinery/machinery.dm:552` — `own_move(B, src, nameof(component_parts))`
- `code/game/machinery/machinery.dm:603` — `own_move(M, A, nameof(A.circuit)) // the board moves from the machine to the frame (CONTAINED there)`
- `code/game/machinery/protean_reconstitutor.dm:292` — `own_move(salvaged_brain, BR, nameof(BR.stored_mmi)) //...and implant the salvaged mmi in its place (from our protean_brain)`
- `code/game/machinery/computer/cloning.dm:90` — `own_move(BR, pod, nameof(pod.growing_record))`
- `code/game/machinery/computer/cloning.dm:386` — `own_move(C, pod, nameof(/obj/machinery/clonepod::growing_record))`
- `code/game/machinery/doors/airlock.dm:1087` — `own_move(assembly_electronics, src, nameof(electronics)) // from the assembly to the door`
- `code/game/machinery/doors/windowdoor.dm:265` — `own_move(door_electronics, assembly, nameof(assembly.electronics)) // from the door to the assembly`

## `own_remove` — 4
Ownership helper compatibility path; separate ownership/containment conversion, preserves release/delete/move policy.
- `code/game/machinery/computer/message.dm:275` — `own_remove(linkedServer(), nameof(/obj/machinery/message_server::pda_msgs), log_entry)`
- `code/game/machinery/computer/message.dm:279` — `own_remove(linkedServer(), nameof(/obj/machinery/message_server::rc_msgs), log_entry)`
- `code/game/machinery/telecomms/logbrowser.dm:59` — `own_remove(S, nameof(/obj/machinery/telecomms/server::log_entries), D)`
- `code/modules/power/singularity/particle_accelerator/particle_smasher.dm:274` — `own_remove(src, nameof(storage), I) // consumed`

## `own_take_member` — 7
Ownership helper compatibility path; separate ownership/containment conversion, preserves release/delete/move policy.
- `code/game/machinery/cloning.dm:485` — `own_take_member(src, nameof(containers), G)`
- `code/game/machinery/machinery.dm:518` — `own_take_member(src, nameof(component_parts), C)`
- `code/game/machinery/machinery.dm:550` — `own_take_member(src, nameof(component_parts), A)`
- `code/game/machinery/telecrystal_storage.dm:19` — `own_take_member(src, nameof(item_records), I)`
- `code/game/machinery/washing_machine.dm:89` — `own_take_member(src, nameof(washing), HH)`
- `code/modules/power/batteryrack.dm:170` — `own_take_member(src, nameof(/obj/machinery/power/smes/batteryrack::internal_cells), C)`
- `code/modules/power/batteryrack.dm:319` — `own_take_member(src, nameof(internal_cells), C)`
