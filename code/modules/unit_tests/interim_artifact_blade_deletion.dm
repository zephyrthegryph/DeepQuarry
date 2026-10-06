/// Real pickup records the blade's victim; deletion consequences depend on its actual charge.
/datum/unit_test/interim_artifact_blade_deletion
	var/charged = TRUE

/datum/unit_test/interim_artifact_blade_deletion/uncharged
	charged = FALSE

/datum/unit_test/interim_artifact_blade_deletion/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/melee/artifact_blade/blade = allocate(/obj/item/melee/artifact_blade, T)
	blade.pickup(actor)
	TEST_ASSERT_EQUAL(blade.last_touched(), actor, "The actual pickup hook must bind its real human victim")
	blade.stored_blood = charged ? 10 : 0
	TEST_ASSERT(!actor.has_status(STAT_PARALYZED), "The actual victim must start without paralysis")
	TEST_ASSERT(!actor.has_status(STAT_SLEEPING), "The actual victim must start awake")
	TEST_ASSERT(!actor.has_body_effect(/datum/body_effect/agonize), "The victim must start without the blade's agony effect")
	qdel(blade)
	// The actual consequence creates blood, a conjuring overlay and cosmetic lightning.
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(blade), "The actual blade must be deleted")
	TEST_ASSERT(!QDELETED(actor), "The blade's deletion must preserve its actual victim")
	TEST_ASSERT_EQUAL(actor.loc, T, "The real consequence must preserve the victim's floor")
	if(charged)
		TEST_ASSERT(actor.has_status(STAT_PARALYZED), "Charged blade deletion must actually paralyze its recorded victim")
		TEST_ASSERT(actor.has_status(STAT_SLEEPING), "Charged blade deletion must actually put its recorded victim to sleep")
		TEST_ASSERT(actor.has_status(STAT_JITTERY), "Charged blade deletion must apply its real jitter consequence")
		TEST_ASSERT(actor.has_status(STAT_BLURRY), "Charged blade deletion must apply its real blurry consequence")
		TEST_ASSERT(actor.has_body_effect(/datum/body_effect/agonize), "Charged blade deletion must apply its real agony effect before its victim relation clears")
	else
		TEST_ASSERT(!actor.has_status(STAT_PARALYZED), "An uncharged blade must not paralyze its recorded victim")
		TEST_ASSERT(!actor.has_status(STAT_SLEEPING), "An uncharged blade must not put its recorded victim to sleep")
		TEST_ASSERT(!actor.has_body_effect(/datum/body_effect/agonize), "An uncharged blade must not apply its charged agony consequence")
