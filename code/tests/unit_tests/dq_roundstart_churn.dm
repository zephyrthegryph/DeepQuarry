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

/// A burst of cosmetic APC reports (charge and lamp only) writes the first few cells at once and the rest a few a tick, each cell ends with the charge its last report carried,
/// and a report that moves more than the charge writes at once and cancels a waiting one.
/datum/unit_test/dq_apc_charge_reports_spread

/datum/unit_test/dq_apc_charge_reports_spread/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has a working APC")
	if(!apc)
		return
	test_driver_begin()
	set_global(nameof(GLOB.apc_charge_budget), 2)
	set_global(nameof(GLOB.apc_charge_tick), -1)
	set_global(nameof(GLOB.apc_charge_taken), 0)
	set_global(nameof(GLOB.apc_charge_deferred), GLOB.apc_charge_deferred)
	var/max = apc.cell.maxcharge
	var/charge_before = apc.cell.charge
	var/deferred_before = GLOB.apc_charge_deferred
	for(var/i in 1 to 5)
		apc.on_apc_report(apc.equipment, apc.lighting, apc.environ, apc.charging, apc.power_alarm_raised, apc.main_status, max * i / 10)
	TEST_ASSERT_EQUAL(GLOB.apc_charge_deferred - deferred_before, 3, "two reports wrote at once, three waited")
	TEST_ASSERT_EQUAL(apc.cell.charge, max * 2 / 10, "the cell holds the last charge that was written at once")
	TEST_ASSERT_EQUAL(apc.pending_report_charge, max * 5 / 10, "the waiting charge is the newest report's")
	for(var/frame in 1 to 10)
		native_system().drain() // a native frame applies what waited, a few a tick
	TEST_ASSERT_EQUAL(apc.cell.charge, max * 5 / 10, "the drain wrote the newest reported charge")
	TEST_ASSERT_NULL(apc.pending_report_charge, "nothing is left waiting")
	TEST_ASSERT_EQUAL(length(GLOB.apc_charge_backlog), 0, "the backlog is empty")
	// A report that moves more than the charge writes at once and cancels a waiting charge.
	set_global(nameof(GLOB.apc_charge_tick), world.time)
	set_global(nameof(GLOB.apc_charge_taken), 2)
	apc.on_apc_report(apc.equipment, apc.lighting, apc.environ, apc.charging, apc.power_alarm_raised, apc.main_status, max * 6 / 10)
	TEST_ASSERT_EQUAL(apc.pending_report_charge, max * 6 / 10, "over the budget it waits")
	var/other_status = apc.main_status == APC_EXTERNAL_POWER_GOOD ? APC_EXTERNAL_POWER_NOENERGY : APC_EXTERNAL_POWER_GOOD
	apc.on_apc_report(apc.equipment, apc.lighting, apc.environ, apc.charging, apc.power_alarm_raised, other_status, max * 7 / 10)
	TEST_ASSERT_NULL(apc.pending_report_charge, "a report that moves more than the charge cancels the waiting one")
	TEST_ASSERT_EQUAL(apc.cell.charge, max * 7 / 10, "and writes its own charge at once")
	for(var/frame in 1 to 10)
		native_system().drain()
	TEST_ASSERT_EQUAL(apc.cell.charge, max * 7 / 10, "nothing older overwrites it afterwards")
	apc.cell.set_charge(charge_before)
	test_driver_end()

/// A burst of lamp flips: the lamp and the folded log line are applied late, each APC ends with the lamp its last report carried.
/datum/unit_test/dq_apc_lamp_reports_spread

