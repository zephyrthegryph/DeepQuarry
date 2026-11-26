/// A microwave's own parts are not ingredients: they are never cooked, ejected or spilled when the microwave is destroyed.
/datum/unit_test/dq_microwave_keeps_parts/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/microwave/microwave = allocate(/obj/machinery/microwave, T)
	var/obj/item/reagent_containers/food/snacks/grown/produce = allocate(/obj/item/reagent_containers/food/snacks/grown, T, PLANT_APPLE)
	var/parts = 0
	for(var/obj/item/stock_parts/P in microwave.contents)
		parts++
	TEST_ASSERT(parts > 0, "the microwave is made with its board's parts inside it")
	produce.forceMove(microwave)
	var/list/cooking = microwave.cookingContents()
	TEST_ASSERT_EQUAL(length(cooking), 1, "only the apple put in is an ingredient, not the machine's parts")
	TEST_ASSERT(produce in cooking, "the apple put in is an ingredient")
	qdel(microwave)
	TEST_ASSERT_EQUAL(produce.loc, T, "destroying the microwave puts the ingredient out on the floor")
	for(var/obj/item/stock_parts/P in T)
		TEST_FAIL("destroying the microwave spilled its part [P.type] onto the floor")
	for(var/obj/item/circuitboard/B in T)
		TEST_FAIL("destroying the microwave spilled its board [B.type] onto the floor")
