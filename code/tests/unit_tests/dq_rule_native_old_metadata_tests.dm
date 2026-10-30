// OLD-CODE boundary: native factory conversion must retain these production trigger rows.
/datum/unit_test/dq_rule_native_old_metadata/Run()
	var/list/rules = GLOBAL_TABLE_GET(dq_rules)
	var/list/heat_rules = list(/datum/rule/ignition = PROP_IGNITION_POINT, /datum/rule/melting = PROP_MELTING_POINT, /datum/rule/overheating = PROP_MELTING_POINT)
	for(var/path in heat_rules)
		var/datum/rule/R = rules[path]
		TEST_ASSERT_NOTNULL(R, "Production rule exists")
		TEST_ASSERT_EQUAL(length(R.triggers), 1, "Production heat comparison has one threshold")
		var/datum/rule_trigger/T = R.triggers[1]
		TEST_ASSERT_EQUAL(T.kind, RULE_TRIGGER_THRESHOLD, "Comparison remains native thermal threshold")
		TEST_ASSERT_EQUAL(T.property, PROP_TEMPERATURE, "Left dependency is temperature")
		TEST_ASSERT_EQUAL(T.value_property, heat_rules[path], "Right dependency remains declared static material limit")
		TEST_ASSERT_EQUAL(T.op, SIM_COMPARE_GTE, "Inclusive old operator retained")
