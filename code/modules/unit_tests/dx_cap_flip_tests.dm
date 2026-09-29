// flip() (code/datums/capabilities/library/flip.dm).

/obj/structure/table/standard/cap_fixture
	can_flip_verb = FALSE // only the capability's entries

/obj/structure/table/standard/cap_fixture/capabilities()
	. = ..()
	. += flip()

/datum/unit_test/dx_cap_flip

/datum/unit_test/dx_cap_flip/Run()
	var/turf/T = test_floor()
	var/turf/side = get_step(T, NORTH)
	TEST_ASSERT(side, "the test floor needs a neighbour")
	var/obj/structure/table/standard/cap_fixture/table = allocate(/obj/structure/table/standard/cap_fixture, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, side)

	var/datum/interaction/capability/over = dx_cap_entry(table, "Flip table")
	var/datum/interaction/capability/back = dx_cap_entry(table, "Put table back")
	TEST_ASSERT_NOTNULL(over, "the flip entry")
	TEST_ASSERT_NOTNULL(back, "the put back entry")
	TEST_ASSERT_NULL(over.default_action, "Menu only")
	TEST_ASSERT_EQUAL(back.why_not(H, table, null), "it is not flipped", "nothing to put back")
	TEST_ASSERT(!length(table.caps_examine(H)), "no examine line upright")

	TEST_ASSERT_NULL(over.why_not(H, table, null), "an upright table can flip")
	TEST_ASSERT(over.perform(H, table, null), "flips")
	TEST_ASSERT_EQUAL(table.flipped, 1, "flipped")
	TEST_ASSERT_EQUAL(table.dir, SOUTH, "away from the user")
	TEST_ASSERT_EQUAL(GLOB.dispatch_last_record["log"], LOG_GAME, "logged")
	TEST_ASSERT("It has been flipped on its side." in table.caps_examine(H), "examine says flipped")
	TEST_ASSERT_EQUAL(over.why_not(H, table, null), "it is already flipped", "can't flip twice")

	TEST_ASSERT_NULL(back.why_not(H, table, null), "can be put back")
	TEST_ASSERT(back.perform(H, table, null), "puts it back")
	TEST_ASSERT_EQUAL(table.flipped, 0, "upright again")
