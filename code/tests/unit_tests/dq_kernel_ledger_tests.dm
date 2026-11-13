// The tick ledger (code/world/kernel/measure/ledger.dm): categories plus the residual add up to the window, nested regions take their time out of the
// region around them, a skipped leave is repaired, the rows stay bounded, and the work sites (Move, work items) charge the right category.
// Every test builds its own ledger and drives it with explicit times (percent of a tick), so nothing here touches the live one except where a
// test swaps it in on purpose and puts it back.

/// ms of `percent` of a tick.
#define KL_MS_OF(percent) ((percent) * world.tick_lag)

/// The sum of every category's cumulative ms.
/proc/km_ledger_test_sum(datum/km_ledger/L)
	. = 0
	for(var/i in 1 to KM_CAT_COUNT)
		. += L.lo[i] + L.hi[i]

/// True when `a` and `b` are within a rounding error.
/proc/km_ledger_test_near(a, b)
	return abs(a - b) < 0.0005

/datum/unit_test/dq_km_ledger_categories_sum_to_window

/datum/unit_test/dq_km_ledger_categories_sum_to_window/Run()
	var/datum/km_ledger/L = new
	L.begin(10)
	var/outer = L.enter(KM_CAT_TIMER, /obj/item, "tick_proc", 20)
	var/inner = L.enter(KM_CAT_ON_CHANGE, /obj/item, "hook", 30)
	L.leave(inner, 35)
	L.leave(outer, 50)
	var/window = L.finish(60, 70)
	TEST_ASSERT(km_ledger_test_near(window, KL_MS_OF(70)), "the window is the tick's usage ([window] vs [KL_MS_OF(70)])")
	TEST_ASSERT(km_ledger_test_near(km_ledger_test_sum(L), window), "the categories add up to the window ([km_ledger_test_sum(L)] vs [window])")
	TEST_ASSERT(km_ledger_test_near(L.lo[KM_CAT_BYOND_PRE], KL_MS_OF(10)), "everything before the loop resumed is BYOND's")
	TEST_ASSERT(km_ledger_test_near(L.lo[KM_CAT_TIMER], KL_MS_OF(10 + 15)), "the timer's own time is its 10 before and 15 after the hook")
	TEST_ASSERT(km_ledger_test_near(L.lo[KM_CAT_ON_CHANGE], KL_MS_OF(5)), "the hook's 5 are taken out of the timer's")
	TEST_ASSERT(km_ledger_test_near(L.lo[KM_CAT_UNATTRIBUTED], KL_MS_OF(10 + 10 + 10)), "the residual is what no region covered: 10 to the first region, 10 between, 10 after")
	TEST_ASSERT_EQUAL(L.ticks, 1, "one window closed")
	TEST_ASSERT(!L.active, "and the ledger is closed")
	qdel(L, force = TRUE)

/datum/unit_test/dq_km_ledger_report_adds_up

/datum/unit_test/dq_km_ledger_report_adds_up/Run()
	var/datum/km_ledger/L = new
	for(var/n in 1 to 3)
		L.begin(5)
		var/t = L.enter(KM_CAT_SYSTEM, null, "/datum/system/x:run", 15)
		L.leave(t, 40)
		L.finish(45, 50)
	var/list/data = L.report()
	TEST_ASSERT_EQUAL(length(data["categories"]), KM_CAT_COUNT, "every category is a row")
	TEST_ASSERT(km_ledger_test_near(data["categories_total_ms"], data["window_total_ms"]), "the categories' total is the windows' total (categories [data["categories_total_ms"]], windows [data["window_total_ms"]])")
	TEST_ASSERT(km_ledger_test_near(data["window_avg_ms"], KL_MS_OF(50)), "the mean window is the usage")
	var/total = 0
	var/list/keys = list()
	for(var/list/cat as anything in data["categories"])
		total += cat["avg_ms"]
		TEST_ASSERT(!(cat["key"] in keys), "category key [cat["key"]] is unique")
		keys += cat["key"]
	TEST_ASSERT(abs(total - data["window_avg_ms"]) < 0.01, "the per-tick means add up to the mean window ([total] vs [data["window_avg_ms"]])")
	var/list/system_row
	for(var/list/cat as anything in data["categories"])
		if(cat["key"] == "system")
			system_row = cat
	TEST_ASSERT_NOTNULL(system_row, "the system category is reported")
	TEST_ASSERT_EQUAL(length(system_row["top"]), 1, "with the one item it ran")
	TEST_ASSERT_EQUAL(system_row["top"][1][1], "/datum/system/x:run", "named by its key")
	TEST_ASSERT_EQUAL(system_row["top"][1][2], 3, "and run three times")
	qdel(L, force = TRUE)

