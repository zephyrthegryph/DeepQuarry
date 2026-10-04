// Behaviour pins for how silicons reach machines (doc/rewrite/final_api.html section 8 "Origin, reach, provider, authority"; 16.2 the
// airlock's AI control; 16.8 a cyborg's providers). An AI, a cyborg, a drone and a pAI click, alt-, ctrl-, shift- and middle-click doors, an
// APC, the turret control and an intercom; a cyborg uses a tool module and a gripper. Every input is the click event a client sends, through the
// input inbox, so the same tests drive the legacy silicon hooks and the remote() ops that replace them. Only state is asserted, never text.

/// A player's click of `params` (the client's modifier string) by `actor` on `target`, through the input inbox.
/proc/dq_silicon_click(mob/actor, atom/target, params = "left=1")
	actor.next_click = 0
	var/datum/input_event/click/E = new(actor, target, null, "mapwindow.map", params)
	input_submit(E)
	return E.result

/datum/unit_test/dq_p2_door/silicon
	abstract_type = /datum/unit_test/dq_p2_door/silicon

/// A player's gesture, and the time for it to play out.
/datum/unit_test/dq_p2_door/silicon/proc/gesture(mob/actor, atom/target, params)
	dq_silicon_click(actor, target, params)
	settle()

/// An AI on the room's floor (not in nullspace), where its core sees the whole room.
/datum/unit_test/dq_p2_door/silicon/proc/placed_ai()
	var/mob/living/silicon/ai/AI = make_ai()
	AI.forceMove(tile(0, 0))
	return AI

/// A cyborg beside the door whose ID card has `access` (an empty list: none).
/datum/unit_test/dq_p2_door/silicon/proc/make_borg(list/access, turf/where)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, where || tile(3, 2))
	R.enable_godmode()
	if(!R.module)
		rel_set(R, nameof(R.module), new /obj/item/robot_module/robot/standard(R))
	if(R.idcard && !isnull(access))
		R.idcard.access = access.Copy()
	return R

/// A module of `type` given to the cyborg, activated and selected: the borg's held item.
/datum/unit_test/dq_p2_door/silicon/proc/give_module(mob/living/silicon/robot/R, type)
	var/obj/item/I = new type(R.module)
	rel_add(R.module, nameof(R.module.modules), I)
	R.activate_module(I)
	R.select_module(R.module_slot_of(I))
	return I

// ---------------------------------------------------------------------------------------------------------------------
// The AI's gestures on an airlock: shift opens or closes, ctrl bolts, alt electrifies, middle switches the bolt lights
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/silicon/ai_shift_click_opens_and_closes

/datum/unit_test/dq_p2_door/silicon/ai_shift_click_opens_and_closes/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = placed_ai()
	gesture(AI, D, "left=1;shift=1")
	TEST_ASSERT(!D.density, "an AI's shift-click opens the door")
	gesture(AI, D, "left=1;shift=1")
	TEST_ASSERT(D.density, "and closes it")
	p2_door_set_bolts(D, TRUE)
	gesture(AI, D, "left=1;shift=1")
	TEST_ASSERT(D.density, "a bolted door stays shut")

/datum/unit_test/dq_p2_door/silicon/ai_ctrl_click_bolts

/datum/unit_test/dq_p2_door/silicon/ai_ctrl_click_bolts/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = placed_ai()
	gesture(AI, D, "left=1;ctrl=1")
	TEST_ASSERT(p2_door_bolted(D), "an AI's ctrl-click drops the bolts")
	gesture(AI, D, "left=1;ctrl=1")
	TEST_ASSERT(!p2_door_bolted(D), "and raises them")

/datum/unit_test/dq_p2_door/silicon/ai_alt_click_electrifies

/datum/unit_test/dq_p2_door/silicon/ai_alt_click_electrifies/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = placed_ai()
	gesture(AI, D, "left=1;alt=1")
	TEST_ASSERT(p2_door_electrified(D), "an AI's alt-click electrifies the door")
	gesture(AI, D, "left=1;alt=1")
	TEST_ASSERT(!p2_door_electrified(D), "and stops it")

/datum/unit_test/dq_p2_door/silicon/ai_middle_click_switches_bolt_lights

/datum/unit_test/dq_p2_door/silicon/ai_middle_click_switches_bolt_lights/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = placed_ai()
	var/was = D.lights
	gesture(AI, D, "middle=1")
	TEST_ASSERT_EQUAL(!!D.lights, !was, "an AI's middle-click switches the bolt lights")
	gesture(AI, D, "middle=1")
	TEST_ASSERT_EQUAL(!!D.lights, !!was, "and back")

/datum/unit_test/dq_p2_door/silicon/ai_with_control_wire_cut_cannot_work_the_door

