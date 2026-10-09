// The generated TRACKED setter tells null from a falsy value: DM reads null == 0, null == "" and null == FALSE as true,
// so a plain `==` check dropped those writes without publishing. The setter returns TRUE exactly when it published.

/datum/tracked_null_fixture
	var/count
	var/text
	var/flag

TRACKED(/datum/tracked_null_fixture, count)
TRACKED(/datum/tracked_null_fixture, text)
TRACKED(/datum/tracked_null_fixture, flag)

/datum/unit_test/dq_tracked_null_setter

/datum/unit_test/dq_tracked_null_setter/Run()
	var/datum/tracked_null_fixture/F = new
	TEST_ASSERT(F.set_count(0), "null to 0 publishes")
	TEST_ASSERT(F.set_count(null), "0 to null publishes")
	TEST_ASSERT(!F.set_count(null), "null to null does not publish")
	TEST_ASSERT(F.set_text(""), "null to an empty string publishes")
	TEST_ASSERT(F.set_text(null), "an empty string to null publishes")
	TEST_ASSERT(F.set_flag(FALSE), "null to FALSE publishes")
	TEST_ASSERT(F.set_flag(null), "FALSE to null publishes")
	TEST_ASSERT(F.set_count(3), "a new value publishes")
	TEST_ASSERT(!F.set_count(3), "the same value twice publishes once")
	TEST_ASSERT(F.set_count(0), "3 to 0 publishes")
	TEST_ASSERT(!F.set_count(0), "0 to 0 does not publish")
	TEST_ASSERT(F.set_text("a") && !F.set_text("a"), "a string set twice publishes once")
	TEST_ASSERT(isnull(F.flag), "a null write left the var null")
