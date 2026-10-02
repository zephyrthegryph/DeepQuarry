/datum/unit_test/interim_fake_death_reagent_removal
	var/touch_route = FALSE

/datum/unit_test/interim_fake_death_reagent_removal/Run()
	var/mob/living/carbon/human/recipient = allocate(/mob/living/carbon/human)
	var/datum/reagents/holder = touch_route ? recipient.touching : recipient.bloodstr
	var/reagent_id = touch_route ? REAGENT_ID_LICHPOWDER : REAGENT_ID_ZOMBIEPOWDER
	TEST_ASSERT(!(recipient.status_flags & FAKEDEATH), "The recipient must begin outside fake death")
	holder.add_reagent(reagent_id, 5)
	var/datum/reagent/chemical = holder.get_reagent(reagent_id)
	TEST_ASSERT_NOTNULL(chemical, "Actual reagent insertion must create the tested chemical")
	TEST_ASSERT_EQUAL(chemical.holder, holder, "The chemical must belong to the real recipient holder")
	if(touch_route)
		chemical.affect_touch(recipient, recipient.reagent_tag(), 1)
	else
		chemical.affect_blood(recipient, recipient.reagent_tag(), 1)
	TEST_ASSERT(recipient.status_flags & FAKEDEATH, "The actual chemical effect must induce fake death")
	holder.del_reagent(reagent_id)
	TEST_ASSERT(QDELETED(chemical), "The holder removal must actually destroy the chemical")
	TEST_ASSERT_NULL(holder.get_reagent(reagent_id), "The chemical must leave the real holder index")
	TEST_ASSERT(!QDELETED(recipient), "Removing the chemical must preserve its recipient")
	TEST_ASSERT(!(recipient.status_flags & FAKEDEATH), "Destroying the chemical must release fake death before its holder reference clears")

/datum/unit_test/interim_fake_death_reagent_removal/lichpowder
	touch_route = TRUE
