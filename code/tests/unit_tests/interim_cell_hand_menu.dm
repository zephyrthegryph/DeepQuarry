/// Cell self-use rows preserve exact active/inactive hand admission, and admission is fresh on every menu read.
/datum/unit_test/dq_hc_struct/cell_hand_menu_admission
/datum/unit_test/dq_hc_struct/cell_hand_menu_admission/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/cell/C = allocate(/obj/item/cell, tile(3, 2))
	check_cell_hand_rows(H, C, FALSE)
	TEST_ASSERT(H.put_in_active_hand(C), "the actual actor takes the cell in its active hand")
	TEST_ASSERT_EQUAL(H.get_active_hand(), C, "the real active hand is the exact cell")
	check_cell_hand_rows(H, C, TRUE)
	TEST_ASSERT(H.drop_from_inventory(C), "the actual actor releases the active cell")
	check_cell_hand_rows(H, C, FALSE)
	TEST_ASSERT(H.put_in_inactive_hand(C), "the actual actor takes the cell in its inactive hand")
	TEST_ASSERT_EQUAL(H.get_inactive_hand(), C, "the real inactive hand is the exact cell")
	check_cell_hand_rows(H, C, TRUE)
	TEST_ASSERT(H.drop_from_inventory(C), "the actual actor releases the inactive cell")
	check_cell_hand_rows(H, C, FALSE)

/datum/unit_test/dq_hc_struct/cell_hand_menu_admission/proc/check_cell_hand_rows(mob/H, obj/item/cell/C, expected)
	var/list/rows = op_menu(H, C, H.get_active_hand())
	for(var/key in list("electrovore_charge", "electrovore_drain"))
		var/list/found
		for(var/list/row as anything in rows)
			if(row["key"] == key)
				found = row
		TEST_ASSERT_NOTNULL(found, "the actual [key] row remains visible regardless of hand occupancy")
		TEST_ASSERT_EQUAL(!!found?["enabled"], expected, "[key] admission follows the exact current hand state")
		if(!expected)
			TEST_ASSERT_EQUAL(found?["reason"], "not in your hand", "[key] preserves the original refusal")
