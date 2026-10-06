// Kernel measurement (unified plan step 2, code/controllers/measure/): the system rule, the roll-up of a
// behaviour's cost to its system, the histogram percentiles, overrun attribution, the flight recorder's ring and
// the input latency record. Tests that need a scheduler use the OM harness (om_test_begin(), scheduler_advance()),
// whose scheduler charges its own meter; the rest build meters directly, so nothing here touches the live one
// except where a test swaps it in on purpose and puts it back before asserting.

/datum/om_test_entity/var/km_ticks = 0

/// Charged to "km_fake_system" through its system_key.
/datum/om/behaviour/test/km_fake
	every = 1 SECONDS
	system_key = "km_fake_system"

/datum/om/behaviour/test/km_fake/tick(datum/om_test_entity/E, dt)
	E.km_ticks++

/// Holds the tick until it is over budget: a real overrun charged to "km_burner_system".
/datum/om/behaviour/test/km_burner
	every = 1 SECONDS
	system_key = "km_burner_system"

/datum/om/behaviour/test/km_burner/tick(datum/om_test_entity/E, dt)
	// At least a third of a tick of real work, and on to 120% so the tick is over budget wherever it started.
	var/target = max(TICK_USAGE + 30, 120)
	CONSUME_UNTIL(target)

/// The row of a km_report_systems() list for `key`, or null.
/proc/km_test_row(list/rows, key)
	for(var/list/row as anything in rows)
		if(row["key"] == key)
			return row

/// Registers a test system and returns its index.
/proc/km_test_system(key, kind = KM_KIND_OM, lane = LANE_SIMULATION)
	return km_systems().index_for(key, kind, lane)

// ---------------------------------------------------------------- the system rule

/datum/unit_test/dq_km_system_key_rule

/datum/unit_test/dq_km_system_key_rule/Run()
	// Rule 2: a code folder's row.
	var/list/known = km_system_prefixes()
	TEST_ASSERT(length(known) >= 2, "the prefix table is built (it has [length(known)] rows)")
	TEST_ASSERT_EQUAL(km_system_key_for_path(/datum/om/pipeline/machine), "machines", "the machine pipeline")
	TEST_ASSERT_EQUAL(km_system_key_for_path(/datum/om/behaviour/internal/timers), "om_core", "the scheduler's own behaviours")
	// Rule 3: the family fallback.
	TEST_ASSERT_EQUAL(km_system_key_for_path("/datum/om/behaviour/world/statpanels"), "statpanels", "world/<x> is <x> (as text: the lane is gone)")
	TEST_ASSERT_EQUAL(km_system_key_for_path(/datum/om/behaviour/test/every_second), "test", "any other behaviour is its first segment")
	// A row's prefix matches at a segment (or a family suffix), never in the middle of a name.
	TEST_ASSERT_EQUAL(km_system_key_for_path("/datum/om/pipeline/lifeboat/x"), "lifeboat", "life must not swallow lifeboat")
	return

/datum/unit_test/dq_km_every_behaviour_has_a_system

/datum/unit_test/dq_km_every_behaviour_has_a_system/Run()
	var/datum/om/registry/reg = om_registry()
	var/datum/km_systems/systems = km_systems()
	TEST_ASSERT(length(reg.behaviours) > 0, "the registry has behaviours")
	for(var/datum/om/behaviour/B as anything in reg.behaviours)
		TEST_ASSERT(B.system_idx >= 1 && B.system_idx <= systems.count(), "[B.type] is bound to a system (system_idx [B.system_idx])")
		var/key = systems.key_of(B.system_idx)
		TEST_ASSERT(length(key) && key != "?", "[B.type] resolves to a system key")
		if(B.system_key)
			TEST_ASSERT_EQUAL(key, B.system_key, "[B.type]: an explicit system_key wins")
		else if(!istype(B, /datum/om/behaviour/inline))
			// KM_SYS_OTHER only when the registry ran out of room.
			TEST_ASSERT(B.system_idx != KM_SYS_OTHER, "[B.type] fell into the overflow system: raise KM_MAX_SYSTEMS")
			// The registry binds at boot, inside global initialisation: what it bound is what the rule says now.
			TEST_ASSERT_EQUAL(key, km_system_key_for_path(B.type), "[B.type] was bound by the rule as it stands")
	// Inline behaviours (a bundle's reacts / ticks / events rows) carry their bundle's name.
	var/inline_seen = 0
	for(var/datum/om/behaviour/inline/B in reg.behaviours)
		inline_seen++
		TEST_ASSERT(length(B.system_key), "an inline behaviour ([B.name]) has its bundle's name as its system")
	TEST_ASSERT(inline_seen > 0, "there are inline behaviours to check")
	// Every type the folder rows name is real and owns at least one registered behaviour: a stale row would
	// quietly stop attributing a folder.
	var/list/rows = km_system_rows()
	for(var/key in rows)
		for(var/path in rows[key])
			TEST_ASSERT(ispath(path), "row [key]: [path] is not a type")
			var/owns = FALSE
			for(var/datum/om/behaviour/B as anything in reg.behaviours)
				if(ispath(B.type, path))
					owns = TRUE
					break
			TEST_ASSERT(owns, "row [key]: no registered behaviour is a [path]")
	return

