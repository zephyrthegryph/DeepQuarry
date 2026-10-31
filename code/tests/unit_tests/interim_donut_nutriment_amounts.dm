/// Real data-only donut initialization preserves cumulative nutrition, filling and flavor metadata.
/datum/unit_test/interim_donut_nutriment_amounts/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/static/list/cases = list(
		list(/obj/item/reagent_containers/food/snacks/donut/plain, 9, 0, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/plain/jelly, 12, 5, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/plain/jelly/poisonberry, 12, 5, 0, 0, REAGENT_ID_POISONBERRYJUICE),
		list(/obj/item/reagent_containers/food/snacks/donut/plain/jelly/slimejelly, 12, 5, 0, 0, REAGENT_ID_SLIMEJELLY),
		list(/obj/item/reagent_containers/food/snacks/donut/plain/jelly/cherryjelly, 12, 5, 0, 0, REAGENT_ID_CHERRYJELLY),
		list(/obj/item/reagent_containers/food/snacks/donut/pink, 9, 0, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/pink/jelly, 12, 5, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/purple, 9, 0, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/purple/jelly, 12, 5, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/green, 9, 0, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/green/jelly, 12, 5, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/beige, 9, 0, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/beige/jelly, 12, 5, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/choc, 9, 0, 5, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/choc/jelly, 12, 5, 10, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/blue, 9, 0, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/blue/jelly, 12, 5, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/yellow, 9, 0, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/yellow/jelly, 12, 5, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/olive, 9, 0, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/olive/jelly, 12, 5, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/homer, 9, 0, 0, 1),
		list(/obj/item/reagent_containers/food/snacks/donut/homer/jelly, 12, 5, 0, 2),
		list(/obj/item/reagent_containers/food/snacks/donut/choc_sprinkles, 9, 0, 1, 1),
		list(/obj/item/reagent_containers/food/snacks/donut/choc_sprinkles/jelly, 12, 5, 2, 2),
		list(/obj/item/reagent_containers/food/snacks/donut/laugh, 9, 0, 0, 0),
		list(/obj/item/reagent_containers/food/snacks/donut/laugh/jelly, 12, 5, 0, 0),
	)
	for(var/list/entry as anything in cases)
		var/donut_type = entry[1]
		var/obj/item/reagent_containers/food/snacks/donut/donut = allocate(donut_type, T)
		TEST_ASSERT(!QDELETED(donut), "the real donut initializes alive: [donut_type]")
		TEST_ASSERT_EQUAL(donut.reagents.get_reagent_amount(REAGENT_ID_NUTRIMENT), entry[2], "real donut preserves its original cumulative nutriment: [donut_type]")
		TEST_ASSERT_EQUAL(donut.reagents.get_reagent_amount(REAGENT_ID_BERRYJUICE), entry[3], "real donut preserves its original jelly quantity: [donut_type]")
		TEST_ASSERT_EQUAL(donut.reagents.get_reagent_amount(REAGENT_ID_CHOCOLATE), entry[4], "real donut preserves its original cumulative chocolate: [donut_type]")
		TEST_ASSERT_EQUAL(donut.reagents.get_reagent_amount(REAGENT_ID_SPRINKLES), entry[5], "real donut preserves its original cumulative sprinkles: [donut_type]")
		var/original_volume = entry[2] + entry[3] + entry[4] + entry[5]
		if(length(entry) == 6)
			TEST_ASSERT_EQUAL(donut.reagents.get_reagent_amount(entry[6]), 5, "the inherited jelly donut retains exactly five units of its additional filling: [donut_type]")
			original_volume += 5
		TEST_ASSERT_EQUAL(donut.reagents.total_volume, original_volume, "real donut contains exactly its original mixture: [donut_type]")
		var/datum/reagent/nutriment/nutriment = donut.reagents.get_reagent(REAGENT_ID_NUTRIMENT)
		TEST_ASSERT(istype(nutriment), "real donut contains an actual nutriment datum: [donut_type]")
		TEST_ASSERT_EQUAL(length(nutriment.data), 2, "real nutriment retains exactly its original flavor keys: [donut_type]")
		TEST_ASSERT(("sweetness" in nutriment.data) && ("donut" in nutriment.data), "real nutriment retains its original exact flavor names: [donut_type]")
		TEST_ASSERT_EQUAL(nutriment.data["sweetness"], 0, "real nutriment retains its original merged sweetness weight: [donut_type]")
		TEST_ASSERT_EQUAL(nutriment.data["donut"], 0, "real nutriment retains its original merged donut weight: [donut_type]")
		var/obj/item/reagent_containers/glass/beaker/target = allocate(/obj/item/reagent_containers/glass/beaker, T)
		TEST_ASSERT_EQUAL(donut.reagents.trans_to(target, 3), 3, "the actual food mixture transfers the requested amount: [donut_type]")
		TEST_ASSERT(abs(target.reagents.total_volume - 3) < 0.001, "the real recipient receives three units within reagent rounding precision: [donut_type]")
		TEST_ASSERT(abs(donut.reagents.total_volume - (original_volume - 3)) < 0.001, "the real source loses the transferred amount within reagent rounding precision: [donut_type]")
		TEST_ASSERT(abs(target.reagents.get_reagent_amount(REAGENT_ID_NUTRIMENT) - 3 * entry[2] / original_volume) < 0.001, "actual transfer preserves the original nutrient mixture proportion: [donut_type]")