/datum/unit_test/dq_km_ledger_repairs_a_skipped_leave

/datum/unit_test/dq_km_ledger_repairs_a_skipped_leave/Run()
	var/datum/km_ledger/L = new
	L.begin(0)
	var/outer = L.enter(KM_CAT_TIMER, null, "outer", 10)
	L.enter(KM_CAT_MOVEMENT, null, "inner never left", 20) // a runtime escaped before its leave
	L.leave(outer, 30)
	TEST_ASSERT_EQUAL(L.depth, 0, "the outer leave closes the one nobody left")
	TEST_ASSERT_EQUAL(L.cur, KM_CAT_UNATTRIBUTED, "and the timeline is back in its base")
	L.finish(40, 40)
	TEST_ASSERT(km_ledger_test_near(L.lo[KM_CAT_MOVEMENT], KL_MS_OF(10)), "the skipped region kept the time it was open")
	TEST_ASSERT(km_ledger_test_near(km_ledger_test_sum(L), KL_MS_OF(40)), "and the sum still holds")
	qdel(L, force = TRUE)

/datum/unit_test/dq_km_ledger_ignores_regions_outside_a_window

/datum/unit_test/dq_km_ledger_ignores_regions_outside_a_window/Run()
	var/datum/km_ledger/L = new
	var/token = L.enter(KM_CAT_TIMER, null, "x", 10)
	L.leave(token, 20)
	TEST_ASSERT_EQUAL(km_ledger_test_sum(L), 0, "nothing is charged while no window is open")
	TEST_ASSERT_EQUAL(L.counts[KM_CAT_TIMER], 0, "and nothing is counted")
	L.begin(0)
	L.finish(10, 10)
	token = L.enter(KM_CAT_TIMER, null, "x", 10)
	TEST_ASSERT_EQUAL(L.counts[KM_CAT_TIMER], 0, "a closed window takes no more regions")
	qdel(L, force = TRUE)

/datum/unit_test/dq_km_ledger_depth_is_bounded

/datum/unit_test/dq_km_ledger_depth_is_bounded/Run()
	var/datum/km_ledger/L = new
	L.begin(0)
	var/list/tokens = list()
	for(var/i in 1 to KM_LEDGER_DEPTH + 5)
		tokens += L.enter(KM_CAT_TIMER, null, "deep", i)
	TEST_ASSERT_EQUAL(L.depth, KM_LEDGER_DEPTH, "the stack stops at its bound")
	TEST_ASSERT_EQUAL(L.too_deep, 5, "the extra enters are counted")
	for(var/i in length(tokens) to 1 step -1)
		L.leave(tokens[i], KM_LEDGER_DEPTH + 5 + (length(tokens) - i + 1))
	TEST_ASSERT_EQUAL(L.depth, 0, "every leave closes down to a clean stack")
	L.finish(100, 100)
	TEST_ASSERT(km_ledger_test_near(km_ledger_test_sum(L), KL_MS_OF(100)), "and the sum holds")
	qdel(L, force = TRUE)

/datum/unit_test/dq_km_ledger_rows_stay_bounded

