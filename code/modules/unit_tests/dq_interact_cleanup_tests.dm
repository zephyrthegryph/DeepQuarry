// Wave 5 interaction cleanup: the body rewrite's intent gates read combat mode,
// its medical machines use the actor adapters instead of forwarding overrides,
// and surgery reads welders through get_welder().

// ---- Fixtures: medical types whose attack_ai/attack_robot/attack_ghost only forwarded ----

GLOBAL_LIST_EMPTY(dq_interact_cleanup_calls)

/obj/machinery/sleep_console/dq_cleanup_probe/attack_hand(mob/user)
	GLOB.dq_interact_cleanup_calls += "attack_hand"
/obj/machinery/sleep_console/dq_cleanup_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_interact_cleanup_calls += "tgui_interact"

/obj/machinery/body_scanconsole/dq_cleanup_probe/attack_hand(mob/user)
	GLOB.dq_interact_cleanup_calls += "attack_hand"
/obj/machinery/body_scanconsole/dq_cleanup_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_interact_cleanup_calls += "tgui_interact"

/obj/machinery/clonepod/dq_cleanup_probe/attack_hand(mob/user)
	GLOB.dq_interact_cleanup_calls += "attack_hand"
/obj/machinery/clonepod/dq_cleanup_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_interact_cleanup_calls += "tgui_interact"

/obj/machinery/computer/cloning/dq_cleanup_probe/attack_hand(mob/user)
	GLOB.dq_interact_cleanup_calls += "attack_hand"
/obj/machinery/computer/cloning/dq_cleanup_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_interact_cleanup_calls += "tgui_interact"

/obj/machinery/computer/cryopod/dq_cleanup_probe/attack_hand(mob/user)
	GLOB.dq_interact_cleanup_calls += "attack_hand"
/obj/machinery/computer/cryopod/dq_cleanup_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_interact_cleanup_calls += "tgui_interact"

/obj/machinery/computer/med_data/dq_cleanup_probe/attack_hand(mob/user)
	GLOB.dq_interact_cleanup_calls += "attack_hand"
/obj/machinery/computer/med_data/dq_cleanup_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_interact_cleanup_calls += "tgui_interact"

/obj/machinery/computer/pandemic/dq_cleanup_probe/attack_hand(mob/user)
	GLOB.dq_interact_cleanup_calls += "attack_hand"
/obj/machinery/computer/pandemic/dq_cleanup_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_interact_cleanup_calls += "tgui_interact"

/obj/machinery/computer/transhuman/designer/dq_cleanup_probe/attack_hand(mob/user)
	GLOB.dq_interact_cleanup_calls += "attack_hand"
/obj/machinery/computer/transhuman/designer/dq_cleanup_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_interact_cleanup_calls += "tgui_interact"

/obj/machinery/computer/transhuman/resleeving/dq_cleanup_probe/attack_hand(mob/user)
	GLOB.dq_interact_cleanup_calls += "attack_hand"
/obj/machinery/computer/transhuman/resleeving/dq_cleanup_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_interact_cleanup_calls += "tgui_interact"

/obj/machinery/atmospherics/unary/cryo_cell/dq_cleanup_probe/attack_hand(mob/user)
	GLOB.dq_interact_cleanup_calls += "attack_hand"
/obj/machinery/atmospherics/unary/cryo_cell/dq_cleanup_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_interact_cleanup_calls += "tgui_interact"

/obj/structure/medical_stand/dq_cleanup_probe/attack_hand(mob/user)
	GLOB.dq_interact_cleanup_calls += "attack_hand"
/obj/structure/medical_stand/dq_cleanup_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/custom_state)
	GLOB.dq_interact_cleanup_calls += "tgui_interact"

/datum/unit_test/proc/dq_cleanup_calls_reset()
	GLOB.dq_interact_cleanup_calls.Cut()

/datum/unit_test/proc/dq_cleanup_calls()
	return jointext(GLOB.dq_interact_cleanup_calls, ",")

// ---- Actor adapters ----

/// The AI's attack_ai on the medical consoles is still the hand's Use, now through the machine's silicon_hand() op.
/datum/unit_test/dq_cleanup_medical_ai_parity

/datum/unit_test/dq_cleanup_medical_ai_parity/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)
	AI.forceMove(T)
	var/list/types = list(
		/obj/machinery/sleep_console/dq_cleanup_probe,
		/obj/machinery/body_scanconsole/dq_cleanup_probe,
		/obj/machinery/clonepod/dq_cleanup_probe,
		/obj/machinery/computer/cloning/dq_cleanup_probe,
		/obj/machinery/computer/cryopod/dq_cleanup_probe,
		/obj/machinery/computer/med_data/dq_cleanup_probe,
		/obj/machinery/computer/pandemic/dq_cleanup_probe,
		/obj/machinery/computer/transhuman/designer/dq_cleanup_probe,
		/obj/machinery/computer/transhuman/resleeving/dq_cleanup_probe,
	)
	for(var/path in types)
		var/atom/target = allocate(path, T)
		dq_cleanup_calls_reset()
		// A type with a window op (interface(), ui_open for a remote actor) answers the AI's Use through that op; one without it falls to the hand's Use
		// (silicon_hand()) and the probe's attack_hand records it.
		var/answered = actor_use(/datum/input_adapter/ai, AI, target)
		TEST_ASSERT(answered || dq_cleanup_calls() == "attack_hand", "[path]: the AI's Use is answered, by the window op or the hand's Use")

