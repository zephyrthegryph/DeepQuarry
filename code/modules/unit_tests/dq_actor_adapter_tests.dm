// Actor adapters (roadmap I3): the AI, cyborg, ghost and telekinesis adapters
// produce the hands' actions filtered by what the actor can do, and the
// forwarding attack_ai/attack_robot/attack_ghost overrides are replaced by
// a type's silicon_hand()/silicon_ui() op. The parity tests click real converted types through the router
// and check the same handler runs as the deleted override ran.

// ---- Fixtures ----

GLOBAL_LIST_EMPTY(dq_actor_calls)

/// Three ops on one probe: one only a ghost reaches, one a hand or an interface reaches, one that needs a screwdriver.
/obj/dq_actor_probe
	name = "actor probe"

CAPABILITIES(/obj/dq_actor_probe)
	op("dq_actor_observe", observer(), then(PROC_REF(note_observe)))
	op("dq_actor_handless", inputs(hand(), remote()), then(PROC_REF(note_handless)))
	op("dq_actor_tool", tool(TOOL_SCREWDRIVER), then(PROC_REF(note_tool)))

/obj/dq_actor_probe/proc/note_observe(datum/act/op/A)
	GLOB.dq_actor_calls += "dq_actor_observe"
	return OP_OK

/obj/dq_actor_probe/proc/note_handless(datum/act/op/A)
	GLOB.dq_actor_calls += "dq_actor_handless"
	return OP_OK

/obj/dq_actor_probe/proc/note_tool(datum/act/op/A)
	GLOB.dq_actor_calls += "dq_actor_tool"
	return OP_OK

/// The keys of the ops `actor` could pick from `target`'s menu now (the refused ones left out), sorted and comma-separated.
/// The op `key` performed by `actor` on `target` as its click would (ORIGIN_CLICK): the handlers it recorded.
/datum/unit_test/proc/dq_actor_op(mob/actor, atom/target, key)
	GLOB.dq_actor_calls.Cut()
	var/datum/op_result/R = perform_op(actor, target, key, origin = ORIGIN_CLICK, authority = actor.click_authority())
	test_time(1 SECONDS)
	if(!length(GLOB.dq_actor_calls))
		return "refused: [R?.reason]"
	return jointext(GLOB.dq_actor_calls, ",")

/datum/unit_test/proc/dq_actor_offered(mob/actor, atom/target, obj/item/held)
	var/list/keys = list()
	for(var/list/row as anything in op_menu(actor, target, held))
		if(row["enabled"])
			keys += "[row["key"]]"
	sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
	return jointext(keys, ",")

// Real converted types, recording the hand's and the UI's handlers instead of running them.
// They don't override attack_ai/attack_robot/attack_ghost, so those resolve as on the parent.

/obj/machinery/button/dq_actor_probe/attack_hand(mob/user)
	GLOB.dq_actor_calls += "attack_hand"
/obj/machinery/button/dq_actor_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_actor_calls += "tgui_interact"

/obj/machinery/firealarm/dq_actor_probe/attack_hand(mob/user)
	GLOB.dq_actor_calls += "attack_hand"
/obj/machinery/firealarm/dq_actor_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_actor_calls += "tgui_interact"

/obj/structure/privacyswitch/dq_actor_probe/attack_hand(mob/user)
	GLOB.dq_actor_calls += "attack_hand"

/obj/machinery/door/airlock/dq_actor_probe/attack_hand(mob/user)
	GLOB.dq_actor_calls += "attack_hand"
/obj/machinery/door/airlock/dq_actor_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_actor_calls += "tgui_interact"

/obj/machinery/turretid/dq_actor_probe/attack_hand(mob/user)
	GLOB.dq_actor_calls += "attack_hand"
/obj/machinery/turretid/dq_actor_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_actor_calls += "tgui_interact"

/obj/structure/ladder/dq_actor_probe/attack_hand(mob/user)
	GLOB.dq_actor_calls += "attack_hand"

/obj/structure/closet/dq_actor_probe/attack_hand(mob/user)
	GLOB.dq_actor_calls += "attack_hand"
/obj/structure/closet/dq_actor_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_actor_calls += "tgui_interact"

/// Clicks `target` through the router as `user`; returns what ran, comma-separated.
/// `ops_first` FALSE: the click's ops have had their say already (as after the inbox), so the adapter's own handling shows (the parity tests of the deleted
/// forwarding overrides read it).
/datum/unit_test/proc/dq_actor_click(mob/user, atom/target, params = "left=1", ops_first = TRUE)
	GLOB.dq_actor_calls.Cut()
	user.next_click = 0
	if(!ops_first)
		GLOB.op_click_resolved[user] = TRUE
	GLOB.input_router.route_click(user, target, params)
	GLOB.op_click_resolved -= user
	if(ops_first)
		test_time(1 SECONDS) // an op's effect (a silicon_hand() forward) runs in the op pipeline, not inside the click
	return jointext(GLOB.dq_actor_calls, ",")

// ---- Capability filtering ----

