/// Observe the actor arriving at the holder's object exposure path, then run real chemistry.
/datum/reagents/interim_ethanol_actor_probe
	var/last_actor_ref
	var/touch_count = 0

/datum/reagents/interim_ethanol_actor_probe/touch_obj(obj/target, amount, mob/user = null)
	last_actor_ref = user ? REF(user) : null
	touch_count++
	return ..()

/datum/unit_test/interim_ethanol_transfer_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/datum/reagents/interim_ethanol_actor_probe/source = allocate(/datum/reagents/interim_ethanol_actor_probe)
	source.add_reagent(REAGENT_ID_ETHANOL, 10)
	var/obj/item/paper/paper = allocate(/obj/item/paper, T)
	paper.info = "Written test ink"
	source.trans_to(paper, 5, user = user)
	TEST_ASSERT_EQUAL(source.last_actor_ref, REF(user), "trans_to forwards its explicit actor to object exposure")
	TEST_ASSERT_EQUAL(source.touch_count, 1, "trans_to invokes object exposure once")
	TEST_ASSERT(!paper.info, "real ethanol exposure removes the paper's ink")
	TEST_ASSERT_EQUAL(source.total_volume, 10, "touching a non-container through trans_to preserves the existing source-volume contract")
	paper.info = "More test ink"
	source.touch(paper, 5)
	TEST_ASSERT_NULL(source.last_actor_ref, "an ambient exposure does not inherit a previous actor")
	TEST_ASSERT_EQUAL(source.touch_count, 2, "ambient touch still invokes object exposure")
	TEST_ASSERT(!paper.info, "ambient ethanol exposure still removes ink")

/datum/unit_test/interim_ethanol_book_ink/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/reagent_containers/glass/beaker/source = allocate(/obj/item/reagent_containers/glass/beaker, T)
	var/obj/item/book/book = allocate(/obj/item/book, T)
	var/obj/item/book/tome/tome = allocate(/obj/item/book/tome, T)
	book.dat = "Ordinary book ink"
	tome.dat = "Protected tome ink"
	source.reagents.add_reagent(REAGENT_ID_ETHANOL, 2)
	source.reagents.touch_obj(book, 2, user)
	TEST_ASSERT_EQUAL(book.dat, "Ordinary book ink", "too little ethanol preserves book ink")
	source.reagents.add_reagent(REAGENT_ID_ETHANOL, 8)
	source.reagents.touch_obj(book, 5, user)
	TEST_ASSERT_NULL(book.dat, "sufficient ethanol removes ordinary book ink")
	source.reagents.touch_obj(tome, 5, user)
	TEST_ASSERT_EQUAL(tome.dat, "Protected tome ink", "ethanol cannot erase a protected tome")
	book.dat = "Ink transferred from another book"
	source.reagents.trans_to_obj(book, 5, user = user)
	TEST_ASSERT_NULL(book.dat, "trans_to_obj's temporary holder forwards exposure to real ethanol")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 5, "the temporary exposure transfer debits only its requested amount")

/datum/unit_test/interim_ethanol_spray_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/effect/effect/water/chempuff/puff = allocate(/obj/effect/effect/water/chempuff, T)
	var/obj/item/paper/paper = allocate(/obj/item/paper, T)
	paper.info = "Sprayed paper ink"
	puff.create_reagents(10)
	puff.reagents.add_reagent(REAGENT_ID_ETHANOL, 10)
	puff.set_up(T, user = user)
	TEST_ASSERT_EQUAL(puff.spray_actor, user, "the traveling spray retains the explicit actor as a relation")
	TEST_ASSERT(!paper.info, "the spray's real exposure erases ink along its path")
	qdel(user)
	TEST_ASSERT_NULL(puff.spray_actor, "deleting the actor clears the spray relation")
