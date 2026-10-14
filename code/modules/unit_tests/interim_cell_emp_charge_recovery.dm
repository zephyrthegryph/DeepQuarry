/// Real EMP entry points drain a standard material-built cell according to pulse severity and its actual insulation, preserving capacity and containment; ordinary charging replaces exactly the lost charge.
/datum/unit_test/interim_cell_emp_charge_recovery/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	TEST_ASSERT(user.put_in_active_hand(cell), "the actual actor holds the actual standard power cell")
	var/capacity_before = cell.maxcharge
	var/integrity_before = cell.get_integrity()
	var/resistance = cell.material_emp_resistance
	TEST_ASSERT(resistance >= 0 && resistance < 100, "the actual material-built cell has a finite EMP loss rather than total immunity")
	cell.charge = capacity_before / 2
	var/charge_before = cell.charge
	cell.emp_act(EMP_MEDIUM)
	var/expected_loss = charge_before * (1 - resistance / 100) / EMP_MEDIUM
	TEST_ASSERT(expected_loss > 0, "the actual medium pulse must have a nonzero charge loss")
	TEST_ASSERT(abs(cell.charge - (charge_before - expected_loss)) < 0.001, "the actual medium EMP entry drains the insulated cell's correct charge share")
	TEST_ASSERT_EQUAL(cell.maxcharge, capacity_before, "actual medium EMP charge loss does not corrupt capacity")
	TEST_ASSERT_EQUAL(cell.get_integrity(), integrity_before, "actual EMP charge loss does not apply unrelated structural damage")
	TEST_ASSERT_EQUAL(cell.loc, user, "actual EMP charge loss preserves the cell's actor containment")
	TEST_ASSERT_EQUAL(user.get_active_hand(), cell, "actual EMP charge loss preserves the exact held slot")
	var/missing = capacity_before - cell.charge
	TEST_ASSERT(abs(cell.amount_missing() - missing) < 0.001, "actual charging demand includes the EMP-depleted amount")
	TEST_ASSERT(abs(cell.give(capacity_before, FALSE) - missing) < 0.001, "actual over-requested recharge accepts exactly the missing charge")
	TEST_ASSERT_EQUAL(cell.charge, capacity_before, "actual recharge restores the surviving cell to its original capacity")
	cell.emp_act(EMP_HEAVY)
	var/expected_heavy_loss = capacity_before * (1 - resistance / 100) / EMP_HEAVY
	TEST_ASSERT(abs(cell.charge - (capacity_before - expected_heavy_loss)) < 0.001, "the actual heavy EMP entry applies its stronger severity to the recharged cell")
	TEST_ASSERT_EQUAL(cell.maxcharge, capacity_before, "actual repeated pulse preserves capacity rather than corruption-halving it")
	TEST_ASSERT_EQUAL(user.get_active_hand(), cell, "actual recharge and repeated pulse preserve the original cell identity and held slot")
