/datum/wires/unit_test
	holder_type = /obj
	wire_count = 2
	var/cuts = 0
	var/mends = 0

/datum/wires/unit_test/New(atom/_holder)
	wires = list(WIRE_MAIN_POWER1, WIRE_MAIN_POWER2)
	return ..()

/datum/wires/unit_test/on_cut(wire, mend = FALSE)
	if(mend)
		mends++
	else
		cuts++

/datum/unit_test/wires_bulk_cut_is_idempotent/Run()
	var/obj/holder = allocate(/obj)
	var/datum/wires/unit_test/test_wires = allocate(/datum/wires/unit_test, holder)

	TEST_ASSERT_EQUAL(test_wires.cut_all(), 2, "The first bulk cut should cut every intact wire")
	TEST_ASSERT(test_wires.is_all_cut(), "Every wire should be cut after cut_all()")
	TEST_ASSERT_EQUAL(test_wires.cuts, 2, "Each wire should receive exactly one cut callback")
	TEST_ASSERT_EQUAL(test_wires.mends, 0, "Bulk cutting must not mend wires")

	TEST_ASSERT_EQUAL(test_wires.cut_all(), 0, "A repeated bulk cut should make no changes")
	TEST_ASSERT(test_wires.is_all_cut(), "Repeated bulk cutting must leave every wire cut")
	TEST_ASSERT_EQUAL(test_wires.cuts, 2, "Repeated bulk cutting must not repeat callbacks")
	TEST_ASSERT_EQUAL(test_wires.mends, 0, "Repeated bulk cutting must never mend wires")

	TEST_ASSERT_EQUAL(test_wires.mend_all(), 2, "Bulk mending should mend every cut wire")
	TEST_ASSERT(!test_wires.is_all_cut(), "Bulk mending should leave the wires intact")
	TEST_ASSERT_EQUAL(test_wires.mends, 2, "Each cut wire should receive exactly one mend callback")
	TEST_ASSERT_EQUAL(test_wires.mend_all(), 0, "Repeated bulk mending should make no changes")
	TEST_ASSERT_EQUAL(test_wires.mends, 2, "Repeated bulk mending must not repeat callbacks")

/datum/unit_test/wires_random_cut_only_targets_intact_wires/Run()
	var/obj/holder = allocate(/obj)
	var/datum/wires/unit_test/test_wires = allocate(/datum/wires/unit_test, holder)

	TEST_ASSERT(test_wires.cut_random(), "The first random cut should cut an intact wire")
	TEST_ASSERT(test_wires.cut_random(), "The second random cut should cut the remaining intact wire")
	TEST_ASSERT(test_wires.is_all_cut(), "Random cuts should eventually cut every wire")
	TEST_ASSERT(!test_wires.cut_random(), "Random cutting should be a no-op when every wire is cut")
	TEST_ASSERT_EQUAL(test_wires.cuts, 2, "Random cutting should cut each wire once")
	TEST_ASSERT_EQUAL(test_wires.mends, 0, "Random cutting must never mend wires")

/datum/unit_test/wires_interactive_cut_remains_a_toggle/Run()
	var/obj/holder = allocate(/obj)
	var/datum/wires/unit_test/test_wires = allocate(/datum/wires/unit_test, holder)

	test_wires.cut(WIRE_MAIN_POWER1)
	TEST_ASSERT(test_wires.is_cut(WIRE_MAIN_POWER1), "Interactive cutting should cut an intact wire")
	test_wires.cut(WIRE_MAIN_POWER1)
	TEST_ASSERT(!test_wires.is_cut(WIRE_MAIN_POWER1), "Interactive cutting should mend a cut wire")
	TEST_ASSERT_EQUAL(test_wires.cuts, 1, "Interactive cutting should issue one cut callback")
	TEST_ASSERT_EQUAL(test_wires.mends, 1, "Interactive mending should issue one mend callback")