/// Each adapter offers the interactions its actor can do, and no others.
/datum/unit_test/dq_actor_capabilities

/datum/unit_test/dq_actor_capabilities/Run()
	var/turf/T = test_floor()
	var/obj/dq_actor_probe/probe = allocate(/obj/dq_actor_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)
	AI.forceMove(T) // a new AI starts in nullspace, where it sees nothing

	TEST_ASSERT_EQUAL(dq_actor_offered(H, probe, null), "dq_actor_handless", "hands: the hand op, not the observer's, and the tool op needs its tool")
	TEST_ASSERT_EQUAL(dq_actor_offered(R, probe, null), "dq_actor_handless", "a cyborg: the hand op; its module is its tool")
	TEST_ASSERT_EQUAL(dq_actor_offered(ghost, probe, null), "dq_actor_observe", "a ghost: observer-only")
	TEST_ASSERT_EQUAL(dq_actor_offered(AI, probe, null), "dq_actor_handless", "the AI: remote, tool-less, in sight")
	var/turf/away = locate(T.x + 3, T.y, T.z)
	TEST_ASSERT_NOTNULL(away, "a turf three tiles away")
	var/obj/dq_actor_probe/distant = allocate(/obj/dq_actor_probe, away)
	H.add_mutation(TK)
	TEST_ASSERT_EQUAL(dq_actor_offered(H, distant, null), "dq_actor_handless", "telekinesis: the hand op at range, no tools")
	H.remove_mutation(TK)

	TEST_ASSERT(AI.has_camera_sight(probe), "the AI sees what is in its view")
	probe.moveToNullspace()
	TEST_ASSERT(!AI.has_camera_sight(probe), "the AI can't see what is nowhere")
	TEST_ASSERT_EQUAL(dq_actor_offered(AI, probe, null), "", "and is offered nothing on it")
	probe.forceMove(T)

	var/turf/far = locate(T.x + world.view + 3, T.y, T.z)
	if(far && !AI.is_in_chassis())
		probe.forceMove(far)
		TEST_ASSERT(!AI.has_camera_sight(probe), "a carded AI can't see past its view range")
		probe.forceMove(T)

/// Use through the router runs the resolver first for every actor, with its filter.
/datum/unit_test/dq_actor_use_resolver

/datum/unit_test/dq_actor_use_resolver/Run()
	var/turf/T = test_floor()
	var/obj/dq_actor_probe/probe = allocate(/obj/dq_actor_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	// safety = TRUE: without a brain an AI's Initialize() spawns an empty core and qdels itself
	// (INITIALIZE_HINT_QDEL), so a click would be routed for an already-deleted mob.
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)
	AI.forceMove(T) // a new AI starts in nullspace, where it sees nothing

	TEST_ASSERT_EQUAL(dq_actor_click(H, probe), "dq_actor_handless", "a human's empty-handed Use runs the tool-less interaction")
	TEST_ASSERT_EQUAL(dq_actor_click(R, probe), "dq_actor_handless", "a cyborg's empty-gripper Use goes through the resolver")
	TEST_ASSERT_EQUAL(dq_actor_click(AI, probe), "dq_actor_handless", "the AI's Use goes through the resolver")
	TEST_ASSERT_EQUAL(dq_actor_click(ghost, probe), "dq_actor_observe", "a ghost's Use runs the observer-only interaction")

	var/turf/away = locate(T.x + 3, T.y, T.z)
	TEST_ASSERT_NOTNULL(away, "a turf three tiles away")
	var/obj/dq_actor_probe/distant = allocate(/obj/dq_actor_probe, away)
	H.add_mutation(TK)
	TEST_ASSERT_EQUAL(dq_actor_click(H, distant), "dq_actor_handless", "telekinetic Use runs the tool-less op")
	H.remove_mutation(TK)

	// A probe declaring one op per actor kind: each actor runs its own.
	var/obj/dq_input_probe/plain = allocate(/obj/dq_input_probe, T)
	TEST_ASSERT(dq_route(R, plain, "left=1") in list("attack_hand", "attack_ai"), "the cyborg runs the hand op or the remote op its interface provides")
	TEST_ASSERT_EQUAL(dq_route(AI, plain, "left=1"), "attack_ai", "the AI runs its remote op")
	TEST_ASSERT_EQUAL(dq_route(ghost, plain, "left=1"), "attack_ghost", "the ghost runs its observer op")
	var/obj/dq_input_probe/plain_far = allocate(/obj/dq_input_probe, away)
	H.add_mutation(TK)
	TEST_ASSERT_EQUAL(dq_route(H, plain_far, "left=1"), "attack_tk", "telekinesis runs its tk op")
	H.remove_mutation(TK)

// ---- Parity: the deleted forwarding overrides ----

/// The AI's Use on types whose attack_ai only called attack_hand or tgui_interact.
/datum/unit_test/dq_actor_parity_ai

