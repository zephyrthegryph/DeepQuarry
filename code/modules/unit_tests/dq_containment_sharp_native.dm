// After native slot policy + genuine sharp setter are installed.
// No cold property is disguised as immutable; no fake publication.
/datum/unit_test/dq_containment_sharp_native

/datum/unit_test/dq_containment_sharp_native/Run()
	var/turf/T = dq_containment_floor()
	TEST_ASSERT(T, "clean containment floor exists")
	var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box, T)
	var/obj/item/material/butterfly/knife = allocate(/obj/item/material/butterfly, T)
	var/datum/relation_definition/slot/S = dq_slot_def(/datum/relation_definition/slot/dq_test_main)
	var/list/reads = S.admission_read_keys(box, knife, null)
	var/found = FALSE
	for(var/list/pair as anything in reads)
		if(pair[1] == knife && pair[2] == ITEM_COMBAT_KEY)
			found = TRUE
	TEST_ASSERT(found, "failed native sharp selector records actual candidate combat-trait key")
	TEST_ASSERT_EQUAL(dq_ledger_refusal(knife, box, "main"), "must be sharp", "native folded blade keeps exact old refusal")
	knife.set_active(TRUE)
	knife.update_force()
	TEST_ASSERT_NULL(dq_ledger_refusal(knife, box, "main"), "real activation satisfies native sharp policy")
	TEST_ASSERT(move_into(box, "main", knife), "real sharp insertion succeeds")
	TEST_ASSERT(box.contents_has_tag(TAG_SHARP), "actual contained blade contributes sharp tag")
	knife.set_active(FALSE)
	knife.update_force()
	knife.ledger_refresh_contribution()
	TEST_ASSERT(!box.contents_has_tag(TAG_SHARP), "closing contained blade explicit contribution refresh clears cached aggregate tag")
	TEST_ASSERT_EQUAL(knife.loc, box, "state change preserves custody")
	TEST_ASSERT(!length(dq_ledger(box).verify()), "tracked mutation preserves real incremental ledger invariants")
	TEST_ASSERT(box.slot_remove(knife, T, null), "closed blade can leave despite admission refusal")
	TEST_ASSERT_EQUAL(dq_ledger_refusal(knife, box, "main"), "must be sharp", "closed blade cannot reenter")
