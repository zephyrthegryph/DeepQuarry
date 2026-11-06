// The variable viewer's target is a datum: a list is wrapped in a /datum/vv_list_target (code/modules/admin/view_variables_panel.dm).

/datum/unit_test/dq_vv_panel_target_is_typed

/datum/unit_test/dq_vv_panel_target_is_typed/Run()
	var/datum/view_variables_panel/panel = new(null)
	var/list/viewed = list("a", "b", "c")
	panel.set_view_target(viewed)
	TEST_ASSERT(istype(panel.thing, /datum/vv_list_target), "a list target is held as a wrapper")
	TEST_ASSERT(panel.view_target() == viewed, "and the panel reads the list back through view_target()")
	TEST_ASSERT_EQUAL(panel.refid(), REF(viewed), "with the handle of the list, not of the wrapper")
	var/datum/vv_list_target/wrapper = panel.thing

	var/datum/plain = new /datum
	panel.set_view_target(plain)
	TEST_ASSERT(panel.thing == plain, "a datum target is held as it is")
	TEST_ASSERT(panel.view_target() == plain, "and read back as it is")
	TEST_ASSERT(QDELETED(wrapper), "the wrapper of the list it left is gone")
	panel.set_view_target(null)
	TEST_ASSERT_NULL(panel.thing, "an empty target clears the panel")
	spent(plain)
	spent(panel)

// schema_any() (code/engine/declare/schema.dm): the declaration of a var that carries whatever its producer returns.
/datum/unit_test/dq_schema_any_accepts_every_value

/datum/unit_test/dq_schema_any_accepts_every_value/Run()
	var/datum/schema/S = schema_any()
	var/datum/probe = new /datum
	for(var/value in list(null, 0, 12.5, "text", /obj, list(1, 2), probe))
		var/list/verdict = schema_check(S, value)
		TEST_ASSERT(verdict[1] != SCHEMA_REJECT, "schema_any() takes [isnull(value) ? "null" : "[value]"]")
		TEST_ASSERT_NULL(verdict[2], "and notes nothing about it")
	spent(probe)

/datum/unit_test/dq_schema_any_declarations

/datum/unit_test/dq_schema_any_declarations/Run()
	for(var/list/declared in list(
		list(/datum/act/action, "reply"), list(/datum/config_entry, "config_entry_value"), list(/datum/asset_cache_item, "resource"),
		list(/datum/asset/simple, "assets"), list(/datum/n_Interpreter, "returnVal")))
		var/datum/schema/S = schema_of(declared[1], declared[2])
		TEST_ASSERT_NOTNULL(S, "[declared[1]] declares [declared[2]]")
		TEST_ASSERT_EQUAL(S?.kind, SCHEMA_ANY, "[declared[1]] [declared[2]] is an any-value var")