/datum/unit_test/dq_apc_lamp_reports_spread/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has a working APC")
	if(!apc)
		return
	test_driver_begin()
	set_global(nameof(GLOB.apc_charge_budget), 1)
	set_global(nameof(GLOB.apc_charge_tick), -1)
	set_global(nameof(GLOB.apc_charge_taken), 0)
	set_global(nameof(GLOB.apc_charge_deferred), GLOB.apc_charge_deferred)
	var/was_charging = apc.charging
	var/lamp_a = was_charging == 2 ? 1 : 2
	var/lamp_b = was_charging == 0 ? 1 : 0
	var/charge = apc.cell.maxcharge * 3 / 10
	var/charge_before = apc.cell.charge
	apc.on_apc_report(apc.equipment, apc.lighting, apc.environ, lamp_a, apc.power_alarm_raised, apc.main_status, charge)
	TEST_ASSERT_EQUAL(apc.charging, lamp_a, "the first report of a tick applies at once")
	apc.on_apc_report(apc.equipment, apc.lighting, apc.environ, lamp_b, apc.power_alarm_raised, apc.main_status, charge)
	TEST_ASSERT_EQUAL(apc.charging, lamp_a, "the second waits")
	TEST_ASSERT_EQUAL(apc.pending_report_charging, lamp_b, "with the lamp it carried")
	for(var/frame in 1 to 10)
		native_system().drain()
	TEST_ASSERT_EQUAL(apc.charging, lamp_b, "the drain applied the lamp")
	TEST_ASSERT_NULL(apc.pending_report_charging, "nothing is left waiting")
	apc.set_charging(was_charging)
	apc.cell.set_charge(charge_before)
	test_driver_end()

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

/// The part of a join that follows a tick after the body: it makes the manifest record and speaks the arrival (a joiner whose body was deleted in between is skipped).
/datum/unit_test/dq_latejoin_register_makes_the_record

/datum/unit_test/dq_latejoin_register_makes_the_record/Run()
	var/list/join = SSjob.late_spawn(null, JOB_INTERN)
	var/turf/T = join?["turf"]
	TEST_ASSERT(isturf(T), "the job system gives a late joiner an arrivals turf")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.mind_initialize()
	defer_cleanup(null, GLOBAL_PROC_REF(dq_gameplay_forget_mind), H.mind)
	SSjob.equip_rank(H, JOB_INTERN, TRUE, FALSE)
	refresh_flush()
	var/before = length(GLOB.data_core.general)
	latejoin_register(H, JOB_INTERN, "has arrived", "Common", H.z)
	TEST_ASSERT_EQUAL(length(GLOB.data_core.general), before + 1, "the manifest has the new record")
	var/gone = allocate(/mob/living/carbon/human, T)
	qdel(gone)
	latejoin_register(gone, JOB_INTERN, "has arrived", "Common", T.z)
	TEST_ASSERT_EQUAL(length(GLOB.data_core.general), before + 1, "a joiner deleted before the registration adds none")

/// A character preview render is polled four times a second, not every tick: a poll with nothing to wait for finishes at its first step, a quarter second on.
/datum/unit_test/dq_preview_poll_cadence

/datum/unit_test/dq_preview_poll_cadence/Run()
	test_driver_begin()
	set_global(nameof(GLOB.sched_rec), GLOB.sched_rec) // the first every() of a round makes the scheduler's record: restored with the rest
	var/datum/dq_preview_poll/poll = new
	poll.state = list(1, list(), list(), 1, 1, FALSE, list())
	COOLDOWN_START(poll, timeout_at, 10 SECONDS)
	poll.set_polling(TRUE)
	test_time(0.1 SECONDS)
	TEST_ASSERT(poll.polling, "a tenth of a second on it has not polled yet")
	test_time(0.5 SECONDS)
	TEST_ASSERT(!poll.polling, "half a second on it has polled and finished")
	test_driver_end()
	qdel(poll)

/// A door-only docking port steps while a handshake is in flight and rests once docked or undocked.
/datum/unit_test/dq_docked_simple_port_rests

/datum/unit_test/dq_docked_simple_port_rests/Run()
	var/obj/machinery/embedded_controller/radio/simple_docking_controller/console = allocate(/obj/machinery/embedded_controller/radio/simple_docking_controller, test_floor())
	var/datum/docking_port/port = console.port
	TEST_ASSERT_NOTNULL(port, "the console has its port")
	TEST_ASSERT(!port.needs_step(), "an undocked port has nothing to step")
	port.set_dock_state(1) // DOCKING (the port's defines end with its file)
	TEST_ASSERT(port.needs_step(), "a port that is docking steps")
	port.set_dock_state(3) // DOCKED
	TEST_ASSERT(!port.needs_step(), "a docked port rests")
	port.set_dock_state(2) // UNDOCKING
	TEST_ASSERT(port.needs_step(), "a port that is undocking steps")

