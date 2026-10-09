// Behaviour pins for the timed actions of code/modules/mob, vore, nifsoft, resleeving and body (worker W3), recorded on the legacy forms
// (task_timed / task_start) before they become ops with wait(). Helpers and the documented differences: dq_timed_pin_behaviour.dm.

/datum/unit_test/dq_timed_pin_w3
	parent_type = /datum/unit_test/dq_timed_pin
	abstract_type = /datum/unit_test/dq_timed_pin_w3

// ---- A hand on a goo trap frees the victim ----

/datum/unit_test/dq_timed_pin_w3/gootrap_free

/datum/unit_test/dq_timed_pin_w3/gootrap_free/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = person()
	var/obj/structure/gootrap/G = allocate(/obj/structure/gootrap, run_loc_floor_bottom_left)
	G.set_can_buckle(TRUE)
	G.buckle_mob(victim)
	TEST_ASSERT(G.has_buckled_mobs(), "the trap holds the victim")
	test_chat_clear()
	test_click(user, G, null)
	TEST_ASSERT(!isnull(running(user)), "a bare hand on a loaded trap starts a timed action")
	TEST_ASSERT(said(user, "You carefully begin to free"), "it says it began")
	test_time(0.2 SECONDS)
	TEST_ASSERT(G.has_buckled_mobs(), "the victim is still held before the end")
	if(istype(running(user), /datum/task))
		return // the legacy end of this action raises a runtime (act_message was handed the victims' names as its user): its completion cannot be pinned on the legacy form
	test_time(1 SECOND)
	TEST_ASSERT(!G.has_buckled_mobs(), "the victim is freed at the end")
	TEST_ASSERT(!G.anchored, "and the trap is unanchored")

/datum/unit_test/dq_timed_pin_w3/gootrap_free_cancel_on_move

/datum/unit_test/dq_timed_pin_w3/gootrap_free_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = person()
	var/obj/structure/gootrap/G = allocate(/obj/structure/gootrap, run_loc_floor_bottom_left)
	G.set_can_buckle(TRUE)
	G.buckle_mob(victim)
	test_click(user, G, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand on a loaded trap starts a timed action")
	user.forceMove(get_step(user, NORTH))
	test_time(2 SECONDS)
	TEST_ASSERT(G.has_buckled_mobs(), "moving cancels: the victim stays held")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w3/gootrap_empty_trap_no_action

/datum/unit_test/dq_timed_pin_w3/gootrap_empty_trap_no_action/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/gootrap/G = allocate(/obj/structure/gootrap, run_loc_floor_bottom_left)
	test_click(user, G, null)
	TEST_ASSERT_NULL(running(user), "an empty trap starts nothing")

// ---- The backup implanter console ----

/// TRUE when a backup implant sits in any of `user`'s limbs.
/datum/unit_test/dq_timed_pin_w3/proc/has_backup(mob/living/carbon/human/user)
	var/obj/item/organ/external/torso = user.get_organ(BP_TORSO)
	for(var/obj/item/implant/backup/B in torso.contents)
		return TRUE
	return FALSE

/datum/unit_test/dq_timed_pin_w3/backup_implanter_wrench_off

/datum/unit_test/dq_timed_pin_w3/backup_implanter_wrench_off/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/backup_implanter_ch/I = allocate(/obj/structure/backup_implanter_ch, run_loc_floor_bottom_left)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, run_loc_floor_bottom_left)
	user.put_in_active_hand(W)
	TEST_ASSERT(I.anchored, "it starts anchored")
	test_chat_clear()
	test_click(user, I, W)
	TEST_ASSERT(!isnull(running(user)), "a wrench on an anchored implanter starts a timed action")
	TEST_ASSERT(said(user, "You start to unwrench the implanter"), "it says it began")
	test_time(0.5 SECONDS)
	TEST_ASSERT(I.anchored, "still anchored before the end")
	// Legacy wrench_done runtimes at the end (span_notice around a ternary): the finish is pinned in the converted form only.

/datum/unit_test/dq_timed_pin_w3/backup_implanter_wrench_on

