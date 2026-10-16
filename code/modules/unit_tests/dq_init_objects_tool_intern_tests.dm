// Canonical list identity is real constructor behavior, even with separate argument lists.
/obj/item/dq_init_tool_intern_fixture

CAPABILITIES(/obj/item/dq_init_tool_intern_fixture)
	param(nameof(tool_qualities), pos = 1)

/datum/unit_test/dq_init_objects_tool_intern

/datum/unit_test/dq_init_objects_tool_intern/Run()
	dq_init_objects_fixture_scope()
	var/list/first_input = list(TOOL_SCREWDRIVER = 2)
	var/list/second_input = list(TOOL_SCREWDRIVER = 2)
	TEST_ASSERT(first_input != second_input, "the constructor inputs begin as independently allocated lists")
	var/obj/item/dq_init_tool_intern_fixture/A = allocate(/obj/item/dq_init_tool_intern_fixture, null, first_input)
	var/obj/item/dq_init_tool_intern_fixture/B = allocate(/obj/item/dq_init_tool_intern_fixture, null, second_input)
	TEST_ASSERT_EQUAL(A.tool_qualities, B.tool_qualities, "real item constructors canonicalize equal tool-quality lists")
	TEST_ASSERT_EQUAL(A.tool_qualities[TOOL_SCREWDRIVER], 2, "canonicalization preserves the declared quality tier")
	var/obj/item/dq_init_tool_intern_fixture/C = allocate(/obj/item/dq_init_tool_intern_fixture, null, list(TOOL_SCREWDRIVER = 3))
	TEST_ASSERT(C.tool_qualities != A.tool_qualities, "different tool tiers do not alias a canonical list")
	TEST_ASSERT_EQUAL(C.tool_qualities[TOOL_SCREWDRIVER], 3, "the distinct constructor tier remains intact")
