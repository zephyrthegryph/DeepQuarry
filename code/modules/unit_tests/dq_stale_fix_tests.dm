// Regression tests for the staleness findings (doc/rewrite/final_api.html section 7, "Reactive closure"): after the action, the value a stat serves
// is the value a recompute from scratch gives. No checker involved: each test asserts stat_value() against stat_compute() directly.

/datum/unit_test/dq_stale_fix
	abstract_type = /datum/unit_test/dq_stale_fix

/// Null when the stat's served value and its fresh composition are one value, else what differs.
/proc/stale_fix_difference(datum/E, stat_id, what)
	var/datum/stat_def/def = stat_def_of(stat_id)
	var/served = stat_value(E, stat_id)
	var/fresh = stat_compute(E, def, stat_type_of(E), E.rx?.stats)
	if(stat_values_equal(served, fresh))
		return null
	return "[what]: [E.type] [def.name] serves [served] but composes to [fresh]"

/// The stat's holds as text, for a failure message.
/proc/stale_fix_holds(datum/E, stat_id)
	var/list/out = list()
	for(var/list/row as anything in E.rx?.stats?.holds)
		if(row[H_STAT] == stat_id)
			out += "[row[H_SOURCE]]=[row[H_VALUE]]"
	return jointext(out, ", ")

/// A human with seeing eyes: a bare human has no vision organ, and Life keeps one without eyes blind with a fresh dose each frame.
/proc/stale_fix_sighted_human(datum/unit_test/test)
	var/mob/living/carbon/human/H = test.allocate(/mob/living/carbon/human)
	if(!H.organ_in(H.species.vision_organ))
		H.species.create_organs(H)
	return H

/datum/unit_test/dq_stale_fix/proc/assert_fresh(datum/E, stat_id, what)
	var/difference = stale_fix_difference(E, stat_id, what)
	TEST_ASSERT(!difference, difference)

/datum/unit_test/dq_stale_fix/terminal_hides_through_the_stat

/datum/unit_test/dq_stale_fix/terminal_hides_through_the_stat/Run()
	var/obj/machinery/power/terminal/T = allocate(/obj/machinery/power/terminal)
	T.hide(1)
	TEST_ASSERT_EQUAL(T.invisibility, INVISIBILITY_ABSTRACT, "a terminal under a floor is out of sight")
	assert_fresh(T, STAT_INVISIBILITY, "hidden terminal")
	T.hide(0)
	TEST_ASSERT_EQUAL(T.invisibility, INVISIBILITY_NONE, "and in sight again")
	assert_fresh(T, STAT_INVISIBILITY, "revealed terminal")

/datum/unit_test/dq_stale_fix/under_floor_things_hide_through_the_stat

/datum/unit_test/dq_stale_fix/under_floor_things_hide_through_the_stat/Run()
	for(var/path in list(/obj/structure/cable, /obj/machinery/navbeacon, /obj/machinery/magnetic_module, /obj/structure/disposalpipe/segment))
		var/obj/O = allocate(path)
		O.hide(1)
		TEST_ASSERT_EQUAL(O.invisibility, INVISIBILITY_ABSTRACT, "[path] hides under a floor")
		assert_fresh(O, STAT_INVISIBILITY, "hidden [path]")
		O.hide(0)
		assert_fresh(O, STAT_INVISIBILITY, "revealed [path]")
		TEST_ASSERT_EQUAL(O.invisibility, initial(O.invisibility), "[path] returns to its own invisibility")

/datum/unit_test/dq_stale_fix/pipe_hides_through_the_stat

/datum/unit_test/dq_stale_fix/pipe_hides_through_the_stat/Run()
	var/obj/machinery/atmospherics/pipe/simple/hidden/supply/P = allocate(/obj/machinery/atmospherics/pipe/simple/hidden/supply)
	P.hide(1)
	assert_fresh(P, STAT_INVISIBILITY, "hidden pipe")
	P.hide(0)
	assert_fresh(P, STAT_INVISIBILITY, "revealed pipe")

/datum/unit_test/dq_stale_fix/door_swing_is_held_on_density_and_opacity

