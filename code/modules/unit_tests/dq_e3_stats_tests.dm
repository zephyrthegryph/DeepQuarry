// E3, stats: the gate fixtures of doc/rewrite/final_api.html section 19 "E3, stats" (code/tests/engine/e3_fixtures.dm).
//
// A table-driven test per combine rule (base value, tie-break, VV override); a hold on a type that lacks the stat is a build error naming type
// and stat; a hold dies with its deleted source unless it outlives_source; contributes_to releases on relation change; immunity zeroes a
// status; a stat var read is current on the next line, with no drain. Then the settle rule: a fan-out is marked and drains under a budget.

/datum/unit_test/dq_e3
	abstract_type = /datum/unit_test/dq_e3
	/// TRUE for a test that advances time (timed holds, the drain per tick): it runs on the kernel's test clock.
	var/needs_clock = FALSE

/// Runs `run_e3()` with declaration reports captured, so a deliberate error is read instead of failing the run.
/datum/unit_test/dq_e3/Run()
	GLOB.declare_report_capture = list()
	if(needs_clock)
		test_driver_begin() // the test clock, started before any deadline is computed and put back after
	run_e3()
	if(needs_clock)
		test_driver_end()
	GLOB.declare_report_capture = null
	GLOB.stat_marked = list()
	GLOB.stat_tick_spent = 0

/datum/unit_test/dq_e3/proc/run_e3()
	return

/datum/unit_test/dq_e3/proc/reports()
	var/list/capture = GLOB.declare_report_capture
	return capture ? capture : list()

/// A fresh source of holds.
/datum/unit_test/dq_e3/proc/source()
	return allocate(/obj/e3_source)

// ---------------------------------------------------------------------------------------------------------------------
// The rules
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e3/rules_base_values

/datum/unit_test/dq_e3/rules_base_values/run_e3()
	var/obj/e3_rules/R = allocate(/obj/e3_rules)
	TEST_ASSERT_EQUAL(R.e3_all, TRUE, "ALL is TRUE with nothing contributing")
	TEST_ASSERT_EQUAL(R.e3_any, FALSE, "ANY is FALSE")
	TEST_ASSERT_EQUAL(R.e3_sum, 0, "SUM is 0")
	TEST_ASSERT_EQUAL(R.e3_product, 1, "PRODUCT is 1")
	TEST_ASSERT_NULL(R.e3_max, "MAX has no value without a contribution")
	TEST_ASSERT_NULL(R.e3_min, "MIN has no value without a contribution")
	TEST_ASSERT_NULL(R.e3_top, "TOP has no value without a contribution")
	TEST_ASSERT_EQUAL(R.e3_mask_and, 15, "MASK_AND is its base mask")
	TEST_ASSERT_EQUAL(R.e3_mask_or, 0, "MASK_OR is 0")
	TEST_ASSERT_EQUAL(stat_value(R, STAT_E3_SUM), 0, "stat_value reads the same")
	TEST_ASSERT_EQUAL(length(reports()), 0, "no report: [json_encode(reports())]")

/datum/unit_test/dq_e3/rules_each_combines