// ---------------------------------------------------------------- histogram

/datum/unit_test/dq_km_histogram_bins

/datum/unit_test/dq_km_histogram_bins/Run()
	TEST_ASSERT_EQUAL(km_hist_lower(1), 0, "bin 1 starts at zero")
	TEST_ASSERT(abs(km_hist_lower(2) - KM_HIST_MIN_MS) < 0.0001, "bin 2 starts at the minimum")
	TEST_ASSERT(abs(km_hist_lower(KM_HIST_BINS) - 655.36) < 0.5, "the last closed edge is 0.02 * 2^15 ms (got [km_hist_lower(KM_HIST_BINS)])")
	var/tiny = 0.005
	var/small = 0.021
	var/tick = 50
	var/huge = 100000
	TEST_ASSERT_EQUAL(KM_HIST_BIN(tiny), 1, "under the minimum is bin 1")
	TEST_ASSERT_EQUAL(KM_HIST_BIN(small), 2, "just over the minimum is bin 2")
	TEST_ASSERT_EQUAL(KM_HIST_BIN(huge), KM_HIST_BINS, "anything huge lands in the last bin")
	// A value falls between its bin's edges.
	var/bin = KM_HIST_BIN(tick)
	TEST_ASSERT(km_hist_lower(bin) <= tick && tick < km_hist_upper(bin), "50 ms is inside bin [bin] [km_hist_lower(bin)]..[km_hist_upper(bin)]")
	return

/datum/unit_test/dq_km_histogram_percentiles

/datum/unit_test/dq_km_histogram_percentiles/Run()
	var/datum/km_hist/H = new
	TEST_ASSERT_EQUAL(H.percentile(0.99), 0, "an empty histogram reads 0")
	for(var/i in 1 to 90)
		H.add(1.0)
	for(var/i in 1 to 9)
		H.add(10.0)
	H.add(100.0)
	TEST_ASSERT_EQUAL(H.count, 100, "100 samples")
	var/p50 = H.percentile(0.50)
	var/p95 = H.percentile(0.95)
	var/p99 = H.percentile(0.99)
	// The bins are sqrt(2) wide, so a percentile is exact to one bin, and interpolation stays inside it.
	TEST_ASSERT(p50 >= 0.9 && p50 <= 1.3, "p50 of a 90% mass at 1 ms is about 1 ms (got [p50])")
	TEST_ASSERT(p95 >= 7 && p95 <= 14.2, "p95 lands in the 10 ms bin (got [p95])")
	TEST_ASSERT(p99 >= 7 && p99 <= 14.2, "p99 is the 99th of 100 samples, still in the 10 ms bin, not the 100 ms outlier (got [p99])")
	TEST_ASSERT_EQUAL(H.max_seen, 100, "the exact max is kept")
	TEST_ASSERT_EQUAL(H.min_seen, 1, "the exact min is kept")
	TEST_ASSERT(H.percentile(1) > 50, "the top rank reaches the outlier (got [H.percentile(1)])")
	// A bin of identical samples reads back as that value (clamped to min and max), not a bin edge.
	var/datum/km_hist/same = new
	for(var/i in 1 to 40)
		same.add(5.0)
	TEST_ASSERT_EQUAL(same.percentile(0.5), 5, "identical samples read back exactly")
	TEST_ASSERT_EQUAL(same.percentile(0.99), 5, "identical samples read back exactly at p99")
	H.reset()
	TEST_ASSERT_EQUAL(H.count, 0, "reset empties it")
	TEST_ASSERT_EQUAL(H.percentile(0.5), 0, "and it reads 0 again")
	// The single precision guard: 100 * 0.99 must be rank 99, not 100.
	var/datum/km_hist/ranks = new
	for(var/i in 1 to 99)
		ranks.add(1.0)
	ranks.add(300.0)
	TEST_ASSERT(ranks.percentile(0.99) < 2, "p99 of 99 small and one huge sample is the small ones (got [ranks.percentile(0.99)])")
	return

