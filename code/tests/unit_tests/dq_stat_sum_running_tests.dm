// The running total of a SUM stat's rows (code/engine/stats/store.dm, stat_record.sum_cache): an area's demand stats hold a row per machine, and each
// machine joining or moving used to re-add every row. The total is kept as rows come and go and must equal the full sum at every read.

/// The full sum of `A`'s rows for demand stat `stat_id`, computed with no running total (the reference).
/proc/dq_test_full_stat_sum(area/A, stat_id)
	var/datum/stat_def/def = stat_def_of(stat_id)
	var/datum/stat_record/rec = A.rx?.stats
	if(!rec)
		return def.base
	var/saved = rec.sum_cache
	rec.sum_cache = null
	. = stat_compute(A, def, stat_type_of(A), rec)
	rec.sum_cache = saved

/// Random adds, changes and removals on one area's demand stat; after each step the stat's value is the full recompute's, exactly.
/datum/unit_test/dq_stat_sum_running_total_parity

/datum/unit_test/dq_stat_sum_running_total_parity/Run()
	var/area/target
	for(var/area/A)
		if(!length(A.power_machines))
			continue
		target = A
		break
	TEST_ASSERT_NOTNULL(target, "the test map has an area with machines")
	var/datum/stat_def/def = stat_def_of(STAT_DEMAND_EQUIP)
	var/list/sources = list()
	for(var/i in 1 to 24)
		sources += allocate(/obj/item/dq_rule_test)
	var/list/placed = list()
	rand_seed(7)
	for(var/step in 1 to 600)
		var/obj/item/source = pick(sources)
		var/roll = rand(1, 10)
		var/value
		// Mostly whole watts; sometimes a fraction or a negative, which take the running total out of play until the next full sum.
		if(roll <= 7)
			value = rand(0, 5000)
		else if(roll == 8)
			value = rand(0, 5000) + 0.5
		else if(roll == 9)
			value = -rand(1, 50)
		else
			value = rand(0, 5000)
		if(placed[source] && rand(1, 3) == 1)
			release(target, STAT_DEMAND_EQUIP, source)
			placed -= source
		else
			stat_row_set(target, def, source, value, PRIORITY_DEFAULT, null)
			placed[source] = TRUE
		var/expected = dq_test_full_stat_sum(target, STAT_DEMAND_EQUIP)
		TEST_ASSERT_EQUAL(stat_value(target, STAT_DEMAND_EQUIP), expected, "step [step]: the stat reads the full sum")
	for(var/obj/item/source in placed)
		release(target, STAT_DEMAND_EQUIP, source)
	TEST_ASSERT_EQUAL(stat_value(target, STAT_DEMAND_EQUIP), dq_test_full_stat_sum(target, STAT_DEMAND_EQUIP), "with the test rows released the total is the machines' again")

/// The running total is really in use for whole non-negative rows, and leaves play on a row it cannot hold.
/datum/unit_test/dq_stat_sum_running_total_engages

/datum/unit_test/dq_stat_sum_running_total_engages/Run()
	var/area/target
	for(var/area/A)
		if(length(A.power_machines))
			target = A
			break
	TEST_ASSERT_NOTNULL(target, "the test map has an area with machines")
	var/datum/stat_def/def = stat_def_of(STAT_DEMAND_EQUIP)
	var/obj/item/first = allocate(/obj/item/dq_rule_test)
	var/obj/item/second = allocate(/obj/item/dq_rule_test)
	stat_row_set(target, def, first, 100, PRIORITY_DEFAULT, null)
	var/datum/stat_record/rec = target.rx.stats
	TEST_ASSERT(rec.sum_cache?["[def.skey]"], "whole rows keep a running total")
	stat_row_set(target, def, second, 25.5, PRIORITY_DEFAULT, null)
	TEST_ASSERT(!rec.sum_cache?["[def.skey]"], "a fractional row drops it")
	release(target, STAT_DEMAND_EQUIP, second)
	stat_row_set(target, def, first, 120, PRIORITY_DEFAULT, null)
	TEST_ASSERT(rec.sum_cache?["[def.skey]"], "whole rows again rebuild it")
	release(target, STAT_DEMAND_EQUIP, first)

/// Booted map: every area's demand stats equal the full recompute of their rows.
/datum/unit_test/dq_stat_sum_running_total_booted_map

/datum/unit_test/dq_stat_sum_running_total_booted_map/Run()
	var/checked = 0
	for(var/area/A)
		for(var/stat_id in list(STAT_DEMAND_EQUIP, STAT_DEMAND_LIGHT, STAT_DEMAND_ENVIRON))
			TEST_ASSERT_EQUAL(stat_value(A, stat_id), dq_test_full_stat_sum(A, stat_id), "[A.type] [stat_id]: the demand is the full sum of its rows")
			checked++
	TEST_ASSERT(checked > 0, "areas were checked")
