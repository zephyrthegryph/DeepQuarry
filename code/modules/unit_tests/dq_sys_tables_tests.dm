// TYPE_TABLE / COW_LIST (doc/rewrite/systems.md section 7).

GLOBAL_VAR_INIT(tt_test_builds, 0)

/datum/tt_test
	var/list/tt_test_cow

/datum/tt_test/child
/datum/tt_test/child/grandchild
/datum/tt_test/other

/proc/tt_test_build_other()
	GLOB.tt_test_builds++
	return list("built")

TYPE_TABLE_DECLARE(/datum/tt_test, tt_test_table, list("root"))
TYPE_TABLE(/datum/tt_test/child, tt_test_table, list("child", 2))
TYPE_TABLE(/datum/tt_test/other, tt_test_table, tt_test_build_other())
TYPE_TABLE_DECLARE(/datum/tt_test, tt_test_cow, list("a" = 1))
TYPE_TABLE_DECLARE(/datum/tt_test, tt_test_empty, null)

/// Tables inherit, override per subtype, are shared and built once per type.
/datum/unit_test/dq_sys_tables_inherit

/datum/unit_test/dq_sys_tables_inherit/Run()
	var/datum/tt_test/root = new
	var/datum/tt_test/child/child = new
	var/datum/tt_test/child/grandchild/grand = new
	var/datum/tt_test/child/child2 = new
	TEST_ASSERT_EQUAL(TYPE_TABLE_GET(root, tt_test_table)[1], "root", "the root value")
	TEST_ASSERT_EQUAL(TYPE_TABLE_GET(child, tt_test_table)[1], "child", "a subtype override")
	TEST_ASSERT_EQUAL(TYPE_TABLE_GET(grand, tt_test_table)[1], "child", "inherited by a deeper subtype")
	TEST_ASSERT(TYPE_TABLE_GET(child, tt_test_table) == TYPE_TABLE_GET(child2, tt_test_table), "one shared list per type")
	var/before = GLOB.tt_test_builds
	var/datum/tt_test/other/o1 = new
	var/datum/tt_test/other/o2 = new
	TYPE_TABLE_GET(o1, tt_test_table)
	TYPE_TABLE_GET(o2, tt_test_table)
	TEST_ASSERT(GLOB.tt_test_builds - before <= 1, "a builder value is evaluated at most once per type")
	TEST_ASSERT_NULL(TYPE_TABLE_GET(root, tt_test_empty), "a null table reads null")
	var/list/copy = TYPE_TABLE_COPY(root, tt_test_empty)
	TEST_ASSERT(islist(copy) && !length(copy), "a copy of a null table is an empty list")
	var/list/mine = TYPE_TABLE_COPY(child, tt_test_table)
	mine += "extra"
	TEST_ASSERT_EQUAL(length(TYPE_TABLE_GET(child, tt_test_table)), 2, "a copy does not touch the table")
	for(var/datum/D as anything in list(root, child, grand, child2, o1, o2))
		qdel(D)

/// COW_LIST copies on first write; COW_READ falls back to the table until then.
/datum/unit_test/dq_sys_tables_cow

/datum/unit_test/dq_sys_tables_cow/Run()
	var/datum/tt_test/a = new
	var/datum/tt_test/b = new
	TEST_ASSERT_NULL(a.tt_test_cow, "the instance var starts null")
	TEST_ASSERT(COW_READ(a, tt_test_cow) == TYPE_TABLE_GET(a, tt_test_cow), "a read sees the shared table")
	COW_LIST(a, tt_test_cow)["a"] = 5
	TEST_ASSERT_EQUAL(a.tt_test_cow["a"], 5, "the write landed on the instance")
	TEST_ASSERT_EQUAL(COW_READ(b, tt_test_cow)["a"], 1, "other instances still read the table")
	TEST_ASSERT_EQUAL(TYPE_TABLE_GET(a, tt_test_cow)["a"], 1, "the table is untouched")
	TEST_ASSERT(COW_LIST(a, tt_test_cow) == a.tt_test_cow, "later writes reuse the instance copy")
	qdel(a)
	qdel(b)