/datum/unit_test/dq_e3/rules_each_combines/run_e3()
	var/obj/e3_rules/R = allocate(/obj/e3_rules)
	var/obj/e3_source/A = source()
	var/obj/e3_source/B = source()
	var/obj/e3_source/C = source()
	// ALL: one veto is enough; releasing it restores TRUE. ANY: one force is enough.
	TEST_ASSERT(hold(R, STAT_E3_ALL, null, A), "ALL veto placed")
	TEST_ASSERT_EQUAL(R.e3_all, FALSE, "ALL vetoed")
	release(R, STAT_E3_ALL, A)
	TEST_ASSERT_EQUAL(R.e3_all, TRUE, "ALL released")
	hold(R, STAT_E3_ANY, null, A)
	TEST_ASSERT_EQUAL(R.e3_any, TRUE, "ANY forced")
	release(R, STAT_E3_ANY, A)
	TEST_ASSERT_EQUAL(R.e3_any, FALSE, "ANY released")
	// The direction that can never change anything is refused, naming the stat.
	TEST_ASSERT_NULL(hold(R, STAT_E3_ALL, TRUE, A), "an ALL hold of TRUE is refused")
	TEST_ASSERT(length(reports()) == 1 && findtext(reports()[1], "e3_all"), "the refusal names the stat: [json_encode(reports())]")
	// SUM, PRODUCT, MAX, MIN.
	hold(R, STAT_E3_SUM, 3, A)
	hold(R, STAT_E3_SUM, 4, B)
	TEST_ASSERT_EQUAL(R.e3_sum, 7, "SUM adds")
	release(R, STAT_E3_SUM, A)
	TEST_ASSERT_EQUAL(R.e3_sum, 4, "SUM after a release")
	hold(R, STAT_E3_PRODUCT, 3, A)
	hold(R, STAT_E3_PRODUCT, 4, B)
	TEST_ASSERT_EQUAL(R.e3_product, 12, "PRODUCT multiplies")
	hold(R, STAT_E3_MAX, 3, A)
	hold(R, STAT_E3_MAX, 9, B)
	TEST_ASSERT_EQUAL(R.e3_max, 9, "MAX takes the largest")
	hold(R, STAT_E3_MIN, 3, A)
	hold(R, STAT_E3_MIN, 9, B)
	TEST_ASSERT_EQUAL(R.e3_min, 3, "MIN takes the smallest")
	// TOP: the highest priority wins; at equal priority the most recent hold does.
	hold(R, STAT_E3_TOP, "a", A, priority = PRIORITY_DEFAULT)
	TEST_ASSERT_EQUAL(R.e3_top, "a", "one contribution")
	hold(R, STAT_E3_TOP, "b", B, priority = PRIORITY_FORCE)
	TEST_ASSERT_EQUAL(R.e3_top, "b", "a higher priority wins")
	hold(R, STAT_E3_TOP, "c", C, priority = PRIORITY_FORCE)
	TEST_ASSERT_EQUAL(R.e3_top, "c", "at equal priority the most recent wins")
	release(R, STAT_E3_TOP, C)
	TEST_ASSERT_EQUAL(R.e3_top, "b", "released: the next")
	// SET: the union of the members.
	hold(R, STAT_E3_SET, "x", A)
	hold(R, STAT_E3_SET, "y", B)
	TEST_ASSERT(islist(R.e3_set) && ("x" in R.e3_set) && ("y" in R.e3_set) && length(R.e3_set) == 2, "SET is the union: [json_encode(R.e3_set)]")
	release(R, STAT_E3_SET, A)
	TEST_ASSERT(length(R.e3_set) == 1 && ("y" in R.e3_set), "SET after a release: [json_encode(R.e3_set)]")
	// MASK_AND narrows from the base; MASK_OR accumulates.
	hold(R, STAT_E3_MASK_AND, 12, A)
	TEST_ASSERT_EQUAL(R.e3_mask_and, 12, "MASK_AND of the base and 12")
	hold(R, STAT_E3_MASK_AND, 6, B)
	TEST_ASSERT_EQUAL(R.e3_mask_and, 4, "MASK_AND narrows")
	hold(R, STAT_E3_MASK_OR, 1, A)
	hold(R, STAT_E3_MASK_OR, 4, B)
	TEST_ASSERT_EQUAL(R.e3_mask_or, 5, "MASK_OR accumulates")

/datum/unit_test/dq_e3/rules_sum_per_key

