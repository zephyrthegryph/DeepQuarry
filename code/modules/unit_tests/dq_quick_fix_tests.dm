// Regression tests for track F quick fixes (doc/rewrite/fixes.md): B5, B18, B19.

/// Records who ctrl-shift-clicked it.
/obj/dq_test_ctrl_shift_probe
	var/mob/clicked_by

/obj/dq_test_ctrl_shift_probe/click_ctrl_shift(mob/user)
	clicked_by = user
	return CLICK_ACTION_SUCCESS

/// B5: a cyborg's ctrl-shift-click reaches the clicked atom, not the borg.
/datum/unit_test/dq_borg_ctrl_shift_click_targets_atom

/datum/unit_test/dq_borg_ctrl_shift_click_targets_atom/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	var/obj/dq_test_ctrl_shift_probe/probe = allocate(/obj/dq_test_ctrl_shift_probe, test_floor())
	probe.BorgCtrlShiftClick(R)
	TEST_ASSERT_EQUAL(probe.clicked_by, R, "borg ctrl-shift-click should call click_ctrl_shift on the target with the borg as user")

/// B18: get_all_contents_type walks nested contents and keeps every match.
/datum/unit_test/dq_get_all_contents_type_nested

/datum/unit_test/dq_get_all_contents_type_nested/Run()
	var/obj/item/storage/box/outer = allocate(/obj/item/storage/box, test_floor())
	var/obj/item/storage/box/inner = new(outer)
	var/obj/item/paper/P1 = new(outer)
	var/obj/item/paper/P2 = new(inner)
	var/list/found = outer.get_all_contents_type(/obj/item/paper)
	TEST_ASSERT(P1 in found, "a directly held match should be found")
	TEST_ASSERT(P2 in found, "a nested match should be found")
	var/list/boxes = outer.get_all_contents_type(/obj/item/storage/box)
	TEST_ASSERT((outer in boxes) && (inner in boxes), "the root and nested containers should both match their type")

/// B15 (radiation shielding by revision) moved to the Rust insulation layer in M5; see dq_propagation_tests.dm.

/// B19: an empty belly reuses its surrounding list instead of allocating one each tick.
/datum/unit_test/dq_empty_belly_does_not_allocate

/datum/unit_test/dq_empty_belly_does_not_allocate/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/belly/B = allocate(/obj/belly, H)
	var/list/before = B.belly_surrounding
	B.update_belly_surrounding()
	B.update_belly_surrounding()
	TEST_ASSERT(B.belly_surrounding == before, "an empty belly should keep the same surrounding list")
	TEST_ASSERT_EQUAL(length(B.belly_surrounding), 0, "an empty belly surrounds nobody")
