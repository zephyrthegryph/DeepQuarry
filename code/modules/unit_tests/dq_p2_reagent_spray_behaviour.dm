// Behaviour-preservation tests for the spray bottles (phase 2, reagent containers, step 2): the click that sprays, what it sprays at, what it leaves
// alone, the tank refill, the pepper spray's safety, the chem sprayer's three puffs, the hose nozzle's dial, the Empty verb and the examine. They use the
// base, the click helpers and the adapters of dq_p2_reagent_behaviour.dm; the spray-specific adapters are here.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------------------------------------------------

/// A question a proc asks of its user is answered by the adapter when it is asked (a re-run answer today).
/proc/rc_seed_answer(datum/asker, proc_name, key, value)
	GLOB.om_rerun_answers["[REF(asker)]:[proc_name]"] = list("[key]" = value)

/proc/rc_clear_answers(datum/asker, proc_name)
	GLOB.om_rerun_answers -= "[REF(asker)]:[proc_name]"

/// The person empties the spray bottle (the menu verb), answering yes to the question.
/proc/rc_empty_spray(mob/actor, obj/item/reagent_containers/spray/S)
	rc_seed_answer(S, "spray_verb_empty", "a1", "Yes")
	S.spray_verb_empty(actor, null, null)
	rc_clear_answers(S, "spray_verb_empty")

/// The person turns the hose nozzle's dial (an alt-click on it).
/datum/unit_test/dq_p2_reagents/proc/rc_dial(mob/living/carbon/human/H, obj/item/reagent_containers/spray/chemsprayer/hosed/S)
	rc_alt_click(H, S, S)

/// How many spray puffs of the world are around `where`.
/datum/unit_test/dq_p2_reagents/proc/rc_puffs(atom/where)
	var/count = 0
	for(var/obj/effect/effect/water/W in range(8, where))
		count++
	return count

/// The spray's reagents total.
/proc/rc_units(obj/item/reagent_containers/C)
	return round(C.reagents.total_volume, 0.01)

// ---------------------------------------------------------------------------------------------------------------------
// What a spray bottle is
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_reagents/sprays_start_as_declared

/datum/unit_test/dq_p2_reagents/sprays_start_as_declared/run_gate()
	var/list/expected = list(
		list(/obj/item/reagent_containers/spray/cleaner, 250, 10, 250),
		list(/obj/item/reagent_containers/spray/cleaner/drone, 50, 10, 50),
		list(/obj/item/reagent_containers/spray/sterilizine, 250, 10, 250),
		list(/obj/item/reagent_containers/spray/pepper, 40, 10, 40),
		list(/obj/item/reagent_containers/spray/waterflower, 10, 1, 10),
		list(/obj/item/reagent_containers/spray/chemsprayer, 600, 10, 0),
		list(/obj/item/reagent_containers/spray/chemsprayer/hosed, 600, 10, 0),
		list(/obj/item/reagent_containers/spray/plantbgone, 100, 10, 100),
		list(/obj/item/reagent_containers/spray/windowsealant, 80, 10, 80),
	)
	for(var/list/row in expected)
		var/path = row[1]
		var/obj/item/reagent_containers/spray/S = allocate(path)
		TEST_ASSERT_EQUAL(rc_capacity(S), row[2], "[path]: capacity")
		TEST_ASSERT_EQUAL(S.amount_per_transfer_from_this, row[3], "[path]: the amount of one spray")
		TEST_ASSERT_EQUAL(rc_units(S), row[4], "[path]: what it holds at the start")
		TEST_ASSERT(rc_open(S), "[path]: a spray bottle is open (its top is unscrewed)")
	var/obj/item/reagent_containers/spray/pepper/pepper = allocate(/obj/item/reagent_containers/spray/pepper)
	TEST_ASSERT(pepper.safety, "the pepper spray starts with its safety on")

// ---------------------------------------------------------------------------------------------------------------------
// The spray
// ---------------------------------------------------------------------------------------------------------------------