/datum/unit_test/dq_e3/rules_sum_per_key/run_e3()
	var/obj/e3_rules/R = allocate(/obj/e3_rules)
	var/A = source()
	var/B = source()
	TEST_ASSERT(!length(R.e3_keyed), "SUM_PER_KEY holds no keys with nothing held")
	hold(R, STAT_E3_KEYED, 2, A, key = "x")
	hold(R, STAT_E3_KEYED, 3, B, key = "x")
	hold(R, STAT_E3_KEYED, 1, A, key = "y")
	TEST_ASSERT_EQUAL(R.e3_keyed["x"], 5, "two sources on one key sum")
	TEST_ASSERT_EQUAL(R.e3_keyed["y"], 1, "another key is its own total")
	// The same (source, key) again replaces its count: a lower count lowers the total.
	hold(R, STAT_E3_KEYED, 1, A, key = "x")
	TEST_ASSERT_EQUAL(R.e3_keyed["x"], 4, "holding again from the same source and key replaces the count")
	// A change of a count alone (the key set unchanged) still counts as a change.
	hold(R, STAT_E3_KEYED, 7, A, key = "y")
	TEST_ASSERT_EQUAL(R.e3_keyed["y"], 7, "a changed count under the same keys is written")
	// release() with a key takes that key only; without one, every key of the source.
	TEST_ASSERT(release(R, STAT_E3_KEYED, A, "x"), "releasing one key reports it")
	TEST_ASSERT_EQUAL(R.e3_keyed["x"], 3, "only A's hold on x went")
	TEST_ASSERT_EQUAL(R.e3_keyed["y"], 7, "A's other key stays")
	TEST_ASSERT(release(R, STAT_E3_KEYED, A), "releasing a source takes every key it holds")
	TEST_ASSERT(isnull(R.e3_keyed["y"]) && R.e3_keyed["x"] == 3, "A is gone, B's hold stays")
	// A hold with no key, a non-number, or an override is refused; a key on another rule is refused.
	TEST_ASSERT(!hold(R, STAT_E3_KEYED, 1, A), "a keyed stat needs a key")
	TEST_ASSERT(!hold(R, STAT_E3_KEYED, "n", A, key = "z"), "a keyed stat takes a number")
	TEST_ASSERT(!vars_write(R, "e3_keyed", list("z" = 1)), "a SUM_PER_KEY stat refuses an override")
	TEST_ASSERT(!hold(R, STAT_E3_SUM, 1, A, key = "z"), "key = belongs to a SUM_PER_KEY stat")
	// A datum source's death ends its holds.
	qdel(B)
	TEST_ASSERT(!length(R.e3_keyed), "the source's death released its keys: [json_encode(R.e3_keyed)]")

/datum/unit_test/dq_e3/rules_override_and_vv

/datum/unit_test/dq_e3/rules_override_and_vv/run_e3()
	var/obj/e3_rules/R = allocate(/obj/e3_rules)
	var/obj/e3_source/A = source()
	hold(R, STAT_E3_SUM, 3, A)
	TEST_ASSERT(hold_override(R, STAT_E3_SUM, 100, SRC_VV), "an override is placed")
	TEST_ASSERT_EQUAL(R.e3_sum, 100, "the override replaces the sum")
	hold(R, STAT_E3_SUM, 50, source())
	TEST_ASSERT_EQUAL(R.e3_sum, 100, "later holds do not beat it")
	release(R, STAT_E3_SUM, SRC_VV)
	TEST_ASSERT_EQUAL(R.e3_sum, 53, "released: the composition is back")
	// VV: vars_write on a stat var is a hold_override by the admin source.
	TEST_ASSERT(vars_write(R, "e3_max", 77), "vars_write places the override")
	TEST_ASSERT_EQUAL(R.e3_max, 77, "the stat reads the edited value")
	TEST_ASSERT(held_by_source(R, STAT_E3_MAX, SRC_VV), "it is a hold by SRC_VV")
	hold(R, STAT_E3_MAX, 500, A)
	TEST_ASSERT_EQUAL(R.e3_max, 77, "a contribution does not beat it")
	release(R, STAT_E3_MAX, SRC_VV)
	TEST_ASSERT_EQUAL(R.e3_max, 500, "taking it back restores the composition")
	// A SET stat has no override.
	TEST_ASSERT(!vars_write(R, "e3_set", list("z")), "a SET stat refuses an override")
	// A tracked var goes through its schema.
	var/obj/e1_schema/S = allocate(/obj/e1_schema)
	TEST_ASSERT(vars_write(S, "dial", 99), "vars_write on a schema var clamps")
	TEST_ASSERT_EQUAL(S.dial, 10, "clamped to the schema's maximum")
	TEST_ASSERT(!vars_write(S, "no_such_var", 1), "an unknown var is refused")

/datum/unit_test/dq_e3/formula_follows_what_it_reads

/datum/unit_test/dq_e3/formula_follows_what_it_reads/run_e3()
	var/obj/e3_rules/R = allocate(/obj/e3_rules)
	TEST_ASSERT_EQUAL(R.e3_formula, 2, "the formula computed at init: 1 * 2 + 0")
	R.set_e3_seed(5)
	TEST_ASSERT_EQUAL(R.e3_formula, 10, "a tracked var it reads recomputes it on the next line")
	hold(R, STAT_E3_SUM, 3, source())
	TEST_ASSERT_EQUAL(R.e3_formula, 13, "a stat it reads recomputes it on the next line")

// ---------------------------------------------------------------------------------------------------------------------
// Holds
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e3/hold_on_a_type_that_lacks_the_stat

