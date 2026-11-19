// combine_in_loc() (code/content/items/stacks/stack.dm): a stack dropped on a turf pours into the partial stacks of its kind there.

/datum/unit_test/dq_stack_combine_in_loc

/datum/unit_test/dq_stack_combine_in_loc/Run()
	var/turf/T = test_floor()
	var/obj/item/stack/material/steel/A = allocate(/obj/item/stack/material/steel, T, 10)
	var/obj/item/stack/material/steel/B = allocate(/obj/item/stack/material/steel, T, 15)
	B.combine_in_loc()
	TEST_ASSERT(QDELETED(B), "the dropped stack is used up into the one already there")
	TEST_ASSERT_EQUAL(A.get_amount(), 25, "the two partial stacks merge into one")

	var/max = A.get_max_amount()
	var/obj/item/stack/material/steel/C = allocate(/obj/item/stack/material/steel, T, max - 5)
	C.combine_in_loc()
	var/total = 0
	var/count = 0
	for(var/obj/item/stack/material/steel/S in T)
		if(QDELETED(S))
			continue
		count++
		total += S.get_amount()
		TEST_ASSERT(S.get_amount() <= max, "no stack is filled past its max_amount")
	TEST_ASSERT_EQUAL(total, 25 + max - 5, "no sheet is lost when the merge fills a stack")
	TEST_ASSERT_EQUAL(count, 2, "the remainder stays as a second stack")

	var/obj/item/stack/rods/R = allocate(/obj/item/stack/rods, T, 5)
	R.combine_in_loc()
	TEST_ASSERT(!QDELETED(R) && R.get_amount() == 5, "a stack of another kind does not merge")
