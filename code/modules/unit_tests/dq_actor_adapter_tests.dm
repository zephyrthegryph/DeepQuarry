// Actor adapters (roadmap I3): the AI, cyborg, ghost and telekinesis adapters
// produce the hands' actions filtered by what the actor can do, and the
// forwarding attack_ai/attack_robot/attack_ghost overrides are replaced by
// `silicon_use`. The parity tests click real converted types through the router
// and check the same handler runs as the deleted override ran.

// ---- Fixtures ----

GLOBAL_LIST_EMPTY(dq_actor_calls)

/datum/interaction/dq_actor
	category = INTERACTION_CAT_TOGGLE
	default_action = INPUT_ACTION_USE
	effect = /obj/dq_actor_probe/proc/note_interaction

/// Only ghosts are offered it.
/datum/interaction/dq_actor/observe
	id = "dq_actor_observe"
	name = "Observe"
	priority = 10
	tags = list(INTERACTION_TAG_OBSERVER)

/// Tool-less and remote: everyone but ghosts, the AI only with camera sight.
/datum/interaction/dq_actor/handless
	id = "dq_actor_handless"
	name = "Poke"
	priority = 5
	tags = list(INTERACTION_TAG_REMOTE)

/// Needs a tool: never the AI or telekinesis, even though it is tagged remote.
/datum/interaction/dq_actor/tool
	id = "dq_actor_tool"
	name = "Screw"
	priority = 20
	tool = TOOL_SCREWDRIVER
	tags = list(INTERACTION_TAG_REMOTE)

/obj/dq_actor_probe
	name = "actor probe"

/obj/dq_actor_probe/declare_interactions(list/into)
	..()
	into += list(
		/datum/interaction/dq_actor/observe,
		/datum/interaction/dq_actor/handless,
		/datum/interaction/dq_actor/tool,
	)

/obj/dq_actor_probe/proc/note_interaction(mob/actor, obj/item/held, datum/interaction/interaction)
	GLOB.dq_actor_calls += interaction.id
	return TRUE

/obj/dq_actor_probe/attack_tk(mob/user)
	GLOB.dq_actor_calls += "attack_tk"

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
/datum/unit_test/proc/dq_actor_click(mob/user, atom/target, params = "left=1")
	GLOB.dq_actor_calls.Cut()
	user.next_click = 0
	GLOB.input_router.route_click(user, target, params)
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
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T)
	AI.forceMove(T) // a new AI starts in nullspace, where it sees nothing

	TEST_ASSERT_EQUAL(dq_resolution_text(interactions_for(H, probe, null)), "dq_actor_handless|dq_actor_tool:needs a screwdriver", "hands: everything but observer-only")
	TEST_ASSERT_EQUAL(dq_resolution_text(interactions_for(R, probe, null)), "dq_actor_handless|dq_actor_tool:needs a screwdriver", "a cyborg: everything but observer-only; its module is its tool")
	TEST_ASSERT_EQUAL(dq_resolution_text(interactions_for(ghost, probe, null)), "dq_actor_observe|", "a ghost: observer-only")
	TEST_ASSERT_EQUAL(dq_resolution_text(interactions_for(AI, probe, null)), "dq_actor_handless|", "the AI: remote, tool-less, in sight")
	TEST_ASSERT_EQUAL(dq_resolution_text(interactions_for(H, probe, null, null, INPUT_ADAPTER(telekinesis))), "dq_actor_handless|", "telekinesis: no tools")

	TEST_ASSERT(AI.has_camera_sight(probe), "the AI sees what is in its view")
	probe.moveToNullspace()
	TEST_ASSERT(!AI.has_camera_sight(probe), "the AI can't see what is nowhere")
	TEST_ASSERT_EQUAL(dq_resolution_text(interactions_for(AI, probe, null)), "|", "and is offered nothing on it")
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
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T)
	AI.forceMove(T) // a new AI starts in nullspace, where it sees nothing

	TEST_ASSERT_EQUAL(dq_actor_click(H, probe), "dq_actor_handless", "a human's empty-handed Use runs the tool-less interaction")
	TEST_ASSERT_EQUAL(dq_actor_click(R, probe), "dq_actor_handless", "a cyborg's empty-gripper Use goes through the resolver")
	TEST_ASSERT_EQUAL(dq_actor_click(AI, probe), "dq_actor_handless", "the AI's Use goes through the resolver")
	TEST_ASSERT_EQUAL(dq_actor_click(ghost, probe), "dq_actor_observe", "a ghost's Use runs the observer-only interaction")

	var/datum/input_adapter/telekinesis/telekinesis = INPUT_ADAPTER(telekinesis)
	GLOB.dq_actor_calls.Cut()
	telekinesis.use(H, probe)
	TEST_ASSERT_EQUAL(jointext(GLOB.dq_actor_calls, ","), "dq_actor_handless", "telekinetic Use runs the tool-less interaction")

	// Nothing answers: each falls back to its legacy handler.
	var/obj/dq_input_probe/plain = allocate(/obj/dq_input_probe, T)
	TEST_ASSERT_EQUAL(dq_route(R, plain, "left=1"), "attack_robot", "no interaction: the cyborg falls back to attack_robot")
	TEST_ASSERT_EQUAL(dq_route(AI, plain, "left=1"), "attack_ai", "no interaction: the AI falls back to attack_ai")
	TEST_ASSERT_EQUAL(dq_route(ghost, plain, "left=1"), "attack_ghost", "no interaction: the ghost falls back to attack_ghost")
	plain.last_handler = null
	telekinesis.use(H, plain)
	TEST_ASSERT_EQUAL(plain.last_handler, "attack_tk", "no interaction: telekinesis falls back to attack_tk")