/datum/unit_test/dq_e3/hold_on_a_type_that_lacks_the_stat/run_e3()
	var/obj/e3_machine/M = allocate(/obj/e3_machine)
	TEST_ASSERT_NULL(hold(M, STAT_E3_SUM, 1, source()), "the hold is refused")
	var/list/found = reports()
	TEST_ASSERT(length(found) == 1, "one report: [json_encode(found)]")
	TEST_ASSERT(findtext(found[1], "/obj/e3_machine") && findtext(found[1], "e3_sum"), "it names the type and the stat: [found[1]]")
	TEST_ASSERT_NULL(hold(M, STAT_E3_DRAW, 1, null), "a hold needs a source")
	TEST_ASSERT_NULL(hold(M, STAT_E3_DRAW, 1, "text source"), "text is not a source")
	TEST_ASSERT_EQUAL(M.e3_draw, 2, "nothing was placed")

/datum/unit_test/dq_e3/hold_dies_with_its_source_unless_it_outlives
	needs_clock = TRUE

/datum/unit_test/dq_e3/hold_dies_with_its_source_unless_it_outlives/run_e3()
	var/obj/e3_machine/M = allocate(/obj/e3_machine)
	var/obj/e3_source/timed = new
	var/obj/e3_source/untimed = new
	var/obj/e3_source/keeps = new
	hold(M, STAT_E3_DRAW, 5, timed, lasts = 400, clock = HOLD_CLOCK_WORLD)
	hold(M, STAT_E3_DRAW, 20, untimed)
	hold(M, STAT_E3_DRAW, 100, keeps, lasts = 40, clock = HOLD_CLOCK_WORLD, outlives_source = TRUE)
	TEST_ASSERT_EQUAL(M.e3_draw, 127, "2 + 5 + 20 + 100")
	qdel(untimed)
	TEST_ASSERT_EQUAL(M.e3_draw, 107, "an untimed hold dies with its source")
	qdel(timed)
	TEST_ASSERT_EQUAL(M.e3_draw, 102, "a timed hold dies with its source by default")
	qdel(keeps)
	TEST_ASSERT_EQUAL(M.e3_draw, 102, "outlives_source = TRUE keeps the hold after its source is deleted")
	test_time(50)
	TEST_ASSERT_EQUAL(M.e3_draw, 2, "and it ends on its own deadline")
	TEST_ASSERT_EQUAL(length(held_by(M, STAT_E3_DRAW)), 0, "nothing is held any more")

/datum/unit_test/dq_e3/hold_reapply_follows_the_stat
	needs_clock = TRUE

/datum/unit_test/dq_e3/hold_reapply_follows_the_stat/run_e3()
	var/obj/e3_machine/M = allocate(/obj/e3_machine)
	var/obj/e3_source/A = source()
	hold(M, STAT_E3_DRAW, 5, A, lasts = 100, clock = HOLD_CLOCK_WORLD)
	hold(M, STAT_E3_DRAW, 3, A, lasts = 50, clock = HOLD_CLOCK_WORLD)
	TEST_ASSERT_EQUAL(M.e3_draw, 7, "REAPPLY_MAX keeps the stronger value")
	TEST_ASSERT(hold_left(M, STAT_E3_DRAW, A) > 50, "and never shortens")
	hold_until(M, STAT_E3_DRAW, 1, A, until = scheduler_time_of(M) + 10, clock = HOLD_CLOCK_WORLD)
	TEST_ASSERT_EQUAL(M.e3_draw, 3, "hold_until replaces the value")
	TEST_ASSERT(hold_left(M, STAT_E3_DRAW, A) <= 10, "and may shorten")
	TEST_ASSERT_EQUAL(release_all(M, A), 1, "release_all counts what it released")
	TEST_ASSERT_EQUAL(M.e3_draw, 2, "released")

// ---------------------------------------------------------------------------------------------------------------------
// Contributions, gates and the settle rule
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e3/stat_var_is_current_on_the_next_line

