/// Execute actual legacy filter prompting; observe its report boundary without reading real saved notes.
/datum/admins/interim_player_notes_filter_actor
	var/page_calls = 0
	var/page_actor_ref
	var/page_number
	var/page_filter

/datum/admins/interim_player_notes_filter_actor/PlayerNotesPageLegacy(page, filter, mob/user)
	page_calls++
	page_actor_ref = user ? REF(user) : null
	page_number = page
	page_filter = filter

/// This exercises direct handler prompting, not native privileged topic dispatch or report delivery.
/datum/unit_test/om/interim_player_notes_filter_actor/run_om(list/made)
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	TEST_ASSERT_NULL(actor.client, "the actual prompt fixture has no native privileged client")
	var/fixture_key = "interim_player_notes_filter_actor"
	TEST_ASSERT_NULL(GLOB.directory[fixture_key], "the fixture key has no native client association")
	TEST_ASSERT_NULL(GLOB.admin_datums[fixture_key], "the fixture key starts outside the actual admin registry")
	set_global("admin_datums", GLOB.admin_datums.Copy())
	set_global("deadmins", GLOB.deadmins.Copy())
	var/datum/admins/interim_player_notes_filter_actor/holder = allocate(/datum/admins/interim_player_notes_filter_actor, list(), fixture_key)
	// The real constructor registers its holder; remove this isolated clientless fixture immediately.
	GLOB.admin_datums -= fixture_key
	made += holder.admincaster_feed_message
	made += holder.admincaster_scratch_channel
	TEST_ASSERT_NULL(holder.owner(), "the actual holder has no native administrative owner")
	holder.topic_notes_legacy_filter(actor, list())
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the actual legacy topic handler opens exactly one typed filter prompt")
	var/datum/prompt/text/ask = GLOB.test_prompts[1]
	made += ask
	TEST_ASSERT_EQUAL(ask.answerer, actor, "the actual filter belongs to the explicit topic actor")
	TEST_ASSERT_EQUAL(holder.page_calls, 0, "the report boundary waits for an actual answer")
	TEST_ASSERT_NULL(test_prompt_answer(ask, "^alice$"), "the actual typed filter answer is accepted")
	TEST_ASSERT_EQUAL(holder.page_calls, 1, "the actual answer rerun reaches the report boundary exactly once")
	TEST_ASSERT_EQUAL(holder.page_actor_ref, REF(actor), "the actual answer rerun preserves the explicit actor")
	TEST_ASSERT_EQUAL(holder.page_number, 1, "the actual filter answer resets the legacy report to page one")
	TEST_ASSERT_EQUAL(holder.page_filter, "^alice$", "the actual filter answer preserves the exact regex text")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the actual answer cache prevents a repeated prompt")
	holder.topic_notes_legacy_filter(bystander, list())
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 2, "a separate explicit actor gets a separate actual typed filter prompt")
	var/datum/prompt/text/cancelled = GLOB.test_prompts[2]
	made += cancelled
	TEST_ASSERT_EQUAL(cancelled.answerer, bystander, "the second actual prompt belongs to its own explicit actor")
	TEST_ASSERT_EQUAL(test_prompt_answer(cancelled, null, TRUE), "no answer", "actual cancellation is delivered through the typed prompt API")
	TEST_ASSERT_EQUAL(holder.page_calls, 1, "actual cancellation never reaches the report boundary")
	TEST_ASSERT_EQUAL(holder.page_filter, "^alice$", "actual cancellation preserves the previously accepted filter")
	holder.topic_notes_legacy_list(bystander, list("index" = 3, "filter" = "%5Ebob%24"))
	TEST_ASSERT_EQUAL(holder.page_calls, 2, "the actual page topic reaches the boundary once")
	TEST_ASSERT_EQUAL(holder.page_actor_ref, REF(bystander), "the actual page topic forwards its own explicit actor")
	TEST_ASSERT_EQUAL(holder.page_number, 3, "the actual page topic preserves the requested page")
	TEST_ASSERT_EQUAL(holder.page_filter, "^bob$", "the actual page topic retains URL decoding")
