// T8: a holder whose starting reagents are a per-type constant is filled from its declaration's shared template in one pass. These check the
// result is what adding them one by one gives, and that two fresh holders share nothing a write could reach.

/// Three inert starting reagents: one pass from the template (a single reagent goes add by add, no cheaper in one pass).
/obj/item/dq_reagent_template_probe

CAPABILITIES(/obj/item/dq_reagent_template_probe)
	reagents(40, add = list(REAGENT_ID_COLA = 10, REAGENT_ID_SPACEUP = 10, REAGENT_ID_DRGIBB = 10))

/datum/unit_test/dq_reagent_starting_template_matches_adds

/datum/unit_test/dq_reagent_starting_template_matches_adds/Run()
	for(var/path in list(/obj/item/dq_reagent_template_probe))
		var/obj/item/fresh = allocate(path)
		var/datum/capability/lib/reagents/C = null
		var/datum/type_table/T = type_table_store[path]
		for(var/datum/centry/E as anything in compiled_entries(T, ENTRY_CAPABILITY))
			if(istype(E.item, /datum/capability/lib/reagents))
				C = E.item
		TEST_ASSERT_NOTNULL(C, "[path] declares reagents()")
		TEST_ASSERT_EQUAL(length(C.template_cache), 3, "[path]'s starting reagents are a shared template")
		var/obj/item/manual = allocate(/obj/item)
		manual.create_reagents(fresh.reagents.maximum_volume)
		for(var/id in C.template_cache)
			manual.reagents.add_reagent(id, C.template_cache[id], null, TRUE) // as preinit adds an inert set: no settle
		TEST_ASSERT_EQUAL(fresh.reagents.total_volume, manual.reagents.total_volume, "[path]: same total as adding one by one")
		TEST_ASSERT_EQUAL(fresh.reagents.tint, manual.reagents.tint, "[path]: same tint")
		TEST_ASSERT_EQUAL(fresh.reagents.master_id, manual.reagents.master_id, "[path]: same master reagent")
		TEST_ASSERT_EQUAL(length(fresh.reagents.reagent_list), length(manual.reagents.reagent_list), "[path]: same reagents")
		for(var/datum/reagent/R as anything in manual.reagents.reagent_list)
			TEST_ASSERT_EQUAL(fresh.reagents.get_reagent_amount(R.id), R.volume, "[path]: same amount of [R.id]")
			TEST_ASSERT_EQUAL(fresh.reagents.get_reagent(R.id)?.holder, fresh.reagents, "[path]: [R.id] belongs to its own holder")

/datum/unit_test/dq_reagent_starting_template_holders_independent

/datum/unit_test/dq_reagent_starting_template_holders_independent/Run()
	var/obj/item/reagent_containers/food/drinks/cans/cola/A = allocate(/obj/item/reagent_containers/food/drinks/cans/cola)
	var/obj/item/reagent_containers/food/drinks/cans/cola/B = allocate(/obj/item/reagent_containers/food/drinks/cans/cola)
	TEST_ASSERT(A.reagents.reagent_list != B.reagents.reagent_list, "two fresh cans have their own reagent lists")
	TEST_ASSERT(A.reagents.get_reagent(REAGENT_ID_COLA) != B.reagents.get_reagent(REAGENT_ID_COLA), "and their own cola")
	A.reagents.remove_reagent(REAGENT_ID_COLA, 10)
	A.reagents.add_reagent(REAGENT_ID_WATER, 5)
	TEST_ASSERT_EQUAL(A.reagents.total_volume, 25, "the written can changed")
	TEST_ASSERT_EQUAL(B.reagents.total_volume, 30, "the other can did not")
	TEST_ASSERT(!B.reagents.has_reagent(REAGENT_ID_WATER), "nor took the water")
	var/obj/item/reagent_containers/food/drinks/cans/cola/C = allocate(/obj/item/reagent_containers/food/drinks/cans/cola)
	TEST_ASSERT_EQUAL(C.reagents.get_reagent_amount(REAGENT_ID_COLA), 30, "a can made after the writes still starts with 30 of cola")
