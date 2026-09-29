// Declared UI model (doc/rewrite/systems.md section 3; code/datums/sys/ui.dm).

GLOBAL_LIST_EMPTY(ui_test_calls)

/datum/ui_test_host
	var/name = "ui test host"
	var/charge = 7
	var/tgui_id = "UiTestFromVar"
	var/list/things
	var/refuse_all = FALSE
	var/datum/ui_test_host/forward_to

OM_FIELD(/datum/ui_test_host, level, 0, CHANGE_DATUM_A)

/datum/ui_test_host/proc/charge_percent(mob/user)
	return charge * 10

/datum/ui_test_host/proc/valid_ids()
	return list("alpha", "beta")

/datum/ui_test_host/proc/thing_pool()
	return things

/datum/ui_test_host/ui_slot_fragment(slot, mob/user)
	return list("slot" = slot)

/datum/ui_test_host/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	return !refuse_all

DECLARE_UI(/datum/ui_test_host, "UiTest", UI_TITLE("UI Test"), UI_AUTOUPDATE)
UI_DATA(/datum/ui_test_host, "level", "charge:num", "proc:charge_percent", "slot:SLOT_TEST")
UI_ACT(/datum/ui_test_host, "toggle", ui_act_record)
UI_ACT(/datum/ui_test_host, "set_rate", ui_act_record, UI_ARG_NUM("rate", 0, 100))
UI_ACT(/datum/ui_test_host, "set_count", ui_act_record, UI_ARG_INT("count", 1, 10))
UI_ACT(/datum/ui_test_host, "rename", ui_act_record, UI_ARG_TEXT("name", 5))
UI_ACT(/datum/ui_test_host, "flag", ui_act_record, UI_ARG_BOOL("on"))
UI_ACT(/datum/ui_test_host, "select", ui_act_record, UI_ARG_CHOICE("id", "proc:valid_ids"))
UI_ACT(/datum/ui_test_host, "select_literal", ui_act_record, UI_ARG_CHOICE("id", list("x", "y")))
UI_ACT(/datum/ui_test_host, "pick", ui_act_record, UI_ARG_REF("ref", "proc:thing_pool", /datum/ui_test_host))
UI_ACT(/datum/ui_test_host, "spawn", ui_act_record, UI_ARG_PATH("path", /datum/ui_test_host))
UI_ACT(/datum/ui_test_host, "bulk", ui_act_record, UI_ARG_LIST("items"))
UI_ACT(/datum/ui_test_host, "either", ui_act_record, UI_ARG_VALUE("value", 4))
UI_ACT(/datum/ui_test_host, "override_me", ui_act_parent_only)
UI_ACT_NESTED(/datum/ui_test_host, "set_attribute", "attr", "attribute")
UI_SUBACT(/datum/ui_test_host, "attr", "size", ui_subact_size, UI_ARG_INT("val", 1, 3))
UI_ACT_FORWARD(/datum/ui_test_host, ui_test_forward)

UI_ACT_PROC(/datum/ui_test_host, ui_act_record)
	GLOB.ui_test_calls += list(list(action, params.Copy(), GLOB.ui_rerun))
	return TRUE

UI_ACT_PROC(/datum/ui_test_host, ui_act_parent_only)
	GLOB.ui_test_calls += list(list("parent", null, FALSE))
	return TRUE

UI_SUBACT_PROC(/datum/ui_test_host, ui_subact_size)
	GLOB.ui_test_calls += list(list("attr:[action]", params.Copy(), FALSE))
	return TRUE

/datum/ui_test_host/proc/ui_test_forward(mob/user, action)
	return forward_to

/datum/ui_test_host/child
	name = "ui test child"

UI_ACT(/datum/ui_test_host/child, "child_only", ui_act_record)
UI_ACT_OVERRIDE(/datum/ui_test_host/child, ui_act_parent_only)
	GLOB.ui_test_calls += list(list("child", null, FALSE))
	return TRUE

/datum/ui_test_host/from_var
DECLARE_UI(/datum/ui_test_host/from_var, UI_FROM_VAR("tgui_id"))

/// A datum with no declaration at all.
/datum/ui_test_bare

/proc/ui_test_window(datum/host)
	var/datum/tgui/ui = new(null, host, "UiTest")
	ui.status = STATUS_INTERACTIVE
	return ui

/proc/ui_test_last_call()
	return length(GLOB.ui_test_calls) ? GLOB.ui_test_calls[length(GLOB.ui_test_calls)] : null

