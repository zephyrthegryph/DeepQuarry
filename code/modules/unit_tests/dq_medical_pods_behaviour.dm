// Behaviour pins for the medical occupancy machines: the sleeper and its console, the cryo cell, the body scanner and its console. They were written
// against the legacy code first (green there), and pass the same after the machines moved onto occupant_pod(), paired_console() and beaker_bay()
// (doc/rewrite/intended_changes.md, "Medical pods" lists every pin that changed on purpose, with its reason).
//
// Rules: input goes through public paths (drags, clicks, window buttons, the context menu, time) and the adapters below; state is read through the
// adapters and plain vars; every input is followed by test_time(); nothing depends on message text.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------------------------------------------------

/// Who is inside a pod.
/proc/medpod_occupant(atom/pod)
	return occupant_of(pod)

/// Puts `M` straight into the pod, as code (a spawn, a test) does: no wait, no checks of a player's op.
/proc/medpod_put_in(atom/pod, mob/living/M)
	return occupant_enter(pod, M, M)

/// The occupant presses a direction key: the movement its client would relay to the machine it is inside.
/proc/medpod_struggle(mob/living/M)
	var/datum/act/relay_movement/relay = ACT_TRY(M, relay_movement, NORTH)
	if(!relay)
		return
	act_cancel(relay)
	if(isobj(M.loc))
		M.loc.relaymove(M, NORTH)

/// How deep the stasis holding `M` is (0: none, 1: life stopped).
/proc/medpod_stasis(mob/living/M)
	return M.factor(BF_STASIS)

/// The context menu row of `pod` whose label starts with `prefix`, picked by `actor`. FALSE when there is none.
/proc/medpod_menu(mob/actor, atom/pod, prefix)
	for(var/list/row in action_options(actor, pod, actor.get_active_hand()))
		if(findtext(row["label"], prefix) == 1)
			test_menu(actor, pod, row["key"])
			return TRUE
	return FALSE

/// A window button pressed on `host` (an op's ui_act() binding, or the legacy action table).
/proc/medpod_ui(mob/actor, datum/host, action, list/args)
	return hc_ui(actor, host, action, args)

// ---------------------------------------------------------------------------------------------------------------------
// The base
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_medpod
	abstract_type = /datum/unit_test/dq_medpod

/datum/unit_test/dq_medpod/Run()
	test_driver_begin()
	test_rng(1)
	run_pods()
	for(var/dx in 0 to 3)
		for(var/dy in 0 to 3)
			var/turf/T = floor_at(dx, dy)
			if(T)
				own_turf_contents(T)
	test_driver_end()

/datum/unit_test/dq_medpod/proc/run_pods()
	return

/datum/unit_test/dq_medpod/proc/floor_at(dx, dy)
	var/turf/origin = run_loc_floor_bottom_left
	return locate(origin.x + dx, origin.y + dy, origin.z)

/// A conscious person with hands who cannot be hurt.
/datum/unit_test/dq_medpod/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || floor_at(0, 0))
	H.enable_godmode()
	dq_give_zone_sel(H)
	return H

/// A person who can be hurt and treated.
/datum/unit_test/dq_medpod/proc/patient(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || floor_at(0, 0))
	dq_give_zone_sel(H)
	return H

/// `grabber` takes hold of `victim`: the grab in hand, or null.
/datum/unit_test/dq_medpod/proc/grab(mob/living/carbon/human/grabber, mob/living/victim)
	dq_attack_variant_op(grabber, victim, ATTACK_VARIANT_GRAB)
	var/obj/item/grab/G = grabber.get_active_hand()
	return istype(G) ? G : null

/datum/unit_test/dq_medpod/proc/give(mob/living/carbon/human/H, obj/item/I)
	if(H.get_active_hand())
		H.drop_item()
	H.put_in_active_hand(I)
	return I

/datum/unit_test/dq_medpod/proc/empty_hands(mob/living/carbon/human/H)
	if(H.get_active_hand())
		H.drop_item()

