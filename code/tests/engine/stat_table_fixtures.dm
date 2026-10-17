// The stat layer's table holds, bounds and fast paths (code/modules/unit_tests/dq_stat_layer_tests.dm).
//
// /obj/stat_table_fixture declares one stat of each numeric rule a body factor uses, with a var of its own (the stat is a real var). The
// /contributing subtype gives each a type-level contribution, so the no-row fast path has something to fold.

/obj/stat_table_fixture
	name = "stat table fixture"

STAT(/obj/stat_table_fixture, tb_sum, SUM, bounds = list(-10, 20))
STAT(/obj/stat_table_fixture, tb_product, PRODUCT, bounds = list(0, 4))
STAT(/obj/stat_table_fixture, tb_max, MAX, base = 0, bounds = list(0, 1), schema = num(0, 1))
STAT(/obj/stat_table_fixture, tb_min, MIN, base = 5)
STAT(/obj/stat_table_fixture, tb_mask, MASK_OR)
STAT(/obj/stat_table_fixture, tb_free, SUM)

/// The same stats with a contribution of the type's own on each.
/obj/stat_table_fixture/contributing
	name = "stat table fixture (contributing)"

CAPABILITIES(/obj/stat_table_fixture/contributing)
	contributes(STAT_TB_SUM, 3)
	contributes(STAT_TB_PRODUCT, 0.5)
	contributes(STAT_TB_MAX, 0.25)
	contributes(STAT_TB_MIN, 2)
	contributes(STAT_TB_MASK, 6)

/// A source whose factors() entries put tables on the fixture its `target` names (code/modules/unit_tests/dq_stat_layer_tests.dm, dq_stat_factors_entry).
/datum/factor_source_fixture
	/// The fixture that receives the tables: a relation view.
	var/obj/stat_table_fixture/target
	/// The scale of the first table (tracked by being read by the entry: written through set_level()).
	var/level = 1
	/// The stacks of the first table (written through set_stacks()).
	var/stacks = 1
	/// TRUE while the second table (a proc's, which names two stats) is wanted: a when() gate.
	var/wide = FALSE

CAPABILITIES(/datum/factor_source_fixture)
	ref_one(nameof(target), /obj/stat_table_fixture)
	factors(PROC_REF(first_table), scale = nameof(level), stacks = nameof(stacks), to = nameof(target))
	factors(alist(STAT_TB_FREE = 4), to = nameof(target), part = "free")
	when(nameof(wide), factors(PROC_REF(wide_table), to = nameof(target), part = "wide"))

/datum/factor_source_fixture/proc/first_table(datum/act/eval/A)
	return alist(STAT_TB_SUM = 4, STAT_TB_PRODUCT = 0.5)

/datum/factor_source_fixture/proc/wide_table(datum/act/eval/A)
	return alist(STAT_TB_SUM = 1, STAT_TB_MAX = 0.4)
