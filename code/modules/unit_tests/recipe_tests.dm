/// Validates every kitchen recipe defines a well-formed result.

/datum/unit_test/recipe_test/Run()
	var/list/rules = xform_rules_in(MEDIUM_CONTENTS, REGIME_COOKING)
	TEST_ASSERT(length(rules) > 0, "Recipes - no kitchen recipe was compiled.")
	for(var/datum/xform/R as anything in rules)
		TEST_ASSERT_NOTNULL(R.result, "[R.rule_type]: Recipes - Missing result.")
		TEST_ASSERT(ispath(R.result, /atom/movable), "[R.rule_type]: Recipes - Improper result; [R.result] is not an obj or mob.")
		TEST_ASSERT_NOTNULL(R.result_amount, "[R.rule_type]: Recipes - result_quantity must be set.")
		TEST_ASSERT(R.result_amount > 0, "[R.rule_type]: Recipes - result_quantity must be greater than zero.")
		TEST_ASSERT(ISINTEGER(R.result_amount), "[R.rule_type]: Recipes - result_quantity must be an integer.")
		TEST_ASSERT(R.cooks_in > 0, "[R.rule_type]: Recipes - no appliance.")
