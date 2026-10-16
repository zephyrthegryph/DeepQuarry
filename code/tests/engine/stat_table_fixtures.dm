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
