// The act_<action> argument validators (code/datums/capabilities/ui_actions.dm, design review C2).

/// ui_bool: TRUE for true/1/"1"/"true"/"yes"/"on", FALSE for false/0/"0"/"false"/"no"/"off"/"",
/// null for anything else (so a malformed payload is refused).
/datum/unit_test/dx_ui_bool

/datum/unit_test/dx_ui_bool/Run()
	TEST_ASSERT_EQUAL(ui_bool(1), TRUE, "1")
	TEST_ASSERT_EQUAL(ui_bool("1"), TRUE, "\"1\"")
	TEST_ASSERT_EQUAL(ui_bool("true"), TRUE, "\"true\"")
	TEST_ASSERT_EQUAL(ui_bool("TRUE"), TRUE, "\"TRUE\"")
	TEST_ASSERT_EQUAL(ui_bool("on"), TRUE, "\"on\"")
	TEST_ASSERT_EQUAL(ui_bool(0), FALSE, "0")
	TEST_ASSERT_EQUAL(ui_bool("0"), FALSE, "\"0\"")
	TEST_ASSERT_EQUAL(ui_bool("false"), FALSE, "\"false\"")
	TEST_ASSERT_EQUAL(ui_bool(""), FALSE, "empty text")
	TEST_ASSERT(isnull(ui_bool("maybe")), "unrecognised text is not a boolean")
	TEST_ASSERT(isnull(ui_bool(null)), "null is not a boolean")
	TEST_ASSERT(isnull(ui_bool(list(1))), "a list is not a boolean")
	TEST_ASSERT(isnull(ui_bool(allocate(/datum))), "a datum is not a boolean")
