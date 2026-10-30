// "Never respawn": a respawn record carries an explicit forbidden flag. time_till_respawn() reports RESPAWN_NEVER for it, a normal
// wait set afterwards cannot lift it, and clearing the record (what the admin verb does) lets the player respawn.

/datum/unit_test/respawn_never_flag

/datum/unit_test/respawn_never_flag/Run()
	var/key_name = "dqrespawnnevertest"
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	bind_player(H, key_name, as_ckey = TRUE)
	TEST_ASSERT_EQUAL(H.time_till_respawn(), 0, "no record: free to respawn")

	SSmobs.set_respawn_wait(key_name, 5 MINUTES)
	TEST_ASSERT(!SSmobs.respawn_forbidden(key_name), "a timed wait is not a ban")
	TEST_ASSERT(H.time_till_respawn() > 0, "a timed wait reports the time left")

	SSmobs.set_respawn_wait(key_name, 0, forbidden = TRUE)
	TEST_ASSERT(SSmobs.respawn_forbidden(key_name), "the record is marked forbidden")
	TEST_ASSERT_EQUAL(H.time_till_respawn(), RESPAWN_NEVER, "forbidden reports RESPAWN_NEVER even with a zero duration")

	SSmobs.set_respawn_wait(key_name, 1 SECOND)
	TEST_ASSERT_EQUAL(H.time_till_respawn(), RESPAWN_NEVER, "a later normal wait does not lift the ban")
	TEST_ASSERT(key_name in SSmobs.respawn_waiters(), "the admin picker still lists them")

	SSmobs.clear_respawn_wait(key_name)
	TEST_ASSERT(!SSmobs.respawn_forbidden(key_name), "clearing the record drops the flag")
	TEST_ASSERT_EQUAL(H.time_till_respawn(), 0, "the player may respawn after the admin allows it")
	bind_player(H, null, as_ckey = TRUE)

/// set_respawn_timer(RESPAWN_NEVER) is the admin/antag-HUD path: it forbids rather than storing a duration.
/datum/unit_test/respawn_never_from_set_timer

/datum/unit_test/respawn_never_from_set_timer/Run()
	var/key_name = "dqrespawnnevertesttwo"
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	bind_player(H, key_name, as_ckey = TRUE)
	H.set_respawn_timer(RESPAWN_NEVER)
	TEST_ASSERT(SSmobs.respawn_forbidden(key_name), "RESPAWN_NEVER forbids the record")
	TEST_ASSERT_EQUAL(H.time_till_respawn(), RESPAWN_NEVER, "and the mob reads it as never")
	SSmobs.clear_respawn_wait(key_name)
	bind_player(H, null, as_ckey = TRUE)