/datum/unit_test/dq_stale_fix/door_swing_is_held_on_density_and_opacity/Run()
	var/obj/machinery/door/airlock/external/D = allocate(/obj/machinery/door/airlock/external)
	var/shut_opacity = D.opacity
	D.set_density(FALSE)
	D.set_opacity(FALSE)
	TEST_ASSERT(!D.density, "an open door is not solid")
	TEST_ASSERT(!D.opacity, "an open door is clear")
	assert_fresh(D, STAT_DENSITY, "open door")
	assert_fresh(D, STAT_OPACITY, "open door")
	D.set_density(TRUE)
	D.set_opacity(shut_opacity)
	TEST_ASSERT(D.density, "a shut door is solid")
	TEST_ASSERT_EQUAL(!!D.opacity, !!shut_opacity, "a shut door is as opaque as its type says")
	assert_fresh(D, STAT_DENSITY, "shut door")
	assert_fresh(D, STAT_OPACITY, "shut door")
	D.set_opacity(TRUE)
	D.set_opacity(FALSE)
	assert_fresh(D, STAT_OPACITY, "a door cleared after being made opaque")

/datum/unit_test/dq_stale_fix/door_that_starts_open_can_be_shut

/datum/unit_test/dq_stale_fix/door_that_starts_open_can_be_shut/Run()
	var/obj/machinery/door/blast/regular/open/D = allocate(/obj/machinery/door/blast/regular/open)
	TEST_ASSERT(!D.density, "a blast door mapped open is not solid")
	D.set_density(TRUE)
	TEST_ASSERT(D.density, "and can be shut")
	assert_fresh(D, STAT_DENSITY, "shut blast door")

/datum/unit_test/dq_stale_fix/blinded_follows_its_holds

/datum/unit_test/dq_stale_fix/blinded_follows_its_holds/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_blinded(TRUE)
	TEST_ASSERT(H.has_status(STAT_BLINDED), "blind while the sight is held down")
	assert_fresh(H, STAT_BLINDED, "blinded human")
	H.set_blinded(FALSE)
	TEST_ASSERT(!H.has_status(STAT_BLINDED), "sighted once the hold is released")
	assert_fresh(H, STAT_BLINDED, "sighted human")
	H.set_blinded(FALSE)
	assert_fresh(H, STAT_BLINDED, "sighted human, released again")

/// A dose of blindness lapses on the Life clock and the stat follows it down.
/datum/unit_test/life_om/dq_stale_fix_blinded_dose_lapses

/datum/unit_test/life_om/dq_stale_fix_blinded_dose_lapses/run_life()
	var/mob/living/carbon/human/H = stale_fix_sighted_human(src)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.status_set(STAT_BLINDED, 2)
	TEST_ASSERT(H.has_status(STAT_BLINDED), "a dose blinds")
	var/difference = stale_fix_difference(H, STAT_BLINDED, "dosed human")
	TEST_ASSERT(!difference, difference)
	life_test_advance(LIFE_CYCLE_SECONDS * 20)
	TEST_ASSERT(!held_by_source(H, STAT_BLINDED, SRC_STATUS), "the dose wears off (holds: [stale_fix_holds(H, STAT_BLINDED)])")
	TEST_ASSERT_EQUAL(!!H.blinded, !!H.has_status(STAT_BLINDED), "and the blinded var is the stat's value")
	difference = stale_fix_difference(H, STAT_BLINDED, "human after the dose")
	TEST_ASSERT(!difference, difference)

/// A blindfold's hold is released when it comes off, and a visor's with it: the human is sighted again.
/datum/unit_test/life_om/dq_stale_fix_blindfold_hold_released

/datum/unit_test/life_om/dq_stale_fix_blindfold_hold_released/run_life()
	var/mob/living/carbon/human/H = stale_fix_sighted_human(src)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	life_disability_hold(H, STAT_BLINDED, SRC_BLINDFOLD, TRUE)
	TEST_ASSERT(H.has_status(STAT_BLINDED), "a blindfold hold blinds")
	life_test_advance(LIFE_CYCLE_SECONDS * 3)
	TEST_ASSERT(!held_by_source(H, STAT_BLINDED, SRC_BLINDFOLD), "Life finds no blindfold and releases the hold (holds: [stale_fix_holds(H, STAT_BLINDED)])")
	var/difference = stale_fix_difference(H, STAT_BLINDED, "human without the blindfold")
	TEST_ASSERT(!difference, difference)