/// A cryo cell on `T` joined to a pipe (its own network is not built on the test block), full of cold oxygen, switched off.
/datum/unit_test/dq_medpod/proc/cryo_cell(turf/T)
	var/obj/machinery/atmospherics/unary/cryo_cell/cell = allocate(/obj/machinery/atmospherics/unary/cryo_cell, T)
	var/obj/machinery/atmospherics/pipe/simple/pipe = allocate(/obj/machinery/atmospherics/pipe/simple, T)
	rel_set(cell, nameof(cell.node), pipe)
	dq_atmos_test_publish_rust_pipenets(list(cell)) // its port: the occupant's heat link names the pipeline it is in
	cell.air_contents.adjust_gas(/datum/gas/oxygen, 50)
	heat_set(cell.air_contents, 80)
	return cell

/// Makes the tile south of `T` a wall for the test (the block's edge usually is one). Returns the turf to restore, or null.
/datum/unit_test/dq_medpod/proc/wall_south_of(turf/T)
	var/turf/south = get_step(T, SOUTH)
	if(south.density)
		return null
	south.ChangeTurf(/turf/simulated/wall)
	return south

// ---------------------------------------------------------------------------------------------------------------------
// Sleeper
// ---------------------------------------------------------------------------------------------------------------------

/// A person dragged onto a working sleeper is put inside after a two-second wait; the sleeper goes to active power.
/datum/unit_test/dq_medpod/sleeper_drag_in_after_a_wait
/datum/unit_test/dq_medpod/sleeper_drag_in_after_a_wait/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	test_drag(H, P, S)
	test_time(1 SECOND)
	TEST_ASSERT_NULL(medpod_occupant(S), "nobody is inside before the wait is over")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(medpod_occupant(S), P, "the dragged person is inside after it")
	TEST_ASSERT_EQUAL(P.loc, S, "and in the sleeper")
	TEST_ASSERT_EQUAL(S.use_power, USE_POWER_ACTIVE, "an occupied sleeper draws active power")

/// What a sleeper does not take: a mouse, a second person, anyone while it has no power.
/datum/unit_test/dq_medpod/sleeper_refusals
/datum/unit_test/dq_medpod/sleeper_refusals/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	..()

/datum/unit_test/dq_medpod/sleeper_refusals/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, floor_at(1, 0))
	test_drag(H, M, S)
	test_time(3 SECONDS)
	TEST_ASSERT_NULL(medpod_occupant(S), "a mouse is not put inside")
	var/mob/living/carbon/human/first = patient(floor_at(1, 0))
	S.set_grid_power(FALSE)
	test_drag(H, first, S)
	test_time(3 SECONDS)
	TEST_ASSERT_NULL(medpod_occupant(S), "a sleeper without power takes nobody")
	S.set_grid_power(TRUE)
	medpod_put_in(S, first)
	var/mob/living/carbon/human/second = patient(floor_at(2, 1))
	test_drag(H, second, S)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(medpod_occupant(S), first, "an occupied sleeper takes nobody else")
	TEST_ASSERT(second.loc != S, "the second person stays out")

/// The wait to go in rechecks the sleeper: losing power during it keeps the person out.
/datum/unit_test/dq_medpod/sleeper_entry_rechecks_power_after_the_wait
/datum/unit_test/dq_medpod/sleeper_entry_rechecks_power_after_the_wait/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	test_drag(H, P, S)
	test_time(1 SECOND)
	S.set_grid_power(FALSE)
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(medpod_occupant(S), "a sleeper that lost power during the wait takes nobody")

/// A grab used on a sleeper puts the grabbed person inside after the same wait.
/datum/unit_test/dq_medpod/sleeper_grab_puts_inside
/datum/unit_test/dq_medpod/sleeper_grab_puts_inside/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	var/obj/item/grab/G = grab(H, P)
	TEST_ASSERT_NOTNULL(G, "setup: the grab is in hand")
	test_click(H, S, G)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(medpod_occupant(S), P, "the grabbed person is inside")

