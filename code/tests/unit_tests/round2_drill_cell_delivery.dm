/// A real drill adopts only a released cell and requires actual deliverable power, including the current discharge budget.
/datum/unit_test/round2_drill_cell_delivery
	parent_type = /datum/unit_test/dq_p2_engine

/datum/unit_test/round2_drill_cell_delivery/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/mining/drill/drill = allocate(/obj/machinery/mining/drill, T)
	var/obj/item/cell/high/cell = allocate(/obj/item/cell/high, T)
	TEST_ASSERT_EQUAL(drill.get_cell(), null, "actual unloaded drill initially has no cell")
	TEST_ASSERT(drill.charge_use > 0, "actual initialized drill requires positive charge per operation")
	TEST_ASSERT_EQUAL(drill.use_cell_power(), 0, "empty actual bay cannot supply power")
	set_var(drill, nameof(drill.panel_open), TRUE)
	TEST_ASSERT(user.put_in_active_hand(cell), "actor holds original high-capacity cell")
	add_trait(cell, TRAIT_NODROP, "round2_drill_cell_delivery")
	TEST_ASSERT(user.release_refusal(cell, user), "actual source inventory refuses original sticky cell")
	test_click(user, drill, cell)
	TEST_ASSERT_EQUAL(drill.get_cell(), null, "refused insertion leaves actual drill bay empty")
	TEST_ASSERT_EQUAL(user.get_active_hand(), cell, "refused insertion preserves original cell in hand")
	TEST_ASSERT_EQUAL(cell.loc, user, "refused insertion preserves original physical inventory")
	remove_trait(cell, TRAIT_NODROP, "round2_drill_cell_delivery")
	test_time(1 SECOND)
	test_click(user, drill, cell)
	TEST_ASSERT_EQUAL(drill.get_cell(), cell, "allowed native click installs exact original cell")
	TEST_ASSERT_EQUAL(cell.loc, drill, "allowed insertion physically contains original cell")
	TEST_ASSERT_EQUAL(user.get_active_hand(), null, "allowed insertion clears original source hand")
	TEST_ASSERT(cell.check_charge(drill.charge_use), "actual freshly installed cell can deliver one drill operation")
	var/charge_before = cell.charge
	TEST_ASSERT_EQUAL(drill.use_cell_power(), 1, "actual available power supplies one drill operation")
	TEST_ASSERT(cell.charge < charge_before, "successful power use debits actual stored charge")
	cell.refresh_material_discharge()
	var/remaining_credit = cell.material_discharge_credit
	TEST_ASSERT(remaining_credit > 0 && remaining_credit < INFINITY, "actual material-backed cell has a finite positive discharge budget")
	for(var/load_number in 1 to 4)
		if(cell.material_discharge_credit < drill.charge_use)
			break
		cell.give(cell.maxcharge)
		var/credit_before = cell.material_discharge_credit
		TEST_ASSERT(cell.use(credit_before) > 0, "real electrical load uses available discharge budget")
		TEST_ASSERT(cell.material_discharge_credit < credit_before, "real load strictly reduces same-frame discharge budget")
	TEST_ASSERT(cell.material_discharge_credit < drill.charge_use, "actual same-frame discharge budget cannot supply another drill operation")
	cell.give(cell.maxcharge)
	TEST_ASSERT(cell.charge >= drill.charge_use, "actual recharge restores stored energy above the drill's nominal cost")
	TEST_ASSERT(!cell.check_charge(drill.charge_use), "stored energy alone does not restore actual exhausted discharge budget")
	charge_before = cell.charge
	TEST_ASSERT_EQUAL(drill.use_cell_power(), 0, "drill refuses when actual cell cannot deliver its required power")
	TEST_ASSERT_EQUAL(cell.charge, charge_before, "refused power delivery does not debit charge")
	test_time(1 SECOND)
	test_click(user, drill, null)
	TEST_ASSERT_EQUAL(drill.get_cell(), null, "actual empty-hand removal clears drill bay")
	TEST_ASSERT(cell.loc == user && (user.get_active_hand() == cell || user.get_inactive_hand() == cell), "actual removal returns exact original cell to a real hand")
	TEST_ASSERT(!QDELETED(cell), "removed original cell survives")
	qdel(drill)
	TEST_ASSERT(!QDELETED(cell) && cell.loc == user, "empty drill teardown preserves returned original cell")