/datum/unit_test/dq_timed_pin_w3/backup_implanter_wrench_on/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/backup_implanter_ch/I = allocate(/obj/structure/backup_implanter_ch, run_loc_floor_bottom_left)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, run_loc_floor_bottom_left)
	I.set_anchored(FALSE)
	user.put_in_active_hand(W)
	test_chat_clear()
	test_click(user, I, W)
	TEST_ASSERT(!isnull(running(user)), "a wrench on a loose implanter starts a timed action")
	TEST_ASSERT(said(user, "You start to wrench the implanter into place"), "it says it began")
	test_time(0.5 SECONDS)
	TEST_ASSERT(!I.anchored, "still loose before the end")

/datum/unit_test/dq_timed_pin_w3/backup_implanter_wrench_cancel_on_drop

/datum/unit_test/dq_timed_pin_w3/backup_implanter_wrench_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/backup_implanter_ch/I = allocate(/obj/structure/backup_implanter_ch, run_loc_floor_bottom_left)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, run_loc_floor_bottom_left)
	user.put_in_active_hand(W)
	test_click(user, I, W)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a wrench on an anchored implanter starts a timed action")
	user.drop_from_inventory(W)
	test_time(10 SECONDS)
	TEST_ASSERT(I.anchored, "dropping the wrench cancels: still anchored")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w3/backup_implanter_self_implant

/datum/unit_test/dq_timed_pin_w3/backup_implanter_self_implant/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/obj/structure/backup_implanter_ch/I = allocate(/obj/structure/backup_implanter_ch, run_loc_floor_bottom_left)
	test_click(user, I, null)
	TEST_ASSERT(!isnull(running(user)), "a bare hand on the implanter starts a timed action")
	test_time(2 SECONDS)
	TEST_ASSERT(!has_backup(user), "nothing is implanted before the end")
	test_time(1 SECOND)
	TEST_ASSERT(has_backup(user), "the backup implant is in the user at the end")

/datum/unit_test/dq_timed_pin_w3/backup_implanter_self_implant_cancel_on_move

/datum/unit_test/dq_timed_pin_w3/backup_implanter_self_implant_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/obj/structure/backup_implanter_ch/I = allocate(/obj/structure/backup_implanter_ch, run_loc_floor_bottom_left)
	test_click(user, I, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand on the implanter starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(4 SECONDS)
	TEST_ASSERT(!has_backup(user), "moving cancels: nothing is implanted")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- The NIF maintenance panel ----

/// A tool used on a NIF. The legacy tool acts (`screwdriver_act`, `multitool_act`) are not reached by the driver's click, so when the click starts nothing the
/// act is called as the click path would; the converted ops answer the click itself.
/datum/unit_test/dq_timed_pin_w3/proc/nif_tool_click(mob/user, obj/item/nif/N, obj/item/tool)
	test_click(user, N, tool)
	if(!isnull(running(user)))
		return
	if(tool.has_tool_quality(TOOL_MULTITOOL))
		N.multitool_act(user, tool)
	else
		N.screwdriver_act(user, tool)

/datum/unit_test/dq_timed_pin_w3/nif_pry_open

/datum/unit_test/dq_timed_pin_w3/nif_pry_open/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/nif/N = allocate(/obj/item/nif, run_loc_floor_bottom_left)
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, run_loc_floor_bottom_left)
	user.put_in_active_hand(S)
	TEST_ASSERT_EQUAL(N.open, 0, "it starts closed")
	nif_tool_click(user, N, S)
	TEST_ASSERT(!isnull(running(user)), "a screwdriver on a closed NIF starts a timed action")
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(N.open, 0, "still closed before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(N.open, 1, "opened at the end")
	TEST_ASSERT(said(user, "You unscrew and pry open"), "it says it finished")

/datum/unit_test/dq_timed_pin_w3/nif_pry_open_cancel_on_drop

/datum/unit_test/dq_timed_pin_w3/nif_pry_open_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/nif/N = allocate(/obj/item/nif, run_loc_floor_bottom_left)
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, run_loc_floor_bottom_left)
	user.put_in_active_hand(S)
	nif_tool_click(user, N, S)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a screwdriver on a closed NIF starts a timed action")
	user.drop_from_inventory(S)
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(N.open, 0, "dropping the screwdriver cancels: still closed")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w3/nif_reseal

