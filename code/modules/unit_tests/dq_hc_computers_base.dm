// Behaviour tests for the computer consoles (code/game/machinery/computer) and the tgui modules they host: they pin what a player, a cyborg or an
// admin observes through window buttons (each UI action's effect, the access refusals, the data a viewer is sent) so the same files pass before
// and after the consoles move from the legacy declaration forms (DECLARE_UI / UI_ACT / om_ask) to interface() / op(ui_act()) / asks().
//   - Input goes through hc_ui(): the engine's op if the console has one for the action, else today's tgui_act().
//   - A question a console asks is answered through p2cl_answer() (the engine's request first, else the collected legacy prompt).
//   - State is read through plain vars and the window data; nothing depends on message text or an op key.

/// Presses a window button as `actor`: the engine's op if the host has one for the action, else today's tgui_act() with an interactive window.
/proc/hc_ui(mob/actor, datum/host, action, list/args)
	var/datum/op_result/result = test_ui(actor, host, action, args)
	if(result)
		return result
	var/datum/tgui/ui = new(actor, host, "HcTest")
	ui.status = STATUS_INTERACTIVE
	. = host.tgui_act(action, args || list(), ui)
	qdel(ui)

/// The window data a viewer is sent (the dynamic part).
/proc/hc_data(datum/host, mob/viewer)
	var/datum/tgui/ui = new(viewer, host, "HcTest")
	ui.status = STATUS_INTERACTIVE
	var/list/data = host.tgui_data(viewer, ui, GLOB.tgui_default_state)
	qdel(ui)
	return data

/datum/unit_test/dq_hc_computers
	abstract_type = /datum/unit_test/dq_hc_computers
	var/list/hc_made
	/// Records a test put in the data core.
	var/list/hc_records

/datum/unit_test/dq_hc_computers/Run()
	set_global("test_prompts", GLOB.test_prompts)
	test_driver_begin()
	test_rng(1)
	p2cl_capture_prompts()
	run_gate()
	// What the consoles made on their tiles (printouts, passes).
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		for(var/obj/item/paper/P in T)
			qdel(P)
		for(var/obj/item/card/id/guest/G in T)
			qdel(G)
	for(var/datum/data/record/R as anything in hc_records)
		if(!QDELETED(R))
			qdel(R)
	hc_records = null
	for(var/atom/movable/AM as anything in hc_made)
		if(!QDELETED(AM))
			qdel(AM)
	test_driver_end()

/datum/unit_test/dq_hc_computers/proc/run_gate()
	return

/// Where the console stands.
/datum/unit_test/dq_hc_computers/proc/hc_spot()
	return get_step(run_loc_floor_bottom_left, EAST)

/// Where the person stands (next to the console).
/datum/unit_test/dq_hc_computers/proc/hc_side()
	return run_loc_floor_bottom_left

/// A console of `type` as a map places it.
/datum/unit_test/dq_hc_computers/proc/hc_console(type, turf/T)
	var/obj/machinery/computer/C = allocate(type, T || hc_spot())
	C.set_grid_power(TRUE)
	C.set_broken_condition(FALSE)
	LAZYADD(hc_made, C)
	return C

/// A conscious person who cannot be hurt by the passing time.
/datum/unit_test/dq_hc_computers/proc/hc_actor(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || hc_side())
	H.enable_godmode()
	return H

/// A person carrying an ID that opens everything.
/datum/unit_test/dq_hc_computers/proc/hc_boss(turf/T)
	var/mob/living/carbon/human/H = hc_actor(T)
	var/obj/item/card/id/I = allocate(/obj/item/card/id, hc_side())
	I.access = SSaccess.get_all_station_access()
	H.equip_to_slot_or_del(allocate(/obj/item/clothing/under/color/grey, hc_side()), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(I, SLOT_ID_ID)
	ASSERT(H.get_equipped_item(SLOT_ID_ID) == I)
	return H

/// The actor presses a button and time passes (a converted op may wait where the old code was instant).
/datum/unit_test/dq_hc_computers/proc/press(mob/actor, datum/host, action, list/args)
	. = hc_ui(actor, host, action, args)
	test_time(10 SECONDS)
