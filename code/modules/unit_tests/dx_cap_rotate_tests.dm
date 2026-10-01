// rotate() (code/datums/capabilities/library/rotate.dm).

/obj/cap_fixture/rotatable/capabilities()
	. = ..()
	. += cap_rotate()

/obj/cap_fixture/rotatable/counter_only/capabilities()
	. = ..()
	. = without(., /datum/capability/rotate)
	. += cap_rotate(clockwise = FALSE, needs_unanchored = FALSE)

/datum/unit_test/dx_cap_rotate

/datum/unit_test/dx_cap_rotate/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/rotatable/F = allocate(/obj/cap_fixture/rotatable, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	F.set_dir(SOUTH)

	var/datum/interaction/capability/cw = dx_cap_entry(F, "Rotate clockwise")
	var/datum/interaction/capability/ccw = dx_cap_entry(F, "Rotate counter-clockwise")
	TEST_ASSERT_NOTNULL(cw, "clockwise entry")
	TEST_ASSERT_NOTNULL(ccw, "counter-clockwise entry")
	TEST_ASSERT_EQUAL(cw.default_action, INPUT_ACTION_ALTERNATE, "clockwise answers Alternate")
	TEST_ASSERT_NULL(ccw.default_action, "counter-clockwise is Menu only")

	TEST_ASSERT(cw.perform(H, F, null), "rotates clockwise")
	TEST_ASSERT_EQUAL(F.dir, WEST, "south turned clockwise is west")
	TEST_ASSERT(ccw.perform(H, F, null), "rotates counter-clockwise")
	TEST_ASSERT_EQUAL(F.dir, SOUTH, "back to south")
	TEST_ASSERT(ccw.perform(H, F, null), "again")
	TEST_ASSERT_EQUAL(F.dir, EAST, "south turned counter-clockwise is east")

	cap_set(F, CAP_BROKEN, TRUE)
	TEST_ASSERT_NULL(cw.why_not(H, F, null), "rotating works broken")
	cap_set(F, CAP_BROKEN, FALSE)

	F.set_anchored(TRUE)
	TEST_ASSERT_EQUAL(cw.why_not(H, F, null), "it's fastened in place", "refused while anchored")
	TEST_ASSERT(!cw.perform(H, F, null), "and does not turn")
	TEST_ASSERT_EQUAL(F.dir, EAST, "unchanged")
	F.set_anchored(FALSE)

	var/obj/cap_fixture/rotatable/counter_only/G = allocate(/obj/cap_fixture/rotatable/counter_only, T)
	G.set_anchored(TRUE)
	TEST_ASSERT_NULL(dx_cap_entry(G, "Rotate clockwise"), "clockwise = FALSE offers no clockwise entry")
	var/datum/interaction/capability/only = dx_cap_entry(G, "Rotate counter-clockwise")
	TEST_ASSERT_EQUAL(only.default_action, INPUT_ACTION_ALTERNATE, "the only entry answers Alternate")
	TEST_ASSERT_NULL(only.why_not(H, G, null), "needs_unanchored = FALSE turns while anchored")
