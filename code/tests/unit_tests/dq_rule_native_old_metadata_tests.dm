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
	var/datum/rule/breaks = rules[/datum/rule/integrity_breaks]
	TEST_ASSERT_EQUAL(length(breaks.triggers), 1, "Static positive-failure guard does not add a wake")
	var/datum/rule_trigger/B = breaks.triggers[1]
	TEST_ASSERT_EQUAL(B.property, PROP_INTEGRITY_RATIO, "Break dependency is live ratio")
	TEST_ASSERT_EQUAL(B.value_property, PROP_INTEGRITY_FAILURE, "Break level is static failure threshold")
	TEST_ASSERT_EQUAL(B.op, SIM_COMPARE_LTE, "Break remains inclusive below")
	var/list/bands = list(/datum/rule/damage_flavour/light = 0.75, /datum/rule/damage_flavour/moderate = 0.5, /datum/rule/damage_flavour/heavy = 0.25)
	for(var/path in bands)
		var/datum/rule/R = rules[path]
		var/datum/rule_trigger/T = R.triggers[1]
		TEST_ASSERT_EQUAL(T.property, PROP_INTEGRITY_RATIO, "Damage band depends on live integrity")
		TEST_ASSERT_EQUAL(T.op, SIM_COMPARE_LT, "Damage band remains strict below")
		TEST_ASSERT_EQUAL(T.value, bands[path], "Exact ordered threshold retained")
	var/datum/rule/destroyed = rules[/datum/rule/integrity_destroyed]
	var/datum/rule_trigger/D = destroyed.triggers[1]
	TEST_ASSERT_EQUAL(D.op, SIM_COMPARE_LTE, "Destroy threshold remains inclusive zero")
	TEST_ASSERT_EQUAL(D.value, 0, "Destroy threshold remains zero")
