#ifdef UNIT_TESTS
GLOBAL_VAR_INIT(interim_stamp_choice_allocations, 0)

/obj/item/stamp/interim_choice_observer
	name = "allocation observer rubber stamp"
	icon_state = "stamp-qm"

/obj/item/stamp/interim_choice_observer/Initialize(mapload)
	GLOB.interim_stamp_choice_allocations++
	return ..()

/obj/item/stamp/interim_duplicate_first
	name = "duplicate observer rubber stamp"

/obj/item/stamp/interim_duplicate_last
	name = "duplicate observer rubber stamp"

/datum/unit_test/interim_stamp_choice_metadata/Run()
	var/obj/item/stamp/chameleon/C = allocate(/obj/item/stamp/chameleon, run_loc_floor_bottom_left)
	var/duplicate_winner
	for(var/stamp_type in typesof(/obj/item/stamp) - C.type)
		if(stamp_type == /obj/item/stamp/interim_duplicate_first || stamp_type == /obj/item/stamp/interim_duplicate_last)
			duplicate_winner = stamp_type
	TEST_ASSERT_NOTNULL(duplicate_winner, "both real duplicate-label fixture types are enumerated")
	var/before = GLOB.interim_stamp_choice_allocations
	var/list/choices = C.stamp_choice_types()
	TEST_ASSERT_EQUAL(choices["Duplicate observer rubber stamp"], duplicate_winner, "duplicate labels retain the final type in actual enumeration order")
	TEST_ASSERT(length(choices) > 3, "the real choice builder enumerates canonical stamps")
	TEST_ASSERT_EQUAL(choices["Rubber stamp"], /obj/item/stamp/fluff, "the existing duplicate label keeps its original final fluff type")
	TEST_ASSERT_EQUAL(choices["Site manager's rubber stamp"], /obj/item/stamp/captain, "the captain label retains its canonical type")
	TEST_ASSERT_EQUAL(choices["Quartermaster's rubber stamp"], /obj/item/stamp/qm, "the quartermaster label retains its canonical type")
	TEST_ASSERT_EQUAL(choices["Allocation observer rubber stamp"], /obj/item/stamp/interim_choice_observer, "the actual types enumeration includes the allocation observer")
	TEST_ASSERT_EQUAL(GLOB.interim_stamp_choice_allocations, before, "enumerating every choice constructs zero observer stamp atoms")
	for(var/label in choices)
		TEST_ASSERT(choices[label] != C.type, "the picker excludes its exact source type")
	var/obj/item/stamp/captain/captain_type = choices["Site manager's rubber stamp"]
	var/obj/item/stamp/qm/qm_type = choices["Quartermaster's rubber stamp"]
	TEST_ASSERT_EQUAL(initial(captain_type.icon_state), "stamp-cap", "the selected captain type supplies its original icon")
	TEST_ASSERT_EQUAL(initial(qm_type.icon_state), "stamp-qm", "the selected quartermaster type supplies its original icon")
#endif