/// The table is built once per type, inherits along the host hierarchy and a subtype row replaces
/// its parent's.
/datum/unit_test/dq_sys_ui_declaration

/datum/unit_test/dq_sys_ui_declaration/Run()
	var/datum/ui_test_host/host = new
	var/datum/ui_test_host/child/child = new
	var/datum/ui_decl/decl = ui_decl_of(host)
	TEST_ASSERT_NOTNULL(decl, "a declared host has a table")
	TEST_ASSERT(decl == ui_decl_of(new /datum/ui_test_host), "one table per type")
	TEST_ASSERT_EQUAL(decl.interface, "UiTest", "DECLARE_UI's interface")
	TEST_ASSERT_EQUAL(decl.title, "UI Test", "UI_TITLE")
	TEST_ASSERT(decl.autoupdate, "UI_AUTOUPDATE")
	TEST_ASSERT(decl.watch & CHANGE_DATUM_A, "a UI_DATA field's declared channel joins the watch mask")
	var/datum/ui_decl/child_decl = ui_decl_of(child)
	TEST_ASSERT_EQUAL(child_decl.interface, "UiTest", "the declaration is inherited")
	TEST_ASSERT(child_decl.acts["toggle"], "rows are inherited")
	TEST_ASSERT(child_decl.acts["child_only"], "a subtype adds rows")
	TEST_ASSERT(!decl.acts["child_only"], "a subtype's row does not leak to the parent")
	TEST_ASSERT(decl.acts["change_ui_state"], "the base /datum row reaches every host")
	var/datum/ui_test_bare/bare = new
	TEST_ASSERT_NULL(ui_decl_of(bare).interface, "an undeclared datum has no interface")
	TEST_ASSERT(!bare.tgui_interact(null), "an undeclared datum opens no window")
	TEST_ASSERT_EQUAL(host.ui_title(null), "UI Test", "ui_title() reads UI_TITLE")
	var/datum/ui_test_host/from_var/from_var = new
	TEST_ASSERT_EQUAL(from_var.ui_interface(null), "UiTestFromVar", "UI_FROM_VAR reads the host var")

/// Declared data: vars, getters and slot fragments.
/datum/unit_test/dq_sys_ui_data

/datum/unit_test/dq_sys_ui_data/Run()
	var/datum/ui_test_host/host = new
	host.set_level(3)
	var/list/data = host.tgui_data(null)
	TEST_ASSERT_EQUAL(data["level"], 3, "a var field")
	TEST_ASSERT_EQUAL(data["charge"], 7, "a typed var field (name:type)")
	TEST_ASSERT_EQUAL(data["charge_percent"], 70, "a proc: field")
	TEST_ASSERT_EQUAL(data["SLOT_TEST"]?["slot"], "SLOT_TEST", "a slot: field asks ui_slot_fragment()")

/// Central parsing: each kind converts, clamps and rejects; the handler only sees declared keys.
/datum/unit_test/dq_sys_ui_parse