/datum/unit_test/dq_p2_door/silicon/ai_with_control_wire_cut_cannot_work_the_door/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = placed_ai()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_cut(D, WIRE_AI_CONTROL, H)
	gesture(AI, D, "left=1;ctrl=1")
	TEST_ASSERT(!p2_door_bolted(D), "with the AI wire cut its ctrl-click does not bolt")
	gesture(AI, D, "left=1;shift=1")
	TEST_ASSERT(D.density, "nor does its shift-click open the door")
	p2_door_wire_cut(D, WIRE_AI_CONTROL, H) // mend
	gesture(AI, D, "left=1;ctrl=1")
	TEST_ASSERT(p2_door_bolted(D), "mended, it bolts")

/datum/unit_test/dq_p2_door/silicon/ai_with_wireless_disabled_does_nothing

/datum/unit_test/dq_p2_door/silicon/ai_with_wireless_disabled_does_nothing/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = placed_ai()
	AI.control_disabled = TRUE
	gesture(AI, D, "left=1;ctrl=1")
	TEST_ASSERT(!p2_door_bolted(D), "an AI whose wireless interface is off cannot bolt")
	gesture(AI, D, "left=1;shift=1")
	TEST_ASSERT(D.density, "nor open")
	AI.control_disabled = FALSE
	gesture(AI, D, "left=1;ctrl=1")
	TEST_ASSERT(p2_door_bolted(D), "with it back on, it can")

/// A human's ctrl- and shift-clicks are a pull and an examine, never the remote controls.
/datum/unit_test/dq_p2_door/silicon/human_gestures_are_not_remote_control

/datum/unit_test/dq_p2_door/silicon/human_gestures_are_not_remote_control/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE))
	gesture(H, D, "left=1;ctrl=1")
	TEST_ASSERT(!p2_door_bolted(D), "a human's ctrl-click does not bolt")
	gesture(H, D, "left=1;shift=1")
	TEST_ASSERT(D.density, "nor its shift-click open")
	gesture(H, D, "left=1;alt=1")
	TEST_ASSERT(!p2_door_electrified(D), "nor its alt-click electrify")

// ---------------------------------------------------------------------------------------------------------------------
// Cyborgs, drones and pAIs at the airlock
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/silicon/borg_gestures_need_the_door_access

/datum/unit_test/dq_p2_door/silicon/borg_gestures_need_the_door_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/silicon/robot/R = make_borg(list(ACCESS_ENGINE), tile(4, 4))
	gesture(R, D, "left=1;ctrl=1")
	TEST_ASSERT(p2_door_bolted(D), "a cyborg with the door's access bolts it from across the room")
	gesture(R, D, "left=1;ctrl=1")
	TEST_ASSERT(!p2_door_bolted(D), "and unbolts it")
	gesture(R, D, "left=1;shift=1")
	TEST_ASSERT(!D.density, "its shift-click opens it")
	gesture(R, D, "left=1;shift=1")
	TEST_ASSERT(D.density, "and closes it")
	R.idcard.access = list()
	gesture(R, D, "left=1;ctrl=1")
	TEST_ASSERT(!p2_door_bolted(D), "without the access it cannot bolt")
	gesture(R, D, "left=1;shift=1")
	TEST_ASSERT(D.density, "nor open")
	gesture(R, D, "left=1;alt=1")
	TEST_ASSERT(!p2_door_electrified(D), "nor electrify")

/datum/unit_test/dq_p2_door/silicon/restraining_bolt_blocks_remote_control

/datum/unit_test/dq_p2_door/silicon/restraining_bolt_blocks_remote_control/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/robot/R = make_borg(list(ACCESS_ENGINE), tile(4, 4))
	var/obj/item/implant/restrainingbolt/bolt = new(R)
	TEST_ASSERT(R.install_bolt(bolt, null), "the bolt goes in")
	gesture(R, D, "left=1;ctrl=1")
	TEST_ASSERT(!p2_door_bolted(D), "a cyborg with a working restraining bolt cannot bolt a door")
	gesture(R, D, "left=1;shift=1")
	TEST_ASSERT(D.density, "nor open one")

/datum/unit_test/dq_p2_door/silicon/drone_bolts_with_access

/datum/unit_test/dq_p2_door/silicon/drone_bolts_with_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/robot/drone/drone = allocate(/mob/living/silicon/robot/drone, tile(3, 2))
	drone.enable_godmode()
	if(drone.idcard)
		drone.idcard.access = list(ACCESS_ENGINE)
	gesture(drone, D, "left=1;ctrl=1")
	TEST_ASSERT(p2_door_bolted(D), "a maintenance drone works the door's remote controls like any cyborg")

/datum/unit_test/dq_p2_door/silicon/pai_has_no_remote_control

/datum/unit_test/dq_p2_door/silicon/pai_has_no_remote_control/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/obj/item/paicard/card = allocate(/obj/item/paicard, tile(0, 4))
	var/mob/living/silicon/pai/P = allocate(/mob/living/silicon/pai, card)
	if(!card.pai)
		rel_set(card, nameof(card.pai), P)
	P.forceMove(tile(3, 2))
	gesture(P, D, "left=1;ctrl=1")
	TEST_ASSERT(!p2_door_bolted(D), "a pAI's ctrl-click does not bolt the door")
	gesture(P, D, "left=1;shift=1")
	TEST_ASSERT(D.density, "nor its shift-click open it")
	card.removePersonality()