/datum/unit_test/dq_km_depth_histogram

/datum/unit_test/dq_km_depth_histogram/Run()
	var/datum/km_depth_hist/D = new
	for(var/usage in list(0, 4.9, 5, 50, 101, 250))
		D.add(usage)
	TEST_ASSERT_EQUAL(D.count, 6, "six samples")
	TEST_ASSERT_EQUAL(D.bins[1], 2, "0 and 4.9 share the first 5% bin")
	TEST_ASSERT_EQUAL(D.bins[2], 1, "5 opens the second")
	TEST_ASSERT_EQUAL(D.bins[KM_DEPTH_BINS], 2, "everything over 100% shares the last bin")
	TEST_ASSERT_EQUAL(D.percentile(0.5), 10, "the median is in the second bin, whose upper edge is 10%")
	return

/datum/unit_test/dq_km_system_stats_totals

/datum/unit_test/dq_km_system_stats_totals/Run()
	var/datum/system_stats/S = new("km_totals", KM_KIND_OM)
	for(var/i in 1 to 50)
		S.record(30, FALSE, 0)
	TEST_ASSERT_EQUAL(S.ticks, 50, "50 ticks recorded")
	TEST_ASSERT_EQUAL(S.ms_total(), 1500, "1500 ms in total")
	TEST_ASSERT_EQUAL(S.ms_hi, 1000, "the total flushed a whole KM_FLUSH_MS into its high part")
	TEST_ASSERT_EQUAL(S.ms_lo, 500, "and kept the rest low")
	S.record(0.05, TRUE, 12)
	TEST_ASSERT_EQUAL(S.overrun_ms, 0.05, "an overrun tick's ms is credited")
	TEST_ASSERT_EQUAL(S.late_max, 12, "the worst lateness is kept")
	S.record(1, FALSE, 3)
	TEST_ASSERT_EQUAL(S.late_max, 12, "a smaller lateness does not lower it")
	qdel(S)
	return

// ---------------------------------------------------------------- rollup

/datum/unit_test/om/dq_km_rollup_charges_a_fake_behaviour

/datum/unit_test/om/dq_km_rollup_charges_a_fake_behaviour/run_om(list/made)
	var/datum/om/behaviour/fake = om_registry().behaviour(/datum/om/behaviour/test/km_fake)
	TEST_ASSERT_NOTNULL(fake, "the fake behaviour is registered")
	var/idx = km_systems().index_by_key["km_fake_system"]
	TEST_ASSERT_EQUAL(fake.system_idx, idx, "its system_key bound it to km_fake_system")
	TEST_ASSERT(fake.id < OM_MAX_STAT_TYPES, "its counters are individually attributable (id [fake.id])")
	var/datum/tick_meter/meter = sched.meter
	TEST_ASSERT(meter != km_meter(), "a test scheduler charges its own meter, not the live one")

	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/km_fake)
	scheduler_advance(3)
	TEST_ASSERT(E.km_ticks >= 2, "the fake behaviour ran ([E.km_ticks])")
	TEST_ASSERT(meter.tick_ms[idx] > 0, "its run was charged to its system this tick")
	TEST_ASSERT(meter.n_touched >= 1, "a system is marked touched")

	// A known charge on top, then close the tick and read the report.
	var/before = meter.tick_ms[idx]
	meter.charge(idx, 12.5)
	TEST_ASSERT(abs(meter.tick_ms[idx] - (before + 12.5)) < 0.001, "charges add up within a tick")
	meter.end_tick(50, 0)
	var/list/rows = km_report_systems(meter.live, sched)
	var/list/row = km_test_row(rows, "km_fake_system")
	TEST_ASSERT_NOTNULL(row, "the report has a row for the fake system")
	TEST_ASSERT_EQUAL(row["ticks"], 1, "the system was charged in one closed tick")
	TEST_ASSERT(row["ms_total"] >= 12.5, "its ms include the known charge (got [row["ms_total"]])")
	TEST_ASSERT(row["runs"] >= 2, "runs are rolled up from the behaviour's counters (got [row["runs"]])")
	TEST_ASSERT_EQUAL(row["behaviours"], 1, "one behaviour belongs to the system")
	TEST_ASSERT(row["p99_ms"] >= 12.5 * 0.7, "p99 reflects the tick (got [row["p99_ms"]])")
	TEST_ASSERT_EQUAL(meter.n_touched, 0, "closing the tick clears the touched list")
	TEST_ASSERT_EQUAL(meter.tick_ms[idx], 0, "and the tick's charge")
	// Another behaviour's cost never lands on this system.
	var/datum/om/behaviour/every = om_registry().behaviour(/datum/om/behaviour/test/every_second)
	TEST_ASSERT(every.system_idx != idx, "a different behaviour is a different system")

	// Counters are deltas against a set's base: a window opened now sees only what runs after.
	var/datum/km_stats_set/window = meter.open_set(sched)
	var/runs_before = row["runs"]
	scheduler_advance(2)
	meter.end_tick(50, 0)
	meter.close_set(window)
	var/list/window_row = km_test_row(km_report_systems(window, sched), "km_fake_system")
	TEST_ASSERT_NOTNULL(window_row, "the window saw the fake system run")
	TEST_ASSERT(window_row["runs"] >= 1 && window_row["runs"] < runs_before + 5, "the window counts only the runs since it opened (got [window_row["runs"]])")
	TEST_ASSERT_EQUAL(window_row["ticks"], 1, "and only the ticks since")
	qdel(window)