/// A parked first draw (lazy first draw, look_stamp.dm) waits out of the queue, is drawn when a client comes near, and a real mark draws it with the
/// first draw it owed.
/datum/unit_test/dq_refresh_parked_first_draw

/datum/unit_test/dq_refresh_parked_first_draw/Run()
	interest_isolate()
	set_global(nameof(GLOB.refresh_parked_woken), GLOB.refresh_parked_woken)
	var/turf/T = test_floor()
	refresh_flush()
	set_global(nameof(GLOB.refresh_park_residual), GLOB.refresh_park_residual) // the park below writes it: the framework restores it
	GLOB.type_look_stamp -= /obj/structure/table // as before the type's verdict is in: fresh instances queue their first draw
	var/obj/structure/table/near = new(T)
	var/obj/structure/table/marked = new(T)
	for(var/obj/structure/table/fresh as anything in list(near, marked)) // caps_init()'s creation mark, as a map load leaves it
		if(!fresh.refresh_queued)
			refresh_mark(fresh, DEP_ALL)
		fresh.refresh_queued |= DEP_CREATED
	TEST_ASSERT(near.refresh_queued & DEP_CREATED, "a fresh table queues its first draw")
	GLOB.type_look_lazy -= /obj/structure/table
	// A type with no lazy verdict is never parked; a lazy verdict parks the fresh ones.
	TEST_ASSERT_EQUAL(refresh_park_backlog(), 0, "no verdict, nothing parked")
	GLOB.type_look_lazy[/obj/structure/table] = TRUE
	TEST_ASSERT(refresh_park_backlog() >= 2, "the fresh tables of a lazy type are parked")
	TEST_ASSERT_EQUAL(near.refresh_queued, DEP_PARKED, "a parked atom owes its first draw and is not queued")
	TEST_ASSERT(!(near in GLOB.refresh_queue), "and is not in the queue")
	TEST_ASSERT(REFRESH_IDLE(near), "a parked atom counts as idle for a first-mark test")
	// A client far away draws nothing; one near draws it.
	var/far = locate(clamp(T.x + 40, 1, world.maxx), T.y, T.z)
	interest_hold_set("dq-test-far", interest_view_keys(far, world.view))
	TEST_ASSERT_EQUAL(near.refresh_queued, DEP_PARKED, "a client far away does not draw it")
	// A real mark on one that was never near: queued, with the first draw it owed.
	TEST_ASSERT_EQUAL(marked.refresh_queued, DEP_PARKED, "the other fresh table is parked too")
	refresh_mark(marked, DEP_UI)
	TEST_ASSERT(!(marked.refresh_queued & DEP_PARKED), "a mark unparks it")
	TEST_ASSERT((marked.refresh_queued & DEP_DRAW) && (marked in GLOB.refresh_queue), "and queues the first draw it owed, whatever the mark named")
	var/near_before = GLOB.refresh_parked_near
	interest_hold_set("dq-test-near", interest_view_keys(T, world.view))
	TEST_ASSERT(near.refresh_queued & DEP_DRAW, "a client near it queues the draw it owed")
	TEST_ASSERT(GLOB.refresh_parked_near > near_before, "and the wake is counted")
	refresh_flush()
	TEST_ASSERT_EQUAL(near.refresh_queued, 0, "the drain draws it")
	// A type whose first draw changed anything but the look is not lazy.
	GLOB.type_look_lazy -= /obj/structure/table
	look_lazy_record(near, "changed-state")
	TEST_ASSERT(!GLOB.type_look_lazy[/obj/structure/table], "a first draw that moved light, opacity, density or verbs keeps the type eager")
	TEST_ASSERT(GLOB.type_look_lazy_why[/obj/structure/table], "and the rule that excluded it is recorded for the park census")
	TEST_ASSERT(findtext(refresh_park_residual_text(list(near)), "rules:"), "the residual census names the rules")
	GLOB.type_look_lazy_why -= /obj/structure/table
	GLOB.type_look_lazy -= /obj/structure/table
	qdel(near)
	qdel(marked)
	for(var/obj/item/stack/material/scrap in T) // a table leaves its material behind
		qdel(scrap)
	refresh_flush()

