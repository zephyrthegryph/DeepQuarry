// Static entries (code/engine/declare/static_entries.dm) and the loot, loot_search and map_resolver entries that use them
// (code/library/loot/loot_entries.dm, code/library/maps/map_resolver_entry.dm).

/// Fixtures: types that declare static entries in real CAPABILITIES blocks, compiled at setup with every other block.
/datum/dq_static_fixture
/datum/dq_static_fixture/parent
/datum/dq_static_fixture/parent/child
/datum/dq_static_fixture/parent/child/grandchild
/datum/dq_static_fixture/other
/datum/dq_static_fixture/searcher

CAPABILITIES(/datum/dq_static_fixture/parent)
	loot(table = list(/obj/item/tool/wrench = 3, loot_set(1, list(/obj/item/tool/crowbar, /obj/item/tool/screwdriver))), count = 2, chance = 50, hook = GLOBAL_PROC_REF(dq_static_fixture_hook))
	map_resolver(GLOBAL_PROC_REF(dq_static_fixture_resolver), vars = list("alpha_var"))

CAPABILITIES(/datum/dq_static_fixture/parent/child)
	configure(loot(all = list(/obj/item/tool/wrench), uncommon = loot_tier(10, list(/obj/item/tool/crowbar))))
	configure(map_resolver(vars = list("beta_var")))

CAPABILITIES(/datum/dq_static_fixture/searcher)
	loot_search(table = /datum/dq_static_fixture/parent, wake_chance = 5)

/proc/dq_static_fixture_hook(atom/spawned, path, list/varedits, datum/loot_rng/rng)
	return

/proc/dq_static_fixture_resolver(atom/loc, path, list/varedits)
	return TRUE

/// The constructors build interned entries; the rows keep their weights and order.
/datum/unit_test/dq_static_entry_constructors

/datum/unit_test/dq_static_entry_constructors/Run()
	var/datum/entry/E = loot(table = list(/obj/item/tool/wrench = 3, /obj/item/tool/crowbar), count = 2)
	TEST_ASSERT_EQUAL(E.kind, ENTRY_LOOT, "loot() makes a loot entry")
	var/list/table = E.args["table"]
	TEST_ASSERT_EQUAL(length(table), 2, "the table keeps its rows")
	TEST_ASSERT_EQUAL(table[/obj/item/tool/wrench], 3, "a weighted row keeps its weight")
	TEST_ASSERT_EQUAL(table[1], /obj/item/tool/wrench, "and its place")
	TEST_ASSERT_EQUAL(E.args["count"], 2, "count is kept")
	TEST_ASSERT_NULL(E.args["chance"], "an argument left out is null")
	TEST_ASSERT_EQUAL(loot(table = list(/obj/item/tool/wrench = 3, /obj/item/tool/crowbar), count = 2), E, "the same arguments are the same entry")
	// The row constructors keep a weighted path (`/path = weight`) and a bare one.
	var/datum/loot_entry/group/G = loot_set(2, list(/obj/item/tool/wrench, /obj/item/tool/crowbar = 4, /obj/item/tool/screwdriver))
	TEST_ASSERT_EQUAL(G.weight, 2, "the group weighs what it was given")
	TEST_ASSERT_EQUAL(length(G.entries), 3, "the group has its three rows")
	TEST_ASSERT_EQUAL(G.entries[/obj/item/tool/crowbar], 4, "a weighted row of a group keeps its weight")
	var/datum/loot_entry/sub/S = loot_sub(1, list(/obj/item/tool/wrench = 3, /obj/item/tool/crowbar))
	TEST_ASSERT_EQUAL(S.total, 4, "a nested pick sums its weights (an unweighted row weighs 1)")
	var/datum/loot_entry/sub/types/T = loot_types(2, list(/obj/item/tool/wrench, /obj/item/tool/crowbar))
	TEST_ASSERT_EQUAL(T.weight, 4, "a computed list weighs its weight per type")
	var/list/tier = loot_tier(10, list(/obj/item/tool/wrench = 2, /obj/item/tool/crowbar))
	TEST_ASSERT_EQUAL(tier[1], 10, "a tier has its chance")
	TEST_ASSERT_EQUAL(length(tier[2]), 2, "and its rows")
	TEST_ASSERT_EQUAL(tier[2][/obj/item/tool/wrench], 2, "with their weights")

/// A subtype's configure() changes what it inherits; a subtype without a block shares its ancestor's declaration.
/datum/unit_test/dq_static_entry_inheritance

