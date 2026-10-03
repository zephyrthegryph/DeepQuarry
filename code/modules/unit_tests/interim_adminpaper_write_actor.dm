/// Observe actor identity while executing the real administrative paper writer.
/obj/item/paper/admin/interim_write_actor
	var/write_actor_ref
	var/prompt_actor_ref
	var/write_calls = 0

/obj/item/paper/admin/interim_write_actor/admin_write(id, mob/user)
	write_actor_ref = user ? REF(user) : null
	write_calls++
	return ..()

/obj/item/paper/admin/interim_write_actor/om_rerun_ask(mob/user, key, proc_name, list/proc_args, prompt, list/fields)
	prompt_actor_ref = user ? REF(user) : null
	return ..()

/datum/unit_test/interim_adminpaper_append_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/admin/interim_write_actor/paper = allocate(/obj/item/paper/admin/interim_write_actor, T)
	TEST_ASSERT_NULL(actor.get_active_hand(), "the actual administrative writer needs no held pen")
	paper.info = "Existing."
	var/space_before = paper.free_space
	var/cache_key = "[REF(paper)]:[nameof(/obj/item/paper/admin/proc/admin_write)]"
	set_global("om_rerun_answers", GLOB.om_rerun_answers.Copy())
	GLOB.om_rerun_answers[cache_key] = list("text" = "Added.")
	TEST_ASSERT(paper.ui_act_write_end(actor, list(), null, null, "write_end"), "the actual administrative UI handles append")
	TEST_ASSERT_EQUAL(paper.write_actor_ref, REF(actor), "the administrative writer receives the supplied actor")
	TEST_ASSERT_EQUAL(paper.prompt_actor_ref, REF(actor), "the actual rerun helper receives that same actor")
	TEST_ASSERT_EQUAL(paper.write_calls, 1, "the actual UI invokes administrative writing exactly once")
	TEST_ASSERT_EQUAL(strip_html_properly(paper.info), "Existing.Added.", "the actual writer appends entered text to existing content")
	TEST_ASSERT_EQUAL(paper.free_space, space_before - length("Added."), "actual appended text consumes exactly its character count")
	TEST_ASSERT(findtext(paper.info_links, "Added."), "the rendered paper content reflects the actual appended text")
	var/info_before = paper.info
	var/remaining_space = paper.free_space
	GLOB.om_rerun_answers[cache_key] = list("text" = "")
	paper.ui_act_write_end(actor, list(), null, null, "write_end")
	TEST_ASSERT_EQUAL(paper.info, info_before, "empty input preserves actual paper content")
	TEST_ASSERT_EQUAL(paper.free_space, remaining_space, "empty input consumes no paper capacity")

/datum/unit_test/interim_adminpaper_field_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/admin/interim_write_actor/paper = allocate(/obj/item/paper/admin/interim_write_actor, T)
	paper.info = "Before<span class=\"paper_field\"></span>After"
	paper.fields = 1
	var/space_before = paper.free_space
	var/cache_key = "[REF(paper)]:[nameof(/obj/item/paper/admin/proc/admin_write)]"
	set_global("om_rerun_answers", GLOB.om_rerun_answers.Copy())
	GLOB.om_rerun_answers[cache_key] = list("text" = "Entered")
	TEST_ASSERT(paper.ui_act_write_field(actor, list("id" = "1"), null, null, "write_field"), "the actual administrative UI handles field insertion")
	TEST_ASSERT_EQUAL(paper.write_actor_ref, REF(actor), "the actual field writer receives the supplied actor")
	TEST_ASSERT_EQUAL(paper.prompt_actor_ref, REF(actor), "the actual field prompt receives the supplied actor")
	TEST_ASSERT_EQUAL(strip_html_properly(paper.info), "BeforeEnteredAfter", "the actual writer inserts entered text between surrounding content")
	TEST_ASSERT_EQUAL(paper.fields, 1, "inserting text leaves the real field count unchanged")
	TEST_ASSERT_EQUAL(paper.free_space, space_before - length("Entered"), "field insertion consumes exactly its entered character count")
	var/list/segments = paper.get_segments()
	TEST_ASSERT_EQUAL(length(segments), 3, "actual paper rendering retains surrounding text and its field")
	paper.free_space = 0
	var/info_before = paper.info
	paper.ui_act_write_field(actor, list("id" = "1"), null, null, "write_field")
	TEST_ASSERT_EQUAL(paper.info, info_before, "the actual full-paper guard refuses further insertion")
	TEST_ASSERT_EQUAL(paper.free_space, 0, "the actual full-paper guard preserves exhausted capacity")
