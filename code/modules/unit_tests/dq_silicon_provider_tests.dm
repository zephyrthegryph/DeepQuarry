// The silicon providers (doc/rewrite/final_api.html section 8, 16.8; round-5 decision NS1): an AI's interface is provides(AFF_CONTROL, authority =
// AUTH_REMOTE_ACCESS), a cyborg's the same beside its module slots, and its selected gripper is its hand (library/mob/silicon.dm). The ops they work
// are remote() ops; a mob with neither refuses.

/// Base: the kernel on its injected clock around the test, a clean driver after.
/datum/unit_test/dq_silicon
	abstract_type = /datum/unit_test/dq_silicon

/datum/unit_test/dq_silicon/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_silicon/proc/run_gate()
	return

/// A silicon AI, its core beside the fixtures, and a cyborg and a human (in godmode, so the clock cannot hurt them).
/datum/unit_test/dq_silicon/proc/make_ai(turf/T)
	return allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)

/datum/unit_test/dq_silicon/proc/make_borg(turf/T)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	R.enable_godmode()
	return R

/datum/unit_test/dq_silicon/proc/make_human(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.enable_godmode()
	return H

/// The providers declared on the silicons: the AI's interface alone; the borg's interface and manipulators, and its gripper while selected.
/datum/unit_test/dq_silicon/providers_declared

/datum/unit_test/dq_silicon/providers_declared/run_gate()
	var/turf/T = test_floor()
	var/mob/living/silicon/ai/AI = make_ai(T)
	var/mob/living/silicon/robot/R = make_borg(T)
	var/mob/living/carbon/human/H = make_human(T)
	var/list/ai_aff = list()
	for(var/datum/prov/V as anything in providers_for(AI, null))
		ai_aff += V.aff()
		TEST_ASSERT_EQUAL(V.authority_mask(), AUTH_REMOTE_ACCESS, "the AI's provider is remote access only")
		TEST_ASSERT_NULL(V.reach(), "and supplies no tile reach")
	TEST_ASSERT_EQUAL(length(ai_aff), 1, "the AI has one provider")
	TEST_ASSERT((ai_aff[1] & AFF_CONTROL) == AFF_CONTROL, "of AFF_CONTROL")
	var/hands = 0
	var/interface = 0
	for(var/datum/prov/V as anything in providers_for(R, null))
		if(V.authority_mask() == AUTH_REMOTE_ACCESS)
			interface++
			TEST_ASSERT_EQUAL(V.reach(), BORG_INTERFACE_REACH, "a borg's interface reaches as far as it sees")
		else if((V.aff() & AFF_MANIPULATE))
			hands++
	TEST_ASSERT_EQUAL(interface, 1, "a borg has its interface")
	TEST_ASSERT_EQUAL(hands, 1, "and its chassis manipulators")
	hands = 0
	if(!R.module)
		rel_set(R, nameof(R.module), new /obj/item/robot_module/robot/standard(R))
	var/obj/item/gripper/G = new /obj/item/gripper(R.module)
	rel_add(R.module, nameof(R.module.modules), G)
	R.activate_module(G)
	R.select_module(R.module_slot_of(G))
	for(var/datum/prov/V as anything in providers_for(R, R.held_for_ops()))
		if(V.authority_mask() != AUTH_REMOTE_ACCESS && (V.aff() & AFF_MANIPULATE) && V.source == G)
			hands++
			TEST_ASSERT_EQUAL(V.source, G, "the hand is the selected gripper")
	TEST_ASSERT_EQUAL(hands, 1, "a selected gripper is a hand too")
	var/datum/prov/picked = reach_pick_provider(providers_for(R, null), null, R.held_carrier())
	TEST_ASSERT_EQUAL(picked?.source, G, "and the one that does the work")
	for(var/datum/prov/V as anything in providers_for(H, null))
		TEST_ASSERT(V.authority_mask() != AUTH_REMOTE_ACCESS, "a human has no remote interface")
	TEST_ASSERT_EQUAL(actor_authority(AI), AUTH_REMOTE_ACCESS, "the AI's clicks carry remote access")
	TEST_ASSERT_EQUAL(actor_authority(R), AUTH_PHYSICAL | AUTH_REMOTE_ACCESS, "a borg's carry both")
	TEST_ASSERT_EQUAL(actor_authority(H), AUTH_PHYSICAL, "a human's are physical")

/// The fixture's emergency switch is a remote() op: an AI and a borg click it, a human who picks it from the menu is refused.
/datum/unit_test/dq_silicon/light_emergency_toggle

/datum/unit_test/dq_silicon/light_emergency_toggle/run_gate()
	var/turf/T = test_floor()
	var/turf/side = get_step(T, EAST)
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	var/mob/living/silicon/ai/AI = make_ai(side)
	var/mob/living/silicon/robot/R = make_borg(locate(T.x + 3, T.y, T.z)) // out of its gripper's reach: beside the fixture its empty gripper takes the bulb out instead
	var/mob/living/carbon/human/H = make_human(side)
	var/was = L.no_emergency
	var/datum/op_result/refused = test_menu(H, L, "toggle_emergency")
	TEST_ASSERT(!refused || refused.outcome != ACT_COMMITTED, "a human has no interface to do it with")
	TEST_ASSERT_EQUAL(L.no_emergency, was, "and nothing changed")
	var/datum/op_result/by_ai = test_click(AI, L, null)
	TEST_ASSERT_EQUAL(by_ai?.key, "toggle_emergency", "an AI's click is the remote() op")
	TEST_ASSERT_EQUAL(by_ai?.outcome, ACT_COMMITTED, "and it commits")
	TEST_ASSERT_EQUAL(L.no_emergency, !was, "the fixture's emergency lighting went off")
	var/datum/op_result/by_borg = test_click(R, L, null)
	TEST_ASSERT_EQUAL(by_borg?.key, "toggle_emergency", "a borg's click from across the room is the same op")
	TEST_ASSERT_EQUAL(L.no_emergency, was, "and back on")

/// The APC's windows open for an AI and a borg through the interface() open op's remote() binding, its silicon-only buttons work for them, and a
/// human next to it is refused them.
/datum/unit_test/dq_silicon/apc_remote_and_silicon_ops

/datum/unit_test/dq_silicon/apc_remote_and_silicon_ops/run_gate()
	var/turf/T = test_floor()
	var/turf/side = get_step(T, EAST)
	var/turf/far = locate(T.x + 3, T.y, T.z)
	var/obj/machinery/power/apc/A = allocate(/obj/machinery/power/apc, T)
	var/mob/living/silicon/ai/AI = make_ai(far)
	var/mob/living/silicon/robot/R = make_borg(far)
	var/mob/living/carbon/human/H = make_human(side)
	var/datum/op_result/open_ai = test_click(AI, A, null)
	TEST_ASSERT_EQUAL(open_ai?.key, "ui_open", "an AI's click opens the APC's window")
	var/datum/op_result/open_borg = test_click(R, A, null)
	TEST_ASSERT_EQUAL(open_borg?.key, "ui_open", "so does a borg's, from across the room")
	var/datum/op_result/overload_ai = test_ui(AI, A, "overload")
	TEST_ASSERT_EQUAL(overload_ai?.key, "overload", "an AI presses the silicon-only overload button")
	TEST_ASSERT_EQUAL(overload_ai?.outcome, ACT_COMMITTED, "and it commits")
	var/datum/op_result/overload_borg = test_ui(R, A, "overload")
	TEST_ASSERT_EQUAL(overload_borg?.outcome, ACT_COMMITTED, "a borg presses it too")
	var/datum/op_result/overload_human = test_ui(H, A, "overload")
	TEST_ASSERT(!overload_human || overload_human.outcome != ACT_COMMITTED, "a human is refused it")
	var/was = A.operating
	var/datum/op_result/breaker = test_ui(AI, A, "breaker")
	TEST_ASSERT_EQUAL(breaker?.outcome, ACT_COMMITTED, "an AI works the breaker through its provider")
	TEST_ASSERT_EQUAL(A.operating, !was, "and the breaker went over")
	qdel(A) // it spills its cell as it goes: the test owns that
	for(var/turf/spot in list(T, side, far))
		own_turf_contents(spot)

/// The airlock's control window opens for silicons by their remote() binding: an AI's click is that op, a human's the door's own.
/datum/unit_test/dq_silicon/airlock_remote_control

/datum/unit_test/dq_silicon/airlock_remote_control/run_gate()
	var/turf/T = test_floor()
	var/turf/side = get_step(T, EAST)
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, T)
	var/mob/living/silicon/ai/AI = make_ai(side)
	var/mob/living/silicon/robot/R = make_borg(side)
	var/mob/living/carbon/human/H = make_human(side)
	var/datum/op_result/by_ai = test_click(AI, door, null)
	TEST_ASSERT_EQUAL(by_ai?.key, "ui_open", "an AI's click opens the control window")
	var/datum/op_result/by_borg = test_click(R, door, null)
	TEST_ASSERT_EQUAL(by_borg?.key, "ui_open", "so does a borg's")
	var/datum/op_result/by_human = test_menu(H, door, "ui_open")
	TEST_ASSERT(!by_human || by_human.outcome != ACT_COMMITTED, "a human is not given the silicon window")

