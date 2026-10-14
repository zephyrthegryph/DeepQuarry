/// This exercises existing native stat controls, not client/admin authorization.
/obj/item/pen/interim_sdql_statclick_target

/datum/unit_test/interim_sdql_statclick_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/interim_sdql_statclick_target/target = allocate(/obj/item/pen/interim_sdql_statclick_target, actor)
	var/datum/SDQL_parser/parser = allocate(/datum/SDQL_parser, SDQL2_tokenize("SELECT /obj/item/pen/interim_sdql_statclick_target FROM usr.contents", actor))
	var/list/tree = parser.parse(actor)
	TEST_ASSERT(!parser.error, "the actual parser accepts the bounded actor-contents query")
	var/datum/SDQL2_query/defaults = allocate(/datum/SDQL2_query, list())
	var/datum/SDQL2_query/query = allocate(/datum/SDQL2_query, tree, FALSE, TRUE, defaults.options, FALSE, bystander)
	query.generate_stat()
	var/obj/effect/statclick/SDQL2_action/run_button = query.action_click
	var/obj/effect/statclick/SDQL2_delete/delete_button = query.delete_click
	TEST_ASSERT_NOTNULL(run_button, "the actual query creates its run control")
	TEST_ASSERT_NOTNULL(delete_button, "the actual query creates its delete control")
	TEST_ASSERT_EQUAL(run_button.target, query, "the generated run control targets its actual query")
	TEST_ASSERT_EQUAL(delete_button.target, query, "the generated delete control targets its actual query")
	km_synthetic_click(actor, run_button)
	TEST_ASSERT_EQUAL(query.requester, actor, "the native run control replaces the previous requester with its actual clicked actor")
	TEST_ASSERT(run_until(CALLBACK(src, PROC_REF(query_finished), query)), "the actual yielding query completes within the bounded native-tick wait")
	TEST_ASSERT(query.finished, "the actual bounded query finishes after the run control executes")
	TEST_ASSERT_EQUAL(query.text_state(), "####IDLE", "the actual query returns to its idle state")
	TEST_ASSERT_EQUAL(length(query.select_refs), 1, "the actual actor-contents search selects exactly one object")
	TEST_ASSERT(query.select_refs[REF(target)], "the actual select result identifies the actor's exact pen")
	TEST_ASSERT_EQUAL(target.loc, actor, "the select query preserves the selected pen's actual location")
	query.admin_halt(bystander)
	TEST_ASSERT_EQUAL(query.text_state(), "####IDLE", "an idle query retains the existing halt guard")
	TEST_ASSERT_EQUAL(query.requester, actor, "the idle halt attempt does not change the successful run's requester")
	km_synthetic_click(actor, delete_button)
	TEST_ASSERT(QDELETED(query), "the native delete control actually deletes its query")
	TEST_ASSERT(QDELETED(run_button), "query teardown deletes its owned run control")
	TEST_ASSERT(QDELETED(delete_button), "query teardown deletes its owned delete control")
	TEST_ASSERT(!QDELETED(target), "deleting the query preserves the selected real pen")
	TEST_ASSERT_EQUAL(target.loc, actor, "query deletion preserves the actor's actual pen containment")

/// SDQL CHECK_TICK yields on native world ticks, outside the injected kernel clock.
/datum/unit_test/interim_sdql_statclick_actor/proc/query_finished(datum/SDQL2_query/query)
	return !QDELETED(query) && query.finished