// ---------------------------------------------------------------- overrun attribution

/datum/unit_test/dq_km_overrun_attribution

/datum/unit_test/dq_km_overrun_attribution/Run()
	var/a = km_test_system("km_test_a")
	var/b = km_test_system("km_test_b")
	var/c = km_test_system("km_test_c")
	var/d = km_test_system("km_test_d")
	var/datum/tick_meter/M = new(16)
	// Charged out of order, so the top three are found rather than the first three.
	M.charge(d, 3)
	M.charge(b, 18)
	M.charge(a, 40)
	M.charge(c, 9)
	M.charge(b, 1)
	M.input_ms = 0.4
	M.end_tick(143, 24)
	TEST_ASSERT_EQUAL(M.total_overruns, 1, "usage over 100 is an overrun")
	TEST_ASSERT_EQUAL(M.streak, 1, "the streak starts")
	var/list/top = M.last_overrun_top
	TEST_ASSERT_EQUAL(length(top), KM_TOP_N, "the top three are recorded")
	TEST_ASSERT_EQUAL(top[1]["key"], "km_test_a", "the biggest system first")
	TEST_ASSERT_EQUAL(top[2]["key"], "km_test_b", "then the next: its two charges added up")
	TEST_ASSERT_EQUAL(top[3]["key"], "km_test_c", "then the third; the fourth is left out")
	TEST_ASSERT(abs(top[2]["ms"] - 19) < 0.01, "a system's charges sum within the tick (got [top[2]["ms"]])")
	var/line = M.last_overrun_line
	TEST_ASSERT(findtext(line, "TICK 143%"), "the line names the tick usage: [line]")
	TEST_ASSERT(findtext(line, "km_test_a 40ms"), "and the biggest system with its ms: [line]")
	TEST_ASSERT(findtext(line, "km_test_b 19ms"), "and the next: [line]")
	TEST_ASSERT(!findtext(line, "km_test_d"), "and not the fourth: [line]")
	TEST_ASSERT(findtext(line, "BYOND maptick"), "and the maptick: [line]")
	TEST_ASSERT(findtext(line, "input 0.4ms"), "and the input cost: [line]")
	TEST_ASSERT(findtext(line, "streak 1"), "and the streak: [line]")
	// The tick's top three are also in the flight recorder entry.
	var/list/entries = M.recorded_entries()
	TEST_ASSERT_EQUAL(length(entries), 1, "one tick recorded")
	var/list/entry = entries[1]
	TEST_ASSERT_EQUAL(entry[3], 143, "the entry holds the usage")
	TEST_ASSERT_EQUAL(entry[4], 24, "the maptick")
	TEST_ASSERT(abs(entry[5] - 0.4) < 0.001, "the input cost")
	var/list/keys = entry[7]
	TEST_ASSERT_EQUAL(jointext(keys, ","), "km_test_a,km_test_b,km_test_c", "and the top systems in order")

	// A second overrun: the streak grows, and the systems' overrun shares follow the ms they spent on overruns.
	M.charge(b, 30)
	M.charge(a, 10)
	M.end_tick(160, 0)
	TEST_ASSERT_EQUAL(M.streak, 2, "consecutive overruns extend the streak")
	var/list/rows = km_report_systems(M.live, null)
	var/list/row_a = km_test_row(rows, "km_test_a")
	var/list/row_b = km_test_row(rows, "km_test_b")
	TEST_ASSERT_NOTNULL(row_a, "a has a row")
	TEST_ASSERT_NOTNULL(row_b, "b has a row")
	TEST_ASSERT(abs(row_a["overrun_ms"] - 50) < 0.01, "a spent 40 + 10 ms on overruns (got [row_a["overrun_ms"]])")
	TEST_ASSERT(abs(row_b["overrun_ms"] - 49) < 0.01, "b spent 19 + 30 ms on overruns (got [row_b["overrun_ms"]])")
	TEST_ASSERT(row_a["overrun_share"] > row_b["overrun_share"], "a has the larger overrun share")
	TEST_ASSERT_EQUAL(row_a["overrun_top_ticks"], 2, "a was in the top three of both overruns")
	TEST_ASSERT_EQUAL(km_test_row(rows, "km_test_d")["overrun_top_ticks"], 0, "d never was")
	TEST_ASSERT_EQUAL(rows[1]["key"], "km_test_a", "the report is sorted by overrun share")
	M.end_tick(60, 0)
	TEST_ASSERT_EQUAL(M.streak, 0, "a tick within budget ends the streak")
	TEST_ASSERT_EQUAL(M.live.max_streak, 2, "the set remembers the longest streak")
	TEST_ASSERT_EQUAL(M.live.overruns, 2, "and counts the overruns")
	qdel(M)
	return