/// A client that sees through an eye (an AI's camera view, a camera console, a drone or hologram) holds the chunks around the eye, and around its mob too.
/datum/unit_test/dq_refresh_parked_drawn_for_remote_eye

/datum/unit_test/dq_refresh_parked_drawn_for_remote_eye/Run()
	interest_isolate()
	var/turf/eye_turf = test_floor()
	var/turf/mob_turf = interest_far_from(eye_turf)
	TEST_ASSERT_NOTNULL(mob_turf, "the map has room for a turf four chunks away")
	refresh_flush()
	var/obj/dq_interest_probe/seen_by_eye = new(eye_turf)
	seen_by_eye.refresh_queued = DEP_PARKED
	var/obj/dq_interest_probe/seen_by_mob = new(mob_turf)
	seen_by_mob.refresh_queued = DEP_PARKED
	interest_view_set("dq-test-client", eye_turf, mob_turf, world.view)
	TEST_ASSERT(interest_covers(eye_turf), "the eye's chunk is held")
	TEST_ASSERT(interest_covers(mob_turf), "so is the mob's")
	TEST_ASSERT_EQUAL(seen_by_eye.refresh_queued, 0, "a parked atom around the eye is drawn at once")
	TEST_ASSERT_EQUAL(seen_by_mob.refresh_queued, 0, "and one around the mob")
	// A wider view (zoom, widescreen) reaches further than the default.
	TEST_ASSERT(interest_view_half("31x31") > world.view, "a client's own view setting sets the radius")
	TEST_ASSERT_EQUAL(interest_view_half(9), 9, "a number is the half width")
	qdel(seen_by_eye)
	qdel(seen_by_mob)
	refresh_flush()

/// A floor that shows another turf, as open space shows the level below it.
/turf/simulated/floor/dq_shows_other
	var/turf/shows

/turf/simulated/floor/dq_shows_other/seen_through()
	return shows

/// A parked first draw on a turf a client sees through open space (and through two stacked layers of it) is drawn, though it is far from the client's tile.
/datum/unit_test/dq_refresh_parked_drawn_through_open_space

/datum/unit_test/dq_refresh_parked_drawn_through_open_space/Run()
	interest_isolate()
	var/turf/start = test_floor()
	var/original_type = start.type
	var/turf/middle = locate(clamp(start.x + 40, 1, world.maxx - 1), start.y, start.z)
	var/turf/bottom = locate(middle.x + 1, middle.y, middle.z)
	var/middle_type = middle.type
	refresh_flush()
	var/turf/simulated/floor/dq_shows_other/top = start.ChangeTurf(/turf/simulated/floor/dq_shows_other)
	var/turf/simulated/floor/dq_shows_other/mid = middle.ChangeTurf(/turf/simulated/floor/dq_shows_other)
	top.shows = mid
	mid.shows = bottom
	var/obj/structure/table/under = new(bottom)
	under.refresh_queued = DEP_PARKED
	var/obj/structure/table/beside = new(locate(bottom.x, bottom.y + 20 <= world.maxy ? bottom.y + 20 : bottom.y - 20, bottom.z)) // not under any open space, and in another chunk
	beside.refresh_queued = DEP_PARKED
	interest_view_set("dq-test-client", top, null, world.view)
	TEST_ASSERT_EQUAL(under.refresh_queued, 0, "an atom two layers of open space below the client's tile is drawn at once")
	TEST_ASSERT_EQUAL(beside.refresh_queued, DEP_PARKED, "an atom beside it, under nothing the client sees, stays parked")
	var/turf/beside_turf = beside.loc
	qdel(under)
	qdel(beside)
	for(var/obj/item/stack/material/scrap in bottom)
		qdel(scrap)
	for(var/obj/item/stack/material/scrap in beside_turf)
		qdel(scrap)
	mid.ChangeTurf(middle_type)
	top.ChangeTurf(original_type)
	refresh_flush()