/datum/unit_test/dq_e3/stat_var_is_current_on_the_next_line/run_e3()
	var/obj/e3_machine/M = allocate(/obj/e3_machine)
	TEST_ASSERT_EQUAL(M.e3_operable, TRUE, "operable at init")
	TEST_ASSERT_EQUAL(M.e3_draw, 2, "idle draw at init")
	M.set_e3_on(TRUE)
	TEST_ASSERT_EQUAL(M.e3_draw, 12, "a gated contribution counts the moment its condition flips")
	TEST_ASSERT_EQUAL(stat_marked_count(), 0, "no drain was needed")
	M.set_broken(TRUE)
	TEST_ASSERT_EQUAL(M.e3_operable, FALSE, "operable follows broken")
	TEST_ASSERT_EQUAL(M.e3_can_run, FALSE, "and the stat that reads operable follows it, in the same step")
	M.set_broken(FALSE)
	M.set_e3_on(FALSE)
	TEST_ASSERT_EQUAL(M.e3_operable, TRUE, "restored")
	TEST_ASSERT_EQUAL(M.e3_can_run, TRUE, "restored, read through the stat")
	TEST_ASSERT_EQUAL(M.e3_draw, 2, "gate closed")

/datum/unit_test/dq_e3/contributes_to_releases_on_relation_change

/datum/unit_test/dq_e3/contributes_to_releases_on_relation_change/run_e3()
	var/obj/e3_machine/one = allocate(/obj/e3_machine)
	var/obj/e3_machine/two = allocate(/obj/e3_machine)
	var/obj/e3_wire/W = allocate(/obj/e3_wire)
	rel_set(W, "plugged", one)
	TEST_ASSERT_EQUAL(one.e3_draw, 9, "the wire contributes 7 to what it names")
	rel_set(W, "plugged", two)
	TEST_ASSERT_EQUAL(one.e3_draw, 2, "the old target is released")
	TEST_ASSERT_EQUAL(two.e3_draw, 9, "the new one holds it")
	W.set_live(FALSE)
	TEST_ASSERT_EQUAL(two.e3_draw, 2, "the gate closing releases it")
	W.set_live(TRUE)
	TEST_ASSERT_EQUAL(two.e3_draw, 9, "and reopening restores it")
	qdel(W)
	TEST_ASSERT_EQUAL(two.e3_draw, 2, "the wire's deletion releases it")

/datum/unit_test/dq_e3/immunity_zeroes_a_status

/datum/unit_test/dq_e3/immunity_zeroes_a_status/run_e3()
	var/obj/e3_machine/M = allocate(/obj/e3_machine)
	var/obj/e3_machine/stoic/S = allocate(/obj/e3_machine/stoic)
	stat_status_at_least(S, STAT_E3_STUN, 3, 2)
	TEST_ASSERT_EQUAL(S.e3_stun, 0, "a type that is immune_to the status reads 0")
	TEST_ASSERT(!stat_has_status(S, STAT_E3_STUN), "and does not have it")
	stat_status_at_least(M, STAT_E3_STUN, 3, 2)
	TEST_ASSERT_EQUAL(M.e3_stun, 2, "a status is its intensity")
	TEST_ASSERT(stat_has_status(M, STAT_E3_STUN), "has_status")
	TEST_ASSERT_EQUAL(stat_status_remaining(M, STAT_E3_STUN), 3, "remaining is in units")
	M.set_broken(TRUE)
	TEST_ASSERT_EQUAL(M.e3_stun, 0, "a conditional immunity zeroes it the moment it holds")
	TEST_ASSERT_EQUAL(stat_status_remaining(M, STAT_E3_STUN), 3, "the hold itself keeps its clock")
	M.set_broken(FALSE)
	TEST_ASSERT_EQUAL(M.e3_stun, 2, "and it returns with the immunity gone")
	stat_status_adjust(M, STAT_E3_STUN, -1)
	TEST_ASSERT_EQUAL(stat_status_remaining(M, STAT_E3_STUN), 2, "adjust cuts the time")
	stat_status_set(M, STAT_E3_STUN, 5, 1)
	TEST_ASSERT(M.e3_stun == 1 && stat_status_remaining(M, STAT_E3_STUN) == 5, "set is exact")
	stat_status_end(M, STAT_E3_STUN)
	TEST_ASSERT_EQUAL(M.e3_stun, 0, "end releases")
	TEST_ASSERT(!stat_has_status(M, STAT_E3_STUN), "and it is gone")

// ---------------------------------------------------------------------------------------------------------------------
// The settle rule
// ---------------------------------------------------------------------------------------------------------------------

/// An APC with `count` loads naming it: list(apc, loads).
/datum/unit_test/dq_e3/proc/make_fan(count)
	var/obj/e3_apc/A = allocate(/obj/e3_apc)
	var/list/loads = list()
	for(var/i in 1 to count)
		var/obj/e3_load/L = allocate(/obj/e3_load)
		rel_set(L, "apc", A)
		loads += L
	return list(A, loads)