/datum/unit_test/dq_km_overrun_log_line_is_rate_limited

/datum/unit_test/dq_km_overrun_log_line_is_rate_limited/Run()
	var/a = km_test_system("km_test_a")
	var/datum/tick_meter/M = new(16)
	M.log_overruns = TRUE
	var/logged_before = length(GLOB.admin_activities)
	M.charge(a, 60)
	M.end_tick(160, 0)
	TEST_ASSERT_EQUAL(length(GLOB.admin_activities), logged_before + 1, "an overrun writes one admin-log line")
	TEST_ASSERT_EQUAL(GLOB.admin_activities[length(GLOB.admin_activities)], M.last_overrun_line, "and it is the line the meter built")
	// A sustained overload: every overrun of the first KM_LOG_FULL_STREAK is logged, then one per KM_LOG_MIN_GAP.
	for(var/i in 2 to KM_LOG_FULL_STREAK + 5)
		M.charge(a, 60)
		M.end_tick(160, 0)
	var/logged = length(GLOB.admin_activities) - logged_before
	TEST_ASSERT_EQUAL(logged, KM_LOG_FULL_STREAK, "a long streak stops flooding the log after [KM_LOG_FULL_STREAK] lines (got [logged])")
	TEST_ASSERT_EQUAL(M.suppressed_logs, 5, "and counts what it held back")
	TEST_ASSERT_EQUAL(M.total_overruns, KM_LOG_FULL_STREAK + 5, "every overrun is still counted")
	// The meter's default in a test build is silent.
	var/datum/tick_meter/quiet = new(16)
	TEST_ASSERT(!quiet.log_overruns, "test builds do not log overruns unless a test asks")
	qdel(quiet)
	qdel(M)
	return

/datum/unit_test/om/dq_km_forced_overrun_names_the_burner

/datum/unit_test/om/dq_km_forced_overrun_names_the_burner/run_om(list/made)
	var/datum/tick_meter/meter = sched.meter
	var/burner_idx = km_systems().index_by_key["km_burner_system"]
	TEST_ASSERT_NOTNULL(burner_idx, "the burner's system exists")
	var/datum/om_test_entity/quiet = entity(made)
	om_attach(quiet, /datum/om/behaviour/test/km_fake)
	var/datum/om_test_entity/burner = entity(made)
	om_attach(burner, /datum/om/behaviour/test/km_burner)
	// The presentation lane also runs the refresh drift audit, strictly on every frame in a test
	// build (a few ms each); pause it for this pass so the burner is measured against its peers.
	set_global("refresh_sweep_list", list())
	// One pass: the burner holds the tick over budget, the quiet behaviour costs almost nothing.
	scheduler_advance(1)
	var/usage = TICK_USAGE
	meter.end_tick(usage, 6)
	TEST_ASSERT(usage > KM_OVERRUN_USAGE, "the burner really overran the tick (usage [usage])")
	TEST_ASSERT_EQUAL(meter.total_overruns, 1, "the tick counts as an overrun")
	var/list/top = meter.last_overrun_top
	TEST_ASSERT(length(top) >= 1, "the overrun has attribution")
	TEST_ASSERT_EQUAL(top[1]["key"], "km_burner_system", "the burner is the top system, from inside the scheduler, not a lump: [json_encode(top)]")
	TEST_ASSERT(top[1]["ms"] > 1, "and it is charged real time (got [top[1]["ms"]] ms)")
	TEST_ASSERT(findtext(meter.last_overrun_line, "km_burner_system"), "the line names it: [meter.last_overrun_line]")
	var/list/entry = meter.recorded_entries()[1]
	var/list/keys = entry[7]
	TEST_ASSERT_EQUAL(keys[1], "km_burner_system", "the flight recorder entry names it too")
	TEST_ASSERT(entry[3] > KM_OVERRUN_USAGE, "with the tick's usage")

