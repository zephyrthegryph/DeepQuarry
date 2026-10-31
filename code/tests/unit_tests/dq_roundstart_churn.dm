// Idle-server redraw cost: the audit sweep is paced by world time, the applied-look counters tell first draws from wasted ones, and an idle world
// redraws no turf (doc: perf/roundstart-churn).

/// The audit takes a step at most once per interval and counts the steps it skipped.
/datum/unit_test/dq_refresh_sweep_paced

/datum/unit_test/dq_refresh_sweep_paced/Run()
	set_global(nameof(GLOB.refresh_sweep_next), -1)
	var/ran = GLOB.refresh_sweep_ran
	var/skipped = GLOB.refresh_sweep_skipped
	TEST_ASSERT(refresh_sweep_due(), "the first step is due")
	TEST_ASSERT(!refresh_sweep_due(), "a second step in the same tick is not")
	TEST_ASSERT(!refresh_sweep_due(), "nor a third")
	TEST_ASSERT_EQUAL(GLOB.refresh_sweep_ran - ran, 1, "one step ran")
	TEST_ASSERT_EQUAL(GLOB.refresh_sweep_skipped - skipped, 2, "two were skipped")
	set_global(nameof(GLOB.refresh_sweep_next), world.time - 1)
	TEST_ASSERT(refresh_sweep_due(), "once the interval has passed the next step is due")

/// Drawing an atom again to the same key counts as "same", and an idle world redraws no turf.
/datum/unit_test/dq_idle_turfs_not_redrawn

/datum/unit_test/dq_idle_turfs_not_redrawn/Run()
	test_driver_begin()
	var/turf/simulated/floor/F = test_floor()
	refresh_look(F)
	var/same = GLOB.refresh_look_stats["same"] || 0
	refresh_look(F)
	TEST_ASSERT_EQUAL((GLOB.refresh_look_stats["same"] || 0) - same, 1, "a second draw to the same key counts as same: [refresh_look_stats_text()]")
	// The map's first draws are a backlog the presentation lane works off in the first seconds (they are not redraws): let it finish.
	var/list/before = turf_look_counts()
	for(var/settle in 1 to 24)
		test_time(5 SECONDS)
		var/list/now = turf_look_counts()
		var/moved = FALSE
		for(var/kind in now)
			if(now[kind] != (before[kind] || 0))
				moved = TRUE
		before = now
		if(!moved)
			break
	TEST_ASSERT(!moved_after_settle(before), "the first-draw backlog never settled: [refresh_look_stats_text(12)]")
	test_time(10 SECONDS)
	var/list/after = turf_look_counts()
	test_driver_end()
	for(var/kind in after)
		TEST_ASSERT_EQUAL(after[kind] - (before[kind] || 0), 0, "an idle world redrew turfs ([kind]): [refresh_look_stats_text(12)]")

/datum/unit_test/dq_idle_turfs_not_redrawn/proc/moved_after_settle(list/before)
	var/list/now = turf_look_counts()
	for(var/kind in now)
		if(now[kind] != (before[kind] || 0))
			return TRUE
	return FALSE

/// Applied turf looks so far, by kind.
/datum/unit_test/dq_idle_turfs_not_redrawn/proc/turf_look_counts()
	. = list()
	for(var/key in GLOB.refresh_look_stats)
		var/space = findtext(key, " ")
		if(!space)
			continue
		var/kind = copytext(key, 1, space)
		if(ispath(text2path(copytext(key, space + 1)), /turf))
			.[kind] = (.[kind] || 0) + GLOB.refresh_look_stats[key]

/// A step starts the wait for the next one a full interval ahead, so the audit runs REFRESH_SWEEP_INTERVAL apart (about two steps a second),
/// and a step that is not yet due changes nothing. (The cooldown reads world.time, which the kernel's test clock does not move.)
/datum/unit_test/dq_refresh_sweep_pacing_clock