/datum/unit_test/dq_km_ledger_rows_stay_bounded/Run()
	var/datum/km_ledger/L = new
	L.begin(0)
	var/at = 0
	for(var/i in 1 to KM_LEDGER_ROWS + 80)
		var/t = L.enter(KM_CAT_TIMER, "owner [i]", "proc", at + 1)
		L.leave(t, at + 1 + (i % 7))
		at += 2 + (i % 7)
	L.finish(at + 1, at + 1)
	TEST_ASSERT(L.n_rows[KM_CAT_TIMER] <= KM_LEDGER_ROWS, "the category holds at most its bound ([L.n_rows[KM_CAT_TIMER]])")
	TEST_ASSERT(L.overflowed > 0, "names past the bound were folded into the overflow row")
	TEST_ASSERT(L.prunes > 0, "and the category dropped its cheaper half at the end of the tick")
	TEST_ASSERT(km_ledger_test_near(km_ledger_test_sum(L), KL_MS_OF(at + 1)), "dropping rows does not change the totals")
	var/list/top = L.top_of(KM_CAT_TIMER, 3)
	TEST_ASSERT_EQUAL(length(top), 3, "the heaviest three are listed")
	TEST_ASSERT(top[1][3] >= top[2][3] && top[2][3] >= top[3][3], "heaviest first")
	qdel(L, force = TRUE)

/datum/unit_test/dq_km_ledger_moving_average_follows

/datum/unit_test/dq_km_ledger_moving_average_follows/Run()
	var/datum/km_ledger/L = new
	for(var/n in 1 to 400)
		L.begin(0)
		var/t = L.enter(KM_CAT_MOVEMENT, null, "Move", 0)
		L.leave(t, 10)
		L.finish(10, 10)
	TEST_ASSERT(abs(L.ema[KM_CAT_MOVEMENT] - KL_MS_OF(10)) < KL_MS_OF(10) * 0.2, "after 400 ticks of 10% the average is near it ([L.ema[KM_CAT_MOVEMENT]])")
	TEST_ASSERT(L.ema[KM_CAT_TIMER] < 0.01, "and a category that never ran is at zero")
	qdel(L, force = TRUE)

/datum/unit_test/dq_km_ledger_outside_the_window

/datum/unit_test/dq_km_ledger_outside_the_window/Run()
	var/datum/km_ledger/L = new
	L.note_outside(4, 2, TRUE)
	L.note_outside(30, 1, FALSE)
	var/list/outside = L.report()["outside"]
	TEST_ASSERT_EQUAL(L.world_ticks, 2, "both BYOND ticks count")
	TEST_ASSERT(km_ledger_test_near(outside["post_avg_ms"], 2), "after-the-kernel time is the mean over ticks (4 of 2 ticks)")
	TEST_ASSERT(km_ledger_test_near(outside["idle_avg_ms"], 15), "a tick the kernel did not close counts whole (30 of 2 ticks)")
	TEST_ASSERT(km_ledger_test_near(outside["map_avg_ms"], 1.5), "and the map send is the mean over ticks")
	qdel(L, force = TRUE)

/// The window since the last read is what ran outside the kernel's iteration lately, where the report's own mean is since boot.
/datum/unit_test/dq_km_ledger_outside_since_mark

/datum/unit_test/dq_km_ledger_outside_since_mark/Run()
	var/datum/km_ledger/L = new
	for(var/n in 1 to 10)
		L.note_outside(100, 0, TRUE) // a round start holding every tick
	var/list/first = L.outside_since_mark()
	TEST_ASSERT(km_ledger_test_near(first["post_recent_ms"], 100), "the first window is the ticks so far ([first["post_recent_ms"]] ms)")
	for(var/n in 1 to 10)
		L.note_outside(1, 0, TRUE) // then a quiet stretch
	var/list/second = L.outside_since_mark()
	TEST_ASSERT_EQUAL(second["recent_ticks"], 10, "the second window is the ten ticks since")
	TEST_ASSERT(km_ledger_test_near(second["post_recent_ms"], 1), "and shows the quiet stretch, not the mean since boot ([second["post_recent_ms"]] ms)")
	TEST_ASSERT(L.report()["outside"]["post_avg_ms"] > 40, "while the report's mean since boot still carries the busy start")
	qdel(L, force = TRUE)

