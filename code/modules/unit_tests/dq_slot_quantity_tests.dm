// A slot that takes a quantity (doc/rewrite/proposals/admission.md D2a, D2f): a per-instance limit (capacity = nameof(var)), units, and a partial
// insert: move_into(amount =) moves as many units as there is room for and leaves the rest where they were. Fixtures: code/tests/engine/qty_fixtures.dm.

/datum/unit_test/dq_slot_quantity_partial_insert

/datum/unit_test/dq_slot_quantity_partial_insert/Run()
	var/turf/T = test_floor()
	var/obj/qty_fixture/bay = allocate(/obj/qty_fixture, T)
	var/obj/item/stack/rods/rods = allocate(/obj/item/stack/rods, T, 8)
	TEST_ASSERT_EQUAL(bay.slot_capacity("qty_bay"), 5, "the limit is read off the holder's var")
	TEST_ASSERT_EQUAL(bay.slot_room(rods, "qty_bay"), 5, "five units of room in the empty bay")
	// 8 asked, 5 fit: the part moves, the rest stays on the floor.
	var/moved = move_into(bay, "qty_bay", rods, null, amount = QUANTITY_ALL)
	TEST_ASSERT_EQUAL(moved, 5, "move_into returns the units that landed")
	TEST_ASSERT_EQUAL(rods.get_amount(), 3, "the rest of the stack stays where it was")
	TEST_ASSERT(rods.loc == T, "and it was never taken from the floor")
	TEST_ASSERT_EQUAL(bay.slot_used("qty_bay"), 5, "the bay is full")
	var/list/inside = bay.slot_contents("qty_bay")
	TEST_ASSERT_EQUAL(length(inside), 1, "one stack went in")
	var/obj/item/stack/part = inside[1]
	TEST_ASSERT_EQUAL(part.get_amount(), 5, "carrying five units")
	TEST_ASSERT_EQUAL(bay.slot_room(rods, "qty_bay"), 0, "no room left")
	TEST_ASSERT(!move_into(bay, "qty_bay", rods, null, amount = QUANTITY_ALL), "a full bay refuses the rest")
	TEST_ASSERT_EQUAL(rods.get_amount(), 3, "and the refused stack is untouched")
	// A larger limit makes room by itself (per instance).
	bay.bay_room = 7
	TEST_ASSERT_EQUAL(bay.slot_room(rods, "qty_bay"), 2, "raising the holder's limit opens room")
	TEST_ASSERT_EQUAL(move_into(bay, "qty_bay", rods, null, amount = 1), 1, "an amount below the room moves just that")
	TEST_ASSERT_EQUAL(rods.get_amount(), 2, "two units left")
	// Everything fits: the thing itself goes, whole.
	var/obj/item/stack/rods/one = allocate(/obj/item/stack/rods, T, 1)
	TEST_ASSERT_EQUAL(move_into(bay, "qty_bay", one, null, amount = QUANTITY_ALL), 1, "a stack that fits goes whole")
	TEST_ASSERT(one.loc == bay, "the stack itself is inside")
	TEST_ASSERT_EQUAL(bay.slot_used("qty_bay"), 7, "seven of seven")

/// A slot that is not a quantity ignores amount: the thing goes whole, counted as one.
/datum/unit_test/dq_slot_quantity_whole_slot_ignores_amount

/datum/unit_test/dq_slot_quantity_whole_slot_ignores_amount/Run()
	var/turf/T = test_floor()
	var/obj/qty_fixture/bay = allocate(/obj/qty_fixture, T)
	var/obj/item/stack/rods/rods = allocate(/obj/item/stack/rods, T, 8)
	TEST_ASSERT(move_into(bay, "qty_whole", rods, null, amount = 3), "the whole stack goes into a plain slot")
	TEST_ASSERT(rods.loc == bay, "whole, not split")
	TEST_ASSERT_EQUAL(rods.get_amount(), 8, "with every unit")
	TEST_ASSERT_EQUAL(bay.slot_used("qty_whole"), 1, "and costs one")
