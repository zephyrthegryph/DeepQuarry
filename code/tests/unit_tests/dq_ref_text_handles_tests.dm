// Stored REF() texts replaced by handles (relations.md D9a, lint ref_text).

/// The refresh trace is keyed by the entity's handle: a mark on a traced entity is recorded under it.
/datum/unit_test/dq_ref_text_refresh_trace/Run()
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	var/key = ref_token(pen)
	GLOB.refresh_traced[key] = list()
	refresh_trace_note(pen, "test")
	var/list/lines = GLOB.refresh_traced[key]
	GLOB.refresh_traced -= key
	TEST_ASSERT_EQUAL(length(lines), 1, "the mark was recorded under the handle")
