// A late joiner gets the job's outfit and is drawn wearing it (playtest 2026-11-08: a Visitor joined with "nothing").

/// Equipping a joiner's outfit dresses the human, and the look on screen is the one its draw gives now.
/datum/unit_test/dq_join_outfit_drawn/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.mind_initialize()
	refresh_flush()
	var/naked_key = H.rx?.look_key
	SSjob.equip_rank(H, JOB_INTERN, TRUE, FALSE)
	refresh_flush()
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_UNIFORM), "the joiner wears a uniform")
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_SHOES), "and shoes")
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_ID), "and carries an ID")
	TEST_ASSERT(H.look_layers()[UNIFORM_LAYER], "the draw puts the uniform on its layer")
	TEST_ASSERT(H.rx?.look_key != naked_key, "the applied look changed when the outfit went on")
	TEST_ASSERT_EQUAL(H.rx?.look_key, refresh_look(H, FALSE), "the applied look is the one the draw gives now (nothing was left undrawn)")
