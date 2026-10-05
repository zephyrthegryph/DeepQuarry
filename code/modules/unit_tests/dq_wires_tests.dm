// The wires library's bulk operations on a bare holder: cut-all and mend-all change each wire once, a random cut takes only intact wires, and the
// interactive cut toggles. The holder counts the cut and mend notices it hears.

/datum/wire_set/unit_test
	name = "unit test"
	count = 2
	wires = list(WIRE_MAIN_POWER1, WIRE_MAIN_POWER2)

/obj/wires_unit_test
	var/cuts = 0
	var/mends = 0

CAPABILITIES(/obj/wires_unit_test)
	wires(/datum/wire_set/unit_test, tools = FALSE, at = null)
	on_notice(/datum/notice/wire_cut, then(PROC_REF(heard_cut)))

/obj/wires_unit_test/proc/heard_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(N.mended)
		mends++
	else
		cuts++

/datum/unit_test/wires_bulk_cut_is_idempotent/Run()
	var/obj/wires_unit_test/H = allocate(/obj/wires_unit_test)

	TEST_ASSERT_EQUAL(wires_cut_all(H), 2, "The first bulk cut should cut every intact wire")
	TEST_ASSERT(wires_all_cut(H), "Every wire should be cut after wires_cut_all()")
	TEST_ASSERT_EQUAL(H.cuts, 2, "Each wire should receive exactly one cut notice")
	TEST_ASSERT_EQUAL(H.mends, 0, "Bulk cutting must not mend wires")

	TEST_ASSERT_EQUAL(wires_cut_all(H), 0, "A repeated bulk cut should make no changes")
	TEST_ASSERT(wires_all_cut(H), "Repeated bulk cutting must leave every wire cut")
	TEST_ASSERT_EQUAL(H.cuts, 2, "Repeated bulk cutting must not repeat notices")
	TEST_ASSERT_EQUAL(H.mends, 0, "Repeated bulk cutting must never mend wires")

	TEST_ASSERT_EQUAL(wires_mend_all(H), 2, "Bulk mending should mend every cut wire")
	TEST_ASSERT(!wires_all_cut(H), "Bulk mending should leave the wires intact")
	TEST_ASSERT_EQUAL(H.mends, 2, "Each cut wire should receive exactly one mend notice")
	TEST_ASSERT_EQUAL(wires_mend_all(H), 0, "Repeated bulk mending should make no changes")
	TEST_ASSERT_EQUAL(H.mends, 2, "Repeated bulk mending must not repeat notices")

/datum/unit_test/wires_random_cut_only_targets_intact_wires/Run()
	var/obj/wires_unit_test/H = allocate(/obj/wires_unit_test)

	TEST_ASSERT(wires_cut_random(H), "The first random cut should cut an intact wire")
	TEST_ASSERT(wires_cut_random(H), "The second random cut should cut the remaining intact wire")
	TEST_ASSERT(wires_all_cut(H), "Random cuts should eventually cut every wire")
	TEST_ASSERT(!wires_cut_random(H), "Random cutting should be a no-op when every wire is cut")
	TEST_ASSERT_EQUAL(H.cuts, 2, "Random cutting should cut each wire once")
	TEST_ASSERT_EQUAL(H.mends, 0, "Random cutting must never mend wires")

/datum/unit_test/wires_interactive_cut_remains_a_toggle/Run()
	var/obj/wires_unit_test/H = allocate(/obj/wires_unit_test)

	wires_toggle(H, WIRE_MAIN_POWER1)
	TEST_ASSERT(wire_is_cut(H, WIRE_MAIN_POWER1), "Interactive cutting should cut an intact wire")
	wires_toggle(H, WIRE_MAIN_POWER1)
	TEST_ASSERT(!wire_is_cut(H, WIRE_MAIN_POWER1), "Interactive cutting should mend a cut wire")
	TEST_ASSERT_EQUAL(H.cuts, 1, "Interactive cutting should issue one cut notice")
	TEST_ASSERT_EQUAL(H.mends, 1, "Interactive mending should issue one mend notice")