// ---------------------------------------------------------------- flight recorder

/datum/unit_test/dq_km_flight_recorder_wraps_around

/datum/unit_test/dq_km_flight_recorder_wraps_around/Run()
	// A small ring first, where the arithmetic is easy to follow.
	var/datum/tick_meter/small = new(8)
	for(var/i in 1 to 13)
		small.charge(KM_SYS_OM_CORE, i)
		small.end_tick(i * 10, i)
	TEST_ASSERT_EQUAL(small.ring_count, 8, "a full ring holds its length")
	TEST_ASSERT_EQUAL(small.ring_pos, 5, "13 writes into 8 slots leave the write position at 5")
	var/list/entries = small.recorded_entries()
	TEST_ASSERT_EQUAL(length(entries), 8, "eight entries read back")
	TEST_ASSERT_EQUAL(entries[1][3], 60, "the oldest is tick 6 (usage 60)")
	TEST_ASSERT_EQUAL(entries[8][3], 130, "the newest is tick 13 (usage 130)")
	for(var/n in 1 to 8)
		TEST_ASSERT_EQUAL(entries[n][3], (n + 5) * 10, "entry [n] is in write order across the wrap")
		TEST_ASSERT_EQUAL(entries[n][4], n + 5, "with its own maptick")
		var/list/keys = entries[n][7]
		TEST_ASSERT_EQUAL(keys[1], KM_KEY_OM_CORE, "and its top system")
		var/list/mss = entries[n][8]
		TEST_ASSERT_EQUAL(mss[1], n + 5, "and that system's ms")
	qdel(small)

	// A partly filled ring reads from the start.
	var/datum/tick_meter/partial = new(8)
	for(var/i in 1 to 3)
		partial.end_tick(i, 0)
	TEST_ASSERT_EQUAL(partial.ring_count, 3, "a partly filled ring holds what was written")
	TEST_ASSERT_EQUAL(partial.recorded_entries()[1][3], 1, "oldest first")
	qdel(partial)

	// The real size: KM_RING_LEN ticks, then 37 more.
	var/datum/tick_meter/full = new
	for(var/i in 1 to KM_RING_LEN + 37)
		full.end_tick(i % 100, 0)
	TEST_ASSERT_EQUAL(full.ring_len, KM_RING_LEN, "the ring is KM_RING_LEN ticks")
	TEST_ASSERT_EQUAL(full.ring_count, KM_RING_LEN, "and stays that size")
	var/list/held = full.recorded_entries()
	TEST_ASSERT_EQUAL(length(held), KM_RING_LEN, "every entry reads back")
	TEST_ASSERT_EQUAL(held[1][3], 38 % 100, "the oldest is tick 38")
	TEST_ASSERT_EQUAL(held[KM_RING_LEN][3], (KM_RING_LEN + 37) % 100, "the newest is the last written")
	var/list/overruns_only = full.recorded_entries(TRUE)
	TEST_ASSERT_EQUAL(length(overruns_only), 0, "no tick here went over 100, so the overrun filter is empty")
	qdel(full)
	return

// ---------------------------------------------------------------- input latency

/datum/unit_test/dq_km_input_latency_record

