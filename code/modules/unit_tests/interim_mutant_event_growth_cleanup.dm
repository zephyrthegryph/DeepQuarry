/datum/unit_test/interim_mutant_event_growth_cleanup
	var/lizard = FALSE
	var/contained = FALSE
	var/source_type = /mob/living/simple_mob/animal/passive/mouse/event
	var/product_type = /mob/living/simple_mob/vore/aggressive/rat/event

/datum/unit_test/interim_mutant_event_growth_cleanup/contained
	contained = TRUE

/datum/unit_test/interim_mutant_event_growth_cleanup/lizard
	lizard = TRUE
	source_type = /mob/living/simple_mob/animal/passive/lizard/event
	product_type = /mob/living/simple_mob/vore/aggressive/lizardman

/datum/unit_test/interim_mutant_event_growth_cleanup/lizard/contained
	contained = TRUE

/datum/unit_test/interim_mutant_event_growth_cleanup/Run()
	var/turf/T = test_floor()
	var/mob/living/simple_mob/animal/passive/cat/host
	var/obj/belly/belly
	if(contained)
		host = allocate(/mob/living/simple_mob/animal/passive/cat, T)
		host.init_vore(TRUE)
		belly = host.vore_selected
		TEST_ASSERT(belly && !QDELETED(belly) && belly.owner == host, "The actual host initializes its real owned selected belly")
	var/mob/living/simple_mob/source = allocate(source_type, T)
	TEST_ASSERT(source && !QDELETED(source) && source.stat == CONSCIOUS, "The actual canonical small-animal constructor creates a conscious original source")
	var/atom/original_location = T
	if(contained)
		belly.nom_atom(source, host)
		TEST_ASSERT_EQUAL(source.loc, belly, "The real supported belly insertion genuinely contains its exact original small animal")
		original_location = belly
	var/list/before = contents_of(original_location, product_type)
	if(lizard)
		var/mob/living/simple_mob/animal/passive/lizard/event/L = source
		TEST_ASSERT_NULL(L.man(), "The actual lizard growth-completion callback retains its original null result")
	else
		var/mob/living/simple_mob/animal/passive/mouse/event/M = source
		TEST_ASSERT_NULL(M.rat(), "The actual mouse growth-completion callback retains its original null result")
	own_turf_contents(T)
	var/list/products = contents_of(original_location, product_type) - before
	for(var/mob/living/simple_mob/P as anything in products)
		own(P)
	TEST_ASSERT(QDELETED(source), "Actual growth completion consumes the exact original small animal")
	TEST_ASSERT_EQUAL(length(products), 1, "Actual growth completion creates exactly one real successor at the original floor or belly")
	var/mob/living/simple_mob/product = products[1]
	TEST_ASSERT_EQUAL(product.type, product_type, "The actual original successor has the exact canonical animal family")
	TEST_ASSERT(!QDELETED(product) && product.stat == CONSCIOUS && product.loc == original_location, "The actual original successor survives conscious at its original growth destination")
	if(contained)
		TEST_ASSERT(!QDELETED(host) && host.loc == T, "Actual contained growth preserves its exact original host")
		TEST_ASSERT(!QDELETED(belly) && belly.owner == host, "Actual contained growth preserves its exact original owned belly")
		TEST_ASSERT_NULL(locate_within(T, product_type), "Actual contained growth leaves no extra successor on the outer floor")
