/// Real one-use injectors reject source release before changing their user.
/datum/unit_test/interim_fluff_injector_consumption
	var/sticky = FALSE
	var/numbing = FALSE

/datum/unit_test/interim_fluff_injector_consumption/sticky
	sticky = TRUE

/datum/unit_test/interim_fluff_injector_consumption/numbing
	numbing = TRUE

/datum/unit_test/interim_fluff_injector_consumption/numbing/sticky
	sticky = TRUE

/datum/unit_test/interim_fluff_injector_consumption/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	var/injector_type = numbing ? /obj/item/fluff/injector/numb_bite : /obj/item/fluff/injector/monkey
	var/obj/item/fluff/injector/injector = allocate(injector_type, T)
	var/datum/species/original_species = user.species
	var/primitive_form = original_species.primitive_form
	var/datum/species/primitive_species = GLOB.all_species[primitive_form]
	TEST_ASSERT(user.put_in_active_hand(injector), "actual one-use injector starts held")
	TEST_ASSERT(!user.transforming, "actual human starts without an active transformation")
	TEST_ASSERT(!(/datum/unarmed_attack/bite/sharp/numbing in user.species.unarmed_types), "actual human starts without the injected numbing attack")
	TEST_ASSERT_EQUAL(injector.attack(other, user), ITEM_INTERACT_FAILURE, "actual injector refuses another target")
	TEST_ASSERT(!QDELETED(injector), "other-target refusal preserves the source injector")
	TEST_ASSERT_EQUAL(user.get_active_hand(), injector, "other-target refusal preserves the held source slot")
	TEST_ASSERT_EQUAL(user.species, original_species, "other-target refusal preserves the user's exact species")
	if(sticky)
		add_trait(injector, TRAIT_NODROP, "interim_fluff_injector_consumption")
		TEST_ASSERT(injector.loc.release_refusal(injector, user), "actual sticky injector refuses release")
		TEST_ASSERT_EQUAL(injector.attack(user, user), ITEM_INTERACT_FAILURE, "actual sticky self-injection refuses its irreversible effect")
		TEST_ASSERT(!QDELETED(injector), "refused self-injection preserves the source")
		TEST_ASSERT_EQUAL(user.get_active_hand(), injector, "refused self-injection preserves its held slot")
		TEST_ASSERT_EQUAL(user.species, original_species, "refused self-injection preserves the exact original species")
		TEST_ASSERT(!user.transforming, "refused self-injection starts no transformation")
		TEST_ASSERT(!(/datum/unarmed_attack/bite/sharp/numbing in user.species.unarmed_types), "refused self-injection adds no numbing attack")
		remove_trait(injector, TRAIT_NODROP, "interim_fluff_injector_consumption")
	TEST_ASSERT_EQUAL(injector.attack(user, user), ITEM_INTERACT_SUCCESS, "actual released self-injection succeeds")
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(injector), "successful actual self-injection consumes the exact one-use source")
	TEST_ASSERT_NULL(user.get_active_hand(), "successful actual self-injection vacates its held source slot")
	if(numbing)
		TEST_ASSERT(user.species != original_species, "actual numbing injection creates a private species copy")
		TEST_ASSERT((/datum/unarmed_attack/bite/sharp/numbing in user.species.unarmed_types), "actual injected species declares its numbing bite")
		var/found_attack = FALSE
		for(var/datum/unarmed_attack/attack as anything in user.species.unarmed_attacks)
			if(istype(attack, /datum/unarmed_attack/bite/sharp/numbing))
				found_attack = TRUE
		TEST_ASSERT(found_attack, "actual numbing injection constructs its usable numbing attack datum")
		TEST_ASSERT(!(/datum/unarmed_attack/bite/sharp/numbing in other.species.unarmed_types), "actual private-species injection preserves the other human's attacks")
	else
		TEST_ASSERT(primitive_species, "the actual primitive-form name resolves to a registered species")
		TEST_ASSERT(user.transforming, "actual injection begins the real transformation")
		test_time(4 SECONDS)
		TEST_ASSERT_EQUAL(user.species, original_species, "real transformation preserves the species before its 4.8 second deadline")
		test_time(0.8 SECONDS)
		own_turf_contents(T)
		TEST_ASSERT(!user.transforming, "actual transformation completes at its declared deadline")
		TEST_ASSERT_EQUAL(user.species.type, primitive_species.type, "actual transformation installs the original species's primitive form")
		TEST_ASSERT(!QDELETED(user), "actual transformation preserves its original human actor")