/datum/unit_test/dq_sys_ui_parse/Run()
	GLOB.ui_test_calls = list()
	var/datum/ui_test_host/host = new
	var/datum/ui_test_host/other = new
	host.things = list(other)
	var/datum/tgui/ui = ui_test_window(host)
	var/list/call_row

	TEST_ASSERT(host.tgui_act("set_rate", list("rate" = "250", "junk" = 1), ui), "NUM from numeric text runs")
	call_row = ui_test_last_call()
	TEST_ASSERT_EQUAL(call_row[2]["rate"], 100, "NUM clamps to its bounds")
	TEST_ASSERT(!("junk" in call_row[2]), "undeclared keys never reach the handler")
	var/count_before = length(GLOB.ui_test_calls)
	TEST_ASSERT(!host.tgui_act("set_rate", list("rate" = "lots"), ui), "invalid NUM is refused")
	TEST_ASSERT_EQUAL(length(GLOB.ui_test_calls), count_before, "the handler is not called on invalid args")
	host.tgui_act("set_rate", list(), ui)
	TEST_ASSERT_NULL(ui_test_last_call()[2]["rate"], "an absent arg reads null")

	host.tgui_act("set_count", list("count" = 4.6), ui)
	TEST_ASSERT_EQUAL(ui_test_last_call()[2]["count"], 5, "INT rounds")
	host.tgui_act("rename", list("name" = "abcdefgh"), ui)
	TEST_ASSERT_EQUAL(ui_test_last_call()[2]["name"], "abcde", "TEXT is cut to its length")
	host.tgui_act("rename", list("name" = 12), ui)
	TEST_ASSERT_EQUAL(ui_test_last_call()[2]["name"], "12", "TEXT renders a number")
	host.tgui_act("flag", list("on" = "0"), ui)
	TEST_ASSERT_EQUAL(ui_test_last_call()[2]["on"], FALSE, "BOOL from text")
	host.tgui_act("flag", list("on" = 1), ui)
	TEST_ASSERT_EQUAL(ui_test_last_call()[2]["on"], TRUE, "BOOL from a number")

	TEST_ASSERT(host.tgui_act("select", list("id" = "beta"), ui), "CHOICE from a host getter")
	TEST_ASSERT(!host.tgui_act("select", list("id" = "gamma"), ui), "CHOICE refuses a value not in its source")
	TEST_ASSERT(host.tgui_act("select_literal", list("id" = "y"), ui), "CHOICE from a literal list")

	host.tgui_act("pick", list("ref" = REF(other)), ui)
	TEST_ASSERT_EQUAL(ui_test_last_call()[2]["ref"], other, "REF resolves inside its source")
	var/datum/ui_test_host/stranger = new
	TEST_ASSERT(!host.tgui_act("pick", list("ref" = REF(stranger)), ui), "REF refuses a datum outside its source")
	host.things = list(new /datum/ui_test_bare)
	TEST_ASSERT(!host.tgui_act("pick", list("ref" = REF(host.things[1])), ui), "REF refuses the wrong type")

	host.tgui_act("spawn", list("path" = "/datum/ui_test_host/child"), ui)
	TEST_ASSERT_EQUAL(ui_test_last_call()[2]["path"], /datum/ui_test_host/child, "PATH resolves a subtype of its base")
	TEST_ASSERT(!host.tgui_act("spawn", list("path" = "/datum/ui_test_bare"), ui), "PATH refuses other types")

	host.tgui_act("bulk", list("items" = "\[1,2,3\]"), ui)
	TEST_ASSERT_EQUAL(length(ui_test_last_call()[2]["items"]), 3, "LIST decodes JSON text")
	TEST_ASSERT(!host.tgui_act("bulk", list("items" = "\[broken"), ui), "LIST refuses malformed JSON")

	host.tgui_act("either", list("value" = 5), ui)
	TEST_ASSERT_EQUAL(ui_test_last_call()[2]["value"], 5, "VALUE keeps a number")
	host.tgui_act("either", list("value" = "maximum"), ui)
	TEST_ASSERT_EQUAL(ui_test_last_call()[2]["value"], "maxi", "VALUE cuts text")
	TEST_ASSERT(!host.tgui_act("either", list("value" = list(1)), ui), "VALUE refuses a list")

/// Dispatch: gates, overrides, fallbacks, forwarding, nesting and act_ask re-runs.
/datum/unit_test/dq_sys_ui_dispatch

/datum/unit_test/dq_sys_ui_dispatch/Run()
	GLOB.ui_test_calls = list()
	var/datum/ui_test_host/host = new
	var/datum/tgui/ui = ui_test_window(host)

	TEST_ASSERT(host.tgui_act("toggle", list(), ui), "a row runs its handler")
	TEST_ASSERT_EQUAL(ui_test_last_call()[1], "toggle", "the handler reads the action")
	host.refuse_all = TRUE
	var/count_before = length(GLOB.ui_test_calls)
	TEST_ASSERT(!host.tgui_act("toggle", list(), ui), "ui_act_allowed() refuses")
	TEST_ASSERT_EQUAL(length(GLOB.ui_test_calls), count_before, "a refused action runs nothing")
	host.refuse_all = FALSE
	ui.status = STATUS_UPDATE
	host.tgui_act("toggle", list(), ui)
	TEST_ASSERT_EQUAL(length(GLOB.ui_test_calls), count_before, "a window that is not interactive runs nothing")
	ui.status = STATUS_INTERACTIVE

	var/datum/ui_test_host/child/child = new
	var/datum/tgui/child_ui = ui_test_window(child)
	child.tgui_act("override_me", list(), child_ui)
	TEST_ASSERT_EQUAL(ui_test_last_call()[1], "child", "UI_ACT_OVERRIDE replaces the inherited handler")

	var/datum/ui_test_host/target = new
	host.forward_to = target
	TEST_ASSERT(host.tgui_act("child_only", list(), ui) == null, "an action no row names and the forward target lacks does nothing")
	var/datum/ui_test_host/child/child_target = new
	host.forward_to = child_target
	TEST_ASSERT(host.tgui_act("child_only", list(), ui), "UI_ACT_FORWARD hands an unknown action to its target's rows")

	TEST_ASSERT(host.tgui_act("set_attribute", list("attribute" = "size", "val" = "9"), ui), "UI_ACT_NESTED routes to the sub-action")
	var/list/call_row = ui_test_last_call()
	TEST_ASSERT_EQUAL(call_row[1], "attr:size", "the sub-action's handler runs")
	TEST_ASSERT_EQUAL(call_row[2]["val"], 3, "the sub-action parses with its own args")
	TEST_ASSERT(!host.tgui_act("set_attribute", list("attribute" = "colour"), ui), "an unknown sub-action is refused")
	TEST_ASSERT(!host.tgui_act("size", list("val" = 1), ui), "a sub-action is not reachable as a top-level action")
	TEST_ASSERT(ui_subdispatch(host, "attr", "size", list("val" = 2), null, ui, null), "ui_subdispatch() runs a sub-action")

	TEST_ASSERT(ui_dispatch_typed(host, "set_rate", list("rate" = 30, "om_answer_x" = 1), ui, null), "a typed re-run runs the row")
	call_row = ui_test_last_call()
	TEST_ASSERT_EQUAL(call_row[2]["om_answer_x"], 1, "a re-run keeps the server-side answer")
	TEST_ASSERT(call_row[3], "GLOB.ui_rerun is set during a re-run")
	TEST_ASSERT(!GLOB.ui_rerun, "GLOB.ui_rerun is cleared afterwards")

