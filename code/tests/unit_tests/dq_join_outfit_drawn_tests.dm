// A late joiner gets the job's outfit and is drawn wearing it (playtest 2026-11-08: a Visitor joined with "nothing").

/// Equipping a joiner's outfit dresses the human, and the look on screen is the one its draw gives now.
/datum/unit_test/dq_join_outfit_drawn/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.mind_initialize()
	refresh_flush()
	var/naked_key = H.rx?.look_key
	SSjob.equip_rank(H, JOB_ALT_VISITOR, TRUE, FALSE)
	refresh_flush()
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_UNIFORM), "the joiner wears a uniform")
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_SHOES), "and shoes")
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_ID), "and carries an ID")
	TEST_ASSERT(H.look_layers()[UNIFORM_LAYER], "the draw puts the uniform on its layer")
	TEST_ASSERT(H.rx?.look_key != naked_key, "the applied look changed when the outfit went on")
	TEST_ASSERT_EQUAL(H.rx?.look_key, refresh_look(H, FALSE), "the applied look is the one the draw gives now (nothing was left undrawn)")

/// The same join with nobody looking where the joiner is made: the draw queue draws the joiner and everything it wears all the same.
/datum/unit_test/dq_join_outfit_drawn_unseen/Run()
	draw_isolate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.mind_initialize()
	SSjob.equip_rank(H, JOB_ALT_VISITOR, TRUE, FALSE)
	refresh_flush()
	var/obj/item/uniform = H.get_equipped_item(SLOT_ID_UNIFORM)
	TEST_ASSERT(uniform, "the joiner wears a uniform")
	TEST_ASSERT(!H.refresh_queued, "the joiner owes no draw after the drain")
	for(var/obj/item/worn in H.get_equipped_items())
		TEST_ASSERT(!worn.refresh_queued, "[worn] owes no draw after the drain")
	TEST_ASSERT(H.look_layers()[UNIFORM_LAYER], "the draw puts the uniform on its layer")
	TEST_ASSERT_EQUAL(H.rx?.look_key, refresh_look(H, FALSE), "the joiner on screen is the one its draw gives now")

/// Every job a player can take has an outfit: a job whose outfit_type is lost (a codemod once moved the Assistant's into a proc body, so every Visitor
/// and Assistant spawned naked) equips nothing and says nothing.
/datum/unit_test/dq_join_every_job_has_an_outfit/Run()
	for(var/rank in job_occupations_by_name())
		var/datum/job/J = SSjob.get_job(rank)
		if(!J || (J.mob_type & JOB_SILICON))
			continue
		TEST_ASSERT(J.get_outfit(null, null), "[rank] ([J.type]) has an outfit")
