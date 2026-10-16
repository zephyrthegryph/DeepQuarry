// The stat layer's engine gaps for body factors (doc/rewrite/proposals/stat_layer.md, section 3): bounds clamp the composed value of a numeric
// stat, the no-row fast path equals the general path for every numeric rule, and hold_table() places a source's table as rows (scale, stacks,
// swap, parts, passes) that settle once.

#define STAT_NEAR(a, b) (abs((a) - (b)) <= 0.000001)

/datum/unit_test/dq_stat_layer
	abstract_type = /datum/unit_test/dq_stat_layer

/// Runs `run_layer()` with declaration reports captured, so a deliberate refusal is read instead of failing the run.
/datum/unit_test/dq_stat_layer/Run()
	GLOB.declare_report_capture = list()
	run_layer()
	GLOB.declare_report_capture = null
	GLOB.stat_marked = list()

/datum/unit_test/dq_stat_layer/proc/run_layer()
	return

/datum/unit_test/dq_stat_layer/proc/reports()
	var/list/capture = GLOB.declare_report_capture
	return capture ? capture : list()

/datum/unit_test/dq_stat_layer/proc/source()
	return allocate(/obj/e3_source)

/// How many rows the entity keeps for a stat.
/datum/unit_test/dq_stat_layer/proc/rows_of(datum/E, stat_id)
	var/datum/stat_record/rec = E.rx?.stats
	return length(rec?.by_stat?["[stat_id]"])

// ---------------------------------------------------------------------------------------------------------------------
// Bounds
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_stat_layer/dq_stat_bounds

/datum/unit_test/dq_stat_layer/dq_stat_bounds/run_layer()
	var/obj/stat_table_fixture/F = allocate(/obj/stat_table_fixture)
	var/obj/e3_source/A = source()
	var/obj/e3_source/B = source()
	hold(F, STAT_TB_SUM, 25, A)
	TEST_ASSERT_EQUAL(F.tb_sum, 20, "the sum is held to its upper bound")
	hold(F, STAT_TB_SUM, -30, B)
	TEST_ASSERT_EQUAL(F.tb_sum, -5, "a contribution beyond the bound still counts: 25 and -30 compose to -5")
	release(F, STAT_TB_SUM, A)
	TEST_ASSERT_EQUAL(F.tb_sum, -10, "and the sum is held to its lower bound")
	release(F, STAT_TB_SUM, B)
	TEST_ASSERT_EQUAL(F.tb_sum, 0, "released: the base")
	hold(F, STAT_TB_PRODUCT, 10, A)
	TEST_ASSERT_EQUAL(F.tb_product, 4, "the product is held to its upper bound")
	hold(F, STAT_TB_PRODUCT, 0, B)
	TEST_ASSERT_EQUAL(F.tb_product, 0, "and to its lower")
	release(F, STAT_TB_PRODUCT, A)
	release(F, STAT_TB_PRODUCT, B)
	TEST_ASSERT_EQUAL(F.tb_product, 1, "released: the base")
	hold(F, STAT_TB_FREE, 1000000, A)
	TEST_ASSERT_EQUAL(F.tb_free, 1000000, "a stat with no bounds is not clamped")
	// An override replaces the composed value, so it sits outside the bounds when an admin says so.
	hold(F, STAT_TB_SUM, 5, A)
	hold_override(F, STAT_TB_SUM, 99, SRC_VV)
	TEST_ASSERT_EQUAL(F.tb_sum, 99, "an override is not clamped")
	release(F, STAT_TB_SUM, SRC_VV)
	TEST_ASSERT_EQUAL(F.tb_sum, 5, "released: the composed value again")
	TEST_ASSERT_EQUAL(length(reports()), 0, "no report: [json_encode(reports())]")

// ---------------------------------------------------------------------------------------------------------------------
// Fast paths
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_stat_layer/dq_stat_fast_paths