/datum/unit_test/dq_e3/settle_fan_out_is_marked_and_drained

/datum/unit_test/dq_e3/settle_fan_out_is_marked_and_drained/run_e3()
	var/list/fan = make_fan(50)
	var/obj/e3_apc/A = fan[1]
	var/list/loads = fan[2]
	var/obj/e3_load/first = loads[1]
	TEST_ASSERT_EQUAL(first.e3_powered, TRUE, "powered at init")
	A.set_channel_on(FALSE)
	TEST_ASSERT_EQUAL(stat_marked_count(), 50, "a collection edge marks its readers, it does not recompute them inline")
	TEST_ASSERT_EQUAL(first.e3_powered, TRUE, "until the marked drain runs")
	var/ran = stat_drain_marked(LANE_SIMULATION)
	TEST_ASSERT_EQUAL(ran, 50, "the drain recomputes each once")
	var/still_powered = 0
	for(var/obj/e3_load/L as anything in loads)
		if(L.e3_powered)
			still_powered++
	TEST_ASSERT_EQUAL(still_powered, 0, "every load settled after the drain")
	TEST_ASSERT_EQUAL(stat_marked_count(), 0, "nothing left marked")
	A.set_channel_on(TRUE)
	TEST_ASSERT_EQUAL(stat_drain_marked(LANE_SIMULATION), 50, "and back")
	TEST_ASSERT_EQUAL(first.e3_powered, TRUE, "restored")

/datum/unit_test/dq_e3/settle_marked_drain_spills_under_a_budget

/datum/unit_test/dq_e3/settle_marked_drain_spills_under_a_budget/run_e3()
	var/list/fan = make_fan(60)
	var/obj/e3_apc/A = fan[1]
	var/list/loads = fan[2]
	test_budget(LANE_SIMULATION, 20 * TEST_EVAL_COST)
	A.set_channel_on(FALSE)
	var/spills_before = test_spill_count()
	TEST_ASSERT_EQUAL(stat_drain_marked(LANE_SIMULATION), 20, "20 evaluations fit the budget")
	TEST_ASSERT(test_spill_count() > spills_before, "the pass says it spilled")
	TEST_ASSERT_EQUAL(stat_marked_count(), 40, "the rest waits")
	var/done = 0
	for(var/obj/e3_load/L as anything in loads)
		if(!L.e3_powered)
			done++
	TEST_ASSERT_EQUAL(done, 20, "only the drained ones changed")
	stat_drain_marked(LANE_SIMULATION)
	stat_drain_marked(LANE_SIMULATION)
	test_budget(LANE_SIMULATION, null)
	TEST_ASSERT_EQUAL(stat_marked_count(), 0, "three drains settle sixty")
	var/unsettled = 0
	for(var/obj/e3_load/L as anything in loads)
		if(L.e3_powered)
			unsettled++
	TEST_ASSERT_EQUAL(unsettled, 0, "every load settled")

/datum/unit_test/dq_e3/settle_reader_follows_its_relation

/datum/unit_test/dq_e3/settle_reader_follows_its_relation/run_e3()
	var/list/fan = make_fan(1)
	var/obj/e3_apc/A = fan[1]
	var/list/loads = fan[2]
	var/obj/e3_load/L = loads[1]
	var/obj/e3_apc/other = allocate(/obj/e3_apc)
	other.set_channel_on(FALSE)
	rel_set(L, "apc", other)
	TEST_ASSERT_EQUAL(L.e3_powered, FALSE, "naming another APC recomputes the reader on the entity itself (inline)")
	rel_set(L, "apc", A)
	TEST_ASSERT_EQUAL(L.e3_powered, TRUE, "and back")

/// The stat half of E0 proof 8 (the notice chain waits on E4): sixty lamps read the night system through its accessor, a flip marks them all, and
/// a 20-evaluation budget settles them over several drain points with none lost.
/datum/unit_test/dq_e3/settle_night_cascade_under_budget
	needs_clock = TRUE