/// The context menu ejects the occupant onto the sleeper's tile; leaving turns dialysis and the stomach pump off and back to idle power.
/datum/unit_test/dq_medpod/sleeper_eject_from_the_menu
/datum/unit_test/dq_medpod/sleeper_eject_from_the_menu/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	medpod_put_in(S, P)
	test_time(1 SECOND)
	medpod_ui(H, S, "togglefilter")
	medpod_ui(H, S, "togglepump")
	test_time(1)
	TEST_ASSERT(S.filtering, "setup: dialysis runs")
	TEST_ASSERT(S.pumping, "setup: the stomach pump runs")
	TEST_ASSERT(medpod_menu(H, S, "Eject"), "the menu offers the eject")
	test_time(1 SECOND)
	TEST_ASSERT_NULL(medpod_occupant(S), "the occupant is out")
	TEST_ASSERT_EQUAL(P.loc, get_turf(S), "on the sleeper's tile")
	TEST_ASSERT(!S.filtering, "dialysis is off")
	TEST_ASSERT(!S.pumping, "the stomach pump is off")
	TEST_ASSERT_EQUAL(S.use_power, USE_POWER_IDLE, "an empty sleeper idles")

/// A conscious occupant who moves gets out.
/datum/unit_test/dq_medpod/sleeper_occupant_moves_out
/datum/unit_test/dq_medpod/sleeper_occupant_moves_out/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	medpod_put_in(S, P)
	test_time(1 SECOND)
	medpod_struggle(P)
	test_time(1 SECOND)
	TEST_ASSERT_NULL(medpod_occupant(S), "the occupant moved out")

/// A stasis level picked in the window holds the occupant; leaving releases it.
/datum/unit_test/dq_medpod/sleeper_stasis_holds_the_occupant
/datum/unit_test/dq_medpod/sleeper_stasis_holds_the_occupant/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	medpod_put_in(S, P)
	medpod_ui(H, S, "changestasis")
	test_answer(H, "Deep (10%)")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(medpod_stasis(P), 0.9, "deep stasis holds the occupant at 10% speed")
	medpod_ui(H, S, "ejectify")
	test_time(1 SECOND)
	TEST_ASSERT_NULL(medpod_occupant(S), "the window's eject lets them out")
	TEST_ASSERT_EQUAL(medpod_stasis(P), 0, "and the stasis ends")

/// A sleeper that loses power stops holding its occupant in stasis.
/datum/unit_test/dq_medpod/sleeper_stasis_needs_power
/datum/unit_test/dq_medpod/sleeper_stasis_needs_power/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	medpod_put_in(S, P)
	medpod_ui(H, S, "changestasis")
	test_answer(H, "Complete (1%)")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(medpod_stasis(P), 0.99, "setup: complete stasis")
	S.set_grid_power(FALSE)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(medpod_stasis(P), 0, "an unpowered sleeper lets go of its occupant's stasis")
	S.set_grid_power(TRUE)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(medpod_stasis(P), 0.99, "and holds them again when the power comes back")

