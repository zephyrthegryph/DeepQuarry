// Per-type lists and non-atom declaration start (doc/rewrite/dx_conventions.md §2, §5.6).

/datum/type_list_fixture
	var/instance_value = 1
	var/static/built = 0

/datum/type_list_fixture/proc/fixture_list()
	built++
	return list("base")

/datum/type_list_fixture/child/fixture_list()
	return ..() + list("child")

/datum/type_list_fixture/impure/fixture_list()
	return list(instance_value)

/// A per-type list is built once per type, extends its parent with ..(), and is shared.
/datum/unit_test/type_list_cached_per_type/Run()
	var/datum/type_list_fixture/child/A = new
	var/datum/type_list_fixture/child/B = new
	var/datum/type_list_fixture/child/C = new
	var/before = A.built
	var/list/first = type_list(A, TYPE_PROC_REF(/datum/type_list_fixture, fixture_list))
	var/list/second = type_list(B, TYPE_PROC_REF(/datum/type_list_fixture, fixture_list))
	TEST_ASSERT_EQUAL(jointext(first, ","), "base,child", "the child's list extends the parent's")
	TEST_ASSERT(first == second, "two instances share one list")
	TEST_ASSERT(type_list(C, TYPE_PROC_REF(/datum/type_list_fixture, fixture_list)) == first, "a third instance shares it too")
	// Once for the type, plus once for the test-build purity check on the second instance.
	TEST_ASSERT_EQUAL(A.built - before, 2, "the proc ran once for the type (and once for the purity check)")
	qdel(A)
	qdel(B)
	qdel(C)

/// A per-type list that reads instance state is reported when a second instance differs.
/datum/unit_test/type_list_impurity_reported/Run()
	var/datum/type_list_fixture/impure/A = new
	var/datum/type_list_fixture/impure/B = new
	B.instance_value = 2
	type_list(A, TYPE_PROC_REF(/datum/type_list_fixture, fixture_list))
	var/before = length(GLOB.type_list_impure)
	GLOB.type_list_expect_impure = TRUE
	type_list(B, TYPE_PROC_REF(/datum/type_list_fixture, fixture_list))
	GLOB.type_list_expect_impure = FALSE
	TEST_ASSERT_EQUAL(length(GLOB.type_list_impure) - before, 1, "an impure per-type list is reported")
	qdel(A)
	qdel(B)

/// Structural comparison treats freshly built constructor datums with equal vars as equal.
/datum/unit_test/type_list_same_structural/Run()
	var/datum/type_list_fixture/X = new
	var/datum/type_list_fixture/Y = new
	TEST_ASSERT(type_list_same(list(X, "a" = 1), list(Y, "a" = 1), 0), "equal datums and pairs compare equal")
	Y.instance_value = 5
	TEST_ASSERT(!type_list_same(list(X), list(Y), 0), "a differing var compares unequal")
	qdel(X)
	qdel(Y)