/datum/unit_test/dq_actor_parity_ai/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)
	AI.forceMove(T) // a new AI starts in nullspace, where it sees nothing
	// Were `return attack_hand(user)`.
	TEST_ASSERT_EQUAL(dq_actor_click(AI, allocate(/obj/machinery/button/dq_actor_probe, T)), "attack_hand", "button: the AI's Use is the hand's")
	TEST_ASSERT_EQUAL(dq_actor_click(AI, allocate(/obj/machinery/firealarm/dq_actor_probe, T)), "attack_hand", "fire alarm: the AI's Use is the hand's")
	// silicon_hand(): the switch's own remote() op now, not the adapter's fallback.
	TEST_ASSERT_EQUAL(dq_actor_op(AI, allocate(/obj/structure/privacyswitch/dq_actor_probe, T), "silicon_hand"), "attack_hand", "privacy switch (not a machine): the AI's Use is the hand's")
	// Were `tgui_interact(user)`.
	TEST_ASSERT_EQUAL(dq_actor_click(AI, allocate(/obj/machinery/door/airlock/dq_actor_probe, T)), "tgui_interact", "airlock: the AI's Use opens the UI, not the hand's Use")
	// The turret control opens through its interface's remote() binding now, which needs the AI to see it (a camera); dq_silicon_entry_tests covers it.
	// Never overridden: unchanged.
	TEST_ASSERT_EQUAL(dq_actor_click(AI, allocate(/obj/structure/closet/dq_actor_probe, T)), "", "closet: the AI's Use does nothing, as before")

/// A cyborg's empty-gripper Use on types whose attack_robot only called attack_hand.
/datum/unit_test/dq_actor_parity_robot

/datum/unit_test/dq_actor_parity_robot/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	// Was `attack_hand(M)`.
	// silicon_hand(robots = TRUE), an op with a remote() binding now: the adapter's fallback is not involved.
	TEST_ASSERT_EQUAL(dq_actor_op(R, allocate(/obj/structure/ladder/dq_actor_probe, T), "silicon_hand"), "attack_hand", "ladder: the cyborg's Use is the hand's")
	// Was `if(Adjacent(user)) attack_hand(user)`.
	var/obj/structure/closet/dq_actor_probe/closet = allocate(/obj/structure/closet/dq_actor_probe, T)
	TEST_ASSERT_EQUAL(dq_actor_op(R, closet, "silicon_hand"), "attack_hand", "closet, adjacent: the cyborg's Use is the hand's (silicon_hand(adjacent = TRUE))")
	var/turf/far = locate(T.x + 3, T.y, T.z)
	if(far)
		closet.forceMove(far)
		TEST_ASSERT(dq_actor_op(R, closet, "silicon_hand") != "attack_hand", "closet, at range: nothing, and no AI-style interfacing")
		closet.forceMove(T)
	// The AI-style forwards reach the cyborg through attack_robot -> attack_ai. A cyborg
	// looking through a camera can't control machines remotely (a cyborg with no client is not blocked: only a player's click or a script reaches it).
	TEST_ASSERT_EQUAL(dq_actor_op(R, allocate(/obj/structure/privacyswitch/dq_actor_probe, T), "silicon_hand"), "attack_hand", "privacy switch: the cyborg interfaces like the AI")
	TEST_ASSERT_EQUAL(dq_actor_op(R, allocate(/obj/machinery/button/dq_actor_probe, T), "silicon_hand"), "attack_hand", "button: a cyborg not looking through a camera controls a machine like the AI")

/// A ghost's Use on types whose attack_ghost only called tgui_interact.
/datum/unit_test/dq_actor_parity_ghost

/datum/unit_test/dq_actor_parity_ghost/Run()
	var/turf/T = test_floor()
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	TEST_ASSERT_EQUAL(dq_actor_click(ghost, allocate(/obj/machinery/door/airlock/dq_actor_probe, T)), "tgui_interact", "airlock: a ghost's Use opens the UI to view")
	TEST_ASSERT_EQUAL(dq_actor_click(ghost, allocate(/obj/machinery/turretid/dq_actor_probe, T)), "tgui_interact", "turret control: a ghost's Use opens the UI to view")
	TEST_ASSERT_EQUAL(dq_actor_click(ghost, allocate(/obj/machinery/button/dq_actor_probe, T)), "tgui_interact", "button (never overridden): the same, as before")

/// Telekinesis with no tk op falls to the adapter default, which for anchored objects is an unarmed attack.
/datum/unit_test/dq_actor_parity_telekinesis

/datum/unit_test/dq_actor_parity_telekinesis/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/input_adapter/telekinesis/telekinesis = INPUT_ADAPTER(telekinesis)
	GLOB.dq_actor_calls.Cut()
	GLOB.op_click_resolved[H] = TRUE // the adapter's own handling, after the ops
	telekinesis.use(H, allocate(/obj/machinery/button/dq_actor_probe, T))
	GLOB.op_click_resolved -= H
	TEST_ASSERT_EQUAL(jointext(GLOB.dq_actor_calls, ","), "attack_hand", "button: telekinesis presses it with an unarmed attack")
