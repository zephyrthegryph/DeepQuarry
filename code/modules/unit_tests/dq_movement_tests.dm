/datum/unit_test/dq_resting_allows_crawling

/datum/unit_test/dq_resting_allows_crawling/Run()
	var/mob/living/carbon/human/human = allocate(/mob/living/carbon/human)
	human.SetResting(TRUE)
	TEST_ASSERT(human.lying, "voluntary rest did not put the mob prone")
	TEST_ASSERT(human.canmove, "voluntary rest incorrectly disabled crawling")
	TEST_ASSERT(human.movement_delay() >= 8, "resting crawl did not retain its prone movement penalty")

	human.SetResting(FALSE)
	human.status_set(EFFECT_WEAKENED, 2)
	TEST_ASSERT(human.lying, "conscious knockdown did not put the mob prone")
	TEST_ASSERT(human.canmove, "conscious knockdown incorrectly disabled crawling")
	TEST_ASSERT(human.movement_delay() >= 14, "weakened crawl did not retain its movement penalty")

	human.status_set(EFFECT_WEAKENED, 0)
	human.status_set(EFFECT_STUNNED, 2)
	TEST_ASSERT(!human.canmove, "stun incorrectly allowed crawling")

	human.status_set(EFFECT_STUNNED, 0)
	human.status_set(EFFECT_PARALYZED, 2)
	human.update_canmove()
	TEST_ASSERT(!human.canmove, "paralysis incorrectly allowed crawling")