/// The survival pod holds its occupant in complete stasis from the moment they are inside.
/datum/unit_test/dq_medpod/survival_pod_stasis
/datum/unit_test/dq_medpod/survival_pod_stasis/run_pods()
	var/obj/machinery/sleeper/survival_pod/S = allocate(/obj/machinery/sleeper/survival_pod, floor_at(1, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	medpod_put_in(S, P)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(medpod_stasis(P), 0.99, "complete stasis")

/// Dialysis draws the occupant's blood chemicals into the beaker; with no beaker it switches itself off.
/datum/unit_test/dq_medpod/sleeper_dialysis
/datum/unit_test/dq_medpod/sleeper_dialysis/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	TEST_ASSERT_NOTNULL(S.beaker, "a sleeper starts with a beaker")
	medpod_put_in(S, P)
	P.reagents.add_reagent(REAGENT_ID_TOXIN, 20)
	medpod_ui(H, S, "togglefilter")
	test_time(10 SECONDS)
	TEST_ASSERT(S.beaker.reagents.get_reagent_amount(REAGENT_ID_TOXIN) > 0, "the beaker fills with what the blood carried")
	TEST_ASSERT(P.reagents.get_reagent_amount(REAGENT_ID_TOXIN) < 20, "and the blood has less of it")
	medpod_ui(H, S, "removebeaker")
	test_time(1 SECOND)
	TEST_ASSERT_NULL(S.beaker, "the window's button takes the beaker out")
	test_time(5 SECONDS)
	TEST_ASSERT(!S.filtering, "dialysis stops with no beaker")

/// A beaker clicked on the sleeper goes in when it has none; a second is refused.
/datum/unit_test/dq_medpod/sleeper_beaker_bay
/datum/unit_test/dq_medpod/sleeper_beaker_bay/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/obj/item/reagent_containers/glass/old = S.beaker
	medpod_ui(H, S, "removebeaker")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(old.loc, get_turf(S), "the removed beaker is on the sleeper's tile")
	var/obj/item/reagent_containers/glass/beaker/B = give(H, allocate(/obj/item/reagent_containers/glass/beaker, floor_at(0, 1)))
	test_click(H, S, B)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(S.beaker, B, "a beaker click loads it")
	var/obj/item/reagent_containers/glass/beaker/B2 = give(H, allocate(/obj/item/reagent_containers/glass/beaker, floor_at(0, 1)))
	test_click(H, S, B2)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(B2.loc, H, "a second beaker stays in hand")

/// A chemical button injects the occupant; an unlisted one injects nothing.
/datum/unit_test/dq_medpod/sleeper_injects
/datum/unit_test/dq_medpod/sleeper_injects/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	medpod_put_in(S, P)
	medpod_ui(H, S, "chemical", list("chemid" = REAGENT_ID_INAPROVALINE, "amount" = 5))
	test_time(1)
	TEST_ASSERT_EQUAL(P.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE), 5, "the occupant got five units")
	medpod_ui(H, S, "chemical", list("chemid" = REAGENT_ID_TOXIN, "amount" = 5))
	test_time(1)
	TEST_ASSERT_EQUAL(P.reagents.get_reagent_amount(REAGENT_ID_TOXIN), 0, "an unlisted chemical is never injected")

/// A dead occupant is put out when auto-eject is on.
/datum/unit_test/dq_medpod/sleeper_auto_ejects_the_dead
/datum/unit_test/dq_medpod/sleeper_auto_ejects_the_dead/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	medpod_put_in(S, P)
	medpod_ui(H, S, "auto_eject_dead_on")
	test_time(1)
	TEST_ASSERT(S.auto_eject_dead, "setup: auto-eject is on")
	P.death()
	test_time(10 SECONDS)
	TEST_ASSERT_NULL(medpod_occupant(S), "the dead occupant is put out")

/// The occupant works the window only when the sleeper has controls inside.
/datum/unit_test/dq_medpod/sleeper_controls_inside
/datum/unit_test/dq_medpod/sleeper_controls_inside/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/P = person(floor_at(1, 0))
	medpod_put_in(S, P)
	medpod_ui(P, S, "auto_eject_dead_on")
	test_time(1)
	TEST_ASSERT(!S.auto_eject_dead, "an occupant without controls inside works nothing")
	S.controls_inside = TRUE
	medpod_ui(P, S, "auto_eject_dead_on")
	test_time(1)
	TEST_ASSERT(S.auto_eject_dead, "with controls inside the occupant works the window")

/// A pulse turns dialysis off and throws the occupant out of a working sleeper.
/datum/unit_test/dq_medpod/sleeper_emp
/datum/unit_test/dq_medpod/sleeper_emp/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	medpod_put_in(S, P)
	medpod_ui(H, S, "togglefilter")
	test_time(1)
	TEST_ASSERT(S.filtering, "setup: dialysis runs")
	S.emp_act(EMP_MEDIUM)
	test_time(1 SECOND)
	TEST_ASSERT(!S.filtering, "dialysis is off")
	TEST_ASSERT_NULL(medpod_occupant(S), "the occupant is thrown out")

/// A screwdriver does nothing to an occupied sleeper; an empty one opens.
/datum/unit_test/dq_medpod/sleeper_tools_wait_for_an_empty_sleeper
/datum/unit_test/dq_medpod/sleeper_tools_wait_for_an_empty_sleeper/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	medpod_put_in(S, P)
	var/obj/item/tool/screwdriver/SD = give(H, allocate(/obj/item/tool/screwdriver, floor_at(0, 1)))
	test_click(H, S, SD)
	test_time(5 SECONDS)
	TEST_ASSERT(!S.panel_open, "an occupied sleeper's panel stays shut")
	medpod_menu(H, S, "Eject")
	test_time(1 SECOND)
	test_click(H, S, SD)
	test_time(5 SECONDS)
	TEST_ASSERT(S.panel_open, "an empty one opens")

/// A console beside a sleeper pairs with it; the console's window is the sleeper's.
/datum/unit_test/dq_medpod/sleeper_console_pairs
/datum/unit_test/dq_medpod/sleeper_console_pairs/run_pods()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, floor_at(2, 1))
	var/obj/machinery/sleep_console/C = allocate(/obj/machinery/sleep_console, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(1, 0))
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(C.sleeper, S, "the console found the sleeper beside it")
	TEST_ASSERT_EQUAL(S.console, C, "and the sleeper knows its console")
	medpod_ui(H, C, "auto_eject_dead_on")
	test_time(1)
	TEST_ASSERT(S.auto_eject_dead, "a button pressed on the console works the sleeper")
	var/list/data = hc_data(C, H)
	TEST_ASSERT_EQUAL(data["auto_eject_dead"], TRUE, "the console shows the sleeper's data")
	var/obj/machinery/sleep_console/lonely = allocate(/obj/machinery/sleep_console, floor_at(0, 3))
	test_time(1 SECOND)
	TEST_ASSERT_NULL(lonely.sleeper, "a console with no sleeper beside it pairs with nothing")

