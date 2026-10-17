// Regressions seen on the live server at round start (docking airlocks, first draw, hidden mapping helpers).

/datum/unit_test/dq_shuttle_docking_opens_airlocks

/// A shuttle that docks completes the handshake, and the airlocks of both docking controllers open.
/datum/unit_test/dq_shuttle_docking_opens_airlocks/Run()
	var/datum/shuttle/autodock/ferry/shuttle = SSshuttles.shuttles["Ferry-Demo"]
	TEST_ASSERT_NOTNULL(shuttle, "Ferry-Demo is not mapped")
	TEST_ASSERT_NOTNULL(shuttle.shuttle_docking_controller, "Ferry-Demo has no docking controller of its own")
	// Leave the dock and come back the way the shuttle's own arrival does, so the whole handshake runs.
	shuttle.force_undock()
	TEST_ASSERT(shuttle.attempt_move(shuttle.landmark_offsite()), "Ferry-Demo could not leave the station landmark")
	TEST_ASSERT(shuttle.attempt_move(shuttle.landmark_station()), "Ferry-Demo could not return to its station landmark")
	shuttle.set_active_docking_controller(shuttle.landmark_station().docking_controller())
	shuttle.update_docking_target(shuttle.landmark_station())
	shuttle.dock()
	var/deadline = world.time + 60 SECONDS
	while(world.time < deadline && !shuttle.check_docked())
		sleep(1 SECOND)
	var/datum/embedded_program/docking/ours = shuttle.shuttle_docking_controller
	var/datum/embedded_program/docking/theirs = shuttle.active_docking_controller()
	TEST_ASSERT_NOTNULL(theirs, "Ferry-Demo has no active docking controller at the station")
	TEST_ASSERT(shuttle.check_docked(), "Ferry-Demo never finished docking: shuttle side [ours.get_docking_status()], station side [theirs.get_docking_status()]; [dq_docking_diagnostics(ours)]; [dq_docking_diagnostics(theirs)]")
	// The doors are told to open once the handshake is done; give the airlock commands their swing time.
	var/open_deadline = world.time + 30 SECONDS
	var/list/closed
	while(world.time < open_deadline)
		closed = list()
		for(var/area/A as anything in shuttle.shuttle_area)
			for(var/obj/machinery/door/airlock/D in contents_of(A))
				if(D.density)
					closed += "[D.type] at [D.x],[D.y],[D.z] (id_tag [D.id_tag], power [D.power_systems_on()], bolted [is_bolted(D)], cmd [D.cur_command])"
		if(!length(closed))
			break
		sleep(1 SECOND)
	TEST_ASSERT(!length(closed), "docked Ferry-Demo airlocks stayed closed: [jointext(closed, "; ")]")

/datum/unit_test/dq_arrivals_shuttle_docks_and_opens

/// The arrivals shuttle flies in from its off-station start, docks, and its airlocks open for the passengers (Southern Cross).
/datum/unit_test/dq_arrivals_shuttle_docks_and_opens/Run()
	var/datum/shuttle/autodock/ferry/arrivals/shuttle = SSshuttles.shuttles["Arrivals"]
	TEST_ASSERT_NOTNULL(shuttle, "the arrivals shuttle is not registered (run with --full-map)")
	TEST_ASSERT(shuttle.current_location() == shuttle.landmark_offsite(), "the arrivals shuttle does not start off-station")
	shuttle.warmup_time = 0
	shuttle.launch(src)
	var/deadline = world.time + 120 SECONDS
	while(world.time < deadline && (shuttle.current_location() != shuttle.landmark_station() || shuttle.process_state != IDLE_STATE))
		sleep(1 SECOND)
	TEST_ASSERT(shuttle.current_location() == shuttle.landmark_station(), "the arrivals shuttle never reached the station (state [shuttle.process_state], moving [shuttle.moving_status])")
	var/datum/embedded_program/docking/ours = shuttle.shuttle_docking_controller
	var/datum/embedded_program/docking/theirs = shuttle.active_docking_controller()
	TEST_ASSERT(shuttle.check_docked(), "the arrivals shuttle never finished docking: ours [ours?.get_docking_status()], station [theirs?.get_docking_status()]; [dq_docking_diagnostics(ours)]; [dq_docking_diagnostics(theirs)]")
	var/open_deadline = world.time + 30 SECONDS
	var/list/closed
	var/list/doors = list()
	while(world.time < open_deadline)
		closed = list()
		doors = list()
		for(var/area/A as anything in shuttle.shuttle_area)
			for(var/obj/machinery/door/airlock/D in contents_of(A))
				doors += D
				if(D.density)
					closed += "[D.type] at [D.x],[D.y],[D.z] (id_tag [D.id_tag], power [D.power_systems_on()], bolted [is_bolted(D)], cmd [D.cur_command])"
		if(length(doors) && !length(closed))
			break
		sleep(1 SECOND)
	TEST_ASSERT(length(doors), "the arrivals shuttle has no airlock")
	TEST_ASSERT(!length(closed), "docked arrivals shuttle airlocks stayed closed: [jointext(closed, "; ")]")