/datum/unit_test/dq_stat_layer/dq_stat_fast_paths/run_layer()
	var/obj/stat_table_fixture/bare = allocate(/obj/stat_table_fixture)
	TEST_ASSERT_EQUAL(bare.tb_sum, 0, "SUM base")
	TEST_ASSERT_EQUAL(bare.tb_product, 1, "PRODUCT base")
	TEST_ASSERT_EQUAL(bare.tb_max, 0, "MAX base")
	TEST_ASSERT_EQUAL(bare.tb_min, 5, "MIN base")
	TEST_ASSERT_EQUAL(bare.tb_mask, 0, "MASK_OR base")
	var/obj/stat_table_fixture/contributing/F = allocate(/obj/stat_table_fixture/contributing)
	TEST_ASSERT_EQUAL(F.tb_sum, 3, "SUM folds the contribution (fast path)")
	TEST_ASSERT(STAT_NEAR(F.tb_product, 0.5), "PRODUCT folds it")
	TEST_ASSERT(STAT_NEAR(F.tb_max, 0.25), "MAX folds it")
	TEST_ASSERT_EQUAL(F.tb_min, 2, "MIN folds it")
	TEST_ASSERT_EQUAL(F.tb_mask, 6, "MASK_OR folds it")
	var/list/stats = list(STAT_TB_SUM, STAT_TB_PRODUCT, STAT_TB_MAX, STAT_TB_MIN, STAT_TB_MASK)
	for(var/stat_id in stats)
		TEST_ASSERT_EQUAL(rows_of(F, stat_id), 0, "[stat_label(stat_id)] has no row: the fast path ran")
	// A row of the rule's neutral value puts every stat on the general path; the value must not move.
	var/obj/e3_source/A = source()
	hold(F, STAT_TB_SUM, 0, A)
	hold(F, STAT_TB_PRODUCT, 1, A)
	hold(F, STAT_TB_MAX, 0, A)
	hold(F, STAT_TB_MIN, 5, A)
	hold(F, STAT_TB_MASK, 0, A)
	for(var/stat_id in stats)
		TEST_ASSERT_EQUAL(rows_of(F, stat_id), 1, "[stat_label(stat_id)] has its neutral row")
	TEST_ASSERT_EQUAL(F.tb_sum, 3, "SUM, general path")
	TEST_ASSERT(STAT_NEAR(F.tb_product, 0.5), "PRODUCT, general path")
	TEST_ASSERT(STAT_NEAR(F.tb_max, 0.25), "MAX, general path")
	TEST_ASSERT_EQUAL(F.tb_min, 2, "MIN, general path")
	TEST_ASSERT_EQUAL(F.tb_mask, 6, "MASK_OR, general path")
	release_all(F, A)
	TEST_ASSERT_EQUAL(F.tb_sum, 3, "SUM, fast path again")
	TEST_ASSERT_EQUAL(F.tb_mask, 6, "MASK_OR, fast path again")
	TEST_ASSERT_EQUAL(length(reports()), 0, "no report: [json_encode(reports())]")

// ---------------------------------------------------------------------------------------------------------------------
// hold_table
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_stat_layer/dq_stat_hold_table