// ---------------------------------------------------------------------------------------------------------------------
// Cryo cell
// ---------------------------------------------------------------------------------------------------------------------

/// A grab used on an occupied cell is refused: the grab stays in hand and nobody goes in.
/datum/unit_test/dq_medpod/cryo_grab_on_an_occupied_cell
/datum/unit_test/dq_medpod/cryo_grab_on_an_occupied_cell/run_pods()
	var/obj/machinery/atmospherics/unary/cryo_cell/cell = cryo_cell(floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/first = patient(floor_at(1, 0))
	var/mob/living/carbon/human/second = patient(floor_at(0, 0))
	medpod_put_in(cell, first)
	var/obj/item/grab/G = grab(H, second)
	TEST_ASSERT_NOTNULL(G, "setup: the grab is in hand")
	test_click(H, cell, G)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(medpod_occupant(cell), first, "the occupant stays")
	TEST_ASSERT(second.loc != cell, "the grabbed person is not put in")
	TEST_ASSERT(!QDELETED(G) && G.loc == H, "the grab stays in hand")

/// A grab used on an empty working cell puts the grabbed person inside.
/datum/unit_test/dq_medpod/cryo_grab_puts_inside
/datum/unit_test/dq_medpod/cryo_grab_puts_inside/run_pods()
	var/obj/machinery/atmospherics/unary/cryo_cell/cell = cryo_cell(floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	var/obj/item/grab/G = grab(H, P)
	test_click(H, cell, G)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(medpod_occupant(cell), P, "the grabbed person is inside")
	TEST_ASSERT(P in cell.vis_contents, "shown in the tube")
	TEST_ASSERT_EQUAL(P.buckled_to(), cell, "held upright in it")

/// The occupant and the beaker leave to the tile south of the cell when it is open; with a wall there, onto the cell's own tile.
/datum/unit_test/dq_medpod/cryo_exit_south
/datum/unit_test/dq_medpod/cryo_exit_south/run_pods()
	var/turf/here = floor_at(1, 0)
	var/turf/restore = wall_south_of(here)
	var/turf/south = get_step(here, SOUTH)
	var/obj/machinery/atmospherics/unary/cryo_cell/cell = cryo_cell(here)
	var/mob/living/carbon/human/H = person(floor_at(0, 0))
	var/mob/living/carbon/human/P = patient(floor_at(1, 1))
	medpod_put_in(cell, P)
	var/obj/item/reagent_containers/glass/beaker/B = give(H, allocate(/obj/item/reagent_containers/glass/beaker, floor_at(0, 0)))
	test_click(H, cell, B)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(cell.beaker, B, "setup: the beaker is loaded")
	medpod_ui(H, cell, "ejectBeaker")
	medpod_ui(H, cell, "ejectOccupant")
	test_time(1 SECOND)
	TEST_ASSERT_NULL(medpod_occupant(cell), "the occupant is out")
	TEST_ASSERT_EQUAL(P.loc, here, "the occupant is not put in the wall")
	TEST_ASSERT_EQUAL(B.loc, here, "nor is the beaker")
	P.forceMove(here)
	B.forceMove(here)
	restore?.ChangeTurf(/turf/simulated/floor)

/// The cell treats, sends to sleep and cools its occupant while it is on and powered; with no power it does nothing.
/datum/unit_test/dq_medpod/cryo_treats_while_on
/datum/unit_test/dq_medpod/cryo_treats_while_on/run_pods()
	var/obj/machinery/atmospherics/unary/cryo_cell/cell = cryo_cell(floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	P.injure(INJURY_CUT, 25, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	medpod_put_in(cell, P)
	P.set_bodytemperature(T20C)
	medpod_ui(H, cell, "switchOn")
	test_time(1)
	TEST_ASSERT(cell.cooling, "setup: the cell is on")
	test_time(10 SECONDS)
	TEST_ASSERT(P.body_temperature() < T20C, "the occupant is cooled")
	TEST_ASSERT_EQUAL(P.stat, UNCONSCIOUS, "and kept asleep")
	var/load = P.injury_load(INJURY_CATEGORY_PHYSICAL)
	cell.set_grid_power(FALSE)
	P.set_bodytemperature(100)
	test_time(10 SECONDS)
	// Sleep itself may mend a point (a 2% roll per sleeping Life frame): the cell's treatment would take far more.
	TEST_ASSERT(P.injury_load(INJURY_CATEGORY_PHYSICAL) >= load - 1, "an unpowered cell treats nothing ([load] -> [P.injury_load(INJURY_CATEGORY_PHYSICAL)])")
	TEST_ASSERT(!P.has_status(STAT_SLEEPING) || P.status_remaining(STAT_SLEEPING) > 0, "and holds nobody asleep (only the cold's own timed sleep is left)")

/// An occupant ejected while frozen is warmed to 261 K on the way out.
/datum/unit_test/dq_medpod/cryo_eject_warms_the_frozen
/datum/unit_test/dq_medpod/cryo_eject_warms_the_frozen/run_pods()
	var/obj/machinery/atmospherics/unary/cryo_cell/cell = cryo_cell(floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 2))
	medpod_put_in(cell, P)
	P.set_bodytemperature(100)
	TEST_ASSERT(medpod_menu(H, cell, "Eject"), "the menu offers the eject")
	test_time(1 SECOND)
	TEST_ASSERT_NULL(medpod_occupant(cell), "the occupant is out")
	TEST_ASSERT_EQUAL(P.body_temperature(), 261, "warmed to 261 K")
	TEST_ASSERT(!(P in cell.vis_contents), "no longer shown in the tube")
	TEST_ASSERT_EQUAL(P.pixel_y, P.default_pixel_y, "at their own height")
	TEST_ASSERT_NULL(P.buckled_to(), "and free")

/// The occupant's own eject takes two minutes.
/datum/unit_test/dq_medpod/cryo_release_sequence
/datum/unit_test/dq_medpod/cryo_release_sequence/run_pods()
	var/obj/machinery/atmospherics/unary/cryo_cell/cell = cryo_cell(floor_at(1, 1))
	var/mob/living/carbon/human/P = person(floor_at(1, 2))
	medpod_put_in(cell, P)
	TEST_ASSERT(medpod_menu(P, cell, "Eject"), "the occupant's menu offers the eject")
	test_time(1 MINUTES)
	TEST_ASSERT_EQUAL(medpod_occupant(cell), P, "still inside after a minute")
	test_time(70 SECONDS)
	TEST_ASSERT_NULL(medpod_occupant(cell), "out after two")

/// A diona nymph (carbon, not human) is taken by a drag as by the menu: the cell takes any carbon.
/datum/unit_test/dq_medpod/cryo_accepts_carbons
/datum/unit_test/dq_medpod/cryo_accepts_carbons/run_pods()
	var/obj/machinery/atmospherics/unary/cryo_cell/cell = cryo_cell(floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/alien/diona/nymph = allocate(/mob/living/carbon/alien/diona, floor_at(1, 0))
	test_drag(H, nymph, cell)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(medpod_occupant(cell), nymph, "a dragged nymph is taken")

// ---------------------------------------------------------------------------------------------------------------------
// Body scanner
// ---------------------------------------------------------------------------------------------------------------------

/// A grab used on the scanner puts the grabbed person inside at once and uses up the grab.
/datum/unit_test/dq_medpod/scanner_grab_puts_inside
/datum/unit_test/dq_medpod/scanner_grab_puts_inside/run_pods()
	var/obj/machinery/bodyscanner/S = allocate(/obj/machinery/bodyscanner, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	var/obj/item/grab/G = grab(H, P)
	test_click(H, S, G)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(medpod_occupant(S), P, "the grabbed person is inside")
	TEST_ASSERT(QDELETED(G), "the grab is used up")

/// An occupant who moves gets out; a screwdriver does nothing while someone is inside.
/datum/unit_test/dq_medpod/scanner_occupant_and_tools
/datum/unit_test/dq_medpod/scanner_occupant_and_tools/run_pods()
	var/obj/machinery/bodyscanner/S = allocate(/obj/machinery/bodyscanner, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	medpod_put_in(S, P)
	var/obj/item/tool/screwdriver/SD = give(H, allocate(/obj/item/tool/screwdriver, floor_at(0, 1)))
	test_click(H, S, SD)
	test_time(5 SECONDS)
	TEST_ASSERT(!S.panel_open, "an occupied scanner's panel stays shut")
	medpod_struggle(P)
	test_time(1 SECOND)
	TEST_ASSERT_NULL(medpod_occupant(S), "the occupant moved out")
	TEST_ASSERT_EQUAL(P.loc, get_turf(S), "onto the scanner's tile")

/// The window's eject button lets the occupant out.
/datum/unit_test/dq_medpod/scanner_window_eject
/datum/unit_test/dq_medpod/scanner_window_eject/run_pods()
	var/obj/machinery/bodyscanner/S = allocate(/obj/machinery/bodyscanner, floor_at(1, 1))
	var/mob/living/carbon/human/H = person(floor_at(0, 1))
	var/mob/living/carbon/human/P = patient(floor_at(1, 0))
	medpod_put_in(S, P)
	medpod_ui(H, S, "ejectify")
	test_time(1 SECOND)
	TEST_ASSERT_NULL(medpod_occupant(S), "the occupant is out")

/// A console beside a scanner pairs with it and turns to face it; a multitool links a console to a scanner by hand.
/datum/unit_test/dq_medpod/scanner_console_pairs
/datum/unit_test/dq_medpod/scanner_console_pairs/run_pods()
	var/obj/machinery/bodyscanner/S = allocate(/obj/machinery/bodyscanner, floor_at(2, 1))
	var/obj/machinery/body_scanconsole/C = allocate(/obj/machinery/body_scanconsole, floor_at(1, 1))
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(C.scanner, S, "the console found the scanner beside it")
	TEST_ASSERT_EQUAL(S.console, C, "and the scanner knows its console")
	TEST_ASSERT_EQUAL(C.dir, EAST, "the console faces it")