// ---- Parity: the deleted forwarding overrides ----

/// The AI's Use on types whose attack_ai only called attack_hand or tgui_interact.
/datum/unit_test/dq_actor_parity_ai

/datum/unit_test/dq_actor_parity_ai/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T)
	AI.forceMove(T) // a new AI starts in nullspace, where it sees nothing
	// Were `return attack_hand(user)`.
	TEST_ASSERT_EQUAL(dq_actor_click(AI, allocate(/obj/machinery/button/dq_actor_probe, T)), "attack_hand", "button: the AI's Use is the hand's")
	TEST_ASSERT_EQUAL(dq_actor_click(AI, allocate(/obj/machinery/firealarm/dq_actor_probe, T)), "attack_hand", "fire alarm: the AI's Use is the hand's")
	TEST_ASSERT_EQUAL(dq_actor_click(AI, allocate(/obj/structure/privacyswitch/dq_actor_probe, T)), "attack_hand", "privacy switch (not a machine): the AI's Use is the hand's")
	// Were `tgui_interact(user)`.
	TEST_ASSERT_EQUAL(dq_actor_click(AI, allocate(/obj/machinery/door/airlock/dq_actor_probe, T)), "tgui_interact", "airlock: the AI's Use opens the UI, not the hand's Use")
	TEST_ASSERT_EQUAL(dq_actor_click(AI, allocate(/obj/machinery/turretid/dq_actor_probe, T)), "tgui_interact", "turret control: the AI's Use opens the UI")
	// Never overridden: unchanged.
	TEST_ASSERT_EQUAL(dq_actor_click(AI, allocate(/obj/structure/closet/dq_actor_probe, T)), "", "closet: the AI's Use does nothing, as before")

/// A cyborg's empty-gripper Use on types whose attack_robot only called attack_hand.
/datum/unit_test/dq_actor_parity_robot

/datum/unit_test/dq_actor_parity_robot/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	// Was `attack_hand(M)`.
	TEST_ASSERT_EQUAL(dq_actor_click(R, allocate(/obj/structure/ladder/dq_actor_probe, T)), "attack_hand", "ladder: the cyborg's Use is the hand's")
	// Was `if(Adjacent(user)) attack_hand(user)`.
	var/obj/structure/closet/dq_actor_probe/closet = allocate(/obj/structure/closet/dq_actor_probe, T)
	TEST_ASSERT_EQUAL(dq_actor_click(R, closet), "attack_hand", "closet, adjacent: the cyborg's Use is the hand's")
	var/turf/far = locate(T.x + 3, T.y, T.z)
	if(far)
		closet.forceMove(far)
		TEST_ASSERT_EQUAL(dq_actor_click(R, closet), "", "closet, at range: nothing, and no AI-style interfacing")
		closet.forceMove(T)
	// The AI-style forwards reach the cyborg through attack_robot -> attack_ai. A cyborg
	// with no client (or one looking through a camera) can't control machines remotely.
	TEST_ASSERT_EQUAL(dq_actor_click(R, allocate(/obj/structure/privacyswitch/dq_actor_probe, T)), "attack_hand", "privacy switch: the cyborg interfaces like the AI")
	TEST_ASSERT_EQUAL(dq_actor_click(R, allocate(/obj/machinery/button/dq_actor_probe, T)), "", "button: a cyborg without a client can't control a machine remotely")

/// A ghost's Use on types whose attack_ghost only called tgui_interact.
/datum/unit_test/dq_actor_parity_ghost

/datum/unit_test/dq_actor_parity_ghost/Run()
	var/turf/T = test_floor()
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	TEST_ASSERT_EQUAL(dq_actor_click(ghost, allocate(/obj/machinery/door/airlock/dq_actor_probe, T)), "tgui_interact", "airlock: a ghost's Use opens the UI to view")
	TEST_ASSERT_EQUAL(dq_actor_click(ghost, allocate(/obj/machinery/turretid/dq_actor_probe, T)), "tgui_interact", "turret control: a ghost's Use opens the UI to view")
	TEST_ASSERT_EQUAL(dq_actor_click(ghost, allocate(/obj/machinery/button/dq_actor_probe, T)), "tgui_interact", "button (never overridden): the same, as before")

/// Telekinesis reaches the same handlers as before: attack_tk, which for anchored objects is an unarmed attack.
/datum/unit_test/dq_actor_parity_telekinesis

/datum/unit_test/dq_actor_parity_telekinesis/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/input_adapter/telekinesis/telekinesis = INPUT_ADAPTER(telekinesis)
	GLOB.dq_actor_calls.Cut()
	telekinesis.use(H, allocate(/obj/machinery/button/dq_actor_probe, T))
	TEST_ASSERT_EQUAL(jointext(GLOB.dq_actor_calls, ","), "attack_hand", "button: telekinesis presses it with an unarmed attack")
