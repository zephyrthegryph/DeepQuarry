// Stored references (doc/rewrite/proposals/reference_storage.md): fixes found while converting the lists.

/// The medical console lists the records of GLOB.virusDB (virus id -> record); it once walked the keys as records and listed nothing.
/datum/unit_test/dq_refs_medical_lists_virus_records

/datum/unit_test/dq_refs_medical_lists_virus_records/Run()
	var/list/saved = GLOB.virusDB
	GLOB.virusDB = list()
	var/datum/data/record/rec = new
	rec.fields["name"] = "Test Plague"
	GLOB.virusDB["77"] = rec
	var/list/entries = medical_virus_entries()
	TEST_ASSERT_EQUAL(length(entries), 1, "the console lists the one discovered virus")
	TEST_ASSERT_EQUAL(entries[1]["name"], "Test Plague", "the entry carries the record's name")
	GLOB.virusDB = saved

/// The admin fax cache keeps the newest ADMIN_FAX_KEEP copies and deletes the older ones.
/datum/unit_test/dq_refs_admin_fax_cache_is_bounded

/datum/unit_test/dq_refs_admin_fax_cache_is_bounded/Run()
	test_driver_begin()
	var/list/saved = GLOB.adminfaxes
	GLOB.adminfaxes = list()
	var/obj/item/pen/first = new(null)
	admin_fax_keep(first)
	for(var/i in 1 to ADMIN_FAX_KEEP)
		admin_fax_keep(new /obj/item/pen(null))
	TEST_ASSERT_EQUAL(length(GLOB.adminfaxes), ADMIN_FAX_KEEP, "the cache holds no more than its limit")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(first), "the oldest copy was deleted when it fell out of the cache")
	QDEL_LIST(GLOB.adminfaxes)
	GLOB.adminfaxes = saved

/// A deleted fake sun leaves the family registry (it was a static list nothing removed from).
/datum/unit_test/dq_refs_fake_sun_leaves_registry

/datum/unit_test/dq_refs_fake_sun_leaves_registry/Run()
	var/obj/effect/fake_sun/sun = allocate(/obj/effect/fake_sun, run_loc_floor_bottom_left)
	TEST_ASSERT(sun in REGISTRY_MEMBERS(REGISTRY_FAKE_SUNS), "a fake sun joins the registry")
	qdel(sun)
	TEST_ASSERT(!(sun in REGISTRY_MEMBERS(REGISTRY_FAKE_SUNS)), "a deleted fake sun leaves the registry")

/// A player's preferences refuse an unforced delete (they persist for the round) and a forced one removes them.
/datum/unit_test/dq_refs_preferences_refuse_unforced_delete

/datum/unit_test/dq_refs_preferences_refuse_unforced_delete/Run()
	var/datum/preferences/dq_preview_test_stub/prefs = new()
	qdel(prefs)
	TEST_ASSERT(!QDELETED(prefs), "an unforced delete leaves the preferences whole")
	qdel(prefs, TRUE)
	TEST_ASSERT(QDELETED(prefs), "a forced delete removes them")

/// An op's earlier answers stay readable at its later steps: the op owns the answered prompts (the request layer no longer deletes one an op
/// adopted), so a handler after a wait reads the first question's fields, not a deleted prompt (and the op deletes them when it ends).
/obj/refs_two_step
	name = "two step fixture"
	anchored = TRUE
	var/seen_value
	var/list/seen_choices
	var/seen_second

CAPABILITIES(/obj/refs_two_step)
	op("two", ui_act("two"), asks(/datum/prompt/choice, fields = list("question" = "Which?", "choices" = list("a", "b"), "timeout" = 0), step = "first"), asks(/datum/prompt/text, fields = list("question" = "Why?", "timeout" = 0), step = "second"), then(PROC_REF(finish)))

/obj/refs_two_step/proc/finish(datum/act/op/A)
	var/datum/prompt/choice/first = A.step_answers?["first"]
	seen_value = first?.value
	seen_choices = first?.choices
	seen_second = A.step_value("second")
	return OP_OK

/datum/unit_test/dq_refs_two_step_op_reads_first_prompt_after_wait

/datum/unit_test/dq_refs_two_step_op_reads_first_prompt_after_wait/Run()
	test_driver_begin()
	test_prompts_reset()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/refs_two_step/C = allocate(/obj/refs_two_step)
	var/datum/op_result/waiting = test_ui(M, C, "two", list())
	TEST_ASSERT_NULL(waiting?.outcome, "the op waits on its first question")
	var/datum/prompt/choice/first_prompt = GLOB.test_prompts[1]
	var/datum/op_result/second = test_answer(M, "a")
	TEST_ASSERT_NULL(second?.outcome, "the op waits on its second question")
	TEST_ASSERT(!QDELETED(first_prompt), "the answered first prompt is kept for the op's later handlers")
	var/datum/op_result/done = test_answer(M, "because")
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "the op commits after the second answer")
	TEST_ASSERT_EQUAL(C.seen_value, "a", "the handler read the first answer after a later wait")
	TEST_ASSERT_EQUAL(length(C.seen_choices), 2, "and a field of the first prompt (its choices)")
	TEST_ASSERT_EQUAL(C.seen_second, "because", "and the second answer")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(first_prompt), "the first prompt is deleted with the op, not kept for the round")
	GLOB.test_prompts = null
	test_driver_end()