/datum/unit_test/dq_e3/settle_night_cascade_under_budget/run_e3()
	var/list/lamps = list()
	for(var/i in 1 to 60)
		lamps += allocate(/obj/e0_fixture/lamp)
	var/obj/e0_fixture/lamp/sample = lamps[1]
	TEST_ASSERT_EQUAL(sample.e0_lamp_range, E0_LAMP_DAY_RANGE, "a lamp reads the day range at init")
	test_budget(LANE_SIMULATION, 20 * TEST_EVAL_COST)
	test_counters_reset()
	e0_flip_night(TRUE)
	TEST_ASSERT_EQUAL(stat_marked_count(), 60, "the flip marks every reader of the accessor (a system edge is never inline)")
	var/ticks = 0
	var/settled = FALSE
	for(var/i in 1 to 30)
		test_time(world.tick_lag)
		test_drain()
		ticks++
		settled = TRUE
		for(var/obj/e0_fixture/lamp/L as anything in lamps)
			if(L.e0_lamp_range != E0_LAMP_NIGHT_RANGE)
				settled = FALSE
				break
		if(settled)
			break
	test_budget(LANE_SIMULATION, null)
	e0_flip_night(FALSE)
	stat_drain_marked(LANE_SIMULATION)
	TEST_ASSERT(test_spill_count() > 0, "60 lamps against a 20-evaluation budget spill")
	TEST_ASSERT(ticks > 1, "so the cascade took more than one drain point")
	TEST_ASSERT(settled, "and it settled: no effect was lost")
	TEST_ASSERT_EQUAL(sample.e0_lamp_range, E0_LAMP_DAY_RANGE, "and the day returns")

/datum/unit_test/dq_e3/settle_hop_index_follows_deletions

/datum/unit_test/dq_e3/settle_hop_index_follows_deletions/run_e3()
	var/list/fan = make_fan(3)
	var/obj/e3_apc/A = fan[1]
	var/list/loads = fan[2]
	var/obj/e3_load/gone = loads[1]
	var/obj/e3_load/kept = loads[2]
	qdel(gone)
	A.set_channel_on(FALSE)
	TEST_ASSERT_EQUAL(stat_marked_count(), 2, "a deleted reader is no longer marked by the flip")
	stat_drain_marked(LANE_SIMULATION)
	TEST_ASSERT_EQUAL(kept.e3_powered, FALSE, "the others settle")
	// The target going: its readers lose the relation and read the default again.
	qdel(A)
	stat_drain_marked(LANE_SIMULATION)
	TEST_ASSERT_EQUAL(kept.e3_powered, TRUE, "with the APC gone a reader reads what an unnamed APC gives (powered)")
	TEST_ASSERT_EQUAL(stat_marked_count(), 0, "nothing is left marked")

/datum/unit_test/dq_e3/init_is_silent

/datum/unit_test/dq_e3/init_is_silent/run_e3()
	var/obj/e3_machine/watched = allocate(/obj/e3_machine)
	test_record(watched)
	var/obj/e3_machine/M = allocate(/obj/e3_machine)
	var/list/events = test_recorded()
	TEST_ASSERT_EQUAL(length(events), 0, "creating a machine whose stats have contributions publishes no delta")
	TEST_ASSERT_EQUAL(M.e3_draw, 2, "though its stats are computed")
	TEST_ASSERT_EQUAL(stat_marked_count(), 0, "and nothing is marked")

/datum/unit_test/dq_e3/base_stat_vars_and_virtual_stats

/datum/unit_test/dq_e3/base_stat_vars_and_virtual_stats/run_e3()
	var/obj/machinery/e3_probe/M = allocate(/obj/machinery/e3_probe)
	TEST_ASSERT_EQUAL(stat_value(M, STAT_OPERABLE), TRUE, "a virtual base stat (no var) reads its base through stat_value")
	hold(M, STAT_OPERABLE, null, source())
	TEST_ASSERT_EQUAL(stat_value(M, STAT_OPERABLE), FALSE, "and a hold on it vetoes")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.can_act, TRUE, "can_act is a var on a living mob")
	hold(H, STAT_CAN_ACT, null, source())
	TEST_ASSERT_EQUAL(H.can_act, FALSE, "a veto from any source clears it")
	TEST_ASSERT_EQUAL(H.acts_via, ORIGIN_ALL, "acts_via starts as every origin")
	hold(H, STAT_ACTS_VIA, ORIGIN_CLICK | ORIGIN_UI, source())
	TEST_ASSERT_EQUAL(H.acts_via, ORIGIN_CLICK | ORIGIN_UI, "MASK_AND narrows it")
