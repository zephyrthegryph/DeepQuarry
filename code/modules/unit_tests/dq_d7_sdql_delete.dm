GLOBAL_LIST_EMPTY(dq_d7_endings)

/obj/item/pen/dq_d7_delete_probe
CAPABILITIES(/obj/item/pen/dq_d7_delete_probe)
	on_ending(PROC_REF(record_admin_ending))
/obj/item/pen/dq_d7_delete_probe/proc/record_admin_ending(cause, datum/by)
	GLOB.dq_d7_endings += list(list(cause, by))

/datum/unit_test/dq_d7_sdql_delete/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.dq_d7_endings), list())
	test_driver_begin()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/pen/dq_d7_delete_probe/target = allocate(/obj/item/pen/dq_d7_delete_probe, actor)
	var/obj/item/pen/untouched = allocate(/obj/item/pen, actor)
	var/datum/SDQL_parser/parser = allocate(/datum/SDQL_parser, SDQL2_tokenize("DELETE /obj/item/pen/dq_d7_delete_probe FROM usr.contents", actor))
	var/list/tree = parser.parse(actor)
	TEST_ASSERT(!parser.error, "The real parser accepts a bounded inventory deletion query")
	var/datum/SDQL2_query/defaults = allocate(/datum/SDQL2_query, list())
	var/datum/SDQL2_query/query = allocate(/datum/SDQL2_query, tree, FALSE, TRUE, defaults.options, FALSE, actor)
	query.admin_run(actor)
	TEST_ASSERT(run_until(CALLBACK(src, PROC_REF(query_finished), query)), "The actual yielding deletion query finishes")
	TEST_ASSERT(QDELETED(target), "The matched real item is deleted")
	TEST_ASSERT(!QDELETED(untouched), "An unmatched item stays alive")
	TEST_ASSERT_EQUAL(untouched.loc, actor, "Deletion does not move unmatched inventory")
	TEST_ASSERT_EQUAL(length(GLOB.dq_d7_endings), 1, "The matched item ends once")
	var/list/ending = GLOB.dq_d7_endings[1]
	TEST_ASSERT_EQUAL(ending[1], END_ENGINE, "Administrative deletion preserves qdel's original engine cause")
	TEST_ASSERT_NULL(ending[2], "Administrative deletion preserves the original unassigned ending source")

/datum/unit_test/dq_d7_sdql_delete/proc/query_finished(datum/SDQL2_query/query)
	return !QDELETED(query) && query.finished
