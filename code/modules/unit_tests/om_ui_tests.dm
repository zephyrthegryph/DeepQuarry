/datum/object_model/ui/test
	interface = "ObjectModelTest"
	title = "Object model test"
	actions = list("set" = list("value" = list("type" = "number", "min" = 0, "max" = 10)))

/datum/object_model/ui/test/data(datum/source, mob/user, datum/object_model/ui_data/D)
	var/datum/object_model/ui_test_entity/E = source
	D.put("value", E.value)

/datum/object_model/ui/test/can_act(datum/source, mob/user, action, list/params)
	var/datum/object_model/ui_test_entity/E = source
	return E.enabled

/datum/object_model/ui/test/act(datum/source, mob/user, action, list/params)
	var/datum/object_model/ui_test_entity/E = source
	if(action != "set")
		return FALSE
	E.value = params["value"]
	return TRUE

/datum/object_model/ui_test_entity
	var/value = 0
	var/enabled = TRUE

/datum/object_model/ui_test_entity/om_declare(datum/object_model/archetype/A)
	. = ..()
	A.ui(/datum/object_model/ui/test)

/datum/unit_test/om_ui_adapter
	needs_test_block = FALSE

/datum/unit_test/om_ui_adapter/Run()
	var/datum/object_model/ui/generated = om_ui_definition(/datum/object_model/ui/schema_fixture)
	TEST_ASSERT(islist(generated.actions["set"]), "Generated DM action schema is available to the UI adapter")
	var/list/generated_schema = generated.actions["set"]
	TEST_ASSERT(isnull(om_ui_params(generated_schema, list("value" = 11))), "Generated action bounds reject invalid input")
	var/datum/object_model/ui_data/generated_data = new(generated.data_schema)
	TEST_ASSERT(generated_data.put("value", 4), "Generated data schema accepts a typed value")
	TEST_ASSERT(!generated_data.put("unknown", 4), "Generated data schema rejects undeclared fields")
	qdel(generated_data)
	var/datum/object_model/ui_test_entity/E = new
	var/mob/user = new
	var/datum/object_model/ui/definition = om_ui_definition(/datum/object_model/ui/test)
	var/datum/object_model/ui_session/session = new(E, user, definition)
	TEST_ASSERT(om_claim(E, "om:ui", session), "UI session has one lifetime authority")
	var/list/data = session.tgui_data(user)
	TEST_ASSERT_EQUAL(data["value"], 0, "Definition contributes typed data")
	TEST_ASSERT_EQUAL(data["can"]["set"], null, "Enabled action has no failure reason")
	TEST_ASSERT(!session.dispatch("set", list("value" = 5)), "Missing revision is rejected")
	TEST_ASSERT(!session.dispatch("set", list("revision" = 0, "value" = 11)), "Out-of-range parameter is rejected")
	TEST_ASSERT(!session.dispatch("set", list("revision" = 0, "value" = "garbage")), "Non-numeric parameter is rejected")
	TEST_ASSERT(session.dispatch("set", list("revision" = 0, "value" = "7")), "Validated numeric parameter dispatches")
	TEST_ASSERT_EQUAL(E.value, 7, "Action receives normalized parameter")
	TEST_ASSERT(!session.dispatch("set", list("revision" = 0, "value" = 8)), "Stale revision is rejected")
	E.enabled = FALSE
	TEST_ASSERT(!session.dispatch("set", list("revision" = E.om_state.revision, "value" = 8)), "Server repeats permission check")
	qdel(E)
	qdel(user)