/// A click on a floor sprays one amount out as a puff, and a hostile one the same. A click on a person sprays nothing: the attack handler of a person
/// ends the click before the bottle's own is reached (as it does for any item that does no harm), so a person is not sprayed by a click on them.
/datum/unit_test/dq_p2_reagents/spray_puffs_at_a_floor_and_leaves_a_person_alone

/datum/unit_test/dq_p2_reagents/spray_puffs_at_a_floor_and_leaves_a_person_alone/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/spray/cleaner/S = allocate(/obj/item/reagent_containers/spray/cleaner)
	var/turf/T = get_turf(H)
	TEST_ASSERT_EQUAL(rc_puffs(T), 0, "no spray in the air to start")
	rc_click(H, T, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 240, "the bottle gave one amount (10)")
	TEST_ASSERT(rc_puffs(T) > 0, "and it is in the air as a puff")
	var/mob/living/carbon/human/other = rc_actor()
	rc_click(H, other, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 240, "a person clicked on is not sprayed")
	rc_click(H, other, S, I_HURT, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 240, "nor in a hostile stance")
	rc_click(H, T, S, I_HURT, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 230, "a hostile click on the floor sprays the same amount")

/// A spray bottle works at range: a click on a far floor sprays one amount.
/datum/unit_test/dq_p2_reagents/spray_works_at_range

/datum/unit_test/dq_p2_reagents/spray_works_at_range/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/spray/cleaner/S = allocate(/obj/item/reagent_containers/spray/cleaner)
	var/turf/far = run_loc_floor_top_right
	TEST_ASSERT(get_dist(H, far) > 3, "the target is far away")
	rc_click(H, far, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 240, "a click at range sprays one amount")
	var/mob/living/carbon/human/farther = rc_actor(far)
	rc_click(H, farther, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 230, "also at a person far away (a puff towards them)")

/// Less than one amount left sprays nothing.
/datum/unit_test/dq_p2_reagents/spray_needs_a_full_amount

/datum/unit_test/dq_p2_reagents/spray_needs_a_full_amount/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/spray/S = rc_filled(/obj/item/reagent_containers/spray, 9)
	var/turf/T = get_turf(H)
	rc_click(H, T, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 9, "9 units are less than one spray: nothing is sprayed")
	S.reagents.add_reagent(REAGENT_ID_WATER, 1)
	rc_click(H, T, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 0, "with 10 it sprays all of them")

/// Containers, tables, closets, sinks, a janitor's cart and storage are not sprayed: they are put things in.
/datum/unit_test/dq_p2_reagents/spray_leaves_containers_and_furniture_alone

/datum/unit_test/dq_p2_reagents/spray_leaves_containers_and_furniture_alone/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/spray/cleaner/S = allocate(/obj/item/reagent_containers/spray/cleaner)
	var/list/things = list(
		allocate(/obj/item/reagent_containers/glass/beaker),
		allocate(/obj/structure/table),
		allocate(/obj/structure/closet),
		allocate(/obj/structure/janitorialcart),
		allocate(/obj/item/storage/box))
	for(var/atom/A as anything in things)
		rc_click(H, A, S, I_HELP, FALSE)
		TEST_ASSERT_EQUAL(rc_units(S), 250, "[A.type]: not sprayed")

/// A closed tank refills a spray bottle with the tank's own amount; a full one takes nothing and does not spray.
/datum/unit_test/dq_p2_reagents/spray_is_refilled_from_a_tank

/datum/unit_test/dq_p2_reagents/spray_is_refilled_from_a_tank/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/structure/reagent_dispensers/watertank/tank = allocate(/obj/structure/reagent_dispensers/watertank)
	var/tank_before = tank.reagents.total_volume
	var/obj/item/reagent_containers/spray/S = rc_filled(/obj/item/reagent_containers/spray, 100)
	rc_click(H, tank, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 110, "the tank gave its 10")
	TEST_ASSERT_EQUAL(tank.reagents.total_volume, tank_before - 10, "and lost it")
	var/obj/item/reagent_containers/spray/full = rc_filled(/obj/item/reagent_containers/spray, 250)
	rc_click(H, tank, full, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(full), 250, "a full bottle takes nothing")
	TEST_ASSERT_EQUAL(tank.reagents.total_volume, tank_before - 10, "and is not sprayed at the tank either")