/datum/unit_test/dq_km_input_latency_record/Run()
	var/datum/tick_meter/M = new(8)
	// Verbs that waited: 90 for ~1 ms, 9 for ~10 ms, one for 100 ms; clicks near zero.
	for(var/i in 1 to 90)
		M.record_input(KM_INPUT_VERB, 1, 20)
	for(var/i in 1 to 9)
		M.record_input(KM_INPUT_VERB, 10, 60)
	M.record_input(KM_INPUT_VERB, 100, 95)
	for(var/i in 1 to 200)
		M.record_input(KM_INPUT_CLICK, 0.005, 5)
	var/list/report = km_report_input(M.live)
	TEST_ASSERT_EQUAL(report["samples"], 300, "300 inputs recorded")
	TEST_ASSERT_EQUAL(report["clicks"], 200, "200 of them clicks")
	TEST_ASSERT_EQUAL(report["verbs_run"], 100, "and 100 verbs")
	// 300 samples: 200 near zero, 90 at 1 ms, 9 at 10 ms, 1 at 100 ms. The 99th percentile is rank 297: in the 10 ms group.
	TEST_ASSERT(report["wait_p50_ms"] < 0.05, "the median input barely waited (got [report["wait_p50_ms"]])")
	TEST_ASSERT(report["wait_p95_ms"] >= 0.7 && report["wait_p95_ms"] <= 1.5, "p95 is the 1 ms group (got [report["wait_p95_ms"]])")
	TEST_ASSERT(report["wait_p99_ms"] >= 7 && report["wait_p99_ms"] <= 14.2, "p99 is the 10 ms group (got [report["wait_p99_ms"]])")
	TEST_ASSERT(abs(report["wait_max_ms"] - 100) < 0.01, "the worst wait is exact (got [report["wait_max_ms"]])")
	TEST_ASSERT(report["click_p99_ms"] < 0.05, "clicks alone waited nothing (got [report["click_p99_ms"]])")
	TEST_ASSERT(report["verb_p99_ms"] >= 7, "verbs alone waited (got [report["verb_p99_ms"]])")
	var/tick_ms = world.tick_lag * 100
	TEST_ASSERT(abs(report["wait_p99_ticks"] - report["wait_p99_ms"] / tick_ms) < 0.001, "the wait is also given in ticks")
	TEST_ASSERT(report["depth_p50"] <= 10, "most input ran near the start of the tick (p50 [report["depth_p50"]]%)")
	TEST_ASSERT(report["depth_p95"] >= 20, "some ran later (p95 [report["depth_p95"]]%)")
	// Queue depth.
	M.verb_queued(3)
	M.verb_queued(7)
	M.verb_queued(2)
	M.verb_direct()
	report = km_report_input(M.live)
	TEST_ASSERT_EQUAL(report["queue_hwm"], 7, "the queue high-water mark is the deepest it got")
	TEST_ASSERT_EQUAL(report["verbs_queued"], 3, "three verbs were queued")
	TEST_ASSERT_EQUAL(report["verbs_direct"], 1, "one ran at once")
	// A window records alongside and clears on its own.
	var/datum/km_stats_set/window = M.open_set()
	M.record_input(KM_INPUT_CLICK, 2, 30)
	TEST_ASSERT_EQUAL(window.input.wait.count, 1, "the window saw the input recorded after it opened")
	TEST_ASSERT_EQUAL(M.live.input.wait.count, 301, "and the live set saw it too")
	M.close_set(window)
	M.record_input(KM_INPUT_CLICK, 2, 30)
	TEST_ASSERT_EQUAL(window.input.wait.count, 1, "a closed window stops recording")
	qdel(window)
	M.live.reset()
	TEST_ASSERT_EQUAL(km_report_input(M.live)["samples"], 0, "reset clears the record")
	qdel(M)
	return

/// The hooks in the input inbox and atom/Click reach the meter: swaps a fresh one in for the length of the test.
/datum/unit_test/dq_km_input_hooks_record_real_paths

/datum/unit_test/dq_km_input_hooks_record_real_paths/Run()
	var/mob/observer/dead/clicker = allocate(/mob/observer/dead, run_loc_floor_bottom_left)
	var/datum/tick_meter/live_meter = km_meter()
	var/datum/tick_meter/probe = new(8)
	var/queue_before = length(SSinput.waiting(GLOB.km_synthetic))
	var/synthetic_before = GLOB.km_synthetic.verbs_run
	// Nothing below sleeps, so the MC cannot call end_tick() on the wrong meter meanwhile.
	km_holder().meter = probe
	for(var/i in 1 to 3)
		km_synthetic_verb()
	var/queued_now = length(SSinput.waiting(GLOB.km_synthetic)) - queue_before
	SSinput.drain_step(1, TRUE)
	km_synthetic_click(clicker, run_loc_floor_bottom_left)
	km_synthetic_click(clicker, run_loc_floor_bottom_left)
	km_holder().meter = live_meter
	var/list/report = km_report_input(probe.live)

	TEST_ASSERT_EQUAL(queued_now, 3, "three verbs sat in the verb queue")
	TEST_ASSERT_EQUAL(report["verbs_queued"], 3, "the meter saw three verbs queued")
	TEST_ASSERT(report["queue_hwm"] >= 3, "and the queue depth reached at least 3 (got [report["queue_hwm"]])")
	// Other verbs may have been waiting in the queue too, so "at least" on what ran.
	TEST_ASSERT(report["verbs_run"] >= 3, "and the verbs run, each with a wait recorded (got [report["verbs_run"]])")
	TEST_ASSERT_EQUAL(GLOB.km_synthetic.verbs_run, synthetic_before + 3, "the queued verbs really ran")
	TEST_ASSERT_EQUAL(report["clicks"], 2, "two real clicks through /atom/Click were stamped")
	TEST_ASSERT_EQUAL(probe.live.input.click_wait.count, 2, "each with a wait sample")
	TEST_ASSERT(probe.live.input.depth.count >= 5, "and a run depth per input (got [probe.live.input.depth.count])")
	TEST_ASSERT(report["wait_max_ms"] < 500, "waits are sane numbers (max [report["wait_max_ms"]] ms)")
	TEST_ASSERT(probe.input_ms >= 0, "the click's own cost is accumulated as input cost")
	qdel(probe)
	return

