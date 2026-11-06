/// Real egg hatching preserves product count bounds, concrete types and original containment.
/datum/unit_test/interim_spider_egg_hatch_cleanup
	var/egg_type = /obj/effect/spider/eggcluster/small
	var/product_type = /obj/effect/spider/spiderling/varied
	var/implanted = FALSE

/datum/unit_test/interim_spider_egg_hatch_cleanup/frost
	egg_type = /obj/effect/spider/eggcluster/small/frost
	product_type = /obj/effect/spider/spiderling/frost

/datum/unit_test/interim_spider_egg_hatch_cleanup/royal
	egg_type = /obj/effect/spider/eggcluster/royal
	product_type = /obj/effect/spider/spiderling/varied

/datum/unit_test/interim_spider_egg_hatch_cleanup/implanted
	implanted = TRUE

/datum/unit_test/interim_spider_egg_hatch_cleanup/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/atom/container = T
	var/mob/living/carbon/human/host
	var/obj/item/organ/external/arm
	if(implanted)
		host = allocate(/mob/living/carbon/human, T)
		arm = host.get_organ(BP_L_ARM)
		TEST_ASSERT(arm, "actual implanted egg fixture supplies a real attached arm")
		container = arm
	var/obj/effect/spider/eggcluster/eggs = allocate(egg_type, container)
	if(implanted)
		rel_add(arm, nameof(arm.implants), eggs)
		TEST_ASSERT((eggs in arm.implants), "actual implantation records the real egg in its host arm")
	TEST_ASSERT(!QDELETED(eggs), "actual egg cluster initializes alive")
	TEST_ASSERT_EQUAL(eggs.loc, container, "actual eggs retain their original floor or attached arm")
	TEST_ASSERT_EQUAL(eggs.amount_grown, 0, "actual initialized eggs start before maturity")
	TEST_ASSERT_EQUAL(eggs.spiders_min, 2, "actual tested egg subtype retains its original minimum yield")
	TEST_ASSERT_EQUAL(eggs.spiders_max, 6, "actual tested egg subtype retains its original maximum yield")
	TEST_ASSERT_EQUAL(eggs.spider_type, product_type, "actual tested egg subtype retains its concrete hatch type")
	TEST_ASSERT(time_scheduler().timer_count(eggs) > 0, "actual initialization arms the real hatch deadline")
	TEST_ASSERT_EQUAL(length(contents_of(container, /obj/effect/spider/spiderling)), 0, "actual fixture starts without hatched spiderlings")
	var/faction_before = eggs.faction
	eggs.hatch()
	var/list/products = contents_of(container, /obj/effect/spider/spiderling)
	for(var/obj/effect/spider/spiderling/product as anything in products)
		own(product)
	TEST_ASSERT(QDELETED(eggs), "actual public hatching consumes the original mature egg cluster")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(eggs), 0, "actual hatch cleanup cancels the source deadline")
	TEST_ASSERT(length(products) >= 2 && length(products) <= 6, "actual hatching creates within the original subtype count bounds")
	for(var/obj/effect/spider/spiderling/product as anything in products)
		TEST_ASSERT(!QDELETED(product), "actual hatching preserves each newly created product")
		TEST_ASSERT_EQUAL(product.type, product_type, "actual hatching creates the exact configured spiderling subtype")
		TEST_ASSERT_EQUAL(product.loc, container, "actual hatch product retains the original source containment")
		TEST_ASSERT_EQUAL(product.faction, faction_before, "actual hatch product preserves its source faction")
		if(implanted)
			TEST_ASSERT((product in arm.implants), "actual contained hatch records every real product in host implants")
	if(implanted)
		TEST_ASSERT(!(eggs in arm.implants), "actual egg cleanup removes the source from its host implant relation")
		TEST_ASSERT_EQUAL(length(arm.implants), length(products), "actual implant relation contains exactly the real hatch products")
		TEST_ASSERT(!QDELETED(host) && !QDELETED(arm), "actual contained hatching preserves its host and attached arm")
		TEST_ASSERT_EQUAL(host.get_organ(BP_L_ARM), arm, "actual hatching preserves the original attached arm identity")
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/effect/spider/spiderling)), 0, "actual contained hatching does not spill its newborn products onto the floor")