/// The cyborg light replacer's use in the hand asks reserves or colour: the colour answer sets the colour, the reserves answer fabricates a light
/// after the borg stands still, and with the reserves empty nothing is fabricated.
/datum/unit_test/dq_silicon/dogborg_light_replacer

/datum/unit_test/dq_silicon/dogborg_light_replacer/run_gate()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = make_borg(T)
	var/obj/item/lightreplacer/dogborg/replacer = allocate(/obj/item/lightreplacer/dogborg, T)
	replacer.glass = new /datum/matter_synth(1000)
	replacer.uses = 5
	var/datum/op_result/asked = test_click(R, replacer, replacer, GESTURE_SELF)
	TEST_ASSERT_EQUAL(asked?.key, "choose", "using it in the hand asks")
	test_answer(R, "Color")
	var/datum/op_result/coloured = test_answer(R, "#12ab34")
	TEST_ASSERT_EQUAL(coloured?.outcome, ACT_COMMITTED, "the colour answer commits")
	TEST_ASSERT_EQUAL(replacer.selected_color, "#12ab34", "and sets the colour")
	TEST_ASSERT_EQUAL(replacer.uses, 5, "the colour change fabricates nothing")
	test_click(R, replacer, replacer, GESTURE_SELF)
	test_answer(R, "Reserves")
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(replacer.uses, 6, "the reserves answer fabricates one light after the wait")
	TEST_ASSERT_EQUAL(replacer.glass.energy, 875, "from the matter reserves")
	replacer.glass.energy = 10
	test_click(R, replacer, replacer, GESTURE_SELF)
	test_answer(R, "Reserves")
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(replacer.uses, 6, "with the reserves empty nothing is fabricated")
	qdel(replacer.glass)
