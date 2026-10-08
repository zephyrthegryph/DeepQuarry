/// The original single Authorize row stays visible without a card and never duplicates the emag route.
/datum/unit_test/dq_hc_struct/shuttle_authorize_menu_parity
/datum/unit_test/dq_hc_struct/shuttle_authorize_menu_parity/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/computer/shuttle/S = mach(/obj/machinery/computer/shuttle, tile(3, 2))
	var/list/row = authorize_row(H, S, null)
	TEST_ASSERT_EQUAL(row?["key"], "shuttle_authorize", "the missing-card menu uses the existing authorization op")
	TEST_ASSERT(!row?["enabled"], "the empty-hand authorization is disabled")
	TEST_ASSERT_EQUAL(row?["reason"], "needs a card", "the original missing-card refusal is exact")
	var/obj/item/card/id/ID = allocate(/obj/item/card/id, tile(2, 2))
	TEST_ASSERT(H.put_in_active_hand(ID), "the actor holds a real ID card")
	row = authorize_row(H, S, ID)
	TEST_ASSERT_EQUAL(row?["key"], "shuttle_authorize", "an ID selects the existing authorization route")
	TEST_ASSERT(row?["enabled"], "a real ID passes card admission even before heads-access effect checks")
	TEST_ASSERT(H.drop_from_inventory(ID), "the actor releases the ID")
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, tile(2, 2))
	TEST_ASSERT(H.put_in_active_hand(E), "the actor holds a real emag")
	row = authorize_row(H, S, E)
	TEST_ASSERT_EQUAL(row?["key"], "shuttle_emag_launch", "the emag only selects its existing launch consent route")
	TEST_ASSERT(row?["enabled"], "the held emag passes its original item binding")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "menu inspection does not open either existing launch consent")
	TEST_ASSERT_EQUAL(length(S.authorized), 0, "inspection never changes actual authorization state")

/datum/unit_test/dq_hc_struct/shuttle_authorize_menu_parity/proc/authorize_row(mob/H, obj/machinery/computer/shuttle/S, obj/item/held)
	var/list/found
	var/count = 0
	for(var/list/row as anything in op_menu(H, S, held))
		if(row["key"] == "shuttle_authorize" || row["key"] == "shuttle_emag_launch")
			count++
			found = row
	TEST_ASSERT_EQUAL(count, 1, "the actual menu has exactly one authorization row")
	TEST_ASSERT_EQUAL(found?["name"], "Authorize", "the original shared authorization label is retained")
	return found