/datum/unit_test/dq_static_entry_inheritance/Run()
	var/datum/loot_decl/parent = loot_decl_for(/datum/dq_static_fixture/parent)
	TEST_ASSERT_NOTNULL(parent, "the parent fixture has a declaration")
	TEST_ASSERT_EQUAL(parent.count, 2, "the parent's count")
	TEST_ASSERT_EQUAL(parent.chance, 50, "the parent's chance")
	TEST_ASSERT(parent.main_table && parent.main_table.total == 4, "the parent's table: a weight 3 path and a weight 1 group")
	TEST_ASSERT_EQUAL(parent.hook, GLOBAL_PROC_REF(dq_static_fixture_hook), "the parent's hook")
	var/datum/loot_decl/child = loot_decl_for(/datum/dq_static_fixture/parent/child)
	TEST_ASSERT_NOTNULL(child, "the child declares by configure()")
	TEST_ASSERT_NULL(child.main_table, "naming `all` replaces what spawns as one unit: the parent's table goes")
	TEST_ASSERT_EQUAL(length(child.all), 1, "the child's own `all`")
	TEST_ASSERT_EQUAL(child.count, 2, "the count it did not name is inherited")
	TEST_ASSERT_EQUAL(child.chance, 50, "so is the chance")
	TEST_ASSERT_EQUAL(child.hook, GLOBAL_PROC_REF(dq_static_fixture_hook), "and the hook")
	TEST_ASSERT_EQUAL(child.uncommon_chance, 10, "a tier the child adds")
	TEST_ASSERT(child != parent, "a configured child has a declaration of its own")
	TEST_ASSERT_EQUAL(loot_decl_for(/datum/dq_static_fixture/parent/child/grandchild), child, "a type without a block shares its nearest declaring ancestor's declaration")
	TEST_ASSERT_NULL(loot_decl_for(/datum/dq_static_fixture/other), "a type under no declaring ancestor has none")
	TEST_ASSERT_NULL(loot_decl_for(/obj/item/tool/wrench), "an ordinary item has none")

	TEST_ASSERT_EQUAL(map_resolver_proc(/datum/dq_static_fixture/parent), GLOBAL_PROC_REF(dq_static_fixture_resolver), "the parent's resolver")
	TEST_ASSERT_EQUAL(map_resolver_proc(/datum/dq_static_fixture/parent/child/grandchild), GLOBAL_PROC_REF(dq_static_fixture_resolver), "a subtype's resolver is inherited")
	var/datum/map_resolver_info/parent_info = GLOB.map_resolvers[/datum/dq_static_fixture/parent]
	var/datum/map_resolver_info/child_info = GLOB.map_resolvers[/datum/dq_static_fixture/parent/child]
	TEST_ASSERT("alpha_var" in parent_info.reads, "the parent reads alpha_var")
	TEST_ASSERT(("beta_var" in child_info.reads) && !("alpha_var" in child_info.reads), "configure(map_resolver(vars =)) replaces the vars and keeps the resolver")
	TEST_ASSERT_EQUAL(child_info.resolver, parent_info.resolver, "the resolver it did not name is inherited")
	TEST_ASSERT_EQUAL(map_resolver_vars_of(/datum/dq_static_fixture/parent/child/grandchild), child_info.reads, "a subtype reads its ancestor's vars")
	TEST_ASSERT_NULL(map_resolver_proc(/datum/dq_static_fixture/other), "a type that declares none has none")

	TEST_ASSERT_EQUAL(loot_search_table(/datum/dq_static_fixture/searcher), /datum/dq_static_fixture/parent, "a pile's table")
	TEST_ASSERT_EQUAL(loot_search_wake_chance(/datum/dq_static_fixture/searcher), 5, "and its wake chance")
	TEST_ASSERT_NULL(loot_search_table(/datum/dq_static_fixture/other), "a type with no loot_search() searches nothing")

/// A second declaration under an inherited one, and a configure() of nothing, are reported (not silently replaced).
/datum/unit_test/dq_static_entry_errors

/datum/unit_test/dq_static_entry_errors/Run()
	var/datum/type_table/parent_table = static_table_of(/datum/dq_static_fixture/parent)
	TEST_ASSERT_NOTNULL(parent_table, "the parent fixture has a static table")
	GLOB.declare_report_capture = list()
	static_compile(/datum/dq_static_fixture/other, parent_table, "dq_test.dm", 10, list(entry_line(11), loot(count = 1)))
	var/list/repeated = GLOB.declare_report_capture
	GLOB.declare_report_capture = list()
	static_compile(/datum/dq_static_fixture/other, null, "dq_test.dm", 20, list(entry_line(21), configure(loot(count = 1))))
	var/list/nothing_to_configure = GLOB.declare_report_capture
	GLOB.declare_report_capture = list()
	static_compile(/datum/dq_static_fixture/other, null, "dq_test.dm", 30, list(entry_line(31), configure(entry_make("not_static", null, null))))
	var/list/not_static = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(repeated), 1, "a plain loot() under an inherited one is one error")
	TEST_ASSERT(findtext(repeated[1], "dq_test.dm:11") && findtext(repeated[1], "configure(loot("), "it names its line and the fix: [repeated[1]]")
	TEST_ASSERT_EQUAL(length(nothing_to_configure), 1, "configure(loot()) with nothing inherited is one error")
	TEST_ASSERT(findtext(nothing_to_configure[1], "does not inherit"), "it says nothing is inherited: [nothing_to_configure[1]]")
	TEST_ASSERT_EQUAL(length(not_static), 1, "configure() of a kind that is not static is one error")