/datum/unit_test/dq_first_draw_backlog_drained_at_boot

/// Every atom's first draw happens before the round is playable: the queue is empty when the first test starts
/// and every drawn atom of a type that derives a look has applied it.
/datum/unit_test/dq_first_draw_backlog_drained_at_boot/Run()
	if(length(GLOB.refresh_queue))
		var/list/by_type = list()
		for(var/datum/D as anything in GLOB.refresh_queue)
			if(D)
				by_type["[D.type]"] += 1
		by_type = sortTim(by_type, GLOBAL_PROC_REF(cmp_numeric_dsc), TRUE)
		var/list/top = list()
		for(var/t in by_type)
			top += "[t] x[by_type[t]]"
			if(length(top) >= 12)
				break
		TEST_FAIL("[length(GLOB.refresh_queue)] first draws were still queued when the world finished booting: [jointext(top, ", ")]")
	var/checked = 0
	var/list/undrawn = list()
	for(var/turf/T in block(locate(1, 1, 1), locate(world.maxx, world.maxy, 1)))
		for(var/atom/A as anything in list(T) + T.contents)
			if(!isobj(A) && !isturf(A))
				continue
			var/flags = type_derive_flags(A)
			if(!(flags & TYPE_DERIVES_LOOK) || A.invisibility >= INVISIBILITY_ABSTRACT)
				continue
			checked++
			if(isnull(A.rx?.look_key) && length(undrawn) < 10)
				undrawn += "[A.type] at [T.x],[T.y],[T.z]"
	log_test("first draw check: [checked] look-deriving atoms on z1")
	TEST_ASSERT(!length(undrawn), "atoms that derive a look were not drawn at boot: [jointext(undrawn, "; ")]")

/datum/unit_test/dq_mapping_helpers_stay_hidden

/// A mapping helper that is invisible by type stays invisible in the running world (landmarks, spawners, markers).
/datum/unit_test/dq_mapping_helpers_stay_hidden/Run()
	var/checked = 0
	var/list/shown = list()
	for(var/obj/effect/E in world)
		var/hidden_by_type = initial(E.invisibility)
		if(hidden_by_type < INVISIBILITY_ABSTRACT)
			continue
		checked++
		if(E.invisibility < hidden_by_type && length(shown) < 10)
			shown += "[E.type] at [E.x],[E.y],[E.z] invisibility [E.invisibility]"
	log_test("hidden helper check: [checked] helpers")
	TEST_ASSERT(!length(shown), "mapping helpers became visible: [jointext(shown, "; ")]")
	for(var/obj/effect/landmark/L in world)
		TEST_ASSERT(L.invisibility >= INVISIBILITY_ABSTRACT, "landmark [L.type] ([L.name]) at [L.x],[L.y],[L.z] is visible")

/// What a stuck docking handshake looks like: the program's state and, for an airlock port, its cycle and doors.
/proc/dq_docking_diagnostics(datum/embedded_program/docking/D)
	if(!D)
		return "no controller"
	var/list/out = list("[D.type] [D.id_tag] state [D.get_docking_status()] mode [D.control_mode] confirm [D.received_confirm] sent [D.response_sent] override [D.override_enabled]")
	var/obj/machinery/embedded_controller/M = D.master
	if(M)
		out += "controller [M.type] on [M.on] power [M.powered()]"
	if(istype(D, /datum/embedded_program/docking/airlock))
		var/datum/embedded_program/docking/airlock/A = D
		var/datum/embedded_program/airlock/P = A.airlock_program
		if(P)
			out += "cycle: state [P.state] target [P.target_state] done [P.done_cycling()] processing [P.memory["processing"]] pressure [P.memory["chamber_sensor_pressure"]] target_pressure [P.memory["target_pressure"]] int [P.memory["interior_status"]?["state"]] ext [P.memory["exterior_status"]?["state"]]"
	if(istype(D, /datum/embedded_program/docking/multi))
		var/datum/embedded_program/docking/multi/Mu = D
		out += "children ready [json_encode(Mu.children_ready)]"
		for(var/obj/machinery/embedded_controller/radio/airlock/docking_port_multi/C in world)
			var/datum/embedded_program/airlock/multi_docking/CP = C.program
			if(!CP || !(CP.id_tag in Mu.children_tags))
				continue
			out += "child [CP.id_tag] controller on [C.on] power [C.powered()] master [CP.master_tag] enabled [CP.docking_enabled] mode [CP.docking_mode] sent [CP.response_sent] override [CP.override_enabled] state [CP.state] target [CP.target_state] done [CP.done_cycling()] mem [json_encode(CP.memory)]"
	return jointext(out, "; ")