/// The pepper spray's safety: on, it sprays nothing; used in hand it goes off, and then it sprays.
/datum/unit_test/dq_p2_reagents/pepper_spray_safety

/datum/unit_test/dq_p2_reagents/pepper_spray_safety/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/spray/pepper/S = allocate(/obj/item/reagent_containers/spray/pepper)
	var/turf/T = get_turf(H)
	rc_click(H, T, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 40, "with the safety on nothing comes out")
	rc_use(H, S)
	TEST_ASSERT(!S.safety, "used in hand the safety goes off")
	rc_click(H, T, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 30, "and it sprays")
	rc_use(H, S)
	TEST_ASSERT(S.safety, "used again it goes back on")

/// The chem sprayer puffs three times in one click: at the target and to each side of it.
/datum/unit_test/dq_p2_reagents/chem_sprayer_sprays_three_puffs

/datum/unit_test/dq_p2_reagents/chem_sprayer_sprays_three_puffs/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/spray/chemsprayer/S = rc_filled(/obj/item/reagent_containers/spray/chemsprayer, 100)
	var/turf/T = get_turf(H)
	rc_click(H, T, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 70, "three amounts leave in a click")
	var/obj/item/reagent_containers/spray/chemsprayer/low = rc_filled(/obj/item/reagent_containers/spray/chemsprayer, 15)
	rc_click(H, T, low, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(low), 0, "with less it empties what it can: 10, then 5, then it is empty")

/// The hose nozzle: an alt-click turns its dial through 1, 2, 3; a heavy spray sends that many streams.
/datum/unit_test/dq_p2_reagents/hose_nozzle_dial

/datum/unit_test/dq_p2_reagents/hose_nozzle_dial/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/spray/chemsprayer/hosed/S = rc_filled(/obj/item/reagent_containers/spray/chemsprayer/hosed, 200)
	TEST_ASSERT_EQUAL(S.spray_particles, 3, "the dial starts at 3")
	rc_dial(H, S)
	TEST_ASSERT_EQUAL(S.spray_particles, 1, "an alt-click turns it past 3 to 1")
	rc_dial(H, S)
	TEST_ASSERT_EQUAL(S.spray_particles, 2, "then 2")
	rc_dial(H, S)
	TEST_ASSERT_EQUAL(S.spray_particles, 3, "then 3")
	var/turf/T = get_turf(H)
	rc_click(H, T, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 170, "a light spray is three puffs of 10")
	S.heavy_spray = TRUE
	S.spray_particles = 2
	rc_click(H, T, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 150, "a heavy spray sends the dial's number of streams, 10 each")

/// The Empty verb pours the whole bottle onto the floor.
/datum/unit_test/dq_p2_reagents/spray_empty_verb

/datum/unit_test/dq_p2_reagents/spray_empty_verb/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/spray/S = rc_filled(/obj/item/reagent_containers/spray, 80)
	rc_empty_spray(H, S)
	TEST_ASSERT_EQUAL(rc_units(S), 0, "the bottle is emptied")

/// Held, a spray bottle says how much is left; looked at on a table it does not.
/datum/unit_test/dq_p2_reagents/spray_examine

/datum/unit_test/dq_p2_reagents/spray_examine/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/spray/S = rc_filled(/obj/item/reagent_containers/spray, 80)
	TEST_ASSERT(!findtext(jointext(S.examine(H), "\n"), "units left"), "on the floor it does not say")
	H.drop_item()
	H.put_in_active_hand(S)
	TEST_ASSERT(findtext(jointext(S.examine(H), "\n"), "80 units left"), "in the hand it says 80 units left")
