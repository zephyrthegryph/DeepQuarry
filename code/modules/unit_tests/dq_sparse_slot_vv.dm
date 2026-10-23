// Sparse slots in View Variables, mass edit and SDQL (code/engine/declare/sparse_vv.dm): every slot a type declares is listed as `@slot.name`,
// edited by name through the sparse writer, reset by clearing it, and reachable from SDQL.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/mob/living/carbon/human/dq_sparse_probe

/// The declaration registry has every sparse() line, and View Variables lists the slots a mob's type declares, set or not.
/datum/unit_test/dq_sparse_slot_vv_listing

/datum/unit_test/dq_sparse_slot_vv_listing/Run()
	var/mob/living/carbon/human/dq_sparse_probe/H = allocate(/mob/living/carbon/human/dq_sparse_probe, test_floor())
	var/list/rows = sparse_slot_rows()
	TEST_ASSERT(length(rows) >= 49, "the registry holds the declared slots, got [length(rows)]")
	for(var/list/row as anything in rows)
		TEST_ASSERT(ispath(row[1]), "slot [row[2]] names a real owner type")
	var/list/listed = sparse_slots_of(H)
	TEST_ASSERT_EQUAL(length(listed), length(sparse_slot_rows_of(H)), "every declared slot is listed once")
	TEST_ASSERT(sparse_slot_label("special_voice") in listed, "an unset human slot is listed")
	TEST_ASSERT(sparse_slot_label("floatiness") in listed, "a /mob slot is listed on a human")
	TEST_ASSERT(sparse_slot_label("breath_cycle") in listed, "a /mob/living/carbon slot is listed on a human")
	TEST_ASSERT(isnull(listed[sparse_slot_label("special_voice")]), "an unset slot shows null")
	TEST_ASSERT(isnull(H.sparse_slots), "listing does not allocate the slot list")
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	TEST_ASSERT_EQUAL(length(sparse_slots_of(pen)), length(sparse_slot_rows_of(pen)), "an object lists only what its type declares")
	TEST_ASSERT(!(sparse_slot_label("special_voice") in sparse_slots_of(pen)), "a human slot is not listed on a pen")
	_sparse_set(H, "special_voice", "Bob")
	TEST_ASSERT_EQUAL(sparse_slots_of(H)[sparse_slot_label("special_voice")], "Bob", "a set slot shows its value")
	TEST_ASSERT(findtext("[H.vv_get_var(sparse_slot_label("special_voice"))]", "Bob"), "vv_get_var renders the slot value")

/// Edit by name writes through the sparse path: by label and by bare name, null clears, an unknown name is refused.
/datum/unit_test/dq_sparse_slot_vv_edit

/datum/unit_test/dq_sparse_slot_vv_edit/Run()
	var/mob/living/carbon/human/dq_sparse_probe/H = allocate(/mob/living/carbon/human/dq_sparse_probe, test_floor())
	TEST_ASSERT(H.vv_edit_var(sparse_slot_label("special_voice"), "Alice"), "the VV edit of a slot is accepted")
	TEST_ASSERT_EQUAL(sparse_get(H, special_voice), "Alice", "and lands in the slot")
	TEST_ASSERT(H.vv_edit_var("special_voice", "Carol"), "the bare slot name is accepted where no var has it")
	TEST_ASSERT_EQUAL(sparse_get(H, special_voice), "Carol", "and lands in the slot")
	TEST_ASSERT(vars_write(H, "special_voice", "Dave"), "vars_write reaches the slot")
	TEST_ASSERT_EQUAL(sparse_get(H, special_voice), "Dave", "and writes it")
	TEST_ASSERT(!(sparse_slot_label("special_voice") in H.vars), "a slot is not a var")
	TEST_ASSERT_EQUAL(vv_var_value(H, sparse_slot_label("special_voice")), "Dave", "the editors read the slot value")
	TEST_ASSERT(H.vv_edit_var(sparse_slot_label("special_voice"), vv_var_default(H, sparse_slot_label("special_voice"))), "Restore to Default is accepted")
	TEST_ASSERT(isnull(sparse_get(H, special_voice)), "reset clears the slot")
	TEST_ASSERT(isnull(H.sparse_slots), "and the slot list goes with its last slot")
	TEST_ASSERT(!H.vv_edit_var("@slot.no_such_slot", 1), "an unknown slot is refused")
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	TEST_ASSERT(!pen.vv_edit_var(sparse_slot_label("special_voice"), "x"), "a slot the type does not declare is refused")
	TEST_ASSERT_EQUAL(vv_var_value(H, "name"), H.name, "an ordinary var reads as before")

/// SDQL reads and updates a slot by its name.
/datum/unit_test/dq_sparse_slot_sdql

/datum/unit_test/dq_sparse_slot_sdql/Run()
	test_driver_begin()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/dq_sparse_probe/H = allocate(/mob/living/carbon/human/dq_sparse_probe, test_floor())
	_sparse_set(H, "special_voice", "Before")
	var/datum/SDQL2_query/defaults = allocate(/datum/SDQL2_query, list())
	var/datum/SDQL_parser/read_parser = allocate(/datum/SDQL_parser, SDQL2_tokenize("SELECT /mob/living/carbon/human/dq_sparse_probe", actor))
	var/list/read_tree = read_parser.parse(actor)
	var/datum/SDQL2_query/reader = allocate(/datum/SDQL2_query, read_tree, FALSE, TRUE, defaults.options, FALSE, actor)
	TEST_ASSERT_EQUAL(reader.SDQL_expression(H, list("special_voice")), "Before", "SDQL reads a slot by its bare name")
	var/datum/SDQL_parser/parser = allocate(/datum/SDQL_parser, SDQL2_tokenize("UPDATE /mob/living/carbon/human/dq_sparse_probe SET special_voice = 'After'", actor))
	var/list/tree = parser.parse(actor)
	TEST_ASSERT(!parser.error, "the real parser accepts an update that names a slot")
	var/datum/SDQL2_query/query = allocate(/datum/SDQL2_query, tree, FALSE, TRUE, defaults.options, FALSE, actor)
	query.admin_run(actor)
	TEST_ASSERT(run_until(CALLBACK(src, PROC_REF(query_finished), query)), "the update query finishes")
	TEST_ASSERT_EQUAL(sparse_get(H, special_voice), "After", "SDQL UPDATE writes the slot through the sparse path")

/datum/unit_test/dq_sparse_slot_sdql/proc/query_finished(datum/SDQL2_query/query)
	return !QDELETED(query) && query.finished

#endif