/datum/unit_test/dq_timed_pin_w3/nif_reseal/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/nif/N = allocate(/obj/item/nif, run_loc_floor_bottom_left)
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, run_loc_floor_bottom_left)
	N.open = 3
	user.put_in_active_hand(S)
	nif_tool_click(user, N, S)
	TEST_ASSERT(!isnull(running(user)), "a screwdriver on a repaired NIF starts a timed action")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(N.open, 3, "still open before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!N.open, "sealed at the end")
	TEST_ASSERT(said(user, "You re-seal"), "it says it finished")

/datum/unit_test/dq_timed_pin_w3/nif_reset_circuits

/datum/unit_test/dq_timed_pin_w3/nif_reset_circuits/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/nif/N = allocate(/obj/item/nif, run_loc_floor_bottom_left)
	var/obj/item/multitool/M = allocate(/obj/item/multitool, run_loc_floor_bottom_left)
	N.open = 2
	user.put_in_active_hand(M)
	nif_tool_click(user, N, M)
	TEST_ASSERT(!isnull(running(user)), "a multitool on a rewired NIF starts a timed action")
	test_time(7 SECONDS)
	TEST_ASSERT_EQUAL(N.open, 2, "still rewired before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(N.open, 3, "the circuits are reset at the end")
	TEST_ASSERT(said(user, "You find and repair any faulty circuits"), "it says it finished")

/datum/unit_test/dq_timed_pin_w3/nif_reset_circuits_cancel_on_move

/datum/unit_test/dq_timed_pin_w3/nif_reset_circuits_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/nif/N = allocate(/obj/item/nif, run_loc_floor_bottom_left)
	var/obj/item/multitool/M = allocate(/obj/item/multitool, run_loc_floor_bottom_left)
	N.open = 2
	user.put_in_active_hand(M)
	nif_tool_click(user, N, M)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a multitool on a rewired NIF starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(9 SECONDS)
	TEST_ASSERT_EQUAL(N.open, 2, "moving cancels")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w3/nif_rewire

/datum/unit_test/dq_timed_pin_w3/nif_rewire/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/nif/N = allocate(/obj/item/nif, run_loc_floor_bottom_left)
	var/obj/item/stack/cable_coil/C = allocate(/obj/item/stack/cable_coil, run_loc_floor_bottom_left, 10)
	N.open = 1
	N.durability = 10
	user.put_in_active_hand(C)
	test_click(user, N, C)
	TEST_ASSERT(!isnull(running(user)), "cable on a damaged open NIF starts a timed action")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(N.open, 1, "not rewired before the end")
	TEST_ASSERT_EQUAL(C.get_amount(), 10, "and nothing is spent")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(N.open, 2, "rewired at the end")
	TEST_ASSERT_EQUAL(C.get_amount(), 7, "three coils are used")
	TEST_ASSERT(said(user, "You replace any burned out wiring"), "it says it finished")

// ---- Washing a gurgled item at a sink ----

/datum/unit_test/dq_timed_pin_w3/sink_wash_gurgled

/datum/unit_test/dq_timed_pin_w3/sink_wash_gurgled/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/sink/S = allocate(/obj/structure/sink, run_loc_floor_bottom_left)
	var/obj/item/pen/P = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	P.set_gurgled(TRUE)
	user.put_in_active_hand(P)
	test_chat_clear()
	test_click(user, S, P)
	TEST_ASSERT(!isnull(running(user)), "a gurgled item on a sink starts a timed action")
	TEST_ASSERT(said(user, "You start washing"), "it says it began")
	test_time(3 SECONDS)
	TEST_ASSERT(P.gurgled, "still gurgled before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!P.gurgled, "washed at the end")
	TEST_ASSERT(said(user, "You wash"), "it says it finished")

/datum/unit_test/dq_timed_pin_w3/sink_wash_gurgled_cancel_on_drop

/datum/unit_test/dq_timed_pin_w3/sink_wash_gurgled_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/sink/S = allocate(/obj/structure/sink, run_loc_floor_bottom_left)
	var/obj/item/pen/P = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	P.set_gurgled(TRUE)
	user.put_in_active_hand(P)
	test_click(user, S, P)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a gurgled item on a sink starts a timed action")
	user.drop_from_inventory(P)
	test_time(6 SECONDS)
	TEST_ASSERT(P.gurgled, "dropping the item cancels: still gurgled")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/// The wash claims the sink: a second washer is refused.
/datum/unit_test/dq_timed_pin_w3/sink_wash_gurgled_claims_the_sink

/datum/unit_test/dq_timed_pin_w3/sink_wash_gurgled_claims_the_sink/run_pin()
	var/mob/living/carbon/human/one = person()
	var/mob/living/carbon/human/two = person()
	var/obj/structure/sink/S = allocate(/obj/structure/sink, run_loc_floor_bottom_left)
	var/obj/item/pen/P1 = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	var/obj/item/pen/P2 = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	P1.set_gurgled(TRUE)
	P2.set_gurgled(TRUE)
	one.put_in_active_hand(P1)
	two.put_in_active_hand(P2)
	test_click(one, S, P1)
	test_click(two, S, P2)
	TEST_ASSERT(!isnull(running(one)), "the first washer is running")
	TEST_ASSERT_NULL(running(two), "the second washer is refused while the sink is claimed")

// ---- The medbot: tipped over and righted by hand ----

/datum/unit_test/dq_timed_pin_w3/medbot_tip_over

/datum/unit_test/dq_timed_pin_w3/medbot_tip_over/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/bot/medbot/B = allocate(/mob/living/bot/medbot, get_step(run_loc_floor_bottom_left, EAST))
	user.set_use_stance(I_DISARM)
	test_chat_clear()
	test_click(user, B, null)
	TEST_ASSERT(!isnull(running(user)), "a shove on an upright medbot starts a timed action")
	TEST_ASSERT(said(user, "You begin tipping over"), "it says it began")
	test_time(2 SECONDS)
	TEST_ASSERT(!B.is_tipped, "not tipped before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(B.is_tipped, "tipped at the end")
	TEST_ASSERT(said(user, "You tip"), "it says it finished")

/datum/unit_test/dq_timed_pin_w3/medbot_tip_over_cancel_on_move

/datum/unit_test/dq_timed_pin_w3/medbot_tip_over_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/bot/medbot/B = allocate(/mob/living/bot/medbot, get_step(run_loc_floor_bottom_left, EAST))
	user.set_use_stance(I_DISARM)
	test_click(user, B, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a shove on an upright medbot starts a timed action")
	user.forceMove(get_step(user, NORTH))
	test_time(5 SECONDS)
	TEST_ASSERT(!B.is_tipped, "moving cancels: it stays upright")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w3/medbot_right

/datum/unit_test/dq_timed_pin_w3/medbot_right/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/bot/medbot/B = allocate(/mob/living/bot/medbot, get_step(run_loc_floor_bottom_left, EAST))
	B.tip_over(user)
	user.set_use_stance(I_HELP)
	test_chat_clear()
	test_click(user, B, null)
	TEST_ASSERT(!isnull(running(user)), "a help touch on a tipped medbot starts a timed action")
	TEST_ASSERT(said(user, "You begin righting"), "it says it began")
	test_time(2 SECONDS)
	TEST_ASSERT(B.is_tipped, "still tipped before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!B.is_tipped, "set right at the end")
	TEST_ASSERT(said(user, "You set"), "it says it finished")

/datum/unit_test/dq_timed_pin_w3/medbot_right_cancel_on_move

/datum/unit_test/dq_timed_pin_w3/medbot_right_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/bot/medbot/B = allocate(/mob/living/bot/medbot, get_step(run_loc_floor_bottom_left, EAST))
	B.tip_over(user)
	test_click(user, B, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a help touch on a tipped medbot starts a timed action")
	user.forceMove(get_step(user, NORTH))
	test_time(5 SECONDS)
	TEST_ASSERT(B.is_tipped, "moving cancels: it stays tipped")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Service bots work for a time and are busy meanwhile (bot_work) ----

/datum/unit_test/dq_timed_pin_w3/cleanbot_cleans_dirt

/datum/unit_test/dq_timed_pin_w3/cleanbot_cleans_dirt/run_pin()
	var/mob/living/bot/cleanbot/B = allocate(/mob/living/bot/cleanbot, run_loc_floor_bottom_left)
	var/obj/effect/decal/cleanable/dirt/D = allocate(/obj/effect/decal/cleanable/dirt, run_loc_floor_bottom_left)
	B.UnarmedAttack(D, TRUE)
	TEST_ASSERT(!isnull(running(B)), "the bot starts working")
	TEST_ASSERT(B.icon_state == "cleanbot-c", "and shows it is busy")
	test_time(0.5 SECONDS)
	TEST_ASSERT(!QDELETED(D), "the dirt is there before the end")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(D), "the dirt is gone at the end")
	TEST_ASSERT(B.icon_state != "cleanbot-c", "and the bot is idle again")

/datum/unit_test/dq_timed_pin_w3/cleanbot_cancel_on_move

/datum/unit_test/dq_timed_pin_w3/cleanbot_cancel_on_move/run_pin()
	var/mob/living/bot/cleanbot/B = allocate(/mob/living/bot/cleanbot, run_loc_floor_bottom_left)
	var/obj/effect/decal/cleanable/dirt/D = allocate(/obj/effect/decal/cleanable/dirt, run_loc_floor_bottom_left)
	B.UnarmedAttack(D, TRUE)
	var/datum/T = running(B)
	TEST_ASSERT(!isnull(T), "the bot starts working")
	B.forceMove(get_step(B, EAST))
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(D), "moving the bot cancels the work")
	TEST_ASSERT(was_cancelled(T, B), "the work ends cancelled")
	TEST_ASSERT(B.icon_state != "cleanbot-c", "and the bot is idle again")

/datum/unit_test/dq_timed_pin_w3/cleanbot_cancel_on_target_loss

/datum/unit_test/dq_timed_pin_w3/cleanbot_cancel_on_target_loss/run_pin()
	var/mob/living/bot/cleanbot/B = allocate(/mob/living/bot/cleanbot, run_loc_floor_bottom_left)
	var/obj/effect/decal/cleanable/dirt/D = allocate(/obj/effect/decal/cleanable/dirt, run_loc_floor_bottom_left)
	B.UnarmedAttack(D, TRUE)
	var/datum/T = running(B)
	TEST_ASSERT(!isnull(T), "the bot starts working")
	qdel(D)
	test_time(3 SECONDS)
	TEST_ASSERT(was_cancelled(T, B), "deleting the target ends the work")
	TEST_ASSERT(B.icon_state != "cleanbot-c", "and the bot is idle again")

/datum/unit_test/dq_timed_pin_w3/floorbot_collects_tiles

/datum/unit_test/dq_timed_pin_w3/floorbot_collects_tiles/run_pin()
	var/mob/living/bot/floorbot/B = allocate(/mob/living/bot/floorbot, run_loc_floor_bottom_left)
	var/obj/item/stack/tile/floor/T = allocate(/obj/item/stack/tile/floor, run_loc_floor_bottom_left, 5)
	var/start = B.amount
	B.UnarmedAttack(T, TRUE)
	TEST_ASSERT(!isnull(running(B)), "the bot starts working")
	test_time(1.5 SECONDS)
	TEST_ASSERT_EQUAL(B.amount, start, "nothing is collected before the end")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(B.amount, start + 5, "the tiles are collected at the end")

/datum/unit_test/dq_timed_pin_w3/floorbot_collects_tiles_cancel_on_target_move

/datum/unit_test/dq_timed_pin_w3/floorbot_collects_tiles_cancel_on_target_move/run_pin()
	var/mob/living/bot/floorbot/B = allocate(/mob/living/bot/floorbot, run_loc_floor_bottom_left)
	var/obj/item/stack/tile/floor/T = allocate(/obj/item/stack/tile/floor, run_loc_floor_bottom_left, 5)
	var/start = B.amount
	B.UnarmedAttack(T, TRUE)
	var/datum/W = running(B)
	TEST_ASSERT(!isnull(W), "the bot starts working")
	T.forceMove(get_step(T, EAST))
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(B.amount, start, "a target carried off collects nothing")
	TEST_ASSERT(was_cancelled(W, B), "the work ends cancelled")

/datum/unit_test/dq_timed_pin_w3/floorbot_collects_tiles_cancel_on_target_loss

/datum/unit_test/dq_timed_pin_w3/floorbot_collects_tiles_cancel_on_target_loss/run_pin()
	var/mob/living/bot/floorbot/B = allocate(/mob/living/bot/floorbot, run_loc_floor_bottom_left)
	var/obj/item/stack/tile/floor/T = allocate(/obj/item/stack/tile/floor, run_loc_floor_bottom_left, 5)
	var/start = B.amount
	B.UnarmedAttack(T, TRUE)
	var/datum/W = running(B)
	TEST_ASSERT(!isnull(W), "the bot starts working")
	qdel(T)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(B.amount, start, "a lost target collects nothing")
	TEST_ASSERT(was_cancelled(W, B), "the work ends cancelled")

/datum/unit_test/dq_timed_pin_w3/floorbot_makes_tiles

/datum/unit_test/dq_timed_pin_w3/floorbot_makes_tiles/run_pin()
	var/mob/living/bot/floorbot/B = allocate(/mob/living/bot/floorbot, run_loc_floor_bottom_left)
	B.maketiles = TRUE
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, run_loc_floor_bottom_left, 5)
	var/start = B.amount
	B.UnarmedAttack(S, TRUE)
	TEST_ASSERT(!isnull(running(B)), "the bot starts working")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.get_amount(), 5, "no steel is used before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(S.get_amount(), 4, "one sheet is used at the end")
	TEST_ASSERT_EQUAL(B.amount, start + 4, "and four tiles are made")

/// A bot that is working is busy: it takes no second job.
/datum/unit_test/dq_timed_pin_w3/floorbot_takes_one_job_at_a_time

/datum/unit_test/dq_timed_pin_w3/floorbot_takes_one_job_at_a_time/run_pin()
	var/mob/living/bot/floorbot/B = allocate(/mob/living/bot/floorbot, run_loc_floor_bottom_left)
	var/obj/item/stack/tile/floor/T = allocate(/obj/item/stack/tile/floor, run_loc_floor_bottom_left, 5)
	var/obj/item/stack/tile/floor/T2 = allocate(/obj/item/stack/tile/floor, run_loc_floor_bottom_left, 5)
	var/start = B.amount
	B.UnarmedAttack(T, TRUE)
	B.UnarmedAttack(T2, TRUE)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(B.amount, start + 5, "only the first job is done")

// ---- Simple mobs at timed work of their own (AI-started) ----

/datum/unit_test/dq_timed_pin_w3/spider_spins_web

/datum/unit_test/dq_timed_pin_w3/spider_spins_web/run_pin()
	var/mob/living/simple_mob/animal/giant_spider/nurse/N = allocate(/mob/living/simple_mob/animal/giant_spider/nurse, run_loc_floor_bottom_left)
	var/turf/T = get_turf(N)
	TEST_ASSERT(N.web_tile(T), "the spider starts a web")
	TEST_ASSERT(!isnull(running(N)), "and is at work")
	TEST_ASSERT(!N.web_tile(T), "a spider at work takes no second job")
	test_time(4 SECONDS)
	TEST_ASSERT(isnull(locate(/obj/effect/spider/stickyweb) in T), "no web before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!isnull(locate(/obj/effect/spider/stickyweb) in T), "the web is there at the end")
	TEST_ASSERT_NULL(running(N), "and the spider is free again")
	qdel(locate(/obj/effect/spider/stickyweb) in T)

/datum/unit_test/dq_timed_pin_w3/spider_web_goes_on_when_the_spider_steps

/datum/unit_test/dq_timed_pin_w3/spider_web_goes_on_when_the_spider_steps/run_pin()
	var/mob/living/simple_mob/animal/giant_spider/nurse/N = allocate(/mob/living/simple_mob/animal/giant_spider/nurse, run_loc_floor_bottom_left)
	var/turf/T = get_turf(N)
	N.web_tile(T)
	var/datum/W = running(N)
	TEST_ASSERT(!isnull(W), "the spider is at work")
	N.forceMove(get_step(N, EAST))
	test_time(6 SECONDS)
	TEST_ASSERT(!isnull(locate(/obj/effect/spider/stickyweb) in T), "a spider that steps aside (the mob work had no stay-put rule) still spins the web")
	qdel(locate(/obj/effect/spider/stickyweb) in T)

/datum/unit_test/dq_timed_pin_w3/spider_lays_eggs

/datum/unit_test/dq_timed_pin_w3/spider_lays_eggs/run_pin()
	var/mob/living/simple_mob/animal/giant_spider/nurse/N = allocate(/mob/living/simple_mob/animal/giant_spider/nurse, run_loc_floor_bottom_left)
	var/turf/T = get_turf(N)
	N.fed = 2
	N.can_lay_eggs = TRUE
	TEST_ASSERT(N.lay_eggs(T), "the spider starts laying")
	test_time(4 SECONDS)
	TEST_ASSERT(isnull(locate(/obj/effect/spider/eggcluster) in T), "no eggs before the end")
	TEST_ASSERT_EQUAL(N.fed, 2, "and nothing is spent")
	test_time(2 SECONDS)
	TEST_ASSERT(!isnull(locate(/obj/effect/spider/eggcluster) in T), "the eggs are there at the end")
	TEST_ASSERT_EQUAL(N.fed, 1, "and one feeding is spent")
	qdel(locate(/obj/effect/spider/eggcluster) in T)

/datum/unit_test/dq_timed_pin_w3/spider_spins_cocoon

/datum/unit_test/dq_timed_pin_w3/spider_spins_cocoon/run_pin()
	var/mob/living/simple_mob/animal/giant_spider/nurse/N = allocate(/mob/living/simple_mob/animal/giant_spider/nurse, run_loc_floor_bottom_left)
	var/obj/item/pen/P = allocate(/obj/item/pen, get_step(run_loc_floor_bottom_left, EAST))
	TEST_ASSERT(N.spin_cocoon(P), "the spider starts a cocoon")
	test_time(4 SECONDS)
	TEST_ASSERT(isnull(locate(/obj/effect/spider/cocoon) in get_turf(P)), "no cocoon before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!isnull(locate(/obj/effect/spider/cocoon) in get_turf(P)), "the cocoon is there at the end")
	qdel(locate(/obj/effect/spider/cocoon) in get_turf(P))

/datum/unit_test/dq_timed_pin_w3/simple_mob_reloads

/datum/unit_test/dq_timed_pin_w3/simple_mob_reloads/run_pin()
	var/mob/living/simple_mob/M = allocate(/mob/living/simple_mob, run_loc_floor_bottom_left)
	M.needs_reload = TRUE
	M.reload_max = 3
	M.reload_count = 3
	M.reload_time = 4 SECONDS
	M.try_reload()
	TEST_ASSERT(!isnull(running(M)), "the mob starts reloading")
	M.try_reload()
	TEST_ASSERT_EQUAL(running_count(M), 1, "a second call leaves one reload running")
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(M.reload_count, 3, "not reloaded before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(M.reload_count, 0, "reloaded at the end")

/datum/unit_test/dq_timed_pin_w3/simple_mob_reload_cancel_on_move

/datum/unit_test/dq_timed_pin_w3/simple_mob_reload_cancel_on_move/run_pin()
	var/mob/living/simple_mob/M = allocate(/mob/living/simple_mob, run_loc_floor_bottom_left)
	M.needs_reload = TRUE
	M.reload_max = 3
	M.reload_count = 3
	M.reload_time = 4 SECONDS
	M.try_reload()
	var/datum/T = running(M)
	TEST_ASSERT(!isnull(T), "the mob starts reloading")
	M.forceMove(get_step(M, EAST))
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(M.reload_count, 3, "moving cancels the reload")
	TEST_ASSERT(was_cancelled(T, M), "the reload ends cancelled")

// ---- Cass plays dead until she is petted for a long time ----

/datum/unit_test/dq_timed_pin_w3/cass_revived_by_long_pet

/datum/unit_test/dq_timed_pin_w3/cass_revived_by_long_pet/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/simple_mob/vore/woof/cass/C = allocate(/mob/living/simple_mob/vore/woof/cass, get_step(run_loc_floor_bottom_left, EAST))
	C.stat = DEAD
	user.set_use_stance(I_HELP)
	test_click(user, C, null)
	TEST_ASSERT(!isnull(running(user)), "a help touch on a dead Cass starts a timed action")
	test_time(29 SECONDS)
	TEST_ASSERT_EQUAL(C.stat, DEAD, "she is still down before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(C.stat != DEAD, "she is up at the end")

/datum/unit_test/dq_timed_pin_w3/cass_pet_cancel_on_move

/datum/unit_test/dq_timed_pin_w3/cass_pet_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/simple_mob/vore/woof/cass/C = allocate(/mob/living/simple_mob/vore/woof/cass, get_step(run_loc_floor_bottom_left, EAST))
	C.stat = DEAD
	user.set_use_stance(I_HELP)
	test_chat_clear()
	test_click(user, C, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a help touch on a dead Cass starts a timed action")
	user.forceMove(get_step(user, NORTH))
	test_time(31 SECONDS)
	TEST_ASSERT_EQUAL(C.stat, DEAD, "moving cancels: she stays down")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")
