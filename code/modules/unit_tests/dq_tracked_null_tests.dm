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

// A setter argument named value must never shadow the actual field named value.
/datum/dq_tracked_value_fixture
	var/value = 2
TRACKED(/datum/dq_tracked_value_fixture, value)

/obj/dq_tracked_schema_value_fixture
	var/value = 2
TRACKED_SCHEMA(/obj/dq_tracked_schema_value_fixture, value, int(0, 10))

/datum/record/dq_tracked_value_fixture
	var/value = 2
TRACKED_DATA(/datum/record/dq_tracked_value_fixture, value)

/obj/dq_tracked_record_value_holder
	var/datum/record/dq_tracked_value_fixture/data
CAPABILITIES(/obj/dq_tracked_record_value_holder)
	profile(nameof(data), /datum/record/dq_tracked_value_fixture)

/datum/unit_test/dq_tracked_value_field/Run()
	var/datum/dq_tracked_value_fixture/F = allocate(/datum/dq_tracked_value_fixture)
	TEST_ASSERT(F.set_value(3), "A different argument named value changes the actual tracked field")
	TEST_ASSERT_EQUAL(F.value, 3, "The setter stores the argument in src.value")
	TEST_ASSERT(!F.set_value(3), "Repeating the actual field value returns FALSE")
	TEST_ASSERT(F.set_value(null), "The actual field can transition to null")
	TEST_ASSERT_NULL(F.value, "The null argument is stored in the actual field")

/datum/unit_test/dq_tracked_schema_value_field/Run()
	var/obj/dq_tracked_schema_value_fixture/F = allocate(/obj/dq_tracked_schema_value_fixture)
	TEST_ASSERT(F.set_value(3), "A valid schema argument changes the actual value field")
	TEST_ASSERT_EQUAL(F.value, 3, "The validated value reaches src.value")
	TEST_ASSERT(!F.set_value(3), "An identical validated value returns FALSE")
	TEST_ASSERT(!F.set_value("not a number"), "A schema rejection returns FALSE")
	TEST_ASSERT_EQUAL(F.value, 3, "Rejecting the argument does not alter the actual field")

/datum/unit_test/dq_tracked_record_value_field/Run()
	var/obj/dq_tracked_record_value_holder/H = allocate(/obj/dq_tracked_record_value_holder)
	var/datum/record/dq_tracked_value_fixture/R = H.data
	TEST_ASSERT_NOTNULL(R, "The real profile declaration creates its record")
	TEST_ASSERT_EQUAL(owner_of(R), H, "The profile record belongs to its actual holder")
	var/datum/dq_b4_key_probe/record_probe = dq_b4_probe(R, nameof(R.value))
	var/datum/dq_b4_key_probe/holder_probe = dq_b4_probe(H, nameof(R.value))
	rx_drain()
	var/record_before = record_probe.hits
	var/holder_before = holder_probe.hits
	TEST_ASSERT(R.set_value(3), "The record setter changes its actual value field")
	TEST_ASSERT_EQUAL(R.value, 3, "The record stores the new argument")
	rx_drain()
	TEST_ASSERT_EQUAL(record_probe.hits, record_before + 1, "The real record key is published once")
	TEST_ASSERT_EQUAL(holder_probe.hits, holder_before + 1, "The record's holder receives the same field publication once")
	TEST_ASSERT(!R.set_value(3), "The unchanged record value returns FALSE")
	rx_drain()
	TEST_ASSERT_EQUAL(record_probe.hits, record_before + 1, "An unchanged record value does not republish")
	TEST_ASSERT_EQUAL(holder_probe.hits, holder_before + 1, "An unchanged record value does not republish on its holder")