/datum/unit_test/dq_refresh_sweep_pacing_clock/Run()
	set_global(nameof(GLOB.refresh_sweep_next), 0)
	set_global(nameof(GLOB.refresh_sweep_ran), GLOB.refresh_sweep_ran)
	set_global(nameof(GLOB.refresh_sweep_skipped), GLOB.refresh_sweep_skipped)
	set_global(nameof(GLOB.refresh_look_log_next), GLOB.refresh_look_log_next)
	TEST_ASSERT(refresh_sweep_due(), "the first step is due")
	var/due_at = GLOB.refresh_sweep_next
	TEST_ASSERT_EQUAL(due_at, world.time + REFRESH_SWEEP_INTERVAL, "the next step waits one interval")
	TEST_ASSERT(!refresh_sweep_due(), "not due again at once")
	TEST_ASSERT_EQUAL(GLOB.refresh_sweep_next, due_at, "a refused step leaves the deadline alone")
	TEST_ASSERT_EQUAL(REFRESH_SWEEP_INTERVAL, 5, "an interval is half a second: about ten steps in five seconds")

/// After the boot drain nothing waits for a first draw, and no atom's look differs from what its draw gives now: an atom whose look only
/// the audit would apply is a missing mark (meaningful with --full-map). Samples up to 25 atoms per type; failures name the types.
/datum/unit_test/dq_initial_render_complete

/datum/unit_test/dq_initial_render_complete/Run()
	refresh_flush()
	TEST_ASSERT_EQUAL(length(GLOB.refresh_queue), 0, "a first draw is still queued after the flush")
	var/list/seen = list()
	var/list/unrendered = list()
	for(var/turf/T in world)
		check_atom(T, seen, unrendered)
		for(var/atom/movable/M as anything in T)
			if(!ismob(M))
				check_atom(M, seen, unrendered)
	var/list/rows = list()
	for(var/type in unrendered)
		rows += "[type] x[unrendered[type]]"
	if(length(rows))
		log_world("REFRESH DRIFT (initial render): [jointext(rows, "; ")]")
	TEST_ASSERT_EQUAL(length(rows), 0, "atoms whose look was never applied: [jointext(rows, "; ")]")

/datum/unit_test/dq_initial_render_complete/proc/check_atom(atom/A, list/seen, list/unrendered)
	if(QDELETED(A) || A.refresh_queued)
		return
	if((seen[A.type] || 0) >= 25)
		return
	seen[A.type] = (seen[A.type] || 0) + 1
	var/key = refresh_look(A, FALSE)
	if(key != A.rx?.look_key)
		unrendered["[A.type]"] = (unrendered["[A.type]"] || 0) + 1

/// A queued first draw within a screen of a client runs ahead of the backlog.
/datum/unit_test/dq_refresh_near_client_first

/datum/unit_test/dq_refresh_near_client_first/Run()
	set_global(nameof(GLOB.refresh_near_drawn), GLOB.refresh_near_drawn)
	var/turf/T = test_floor()
	var/obj/structure/table/O = new(T)
	refresh_flush()
	refresh_mark(O, DEP_ALL)
	TEST_ASSERT(O.refresh_queued, "the mark queued a refresh")
	var/far = locate(clamp(T.x + 40, 1, world.maxx), T.y, T.z)
	refresh_drain_near(list(far)) // a client far away draws nothing here
	TEST_ASSERT(O.refresh_queued, "a client far away does not pull it forward")
	refresh_drain_near(list(T))
	TEST_ASSERT(!O.refresh_queued, "a client near it draws it ahead of the backlog")
	qdel(O)
	refresh_flush()

/// A cell in air at its own temperature starts no material service (it would sample, find nothing and retire); a custom assembly needs one.
/datum/unit_test/dq_cell_service_only_when_needed

/datum/unit_test/dq_cell_service_only_when_needed/Run()
	var/turf/T = test_floor()
	var/datum/gas_mixture/air = T.return_air()
	if(air && abs(air.return_temperature() - T20C) < MATERIAL_THERMAL_RESOLUTION)
		var/obj/item/cell/high/warm = new(T)
		TEST_ASSERT_NULL(material_service_of(warm), "a cell at its air's temperature starts no service")
		TEST_ASSERT(!warm.material_service_needed_at_start(), "and still needs none")
		qdel(warm)
	var/obj/item/cell/high/custom = new(T)
	material_assembly(custom).custom = TRUE
	TEST_ASSERT(custom.material_service_needed_at_start(), "a custom assembly needs its service at once")
	qdel(custom)

