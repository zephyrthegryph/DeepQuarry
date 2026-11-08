// An op ability entry belongs to its mob: when the mob is deleted the entry is deleted too, not only dropped from the list (its slot would leak).

/datum/unit_test/dq_op_ability_goes_with_its_mob

/datum/unit_test/dq_op_ability_goes_with_its_mob/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.add_shadekin(/datum/shadekin/full)
	var/datum/action/op_ability/phase = null
	for(var/datum/action/op_ability/entry in H.actions)
		if(entry.op_key == ABILITY_ID_SHADEKIN_PHASE_SHIFT)
			phase = entry
	TEST_ASSERT_NOTNULL(phase, "the shadekin has its phase shift entry")
	var/leaked_before = slot_leak_report(log = FALSE)["/datum/action/op_ability"] || 0
	qdel(H)
	TEST_ASSERT(QDELETED(phase), "the entry is deleted with its mob")
	TEST_ASSERT_EQUAL(slot_leak_report(log = FALSE)["/datum/action/op_ability"] || 0, leaked_before, "and its slot does not leak")
