#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// The reagent rules whose product is an item (food, soap, material sheets, carpet): what a real reaction makes is pinned by the amounts below, which
// are what the old on_reaction() tails made. Each test fills a beaker on the test floor and counts what lies on the floor after.

/datum/unit_test/proc/dq_chem_spawn_react(list/reagents)
	var/turf/T = test_floor()
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker, T)
	for(var/id in reagents)
		B.reagents.add_reagent(id, reagents[id])
	return T

/// Counts the `type` items on `T` (a stack counts its amount) and deletes them.
/datum/unit_test/proc/dq_chem_spawn_take(turf/T, type)
	var/total = 0
	for(var/obj/item/I in T)
		if(!istype(I, type))
			continue
		var/obj/item/stack/S = I
		total += istype(S) ? S.get_amount() : 1
		qdel(I)
	return total

/datum/unit_test/dq_chem_item_spawn_food
	boot_needs = list()

/datum/unit_test/dq_chem_item_spawn_food/Run()
	var/turf/T = dq_chem_spawn_react(list(REAGENT_ID_SOYMILK = 10, REAGENT_ID_ENZYME = 5))
	TEST_ASSERT_EQUAL(dq_chem_spawn_take(T, /obj/item/reagent_containers/food/snacks/tofu), 1, "soy milk and enzyme make one tofu")

/datum/unit_test/dq_chem_item_spawn_soap
	boot_needs = list()

/datum/unit_test/dq_chem_item_spawn_soap/Run()
	var/turf/T = dq_chem_spawn_react(list(REAGENT_ID_COOKINGOIL = 10, REAGENT_ID_LYE = 2))
	TEST_ASSERT_EQUAL(dq_chem_spawn_take(T, /obj/item/soap), 1, "cooking oil and lye make one soap")
	T = dq_chem_spawn_react(list(REAGENT_ID_PROTEIN = 10, REAGENT_ID_LYE = 10))
	TEST_ASSERT_EQUAL(dq_chem_spawn_take(T, /obj/item/soap/homemade), 1, "protein and lye make one homemade soap (the rule used to make none)")

/datum/unit_test/dq_chem_item_spawn_sheets
	boot_needs = list()

/datum/unit_test/dq_chem_item_spawn_sheets/Run()
	var/turf/T = dq_chem_spawn_react(list(REAGENT_ID_CALCIUM = 2, REAGENT_ID_SILICATE = 2, REAGENT_ID_WATER = 2))
	TEST_ASSERT_EQUAL(dq_chem_spawn_take(T, /obj/item/stack/material/concrete), 1, "the concrete mix makes one sheet")
	T = dq_chem_spawn_react(list(REAGENT_ID_PACID = 1, REAGENT_ID_PLASTICIDE = 2))
	TEST_ASSERT_EQUAL(dq_chem_spawn_take(T, /obj/item/stack/material/plastic), 1, "acid and plasticide make one plastic sheet")
	T = dq_chem_spawn_react(list(REAGENT_ID_LIQUIDCARPET = 2, REAGENT_ID_PLASTICIDE = 1))
	TEST_ASSERT_EQUAL(dq_chem_spawn_take(T, /obj/item/stack/tile/carpet), 2, "liquid carpet and plasticide make two carpet tiles")
	T = dq_chem_spawn_react(list(REAGENT_ID_FROSTOIL = 5, REAGENT_ID_IRON = REAGENTS_PER_SHEET))
	TEST_ASSERT_EQUAL(dq_chem_spawn_take(T, /obj/item/stack/material/iron), 1, "frost oil and iron make one iron sheet")

/// A slime extract reaction that spawns still spends a use of the extract (the base slime rule's tail), and goes inert on the last one.
/datum/unit_test/dq_chem_item_spawn_extract_uses
	boot_needs = list()

/datum/unit_test/dq_chem_item_spawn_extract_uses/Run()
	var/turf/T = test_floor()
	var/obj/item/slime_extract/grey/E = allocate(/obj/item/slime_extract/grey, T)
	E.uses = 2
	E.reagents.add_reagent(REAGENT_ID_BLOOD, 5)
	TEST_ASSERT_EQUAL(dq_chem_spawn_take(T, /obj/item/reagent_containers/food/snacks/monkeycube), 5, "a grey extract with blood makes five monkey cubes")
	TEST_ASSERT_EQUAL(E.uses, 1, "the reaction spent one use")
	E.reagents.add_reagent(REAGENT_ID_BLOOD, 5)
	TEST_ASSERT_EQUAL(dq_chem_spawn_take(T, /obj/item/reagent_containers/food/snacks/monkeycube), 5, "the second use makes five more")
	TEST_ASSERT_EQUAL(E.uses, 0, "the extract is spent")
	TEST_ASSERT(findtext(E.name, "inert"), "a spent extract is called inert")

#endif