/// A locker takes in everything it starts with and every loose item on its tile: none of it is refused for room (the full-map boot logged fifteen such
/// refusals, which fail the boot gate of every full-map run).
/datum/unit_test/dq_lockers_hold_their_contents

/datum/unit_test/dq_lockers_hold_their_contents/Run()
	var/turf/origin = test_floor()
	var/list/refused = list()
	var/spot = 0
	for(var/type in list(/obj/structure/closet/secure_closet/medical3, /obj/structure/closet/wardrobe/red, /obj/structure/closet/wardrobe/science_white, /obj/structure/closet/secure_closet/explorer, /obj/structure/closet/secure_closet/pilot, /obj/structure/closet/secure_closet/pathfinder))
		var/before = GLOB.boot_noise_count
		var/turf/T = locate(origin.x + 2 * ++spot, origin.y, origin.z) // a tile of its own: a locker takes in the loose items on its tile
		var/obj/structure/closet/C = new type(T)
		refresh_flush()
		if(GLOB.boot_noise_count != before)
			refused += "[type] ([GLOB.boot_noise_count - before]): [jointext(GLOB.boot_noise_first, " | ")]"
		qdel(C)
		for(var/obj/item/spilled in T) // the locker spills what it held when it goes
			qdel(spilled)
	TEST_ASSERT_EQUAL(length(refused), 0, "lockers refused their own contents: [jointext(refused, "; ")]")

/// The guard's baseline holds settled alarms: another scan of any air alarm changes none of the settings the guard watches (an alarm's first scan used to land
/// in whichever test was running, which failed the end-of-run compare in two runs of five).
/datum/unit_test/dq_guard_baseline_is_settled

/datum/unit_test/dq_guard_baseline_is_settled/Run()
	var/datum/unit_test_guard/guard = unit_test_guard_session()
	var/list/moved = list()
	for(var/obj/machinery/alarm/A as anything in unit_test_machines_tracked())
		if(QDELETED(A) || !istype(A))
			continue
		var/list/was = guard.machine_state[A]
		A.scan_room()
		for(var/name in was)
			if(A.vars[name] != was[name] && !guard.is_thermostat_answer(A, name))
				moved += "[A] ([A.type]) at ([A.x],[A.y],[A.z]) [name] [was[name]] -> [A.vars[name]]"
	TEST_ASSERT_EQUAL(length(moved), 0, "a scan changed what the guard baselined: [jointext(moved, "; ")]")

/// An APC's look follows its lamp: three lamp states draw three different looks and the same state draws the same one (the draw asks the APC's capability
/// data once per fact, not once per use).
/datum/unit_test/dq_apc_look_follows_the_lamp

/datum/unit_test/dq_apc_look_follows_the_lamp/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has a working APC")
	if(!apc)
		return
	var/was = apc.charging
	var/list/keys = list()
	for(var/lamp in list(0, 1, 2, 1))
		apc.set_charging(lamp)
		keys += "[refresh_look(apc, FALSE)]"
	apc.set_charging(was)
	TEST_ASSERT(keys[1] != keys[2] && keys[2] != keys[3] && keys[1] != keys[3], "three lamp states draw three looks: [jointext(keys, " | ")]")
	TEST_ASSERT_EQUAL(keys[2], keys[4], "the same lamp draws the same look")

/// A radio packet addressed to another door leaves an airlock alone, powered or not (the addressing is tested before the power).
/datum/unit_test/dq_airlock_ignores_a_packet_for_another_door

/datum/unit_test/dq_airlock_ignores_a_packet_for_another_door/Run()
	var/turf/T = test_floor()
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, T)
	door.set_id_tag("mine")
	var/datum/signal/other = new
	other.data = list("tag" = "theirs", "command" = "open")
	door.receive_signal(other)
	TEST_ASSERT_NULL(door.cur_command, "a packet for another tag set no command")
	var/datum/signal/mine = new
	mine.data = list("tag" = "mine", "command" = "update")
	door.receive_signal(mine)
	TEST_ASSERT(isnull(door.cur_command) || door.cur_command == "update", "a packet for this door is taken (when it has power) or refused (when it has none), never mistaken for another command: [door.cur_command]")
