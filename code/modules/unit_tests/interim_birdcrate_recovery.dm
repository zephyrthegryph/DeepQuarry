/// The real bird-crate crowbar path releases each canonical live bird, original cargo and one wood sheet before consuming its source.
/datum/unit_test/interim_birdcrate_recovery/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/book/book = allocate(/obj/item/book, T)
	var/obj/structure/largecrate/birds/crate = allocate(/obj/structure/largecrate/birds, T)
	TEST_ASSERT_EQUAL(book.loc, crate, "The real bird crate gathers the original floor cargo during construction")
	var/obj/item/tool/crowbar/tool = allocate(/obj/item/tool/crowbar, T)
	TEST_ASSERT(actor.put_in_active_hand(tool), "The real actor holds the original crowbar after crate construction")
	var/list/before = turf_contents_of_type(T, /mob/living/simple_mob/animal/passive/bird)
	var/list/wood_before = turf_contents_of_type(T, /obj/item/stack/material/wood)
	TEST_ASSERT(crate.crowbar_act(actor, tool), "The actual public bird-crate opening succeeds")
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(crate), "The real opening consumes its exact original crate")
	TEST_ASSERT(!QDELETED(book) && book.loc == T, "The actual opening releases the exact original gathered book onto its floor")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), tool, "The actual opening preserves the actor's original held crowbar")
	var/list/birds = turf_contents_of_type(T, /mob/living/simple_mob/animal/passive/bird) - before
	TEST_ASSERT_EQUAL(length(birds), 21, "The actual opening releases exactly its original complete bird collection")
	var/list/expected = list( \
		/mob/living/simple_mob/animal/passive/bird, \
		/mob/living/simple_mob/animal/passive/bird/parrot/kea, \
		/mob/living/simple_mob/animal/passive/bird/parrot/eclectus, \
		/mob/living/simple_mob/animal/passive/bird/parrot/grey_parrot, \
		/mob/living/simple_mob/animal/passive/bird/parrot/black_headed_caique, \
		/mob/living/simple_mob/animal/passive/bird/parrot/white_caique, \
		/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar, \
		/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/blue, \
		/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/bluegreen, \
		/mob/living/simple_mob/animal/passive/bird/black_bird, \
		/mob/living/simple_mob/animal/passive/bird/azure_tit, \
		/mob/living/simple_mob/animal/passive/bird/european_robin, \
		/mob/living/simple_mob/animal/passive/bird/goldcrest, \
		/mob/living/simple_mob/animal/passive/bird/ringneck_dove, \
		/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel, \
		/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/white, \
		/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/yellowish, \
		/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/grey, \
		/mob/living/simple_mob/animal/passive/bird/parrot/sulphur_cockatoo, \
		/mob/living/simple_mob/animal/passive/bird/parrot/white_cockatoo, \
		/mob/living/simple_mob/animal/passive/bird/parrot/pink_cockatoo \
	)
	for(var/path in expected)
		var/count = 0
		for(var/mob/living/simple_mob/animal/passive/bird/bird in birds)
			if(bird.type == path)
				count++
			TEST_ASSERT(!QDELETED(bird) && bird.loc == T, "Each actual released original bird survives on the crate's floor")
		TEST_ASSERT_EQUAL(count, 1, "The actual opening releases exactly one canonical [path] bird")
	var/list/wood = turf_contents_of_type(T, /obj/item/stack/material/wood) - wood_before
	TEST_ASSERT_EQUAL(length(wood), 1, "The actual opening returns exactly one real wood stack")
	var/obj/item/stack/material/wood/sheet = wood[1]
	TEST_ASSERT_EQUAL(sheet.get_amount(), 1, "The actual opening preserves the original one-sheet wood recovery")
	TEST_ASSERT_EQUAL(sheet.loc, T, "The actual recovered original wood stays on the crate's floor")
