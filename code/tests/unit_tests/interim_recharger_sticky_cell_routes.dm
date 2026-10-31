/// Both real recharger insertion ops must respect a held cell's release refusal, then adopt and return that same cell once the restriction is removed.
/datum/unit_test/interim_recharger_sticky_cell_routes
	parent_type = /datum/unit_test/dq_p2_chargers

/datum/unit_test/interim_recharger_sticky_cell_routes/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = p2c_actor(T)
	// Explicit op dispatch exercises both real insert effects and their requirements; it does not assert native click selection.
	for(var/route in list("item", "drag"))
		var/obj/machinery/recharger/charger = p2c_recharger(/obj/machinery/recharger, T)
		var/obj/item/cell/cell = allocate(/obj/item/cell, T)
		dq_machine_clear(charger)
		TEST_ASSERT(charger.powered(), "the actual recharger fixture has power for [route] insertion")
		TEST_ASSERT(user.put_in_active_hand(cell), "the actual actor holds the cell for [route] insertion")
		var/charge_before = cell.charge
		add_trait(cell, TRAIT_NODROP, "interim_recharger_sticky_cell")
		TEST_ASSERT(user.release_refusal(cell, user), "the actual inventory refuses the held cell for [route] insertion")
		perform_op(user, charger, route == "item" ? "insert" : "insert_drag", cell, origin = ORIGIN_SYSTEM)
		TEST_ASSERT_NULL(charger.charging, "actual [route] insertion refusal preserves the empty recharger")
		TEST_ASSERT_EQUAL(cell.loc, user, "actual [route] insertion refusal preserves the cell's actor containment")
		TEST_ASSERT_EQUAL(user.get_active_hand(), cell, "actual [route] insertion refusal preserves the exact held slot")
		TEST_ASSERT_EQUAL(cell.charge, charge_before, "actual [route] insertion refusal preserves stored charge")
		remove_trait(cell, TRAIT_NODROP, "interim_recharger_sticky_cell")
		perform_op(user, charger, route == "item" ? "insert" : "insert_drag", cell, origin = ORIGIN_SYSTEM)
		TEST_ASSERT_EQUAL(charger.charging, cell, "actual [route] insertion adopts the same cell after release is allowed")
		TEST_ASSERT_EQUAL(owner_of(cell), charger, "actual insertion stamps the declared charging ownership")
		TEST_ASSERT_EQUAL(cell.loc, charger, "actual [route] insertion places the released cell inside the recharger")
		TEST_ASSERT_NULL(user.get_active_hand(), "actual [route] insertion clears the original hand slot")
		perform_op(user, charger, "take", origin = ORIGIN_SYSTEM)
		TEST_ASSERT_NULL(charger.charging, "actual [route] round-trip removal clears the recharger's ownership view")
		TEST_ASSERT_EQUAL(user.get_active_hand(), cell, "actual [route] round-trip removal returns the original cell to the free hand")
		TEST_ASSERT_NULL(owner_of(cell), "actual removal detaches the original charging ownership stamp")
		TEST_ASSERT_EQUAL(cell.loc, user, "actual [route] round-trip removal restores actual inventory containment")
		TEST_ASSERT_EQUAL(cell.charge, charge_before, "actual [route] insertion and removal preserve stored charge")
		qdel(charger)
		TEST_ASSERT(!QDELETED(cell), "deleting the empty recharger cannot delete its returned original cell")
		TEST_ASSERT_EQUAL(user.get_active_hand(), cell, "empty recharger teardown preserves the returned cell in its real hand")
		TEST_ASSERT(user.drop_from_inventory(cell), "the actual actor releases the returned cell before the next route")