// ---------------------------------------------------------------------------------------------------------------------
// The APC, the turret control and the intercom
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/silicon/ai_ctrl_click_switches_the_apc_breaker

/datum/unit_test/dq_p2_door/silicon/ai_ctrl_click_switches_the_apc_breaker/run_gate()
	var/obj/machinery/power/apc/A = allocate(/obj/machinery/power/apc, tile(2, 4))
	var/mob/living/silicon/ai/AI = placed_ai()
	var/was = A.operating
	gesture(AI, A, "left=1;ctrl=1")
	TEST_ASSERT_EQUAL(!!A.operating, !was, "an AI's ctrl-click throws the APC's breaker")
	gesture(AI, A, "left=1;ctrl=1")
	TEST_ASSERT_EQUAL(!!A.operating, !!was, "and back")
	var/datum/op_result/opened = test_click(AI, A, null)
	TEST_ASSERT_EQUAL(opened?.key, "ui_open", "its plain click opens the window")
	qdel(A)
	tidy(tile(2, 4))

/datum/unit_test/dq_p2_door/silicon/ai_gestures_work_the_turret_control

/datum/unit_test/dq_p2_door/silicon/ai_gestures_work_the_turret_control/run_gate()
	var/obj/machinery/turretid/T = allocate(/obj/machinery/turretid, tile(2, 4))
	var/mob/living/silicon/ai/AI = placed_ai()
	T.lethal_is_configurable = TRUE
	var/was_on = T.enabled
	var/was_lethal = T.lethal
	gesture(AI, T, "left=1;ctrl=1")
	TEST_ASSERT_EQUAL(!!T.enabled, !was_on, "an AI's ctrl-click switches the turrets")
	gesture(AI, T, "left=1;alt=1")
	TEST_ASSERT_EQUAL(!!T.lethal, !was_lethal, "its alt-click switches lethal mode")

/datum/unit_test/dq_p2_door/silicon/ai_gestures_work_an_intercom

/datum/unit_test/dq_p2_door/silicon/ai_gestures_work_an_intercom/run_gate()
	var/obj/item/radio/intercom/I = allocate(/obj/item/radio/intercom, tile(2, 4))
	var/mob/living/silicon/ai/AI = placed_ai()
	var/was = I.broadcasting
	gesture(AI, I, "left=1;ctrl=1")
	TEST_ASSERT_EQUAL(!!I.broadcasting, !was, "an AI's ctrl-click switches the intercom's microphone")
	var/freq = I.frequency
	gesture(AI, I, "left=1;alt=1")
	TEST_ASSERT(I.frequency != freq, "its alt-click switches it to or from the AI channel")
	TEST_ASSERT(I.frequency == AI_FREQ || freq == AI_FREQ, "the AI channel is one end of the switch")

// ---------------------------------------------------------------------------------------------------------------------
// A cyborg's modules: a tool, and the gripper carrying a cell in and out of an APC
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_door/silicon/borg_screwdriver_module_opens_the_panel

/datum/unit_test/dq_p2_door/silicon/borg_screwdriver_module_opens_the_panel/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/robot/R = make_borg(list(ACCESS_ENGINE))
	var/obj/item/tool = give_module(R, /obj/item/tool/screwdriver/cyborg)
	tool.toolspeed = 0
	TEST_ASSERT_EQUAL(R.get_active_hand(), tool, "the module is the cyborg's held item")
	gesture(R, D, "left=1")
	TEST_ASSERT(p2_door_panel_open(D), "the cyborg's screwdriver module opens the door's panel")

/datum/unit_test/dq_p2_door/silicon/gripper_moves_a_cell_in_and_out_of_an_apc

/datum/unit_test/dq_p2_door/silicon/gripper_moves_a_cell_in_and_out_of_an_apc/run_gate()
	var/obj/machinery/power/apc/A = allocate(/obj/machinery/power/apc, tile(2, 3))
	var/mob/living/silicon/robot/R = make_borg(list(ACCESS_ENGINE), tile(2, 2))
	var/obj/item/gripper/G = give_module(R, /obj/item/gripper/engineering)
	var/mob/living/carbon/human/H = make_person(null, tile(3, 3))
	A.coverlocked = FALSE
	click(H, A, give_tool(H, /obj/item/tool/crowbar)) // a person pries the cover open
	H.drop_item()
	TEST_ASSERT(p2_apc_cover_open(A), "the APC's cover is open")
	var/obj/item/cell/original = A.cell
	TEST_ASSERT_NOTNULL(original, "the APC starts with a cell")
	TEST_ASSERT_EQUAL(R.get_active_hand(), G, "the gripper is selected")
	gesture(R, A, "left=1")
	TEST_ASSERT_NULL(A.cell, "an empty gripper takes the APC's cell out")
	qdel(A)
	tidy(tile(2, 3))
	tidy(tile(2, 2)) // the old gripper path dropped the cell on the cyborg's tile
