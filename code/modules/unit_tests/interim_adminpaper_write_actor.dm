/// Observe actor identity while executing the real administrative paper writer.
/obj/item/paper/admin/interim_write_actor
	var/write_actor_ref
	var/write_calls = 0

/obj/item/paper/admin/interim_write_actor/admin_write(id, mob/user)
	write_actor_ref = user ? REF(user) : null
	write_calls++
	return ..()

/// Answers the writer's open native text request as `actor`, after checking it asks that same actor.
/datum/unit_test/proc/interim_adminpaper_answer(mob/actor, text, message)
	var/datum/prompt/text/admin_paper_write_review/ask = SSrequests.open_for(actor)
	TEST_ASSERT(istype(ask), "[message]: the writer opens a native text request")
	TEST_ASSERT_EQUAL(ask.answerer, actor, "[message]: the request asks the supplied actor")
	TEST_ASSERT_EQUAL(ask.write_operator, actor, "[message]: the request carries the supplied actor as writer")
	test_answer(actor, text)
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "[message]: answering completes the request")

/datum/unit_test/interim_adminpaper_append_actor/Run()
	test_driver_begin()
	exercise_write()
	test_driver_end()

/datum/unit_test/interim_adminpaper_append_actor/proc/exercise_write()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/admin/interim_write_actor/paper = allocate(/obj/item/paper/admin/interim_write_actor, T)
	TEST_ASSERT_NULL(actor.get_active_hand(), "the actual administrative writer needs no held pen")
	paper.info = "Existing."
	var/space_before = paper.free_space
	TEST_ASSERT(test_op_handler(paper, "ui_act_write_end", actor), "the actual administrative UI handles append")
	TEST_ASSERT_EQUAL(paper.write_actor_ref, REF(actor), "the administrative writer receives the supplied actor")
	interim_adminpaper_answer(actor, "Added.", "append")
	TEST_ASSERT_EQUAL(paper.write_calls, 1, "the actual UI invokes administrative writing exactly once")
	TEST_ASSERT_EQUAL(strip_html_properly(paper.info), "Existing.Added.", "the actual writer appends entered text to existing content")
	TEST_ASSERT_EQUAL(paper.free_space, space_before - length("Added."), "actual appended text consumes exactly its character count")
	TEST_ASSERT(findtext(paper.info_links, "Added."), "the rendered paper content reflects the actual appended text")
	var/info_before = paper.info
	var/remaining_space = paper.free_space
	test_op_handler(paper, "ui_act_write_end", actor)
	interim_adminpaper_answer(actor, "", "empty append")
	TEST_ASSERT_EQUAL(paper.info, info_before, "empty input preserves actual paper content")
	TEST_ASSERT_EQUAL(paper.free_space, remaining_space, "empty input consumes no paper capacity")

/datum/unit_test/interim_adminpaper_field_actor/Run()
	test_driver_begin()
	exercise_write()
	test_driver_end()

/datum/unit_test/interim_adminpaper_field_actor/proc/exercise_write()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/admin/interim_write_actor/paper = allocate(/obj/item/paper/admin/interim_write_actor, T)
	paper.info = "Before<span class=\"paper_field\"></span>After"
	paper.fields = 1
	var/space_before = paper.free_space
	TEST_ASSERT(test_op_handler(paper, "ui_act_write_field", actor, null, "1"), "the actual administrative UI handles field insertion")
	TEST_ASSERT_EQUAL(paper.write_actor_ref, REF(actor), "the actual field writer receives the supplied actor")
	interim_adminpaper_answer(actor, "Entered", "field")
	TEST_ASSERT_EQUAL(strip_html_properly(paper.info), "BeforeEnteredAfter", "the actual writer inserts entered text between surrounding content")
	TEST_ASSERT_EQUAL(paper.fields, 1, "inserting text leaves the real field count unchanged")
	TEST_ASSERT_EQUAL(paper.free_space, space_before - length("Entered"), "field insertion consumes exactly its entered character count")
	var/list/segments = paper.get_segments()
	TEST_ASSERT_EQUAL(length(segments), 3, "actual paper rendering retains surrounding text and its field")
	paper.free_space = 0
	var/info_before = paper.info
	test_op_handler(paper, "ui_act_write_field", actor, null, "1")
	TEST_ASSERT_EQUAL(paper.info, info_before, "the actual full-paper guard refuses further insertion")
	TEST_ASSERT_EQUAL(paper.free_space, 0, "the actual full-paper guard preserves exhausted capacity")
