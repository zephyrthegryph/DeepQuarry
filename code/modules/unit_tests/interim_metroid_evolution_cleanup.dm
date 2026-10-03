/datum/unit_test/interim_metroid_evolution_cleanup
	var/source_type = /mob/living/simple_mob/metroid/juvenile/baby
	var/product_type = /mob/living/simple_mob/metroid/juvenile/super
	var/with_mind = TRUE

/datum/unit_test/interim_metroid_evolution_cleanup/mindless
	source_type = /mob/living/simple_mob/metroid/juvenile/super
	product_type = /mob/living/simple_mob/metroid/juvenile/alpha
	with_mind = FALSE

/datum/unit_test/interim_metroid_evolution_cleanup/Run()
	var/turf/T = test_floor()
	var/mob/living/simple_mob/metroid/juvenile/source = allocate(source_type, T)
	TEST_ASSERT(!QDELETED(source) && source.stat == CONSCIOUS && source.loc == T, "The actual canonical juvenile constructor creates a living original source")
	TEST_ASSERT_EQUAL(text2path(source.next), product_type, "The actual existing juvenile subtype retains its exact canonical successor")
	var/datum/mind/original_mind
	if(with_mind)
		source.mind_initialize()
		original_mind = source.mind
		own(original_mind)
		SSticker?.minds -= original_mind
		TEST_ASSERT_NOTNULL(original_mind, "The real supported mind initialization creates an actual original mind")
		TEST_ASSERT_EQUAL(original_mind.current, source, "The real original mind genuinely controls its original juvenile body")
	else
		TEST_ASSERT_NULL(source.mind, "The actual mindless canonical source starts without an original mind")
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/list/before = turf_contents_of_type(T, product_type)
	TEST_ASSERT_NULL(source.expand_troid(), "The actual public evolution-completion callback retains its original null result")
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(source), "Actual completed evolution consumes the exact original juvenile body")
	var/list/products = turf_contents_of_type(T, product_type) - before
	TEST_ASSERT_EQUAL(length(products), 1, "Actual completed evolution creates exactly one real canonical successor")
	var/mob/living/simple_mob/metroid/juvenile/product = products[1]
	TEST_ASSERT_EQUAL(product.type, product_type, "The actual original successor has the exact canonical configured type")
	TEST_ASSERT(!QDELETED(product) && product.stat == CONSCIOUS && product.loc == T, "The actual original successor survives alive on the original evolution floor")
	if(with_mind)
		TEST_ASSERT(!QDELETED(original_mind), "Actual original-body deletion preserves its real transferred mind")
		TEST_ASSERT_EQUAL(product.mind, original_mind, "Actual evolution transfers the exact original mind into its real successor")
		TEST_ASSERT_EQUAL(original_mind.current, product, "Actual evolution makes the original mind control the exact real successor")
	else
		TEST_ASSERT_NULL(product.mind, "Actual mindless evolution does not fabricate a controlling mind")
	TEST_ASSERT(!QDELETED(pen) && pen.loc == T, "Actual evolution preserves the original unrelated floor item")