/// Every declared row is well formed: known arg kinds, named args, sources of a known shape.
/datum/unit_test/dq_sys_ui_rows_valid

/datum/unit_test/dq_sys_ui_rows_valid/Run()
	var/list/kinds = list(UI_ARGK_NUM, UI_ARGK_INT, UI_ARGK_TEXT, UI_ARGK_BOOL, UI_ARGK_CHOICE, UI_ARGK_REF, UI_ARGK_PATH, UI_ARGK_LIST, UI_ARGK_VALUE)
	var/rows = 0
	for(var/marker in subtypesof(/datum/ui_declared))
		var/datum/ui_decl/decl = ui_build_decl(marker, null)
		var/list/all_rows = list()
		for(var/action in decl.acts)
			all_rows["[action]"] = decl.acts[action]
		for(var/namespace in decl.subacts)
			for(var/action in decl.subacts[namespace])
				all_rows["[namespace]:[action]"] = decl.subacts[namespace][action]
		for(var/action in all_rows)
			var/list/row = all_rows[action]
			rows++
			if(!row[1] && !row[3])
				TEST_FAIL("[marker] row '[action]' has no handler")
			for(var/list/spec as anything in row[2])
				if(!(spec[1] in kinds) || !istext(spec[2]))
					TEST_FAIL("[marker] row '[action]' has a malformed arg spec")
					continue
				if(spec[1] in list(UI_ARGK_CHOICE, UI_ARGK_REF))
					var/source = spec[3]
					if(!isnull(source) && !islist(source) && !istext(source))
						TEST_FAIL("[marker] row '[action]' arg '[spec[2]]' has a source that is not a list, name or null")
				if(spec[1] == UI_ARGK_PATH && !ispath(spec[3]))
					TEST_FAIL("[marker] row '[action]' PATH arg '[spec[2]]' has no base type")
	TEST_ASSERT(rows > 1000, "the codebase's UI_ACT rows were all visited ([rows])")

/// The -DUI_TYPES_DUMP export writes every declared host (tools/build/lib/ui_types.ts reads it).
/datum/unit_test/dq_sys_ui_types_dump

/datum/unit_test/dq_sys_ui_types_dump/Run()
	var/path = "data/ui_types_unit_test.json"
	var/count = ui_types_dump(path, resolve_vars = FALSE)
	TEST_ASSERT(count > 100, "hosts were exported ([count])")
	var/list/dump = json_decode(rustg_file_read(path))
	fdel(path)
	var/list/found
	for(var/list/entry as anything in dump)
		if(entry["host"] == "/datum/ui_test_host")
			found = entry
	TEST_ASSERT_NOTNULL(found, "the test host is exported")
	TEST_ASSERT("UiTest" in found["interfaces"], "with its interface")
	TEST_ASSERT(found["acts"]["set_rate"], "with its actions")
	TEST_ASSERT(found["acts"]["set_attribute:size"], "nested sub-actions are exported per sub-action")