/// A ghost's Use on the cryo cell and PanD.E.M.I.C. still opens the UI.
/datum/unit_test/dq_cleanup_medical_ghost_parity

/datum/unit_test/dq_cleanup_medical_ghost_parity/Run()
	var/turf/T = test_floor()
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	for(var/path in list(/obj/machinery/computer/pandemic/dq_cleanup_probe, /obj/machinery/atmospherics/unary/cryo_cell/dq_cleanup_probe))
		var/atom/target = allocate(path, T)
		dq_cleanup_calls_reset()
		actor_use(/datum/input_adapter/ghost, ghost, target)
		TEST_ASSERT_EQUAL(dq_cleanup_calls(), "tgui_interact", "[path]: a ghost's Use opens the UI to view")

/// A cyborg uses the medical stand by hand when adjacent, and not at all from range.
/datum/unit_test/dq_cleanup_medical_stand_robot_parity

/datum/unit_test/dq_cleanup_medical_stand_robot_parity/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/obj/structure/medical_stand/dq_cleanup_probe/stand = allocate(/obj/structure/medical_stand/dq_cleanup_probe, T)
	dq_cleanup_calls_reset()
	// The stand's hand is an op now (medical_stand_interaction_hand), so the probe's attack_hand is not called: the op answers.
	TEST_ASSERT(actor_use(/datum/input_adapter/robot, R, stand) || dq_cleanup_calls() == "attack_hand", "adjacent: the cyborg's Use is the hand's")
	var/turf/far = locate(T.x + 3, T.y, T.z)
	TEST_ASSERT_NOTNULL(far, "the test floor has room for a distant turf")
	stand.forceMove(far)
	dq_cleanup_calls_reset()
	actor_use(/datum/input_adapter/robot, R, stand)
	TEST_ASSERT_EQUAL(dq_cleanup_calls(), "", "at range: nothing, and no AI-style interfacing")

// ---- Combat mode gates ----

/// Shredding needs combat mode unless the caller ignores it.
/datum/unit_test/dq_cleanup_shred_needs_combat_mode

/datum/unit_test/dq_cleanup_shred_needs_combat_mode/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_combat_mode(FALSE)
	TEST_ASSERT_EQUAL(H.species.can_shred(H), 0, "combat mode off: no shredding")

/// In combat mode a syringe stabs; the lethal-injection syringe refuses to.
/datum/unit_test/dq_cleanup_syringe_harm_gate

/datum/unit_test/dq_cleanup_syringe_harm_gate/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, T)
	dq_give_zone_sel(user)
	victim.lying = TRUE // a prone target can't dodge the stab, so it always lands
	user.set_combat_mode(TRUE)
	TEST_ASSERT_EQUAL(user.input_stance(), I_HURT, "combat mode on is the harm stance")

	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe, T)
	S.reagents.add_reagent(REAGENT_ID_WATER, 10)
	user.put_in_active_hand(S)
	user.next_click = 0
	input_submit(new /datum/input_event/click(user, victim, null, null, "left=1"))
	TEST_ASSERT(findtext(S.desc, "broken"), "combat mode: the syringe is stabbed in and breaks")

	var/obj/item/reagent_containers/syringe/ld50_syringe/big = allocate(/obj/item/reagent_containers/syringe/ld50_syringe, T)
	big.set_mode(NEEDLE_INJECT)
	big.reagents.add_reagent(REAGENT_ID_WATER, 10)
	user.drop_item()
	user.put_in_active_hand(big)
	user.next_click = 0
	input_submit(new /datum/input_event/click(user, victim, null, null, "left=1"))
	TEST_ASSERT_EQUAL(big.reagents.total_volume, 10, "combat mode: the lethal-injection syringe is too big to stab with")
	TEST_ASSERT(!findtext(big.desc, "broken"), "combat mode: the lethal-injection syringe stays whole")

// ---- Surgery welders ----

/// Plating repair and hardsuit cutting read a welder through get_welder(): it must be lit.
/datum/unit_test/dq_cleanup_surgery_welder_lit

/datum/unit_test/dq_cleanup_surgery_welder_lit/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/surgical_step/weld = surgical_step(/datum/surgical_step/treat/repair_plating)
	var/datum/surgical_step/cut = surgical_step(/datum/surgical_step/cut_hardsuit)
	TEST_ASSERT_NOTNULL(weld, "plating repair is registered")
	TEST_ASSERT_NOTNULL(cut, "hardsuit cutting is registered")

	var/obj/item/weldingtool/unlit = allocate(/obj/item/weldingtool, T)
	TEST_ASSERT(!unlit.isOn(), "a new welder starts unlit")
	TEST_ASSERT_EQUAL(weld.tool_quality(unlit), 0, "an unlit welder can't repair plating")
	TEST_ASSERT(!cut.is_needed(H, H, null, unlit), "an unlit welder can't cut a hardsuit")

	var/obj/item/weldingtool/lit = dq_fueled_welder(T)
	TEST_ASSERT(lit.isOn(), "the fuelled welder is lit")
	TEST_ASSERT(weld.tool_quality(lit) > 0, "a lit welder repairs plating")

	var/obj/item/surgical/circular_saw/saw = allocate(/obj/item/surgical/circular_saw, T)
	TEST_ASSERT_NULL(saw.get_welder(), "a saw lends no welder")
	TEST_ASSERT_EQUAL(weld.tool_quality(saw), 0, "a saw can't repair plating")