// ---------------------------------------------------------------- the input cost

/// The input inbox's drain is charged to the input system, and counts as input cost in the tick record.
/datum/unit_test/dq_km_inbox_drain_is_input_cost

/datum/unit_test/dq_km_inbox_drain_is_input_cost/Run()
	var/datum/tick_meter/live_meter = km_meter()
	var/datum/tick_meter/probe = new(8)
	km_holder().meter = probe
	SSinput.charge_drain(TICK_USAGE - 5)
	km_holder().meter = live_meter
	TEST_ASSERT(probe.input_ms > 0, "the drain's cost is input cost")
	TEST_ASSERT(probe.tick_ms[KM_SYS_INPUT] > 0, "and it is charged to the input system")
	qdel(probe)

// ---------------------------------------------------------------- BYOND reserve, surfaces

/datum/unit_test/dq_km_byond_reserve_follows_maptick

/datum/unit_test/dq_km_byond_reserve_follows_maptick/Run()
	var/datum/tick_meter/M = new(8)
	TEST_ASSERT_EQUAL(M.byond_reserve(), 0, "no reserve before anything is measured")
	M.end_tick(50, 12)
	TEST_ASSERT_EQUAL(M.byond_reserve(), 12, "a spike sets the reserve")
	M.end_tick(50, 0)
	TEST_ASSERT(M.byond_reserve() > 11 && M.byond_reserve() < 12, "and it decays slowly (got [M.byond_reserve()])")
	M.end_tick(50, 20)
	TEST_ASSERT_EQUAL(M.byond_reserve(), 20, "a bigger spike replaces it")
	qdel(M)
	// The define the MC's stress test reads is the live meter's.
	TEST_ASSERT_EQUAL(TICK_BYOND_RESERVE, km_meter().byond_reserve(), "TICK_BYOND_RESERVE is the measured reserve")
	return

/datum/unit_test/dq_km_surfaces_render

/datum/unit_test/dq_km_surfaces_render/Run()
	var/panel = km_panel_data()
	TEST_ASSERT(islist(panel["systems"]), "the panel data has a system list")
	TEST_ASSERT(islist(panel["input"]), "and an input record")
	TEST_ASSERT(!isnull(panel["streak"]) && !isnull(panel["overruns"]), "and the tick counters")
	var/list/diag = km_diagnostics(null)
	TEST_ASSERT(islist(diag["systems"]) && islist(diag["input"]), "diagnostics carry the same records")
	var/list/om = om_diagnostics(GLOB.om_live_sched)
	TEST_ASSERT(islist(om["kernel"]), "om_diagnostics() exposes them")
	TEST_ASSERT(islist(om["kernel"]["systems"]), "with the per-system rows")
	var/datum/tick_meter/M = new(8)
	var/a = km_test_system("km_test_a")
	M.charge(a, 20)
	M.end_tick(120, 3)
	var/datum/tick_meter/live_meter = km_meter()
	km_holder().meter = M
	var/html = km_tick_report_html(FALSE)
	var/html_over = km_tick_report_html(TRUE)
	km_holder().meter = live_meter
	TEST_ASSERT(findtext(html, "<table") && findtext(html, "km_test_a"), "the tick report is a table naming the top system")
	TEST_ASSERT(findtext(html_over, "km_test_a"), "the overruns-only report includes the overrun")
	qdel(M)
	return
