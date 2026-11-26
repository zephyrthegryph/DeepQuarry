// Every mob's sight carries SEE_BLACKNESS after a vision refresh, so a sprite larger than its tile is darkened where it hangs over an unseen tile.

/datum/unit_test/dq_sight_blackness_after_vision_refresh

/datum/unit_test/dq_sight_blackness_after_vision_refresh/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.sight = 0
	H.life_vision()
	TEST_ASSERT(H.sight & SEE_BLACKNESS, "a human's sight lost SEE_BLACKNESS after life_vision() ([H.sight])")
	H.sight = 0
	H.update_sight()
	TEST_ASSERT(H.sight & SEE_BLACKNESS, "update_sight() dropped SEE_BLACKNESS ([H.sight])")
	TEST_ASSERT(!(H.sight & (SEE_TURFS | SEE_OBJS)), "SEE_BLACKNESS must not reveal unseen turfs or objects ([H.sight])")
	var/mob/observer/dead/O = allocate(/mob/observer/dead, run_loc_floor_bottom_left)
	TEST_ASSERT(O.sight & SEE_BLACKNESS, "an observer's base sight lacks SEE_BLACKNESS ([O.sight])")
