/// A surviving card must still support the actual unfold and fold operations.
/datum/unit_test/interim_pai_card_folding/Run()
	var/turf/T = test_floor()
	var/obj/item/paicard/card = allocate(/obj/item/paicard, T)
	var/mob/living/silicon/pai/personality = allocate(/mob/living/silicon/pai, card)
	card.setPersonality(personality)
	personality.fold_out()
	own_turf_contents(T)
	TEST_ASSERT_EQUAL(personality.loc, T, "The real unfolding verb must place the personality on the floor")
	TEST_ASSERT_EQUAL(card.loc, personality, "The unfolded personality must carry its actual card")
	personality.close_up(TRUE)
	own_turf_contents(T)
	TEST_ASSERT_EQUAL(personality.loc, card, "Normal close_up must still fold into the surviving card")
	TEST_ASSERT_EQUAL(card.loc, T, "Normal close_up must return the card to the actual floor")
	TEST_ASSERT_EQUAL(personality.card, card, "Normal folding must preserve the actual card relation")
	TEST_ASSERT_EQUAL(card.pai, personality, "Normal folding must preserve the actual personality relation")
	TEST_ASSERT_EQUAL(personality.stat, CONSCIOUS, "Normal folding must not kill the personality")
	// Finish fixture teardown while its generated effects can still be registered.
	qdel(card)
	own_turf_contents(T)

/// Record the real death event before the card's transaction removes its personality.
/datum/unit_test/interim_pai_card_deletion
	var/death_events = 0
	var/death_stat
	var/death_subject_ref

/datum/unit_test/interim_pai_card_deletion/proc/personality_died(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/silicon/pai/personality = N.target
	death_events++
	death_stat = personality.stat
	death_subject_ref = REF(personality)

/// Card deletion must run the actual pAI death consequence before terminal personality removal.
/datum/unit_test/interim_pai_card_deletion/Run()
	var/turf/T = test_floor()
	var/obj/item/paicard/card = allocate(/obj/item/paicard, T)
	var/mob/living/silicon/pai/personality = allocate(/mob/living/silicon/pai, card)
	card.setPersonality(personality)
	personality.fold_out()
	own_turf_contents(T)
	TEST_ASSERT_EQUAL(personality.loc, T, "The actual unfolding verb must create the floor fixture")
	TEST_ASSERT_EQUAL(card.loc, personality, "The actual unfolded card must be carried by its personality")
	TEST_ASSERT_EQUAL(personality.stat, CONSCIOUS, "The personality must actually be alive before card deletion")
	var/personality_ref = REF(personality)
	var/personality_handle = om_handle(personality)
	observe(personality, /datum/notice/mob_death, src, then(PROC_REF(personality_died)))
	qdel(card)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(card), "The actual card must be deleted")
	TEST_ASSERT_EQUAL(death_events, 1, "Card deletion must deliver the real personality death event exactly once")
	TEST_ASSERT_EQUAL(death_subject_ref, personality_ref, "The actual registered personality must die")
	TEST_ASSERT_EQUAL(death_stat, DEAD, "The real death event must observe the actual DEAD state")
	TEST_ASSERT(QDELETED(personality), "The existing card destruction transaction must complete terminal personality removal")
	TEST_ASSERT_NULL(om_resolve(personality_handle), "The terminal personality's actual handle must end")