/datum/unit_test/dq_stat_layer/dq_stat_hold_table/run_layer()
	var/obj/stat_table_fixture/F = allocate(/obj/stat_table_fixture)
	var/obj/e3_source/A = source()
	var/obj/e3_source/B = source()
	// A multiplier fades toward 1 with the scale and compounds with stacks.
	var/alist/halve = alist(STAT_TB_PRODUCT = 0.5)
	TEST_ASSERT(hold_table(F, A, halve), "placed")
	TEST_ASSERT(STAT_NEAR(F.tb_product, 0.5), "a 0.5 multiplier at full scale")
	hold_table(F, A, halve, scale = 0.5)
	TEST_ASSERT(STAT_NEAR(F.tb_product, 0.75), "at half scale it contributes 1 - 0.5 * 0.5")
	hold_table(F, A, halve, scale = 1, stacks = 2)
	TEST_ASSERT(STAT_NEAR(F.tb_product, 0.25), "two stacks multiply it twice")
	hold_table(F, A, halve, scale = 0)
	TEST_ASSERT_EQUAL(F.tb_product, 1, "a scale of 0 holds nothing")
	TEST_ASSERT_EQUAL(rows_of(F, STAT_TB_PRODUCT), 0, "and leaves no row")
	// An offset scales and stacks linearly; placing it again replaces it exactly, down as well as up.
	hold_table(F, A, alist(STAT_TB_SUM = 4), scale = 0.5, stacks = 3)
	TEST_ASSERT(STAT_NEAR(F.tb_sum, 6), "4 at half scale and three stacks is 6")
	hold_table(F, A, alist(STAT_TB_SUM = 2))
	TEST_ASSERT(STAT_NEAR(F.tb_sum, 2), "placed again with less: it falls (replace, not the stronger of the two)")
	// MAX ignores stacks, MASK_OR holds its bits, MIN keeps the lowest; sources combine by the rule.
	hold_table(F, A, alist(STAT_TB_MAX = 0.6, STAT_TB_MASK = 5, STAT_TB_MIN = 3), scale = 1, stacks = 3)
	TEST_ASSERT(STAT_NEAR(F.tb_max, 0.6), "MAX at three stacks is the value")
	TEST_ASSERT_EQUAL(F.tb_mask, 5, "MASK_OR takes the bits")
	TEST_ASSERT_EQUAL(F.tb_min, 3, "MIN takes the value")
	hold_table(F, B, alist(STAT_TB_MAX = 0.3, STAT_TB_MASK = 2, STAT_TB_MIN = 4))
	TEST_ASSERT(STAT_NEAR(F.tb_max, 0.6), "two sources: the larger MAX")
	TEST_ASSERT_EQUAL(F.tb_mask, 7, "the union of the bits")
	TEST_ASSERT_EQUAL(F.tb_min, 3, "the smaller MIN")
	// A contribution at the rule's neutral value, or at or past the base, is no row at all.
	var/rows_before = rows_of(F, STAT_TB_MAX) + rows_of(F, STAT_TB_MIN) + rows_of(F, STAT_TB_MASK) + rows_of(F, STAT_TB_PRODUCT) + rows_of(F, STAT_TB_SUM)
	hold_table(F, B, alist(STAT_TB_MAX = 0, STAT_TB_MIN = 7, STAT_TB_MASK = 0, STAT_TB_PRODUCT = 1, STAT_TB_SUM = 0))
	var/rows_after = rows_of(F, STAT_TB_MAX) + rows_of(F, STAT_TB_MIN) + rows_of(F, STAT_TB_MASK) + rows_of(F, STAT_TB_PRODUCT) + rows_of(F, STAT_TB_SUM)
	TEST_ASSERT_EQUAL(rows_after, rows_before - 3, "B's three rows went (its table now holds nothing) and no neutral row came")
	release_table(F, A)
	TEST_ASSERT(F.tb_sum == 0 && F.tb_product == 1 && F.tb_max == 0 && F.tb_min == 5 && F.tb_mask == 0, "release_table puts every stat back to its base")
	TEST_ASSERT(!release_table(F, A), "releasing again reports nothing released")

	// A table swap releases the stats the new table no longer names.
	hold_table(F, A, alist(STAT_TB_SUM = 1, STAT_TB_PRODUCT = 0.5))
	hold_table(F, A, alist(STAT_TB_SUM = 2))
	TEST_ASSERT_EQUAL(F.tb_product, 1, "the stat the new table dropped is back at its base")
	TEST_ASSERT_EQUAL(F.tb_sum, 2, "the one it kept has the new value")
	TEST_ASSERT_EQUAL(rows_of(F, STAT_TB_PRODUCT), 0, "and the dropped stat has no row")

	// An unchanged table costs a compare and no recompute.
	var/evals = GLOB.stat_evals
	hold_table(F, A, alist(STAT_TB_SUM = 2))
	TEST_ASSERT_EQUAL(GLOB.stat_evals, evals, "the same table again recomputes nothing")
	hold_table(F, A, alist(STAT_TB_SUM = 3))
	TEST_ASSERT_EQUAL(GLOB.stat_evals, evals + 1, "a changed value recomputes its stat once")
	release_table(F, A)

	// A source's parts are separate sets of rows.
	hold_table(F, A, alist(STAT_TB_SUM = 1), part = "a")
	hold_table(F, A, alist(STAT_TB_SUM = 10), part = "b")
	TEST_ASSERT_EQUAL(F.tb_sum, 11, "two parts of one source both count")
	release_table(F, A, "a")
	TEST_ASSERT_EQUAL(F.tb_sum, 10, "releasing a part leaves the other")
	hold_table(F, A, alist(), part = "b")
	TEST_ASSERT_EQUAL(F.tb_sum, 0, "an empty table for a part releases it")

	// A plain hold of the same source is another row: release() leaves table rows, release_all() takes both.
	hold(F, STAT_TB_FREE, 7, A)
	hold_table(F, A, alist(STAT_TB_FREE = 3))
	TEST_ASSERT_EQUAL(F.tb_free, 10, "a plain hold and a table row of one source both count")
	release(F, STAT_TB_FREE, A)
	TEST_ASSERT_EQUAL(F.tb_free, 3, "release() takes the plain hold only")
	release_all(F, A)
	TEST_ASSERT_EQUAL(F.tb_free, 0, "release_all() takes the table rows too")

	// A pass settles every stat it changed once, and releases the rows no call of the pass placed.
	hold_table(F, B, alist(STAT_TB_SUM = 100)) // outside the pass: B's row stays until a pass finds it unplaced
	TEST_ASSERT_EQUAL(F.tb_sum, 20, "B's 100 composes to the upper bound")
	evals = GLOB.stat_evals
	TEST_ASSERT(hold_tables_begin(F), "pass opened")
	hold_table(F, A, alist(STAT_TB_SUM = 1, STAT_TB_PRODUCT = 0.5))
	hold_table(F, A, alist(STAT_TB_FREE = 2), part = "x")
	TEST_ASSERT_EQUAL(F.tb_sum, 20, "nothing settles inside the pass")
	var/changed = hold_tables_end(F)
	TEST_ASSERT_EQUAL(F.tb_sum, 1, "B's row, not placed by the pass, was released: only A's 1 is left")
	TEST_ASSERT(STAT_NEAR(F.tb_product, 0.5), "A's product holds")
	TEST_ASSERT_EQUAL(F.tb_free, 2, "A's named part holds")
	TEST_ASSERT_EQUAL(changed, 3, "three stats ended different")
	TEST_ASSERT_EQUAL(GLOB.stat_evals, evals + 3, "each settled once")
	changed = hold_tables_end(F)
	TEST_ASSERT_EQUAL(changed, 0, "ending a pass that is not open does nothing")
	hold_tables_begin(F)
	hold_table(F, A, alist(STAT_TB_SUM = 1, STAT_TB_PRODUCT = 0.5))
	evals = GLOB.stat_evals
	changed = hold_tables_end(F)
	TEST_ASSERT_EQUAL(changed, 1, "a pass that places what is already there changes only the part it no longer placed")
	TEST_ASSERT_EQUAL(F.tb_free, 0, "which is released")
	release_all(F, A)

	// A deleted source's rows go with it.
	var/obj/e3_source/gone = new
	hold_table(F, gone, alist(STAT_TB_SUM = 5))
	TEST_ASSERT_EQUAL(F.tb_sum, 5, "held")
	qdel(gone)
	TEST_ASSERT_EQUAL(F.tb_sum, 0, "the source's deletion released its table rows")

	// Refusals: a contribution past a MAX stat's schema, a stat the type lacks, a source that is not one.
	TEST_ASSERT_EQUAL(length(reports()), 0, "no report so far: [json_encode(reports())]")
	hold_table(F, A, alist(STAT_TB_MAX = 2))
	TEST_ASSERT(length(reports()) == 1 && findtext(reports()[1], "tb_max"), "a contribution outside the schema is reported by stat: [json_encode(reports())]")
	TEST_ASSERT_EQUAL(F.tb_max, 0, "and not held")
	hold_table(F, A, alist(STAT_AIRWAY = 0.5))
	TEST_ASSERT(length(reports()) == 2 && findtext(reports()[2], "does not declare"), "a stat the type lacks is reported: [json_encode(reports())]")
	TEST_ASSERT_NULL(hold_table(F, "not a source", alist(STAT_TB_SUM = 1)), "a text source is refused")
	TEST_ASSERT_EQUAL(length(reports()), 3, "and reported")
