/// Single-item menu rows keep the original missing-tool refusals without changing item click bindings.
/datum/unit_test/dq_hc_struct/cycler_missing_item_menu_parity
/datum/unit_test/dq_hc_struct/cycler_missing_item_menu_parity/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/suit_cycler/C = mach(/obj/machinery/suit_cycler, tile(3, 2))
	missing_item_row(H, C, "cycler_insert_grab", "needs a grab")
	missing_item_row(H, C, "cycler_insert_helmet", "needs a void helmet")
	missing_item_row(H, C, "cycler_insert_suit", "needs a voidsuit")
	var/obj/item/clothing/head/helmet/space/void/helmet = allocate(/obj/item/clothing/head/helmet/space/void, tile(2, 2))
	TEST_ASSERT(H.put_in_active_hand(helmet), "the actor holds a real void helmet")
	var/list/row = item_menu_row(H, C, helmet, "cycler_insert_helmet")
	TEST_ASSERT(!row?["enabled"], "the original locked cycler still refuses a real helmet")
	TEST_ASSERT_EQUAL(row?["reason"], "the suit cycler is locked", "the real slot refusal follows the item requirement")
	TEST_ASSERT_NULL(C.helmet, "inspection never inserts the actual helmet")
	TEST_ASSERT_EQUAL(H.get_active_hand(), helmet, "inspection preserves the exact held helmet")

/datum/unit_test/dq_hc_struct/recharger_missing_item_menu_parity
/datum/unit_test/dq_hc_struct/recharger_missing_item_menu_parity/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/recharge_station/C = mach(/obj/machinery/recharge_station, tile(3, 2))
	missing_item_row(H, C, "recharge_station_part_replacement", "needs a rapid part exchange device")
	missing_item_row(H, C, "recharge_station_insert_grab", "needs a grab")
	missing_item_row(H, C, "recharge_station_drag_insert", "needs a mob")
	var/obj/item/storage/part_replacer/R = allocate(/obj/item/storage/part_replacer, tile(2, 2))
	TEST_ASSERT(H.put_in_active_hand(R), "the actor holds a real rapid part exchange device")
	var/list/row = item_menu_row(H, C, R, "recharge_station_part_replacement")
	TEST_ASSERT(row?["enabled"], "the actual device passes the vacant station's original admission")
	TEST_ASSERT_NULL(C.slot_item(OCCUPANT_SLOT_RECHARGE_STATION), "inspection leaves the actual occupant bay empty")
	TEST_ASSERT_EQUAL(H.get_active_hand(), R, "inspection preserves the exact tool")

/datum/unit_test/dq_hc_struct/proc/item_menu_row(mob/H, atom/C, obj/item/held, key)
	var/list/found
	var/count = 0
	for(var/list/row as anything in op_menu(H, C, held))
		if(row["key"] == key)
			count++
			found = row
	TEST_ASSERT_EQUAL(count, 1, "the actual [key] op appears exactly once")
	return found

/datum/unit_test/dq_hc_struct/proc/missing_item_row(mob/H, atom/C, key, reason)
	var/list/row = item_menu_row(H, C, null, key)
	TEST_ASSERT(!row?["enabled"], "the original [key] row is disabled with no held participant")
	TEST_ASSERT_EQUAL(row?["reason"], reason, "[key] retains the exact original missing-item refusal")