/// A report built in slices is the report built at once.
/datum/unit_test/dq_km_ledger_walk_matches_report

/datum/unit_test/dq_km_ledger_walk_matches_report/Run()
	var/datum/km_ledger/L = new
	for(var/n in 1 to 5)
		L.begin(5)
		var/t = L.enter(KM_CAT_SYSTEM, null, "/datum/system/x:run", 15)
		L.leave(t, 40)
		L.finish(45, 50)
	var/list/whole = L.report(3)
	var/datum/km_ledger_walk/W = L.walk_begin(3)
	var/slices = 1
	while(!L.walk_step(W, 0))
		slices++
		TEST_ASSERT(slices <= KM_CAT_COUNT, "the walk ends")
	TEST_ASSERT(slices > 1, "a spent budget leaves the rest for the next turn ([slices] turns)")
	TEST_ASSERT_EQUAL(json_encode(L.walk_result(W)), json_encode(whole), "the slices add up to the report")
	qdel(L, force = TRUE)

/datum/unit_test/dq_km_ledger_item_categories

/datum/unit_test/dq_km_ledger_item_categories/Run()
	var/list/names = km_ledger_names()
	TEST_ASSERT_EQUAL(length(names), KM_CAT_COUNT, "every category has a name")
	TEST_ASSERT_EQUAL(km_ledger_item_category(/datum/system/garbage), KM_CAT_GARBAGE, "garbage items are charged as garbage")
	TEST_ASSERT_EQUAL(km_ledger_item_category(/datum/system/input), KM_CAT_INPUT, "input items as input")
	TEST_ASSERT_EQUAL(km_ledger_item_category(/datum/system/behaviours), KM_CAT_SCHED, "the scheduler's pieces as scheduler")
	TEST_ASSERT_EQUAL(km_ledger_item_category(/datum/system/profiler), KM_CAT_SYSTEM, "any other system as system work")
	for(var/datum/work_item/W as anything in Kernel.work_all)
		TEST_ASSERT(W.ledger_cat >= 1 && W.ledger_cat <= KM_CAT_COUNT, "[W.key] has a ledger category")
		TEST_ASSERT_EQUAL(W.ledger_cat, km_ledger_item_category(W.owner_type), "[W.key] was categorised by its owner")

/// A step is charged to movement, named by the mover's type, and its time comes out of the region it ran inside.
/datum/unit_test/dq_km_ledger_charges_a_step

/datum/unit_test/dq_km_ledger_charges_a_step/Run()
	var/datum/km_ledger/live = GLOB.km_ledger
	var/datum/km_ledger/L = new
	GLOB.km_ledger = L
	var/turf/from = run_loc_floor_bottom_left
	var/turf/dest = get_step(from, EAST)
	var/obj/item/dq_cross_probe/mover = allocate(/obj/item/dq_cross_probe, from)
	L.begin(0)
	var/outer = km_ledger_enter(KM_CAT_TIMER, mover.type, "walk")
	var/moved = mover.Move(dest, EAST)
	km_ledger_leave(outer)
	L.finish(TICK_USAGE, TICK_USAGE)
	GLOB.km_ledger = live
	TEST_ASSERT(moved, "the probe stepped")
	TEST_ASSERT_EQUAL(L.counts[KM_CAT_MOVEMENT], 1, "one step was charged to movement")
	var/list/top = L.top_of(KM_CAT_MOVEMENT, 1)
	TEST_ASSERT_EQUAL(length(top), 1, "and named")
	TEST_ASSERT(findtext(top[1][1], "dq_cross_probe"), "by the mover's type ([top[1][1]])")
	TEST_ASSERT(km_ledger_test_near(km_ledger_test_sum(L), L.last_window_ms), "the window still adds up")
	qdel(L, force = TRUE)

#undef KL_MS_OF
