// Web-shuttle configuration sanity.

/datum/unit_test/dq_arrivals_idle_automation_owned_by_shuttles

/datum/shuttle/autodock/ferry/arrivals/unit_test
	defer_initialisation = TRUE
	shuttle_area = /area

/datum/unit_test/dq_arrivals_idle_automation_owned_by_shuttles/Run()
	var/datum/shuttle/autodock/ferry/arrivals/shuttle = new /datum/shuttle/autodock/ferry/arrivals/unit_test("Unit Test Arrivals")
	TEST_ASSERT(shuttle.always_process, "arrivals shuttle does not request idle processing from SSshuttles")
	var/obj/machinery/computer/shuttle_control/arrivals/console = new(null)
	TEST_ASSERT_EQUAL(console.process(), PROCESS_KILL, "arrivals console still polls an idle shuttle")
	qdel(console)
	qdel(shuttle)

/datum/unit_test/dq_shuttle_active_set_is_event_driven

/datum/shuttle/unit_test_active_set
	shuttle_area = /area
	defer_initialisation = TRUE

/datum/unit_test/dq_shuttle_active_set_is_event_driven/Run()
	var/datum/shuttle/shuttle = new /datum/shuttle/unit_test_active_set
	shuttle.flags |= SHUTTLE_FLAGS_PROCESS
	SSshuttles.process_shuttles |= shuttle
	shuttle.set_process_state(IDLE_STATE)
	TEST_ASSERT(!(shuttle in SSshuttles.active_process_shuttles), "idle shuttle remained in the active processing set")
	shuttle.set_process_state(WAIT_LAUNCH)
	TEST_ASSERT(shuttle in SSshuttles.active_process_shuttles, "launching shuttle did not enter the active processing set")
	shuttle.set_process_state(IDLE_STATE)
	TEST_ASSERT(!(shuttle in SSshuttles.active_process_shuttles), "settled shuttle did not leave the active processing set")
	qdel(shuttle)

/datum/shuttle/autodock/unit_test_controller_relation
	shuttle_area = /area
	defer_initialisation = TRUE

/datum/unit_test/dq_shuttle_docking_controller_relation_lifetime
	needs_test_block = FALSE

/datum/unit_test/dq_shuttle_docking_controller_relation_lifetime/Run()
	var/datum/shuttle/autodock/unit_test_controller_relation/shuttle = new
	var/datum/embedded_program/docking/first = new
	var/datum/embedded_program/docking/second = new
	var/datum/embedded_program/docking/third = new
	TEST_ASSERT(shuttle.set_shuttle_docking_controller(first), "Shuttle could not link its own docking controller")
	TEST_ASSERT(shuttle.set_active_docking_controller(first), "Shuttle could not link the same controller as its active dock")
	TEST_ASSERT(om_has_link(shuttle, /datum/object_model/relation/shuttle_own_docking_controller, first), "Own controller relation was missing")
	TEST_ASSERT(om_has_link(shuttle, /datum/object_model/relation/shuttle_active_docking_controller, first), "Active controller relation was missing")
	TEST_ASSERT(shuttle.set_shuttle_docking_controller(second), "Shuttle could not replace its own controller")
	TEST_ASSERT(shuttle.shuttle_docking_controller == second, "Own controller mirror did not switch")
	TEST_ASSERT(shuttle.active_docking_controller == first, "Replacing own controller disturbed the active controller")
	qdel(first)
	TEST_ASSERT(!shuttle.active_docking_controller, "Deleting active controller left a stale mirror")
	TEST_ASSERT(shuttle.shuttle_docking_controller == second, "Deleting active controller cleared the separate own controller")
	TEST_ASSERT(shuttle.set_active_docking_controller(second), "Shuttle could not share the replacement controller across both roles")
	qdel(second)
	TEST_ASSERT(!shuttle.shuttle_docking_controller, "Deleting shared controller left own controller mirror")
	TEST_ASSERT(!shuttle.active_docking_controller, "Deleting shared controller left active controller mirror")
	TEST_ASSERT(!length(om_linked(shuttle, /datum/object_model/relation/shuttle_own_docking_controller)), "Deleting shared controller left own relation")
	TEST_ASSERT(!length(om_linked(shuttle, /datum/object_model/relation/shuttle_active_docking_controller)), "Deleting shared controller left active relation")
	TEST_ASSERT(shuttle.set_shuttle_docking_controller(third), "Shuttle could not link a surviving controller")
	qdel(shuttle)
	TEST_ASSERT(!length(om_linked_to(third, /datum/object_model/relation/shuttle_own_docking_controller)), "Deleting shuttle left a controller relation")
	qdel(third)

/obj/effect/shuttle_landmark/unit_test_controller_relation
	landmark_tag = "dq-test-landmark-controller-relation"

/datum/embedded_program/docking/unit_test_landmark_lookup
	id_tag = "dq-test-landmark-docking-tag"

/obj/effect/shuttle_landmark/unit_test_resolved_controller
	landmark_tag = "dq-test-landmark-resolved-controller"
	docking_controller = "dq-test-landmark-docking-tag"

/obj/effect/shuttle_landmark/unit_test_missing_controller
	landmark_tag = "dq-test-landmark-missing-controller"
	docking_controller = "dq-test-missing-docking-tag"

/datum/unit_test/dq_shuttle_landmark_controller_relation_lifetime
	needs_test_block = FALSE

/datum/unit_test/dq_shuttle_landmark_controller_relation_lifetime/Run()
	var/turf/spawn_turf = locate(1, 1, 1)
	var/obj/effect/shuttle_landmark/unit_test_controller_relation/landmark = new(spawn_turf)
	var/datum/embedded_program/docking/first = new
	var/datum/embedded_program/docking/second = new
	TEST_ASSERT(landmark.set_docking_controller(first), "Landmark could not link a controller")
	TEST_ASSERT(om_has_link(landmark, /datum/object_model/relation/shuttle_landmark_docking_controller, first), "Landmark controller relation was missing")
	TEST_ASSERT(landmark.set_docking_controller(second), "Landmark could not replace its controller")
	TEST_ASSERT(landmark.docking_controller == second, "Landmark kept the replaced controller")
	TEST_ASSERT(!length(om_linked_to(first, /datum/object_model/relation/shuttle_landmark_docking_controller)), "Replaced controller kept landmark relation")
	qdel(second)
	TEST_ASSERT(!landmark.docking_controller, "Deleted controller remained on landmark")
	TEST_ASSERT(!length(om_linked(landmark, /datum/object_model/relation/shuttle_landmark_docking_controller)), "Deleted controller relation remained on landmark")
	TEST_ASSERT(landmark.set_docking_controller(first), "Landmark could not rebind its controller")
	qdel(landmark)
	TEST_ASSERT(!length(om_linked_to(first, /datum/object_model/relation/shuttle_landmark_docking_controller)), "Deleted landmark kept controller relation")
	SSshuttles.registered_shuttle_landmarks -= "dq-test-landmark-controller-relation"
	qdel(first)
	var/datum/embedded_program/docking/unit_test_landmark_lookup/looked_up = new
	var/obj/effect/shuttle_landmark/unit_test_resolved_controller/resolved = new(spawn_turf)
	resolved.LateInitialize()
	TEST_ASSERT(resolved.docking_controller == looked_up, "Landmark did not resolve its mapped docking tag")
	TEST_ASSERT(om_has_link(resolved, /datum/object_model/relation/shuttle_landmark_docking_controller, looked_up), "Mapped docking tag did not create a relation")
	qdel(resolved)
	SSshuttles.registered_shuttle_landmarks -= "dq-test-landmark-resolved-controller"
	qdel(looked_up)
	var/obj/effect/shuttle_landmark/unit_test_missing_controller/missing = new(spawn_turf)
	missing.LateInitialize()
	TEST_ASSERT(!missing.docking_controller, "Missing docking tag resolved to a stale controller")
	TEST_ASSERT(!length(om_linked(missing, /datum/object_model/relation/shuttle_landmark_docking_controller)), "Missing docking tag created a relation")
	qdel(missing)
	SSshuttles.registered_shuttle_landmarks -= "dq-test-landmark-missing-controller"

/datum/shuttle/autodock/ferry/escape_pod/unit_test_arming_relation
	shuttle_area = /area
	defer_initialisation = TRUE

/datum/shuttle/autodock/ferry/escape_pod/unit_test_arming_relation/first
	name = "DQ arming relation pod one"

/datum/shuttle/autodock/ferry/escape_pod/unit_test_arming_relation/second
	name = "DQ arming relation pod two"

/datum/unit_test/dq_escape_pod_arming_controller_relation_lifetime
	needs_test_block = FALSE

/datum/unit_test/dq_escape_pod_arming_controller_relation_lifetime/Run()
	var/datum/shuttle/autodock/ferry/escape_pod/unit_test_arming_relation/first/first_pod = new
	var/datum/shuttle/autodock/ferry/escape_pod/unit_test_arming_relation/second/second_pod = new
	var/datum/embedded_program/docking/simple/escape_pod_berth/first_berth = new
	var/datum/embedded_program/docking/simple/escape_pod_berth/second_berth = new
	TEST_ASSERT(first_pod.set_arming_controller(first_berth), "First pod could not link its berth")
	TEST_ASSERT(second_pod.set_arming_controller(first_berth), "Second pod could not share the berth")
	TEST_ASSERT(length(om_linked_to(first_berth, /datum/object_model/relation/escape_pod_arming_controller)) == 2, "Shared berth did not track both pods")
	TEST_ASSERT(first_pod.set_arming_controller(second_berth), "First pod could not replace its berth")
	TEST_ASSERT(first_pod.arming_controller == second_berth, "First pod retained the old berth")
	TEST_ASSERT(second_pod.arming_controller == first_berth, "Replacing one pod berth changed the other pod")
	qdel(first_berth)
	TEST_ASSERT(!second_pod.arming_controller, "Deleted shared berth remained on second pod")
	TEST_ASSERT(!second_pod.can_launch(), "Pod could launch without a live arming berth")
	TEST_ASSERT(!second_pod.can_force(), "Pod could force-launch without a live arming berth")
	TEST_ASSERT(first_pod.arming_controller == second_berth, "Deleting old berth cleared replacement on first pod")
	qdel(first_pod)
	TEST_ASSERT(!length(om_linked_to(second_berth, /datum/object_model/relation/escape_pod_arming_controller)), "Deleted pod kept its berth relation")
	TEST_ASSERT(second_pod.set_arming_controller(second_berth), "Second pod could not rebind to surviving berth")
	qdel(second_berth)
	TEST_ASSERT(!second_pod.arming_controller, "Deleted berth remained on second pod")
	qdel(second_pod)
	SSemergency_shuttle.escape_pods -= "DQ arming relation pod one"
	SSemergency_shuttle.escape_pods -= "DQ arming relation pod two"
//
// A web-shuttle destination whose map landmark doesn't exist (e.g. it lived on
// a z-level this map no longer loads) used to survive init with a null
// my_landmark; the autopilot would then long_jump(null, ...) and runtime every
// hop (shuttle.dm create_warning_effect/attempt_move null derefs). Destinations
// and autopaths are now pruned at build time — these tests pin that contract.
/datum/unit_test/dq_web_shuttle_destinations_have_landmarks

/datum/unit_test/dq_web_shuttle_destinations_have_landmarks/Run()
	var/webs = 0
	for(var/name in SSshuttles.shuttles)
		var/datum/shuttle/S = SSshuttles.shuttles[name]
		if(!istype(S, /datum/shuttle/autodock/web_shuttle))
			continue
		var/datum/shuttle/autodock/web_shuttle/WS = S
		if(!WS.web_master)
			continue
		webs++
		for(var/datum/shuttle_destination/D in WS.web_master.destinations)
			TEST_ASSERT_NOTNULL(D.my_landmark, "web shuttle '[name]' kept destination '[D.name]' ([D.type]) with no landmark — should have been pruned")
			// Every surviving route must connect two surviving destinations.
			for(var/datum/shuttle_route/R in D.routes)
				TEST_ASSERT_NOTNULL(R.start, "route on '[D.name]' has a null start")
				TEST_ASSERT_NOTNULL(R.end, "route on '[D.name]' has a null end")
				TEST_ASSERT(R.start.my_landmark && R.end.my_landmark, "web shuttle '[name]' route [R.start.name] <-> [R.end.name] touches a landmark-less destination")
		// Autopaths must only reference destinations that survived the prune.
		for(var/datum/shuttle_autopath/P in WS.web_master.autopaths)
			TEST_ASSERT_NOTNULL(WS.web_master.get_destination_by_type(P.start), "web shuttle '[name]' autopath [P.type] starts at a pruned destination")
			for(var/node_type in P.path_nodes)
				TEST_ASSERT_NOTNULL(WS.web_master.get_destination_by_type(node_type), "web shuttle '[name]' autopath [P.type] routes through pruned destination [node_type]")
	log_test("Checked [webs] web shuttles for landmark-less destinations/autopaths.")

// The jump procs themselves must refuse null landmarks instead of runtiming —
// the last line of defence if config pruning ever regresses.
/datum/unit_test/dq_shuttle_jump_refuses_null_landmark

/datum/unit_test/dq_shuttle_jump_refuses_null_landmark/Run()
	var/datum/shuttle/S
	for(var/name in SSshuttles.shuttles)
		S = SSshuttles.shuttles[name]
		if(istype(S))
			break
	if(!istype(S))
		log_test("No shuttles on this map; skipping null-jump guard check.")
		return
	var/prior_status = S.moving_status
	var/prior_location = S.current_location
	// All three must early-return without runtiming (runtime => test failure).
	S.long_jump(null, null, 10)
	S.short_jump(null)
	TEST_ASSERT(!S.attempt_move(null), "attempt_move(null) did not refuse the move")
	TEST_ASSERT_EQUAL(S.moving_status, prior_status, "null jump changed moving_status")
	TEST_ASSERT_EQUAL(S.current_location, prior_location, "null jump moved the shuttle")
	S.create_warning_effect(null) // must be a no-op

/datum/unit_test/dq_shuttle_repeated_moves_preserve_air

/datum/unit_test/dq_shuttle_repeated_moves_preserve_air/proc/measure_oxygen(datum/shuttle/shuttle)
	. = 0
	for(var/area/A as anything in shuttle.shuttle_area)
		for(var/turf/open/T in A)
			if(!T.blocks_air && T.air)
				. += T.air.get_moles(/datum/gas/oxygen)

/datum/unit_test/dq_shuttle_repeated_moves_preserve_air/proc/gas_diagnostics(datum/shuttle/shuttle)
	var/turf_count = 0
	var/total_moles = 0
	var/oxygen = 0
	for(var/area/A as anything in shuttle.shuttle_area)
		for(var/turf/open/T in A)
			if(T.blocks_air || !T.air)
				continue
			turf_count++
			total_moles += T.air.total_moles()
			oxygen += T.air.get_moles(/datum/gas/oxygen)
	return "turfs=[turf_count], total=[total_moles], oxygen=[oxygen], location=[shuttle.current_location?.landmark_tag] z=[shuttle.current_location?.z]"

/datum/unit_test/dq_shuttle_repeated_moves_preserve_air/proc/wait_for_atmos(cycles)
	// Deterministic gas frames (the test hook), no wall-clock wait.
	SSair.run_gas_frames(cycles)
	return TRUE

/datum/unit_test/dq_shuttle_repeated_moves_preserve_air/proc/find_space_leak(datum/shuttle/shuttle)
	var/list/visited = list()
	var/list/queue = list()
	for(var/area/A as anything in shuttle.shuttle_area)
		for(var/turf/open/T in A)
			if(!T.blocks_air && T.air?.return_pressure() > 80)
				visited[T] = TRUE
				queue += T
	var/head = 1
	while(head <= length(queue))
		var/turf/open/current = queue[head++]
		for(var/turf/open/neighbor as anything in vg_atmos_adjacent_turfs(current))
			if(visited[neighbor])
				continue
			if(!(neighbor.loc in shuttle.shuttle_area))
				var/list/current_contents = list()
				var/list/neighbor_contents = list()
				for(var/obj/current_object in current)
					current_contents += "[current_object.type](density=[current_object.density],atmos=[current_object.can_atmos_pass])"
				for(var/obj/neighbor_object in neighbor)
					neighbor_contents += "[neighbor_object.type](density=[neighbor_object.density],atmos=[neighbor_object.can_atmos_pass])"
				return "[current.x],[current.y],[current.z] [current.type] -> external turf [neighbor.x],[neighbor.y],[neighbor.z] ([neighbor.type], area [neighbor.loc?.type]); current=[current_contents.Join(", ")]; external=[neighbor_contents.Join(", ")]"
			if(istype(neighbor, /turf/space))
				var/list/blockers = list()
				for(var/obj/O in current)
					blockers += "[O.type](density=[O.density],atmos=[O.can_atmos_pass])"
				return "[current.x],[current.y],[current.z] -> space [neighbor.x],[neighbor.y],[neighbor.z]; contents=[blockers.Join(", ")]"
			visited[neighbor] = TRUE
			queue += neighbor

/datum/unit_test/dq_shuttle_repeated_moves_preserve_air/Run()
	var/datum/shuttle/autodock/ferry/shuttle = SSshuttles.shuttles["Ferry-Demo"]
	if(!shuttle)
		log_test("Ferry-Demo is not mapped; skipping generic repeated shuttle move test.")
		return
	// attempt_move() deliberately bypasses the autodock handshake used by launch(),
	// so seal the mapped external hatch before exercising turf translation itself.
	// Poll every tick (same 10 s budget) rather than once a second.
	for(var/attempt in 1 to 100)
		var/all_closed = TRUE
		for(var/area/A as anything in shuttle.shuttle_area)
			for(var/obj/machinery/door/airlock/D in A)
				if(!D.density)
					all_closed = FALSE
					if(!D.operating)
						D.unlock()
						D.close(TRUE, TRUE)
		if(all_closed)
			break
		sleep(1)
	for(var/area/A as anything in shuttle.shuttle_area)
		for(var/obj/machinery/door/airlock/D in A)
			TEST_ASSERT(D.density, "Ferry-Demo test hatch did not close before repeated moves")
	dq_unit_test_wait_air_until_quiescent(5, 1)
	var/baseline = measure_oxygen(shuttle)
	TEST_ASSERT(baseline > 0, "Ferry-Demo began without oxygen")
	for(var/hop in 1 to 8)
		var/obj/effect/shuttle_landmark/next_landmark = shuttle.current_location == shuttle.landmark_offsite ? shuttle.landmark_station : shuttle.landmark_offsite
		TEST_ASSERT(shuttle.attempt_move(next_landmark), "Ferry-Demo repeated move [hop] failed")
		for(var/area/topology_area as anything in shuttle.shuttle_area)
			for(var/turf/open/topology_turf in topology_area)
				if(!topology_turf.blocks_air && topology_turf.air)
					TEST_ASSERT(vg_topology_matches(topology_turf), "Rust/DM atmos topology diverged after shuttle move [hop] at [topology_turf.x],[topology_turf.y],[topology_turf.z]")
		var/immediate_oxygen = measure_oxygen(shuttle)
		TEST_ASSERT(immediate_oxygen >= baseline * 0.99, "Ferry-Demo lost oxygen during turf translation on move [hop]: [baseline] -> [immediate_oxygen]")
		if(next_landmark == shuttle.landmark_offsite)
			var/leak = find_space_leak(shuttle)
			TEST_ASSERT(!leak, "Ferry-Demo pressure volume was connected to space after move [hop]: [leak]")
		// Five gas frames, run deterministically; a leak would drain the
		// shuttle within them.
		for(var/cycle in 1 to 5)
			SSair.run_gas_frames(1)
			for(var/area/cycle_area as anything in shuttle.shuttle_area)
				for(var/turf/open/cycle_turf in cycle_area)
					if(!cycle_turf.blocks_air && cycle_turf.air)
						TEST_ASSERT(vg_topology_matches(cycle_turf), "Rust/DM atmos topology diverged after shuttle move [hop], atmos cycle [cycle], at [cycle_turf.x],[cycle_turf.y],[cycle_turf.z]")
		var/hop_oxygen = measure_oxygen(shuttle)
		if(next_landmark == shuttle.landmark_offsite)
			TEST_ASSERT(hop_oxygen >= baseline * 0.99, "Ferry-Demo lost oxygen after returning offsite on repeated move [hop]: [baseline] -> [hop_oxygen]; [gas_diagnostics(shuttle)]")

/datum/unit_test/dq_arrivals_shuttle_preserves_air

/datum/unit_test/dq_arrivals_shuttle_preserves_air/proc/measure_oxygen(datum/shuttle/shuttle)
	. = 0
	for(var/area/A as anything in shuttle.shuttle_area)
		for(var/turf/open/T in A)
			if(!T.blocks_air && T.air)
				. += T.air.get_moles(/datum/gas/oxygen)

/datum/unit_test/dq_arrivals_shuttle_preserves_air/proc/wait_for_atmos(cycles)
	// Deterministic gas frames (the test hook), no wall-clock wait.
	SSair.run_gas_frames(cycles)
	return TRUE

/datum/unit_test/dq_arrivals_shuttle_preserves_air/Run()
	var/datum/shuttle/autodock/ferry/arrivals/shuttle = SSshuttles.shuttles["Arrivals"]
	TEST_ASSERT_NOTNULL(shuttle, "Southern Cross arrivals shuttle was not registered")
	TEST_ASSERT(shuttle.always_process, "arrivals shuttle is not configured for subsystem-owned idle automation")
	TEST_ASSERT(shuttle in SSshuttles.process_shuttles, "arrivals shuttle is absent from the shuttle processing set")
	TEST_ASSERT(shuttle in SSshuttles.active_process_shuttles, "always-processing arrivals shuttle is absent from the active processing set")
	var/obj/machinery/computer/shuttle_control/arrivals/console = locate() in world
	TEST_ASSERT_NOTNULL(console, "Southern Cross arrivals control console was not mapped")
	TEST_ASSERT_EQUAL(console.process(), PROCESS_KILL, "arrivals console still performs idle polling instead of hibernating")
	TEST_ASSERT_NOTNULL(shuttle.landmark_station, "arrivals shuttle has no station landmark")
	var/total_o2_before = 0
	var/pressurized_turfs_before = 0
	for(var/area/A as anything in shuttle.shuttle_area)
		for(var/turf/open/T in A)
			if(T.blocks_air || !T.air)
				continue
			total_o2_before += T.air.get_moles(/datum/gas/oxygen)
			if(T.air.return_pressure() > 80)
				pressurized_turfs_before++
	TEST_ASSERT(pressurized_turfs_before > 0, "arrivals shuttle is already airless off-station")
	var/list/visited = list()
	for(var/area/A as anything in shuttle.shuttle_area)
		for(var/turf/open/component_seed in A)
			if(component_seed.blocks_air || component_seed.initial_gas_mix != OPENTURF_DEFAULT_ATMOS || visited[component_seed])
				continue
			visited[component_seed] = TRUE
			var/list/queue = list(component_seed)
			var/head = 1
			while(head <= queue.len)
				var/turf/open/current = queue[head++]
				for(var/turf/open/neighbor as anything in vg_atmos_adjacent_turfs(current))
					if(visited[neighbor])
						continue
					TEST_ASSERT(!istype(neighbor, /turf/space), "arrivals shuttle atmosphere from [component_seed.x],[component_seed.y],[component_seed.z] reaches space at [current.x],[current.y],[current.z] -> [neighbor.x],[neighbor.y],[neighbor.z]")
					TEST_ASSERT(neighbor.initial_gas_mix != AIRLESS_ATMOS, "arrivals shuttle atmosphere from [component_seed.x],[component_seed.y],[component_seed.z] reaches an airless turf at [current.x],[current.y],[current.z] -> [neighbor.x],[neighbor.y],[neighbor.z]")
					visited[neighbor] = TRUE
					queue += neighbor
	var/baseline_fires = SSair.times_fired
	var/soak_deadline = world.time + 30 SECONDS
	while(SSair.times_fired < baseline_fires + 40)
		if(world.time >= soak_deadline)
			TEST_FAIL("SSair did not advance during the arrivals soak")
			break
		sleep(max(SSair.wait, 1))
	var/soaked_o2 = 0
	for(var/area/A as anything in shuttle.shuttle_area)
		for(var/turf/open/T in A)
			if(!T.blocks_air && T.air)
				soaked_o2 += T.air.get_moles(/datum/gas/oxygen)
				if(T.initial_gas_mix == OPENTURF_DEFAULT_ATMOS)
					TEST_ASSERT(T.air.return_pressure() > 80, "habitable arrivals shuttle turf became airless while waiting at [T.x],[T.y],[T.z]: [T.air.return_pressure()] kPa in [get_area(T)]")
	TEST_ASSERT(soaked_o2 >= total_o2_before * 0.99, "arrivals shuttle lost oxygen while waiting off-station: [total_o2_before] -> [soaked_o2]")
	TEST_ASSERT(shuttle.attempt_move(shuttle.landmark_station), "arrivals shuttle could not move to its station landmark")
	var/total_o2_after = 0
	var/pressurized_turfs_after = 0
	for(var/area/A as anything in shuttle.shuttle_area)
		for(var/turf/open/T in A)
			if(T.blocks_air || !T.air)
				continue
			total_o2_after += T.air.get_moles(/datum/gas/oxygen)
			if(T.air.return_pressure() > 80)
				pressurized_turfs_after++
			if(T.initial_gas_mix == OPENTURF_DEFAULT_ATMOS)
				TEST_ASSERT(T.air.return_pressure() > 80, "habitable arrivals shuttle turf arrived airless at [T.x],[T.y],[T.z]: [T.air.return_pressure()] kPa in [get_area(T)]")
	TEST_ASSERT(pressurized_turfs_after > 0, "arrivals shuttle became airless after moving")
	TEST_ASSERT(total_o2_after >= total_o2_before * 0.99, "arrivals shuttle lost oxygen while moving: [total_o2_before] -> [total_o2_after]")
	TEST_ASSERT(shuttle.attempt_move(shuttle.landmark_offsite), "arrivals shuttle could not return to its off-station landmark")
	var/repeated_move_baseline = measure_oxygen(shuttle)
	for(var/hop in 1 to 6)
		wait_for_atmos(5)
		var/obj/effect/shuttle_landmark/next_landmark = shuttle.current_location == shuttle.landmark_offsite ? shuttle.landmark_station : shuttle.landmark_offsite
		TEST_ASSERT(shuttle.attempt_move(next_landmark), "arrivals shuttle repeated move [hop] failed")
		wait_for_atmos(5)
		var/hop_oxygen = measure_oxygen(shuttle)
		TEST_ASSERT(hop_oxygen >= repeated_move_baseline * 0.99, "arrivals shuttle lost oxygen over repeated move [hop]: [repeated_move_baseline] -> [hop_oxygen]")

/datum/unit_test/dq_escape_shuttle_preserves_air

/datum/unit_test/dq_escape_shuttle_preserves_air/Run()
	var/datum/shuttle/autodock/ferry/emergency/shuttle = SSshuttles.shuttles["Escape"]
	TEST_ASSERT_NOTNULL(shuttle, "Southern Cross escape shuttle was not registered")
	TEST_ASSERT_NOTNULL(shuttle.landmark_station, "escape shuttle has no station landmark")
	var/total_o2_before = 0
	var/turf/open/component_start
	for(var/area/A as anything in shuttle.shuttle_area)
		for(var/turf/open/T in A)
			if(T.blocks_air || !T.air)
				continue
			total_o2_before += T.air.get_moles(/datum/gas/oxygen)
			if(T.air.return_pressure() > 80)
				component_start ||= T
	TEST_ASSERT_NOTNULL(component_start, "escape shuttle is already airless off-station")
	var/list/visited = list()
	visited[component_start] = TRUE
	var/list/queue = list(component_start)
	var/head = 1
	while(head <= queue.len)
		var/turf/open/current = queue[head++]
		for(var/turf/open/neighbor as anything in vg_atmos_adjacent_turfs(current))
			if(visited[neighbor])
				continue
			TEST_ASSERT(!istype(neighbor, /turf/space), "escape shuttle atmosphere reaches space at [current.x],[current.y],[current.z] -> [neighbor.x],[neighbor.y],[neighbor.z]")
			visited[neighbor] = TRUE
			queue += neighbor
	var/baseline_fires = SSair.times_fired
	var/soak_deadline = world.time + 30 SECONDS
	while(SSair.times_fired < baseline_fires + 40)
		if(world.time >= soak_deadline)
			TEST_FAIL("SSair did not advance during the escape-shuttle soak")
			break
		sleep(max(SSair.wait, 1))
	var/soaked_o2 = 0
	for(var/area/A as anything in shuttle.shuttle_area)
		for(var/turf/open/T in A)
			if(!T.blocks_air && T.air)
				soaked_o2 += T.air.get_moles(/datum/gas/oxygen)
	TEST_ASSERT(soaked_o2 >= total_o2_before * 0.99, "escape shuttle lost oxygen while waiting off-station: [total_o2_before] -> [soaked_o2]")
	TEST_ASSERT(shuttle.attempt_move(shuttle.landmark_station), "escape shuttle could not move to its station landmark")
	var/total_o2_after = 0
	for(var/area/A as anything in shuttle.shuttle_area)
		for(var/turf/open/T in A)
			if(!T.blocks_air && T.air)
				total_o2_after += T.air.get_moles(/datum/gas/oxygen)
	TEST_ASSERT(total_o2_after >= soaked_o2 * 0.99, "escape shuttle lost oxygen while moving: [soaked_o2] -> [total_o2_after]")
	TEST_ASSERT(shuttle.attempt_move(shuttle.landmark_offsite), "escape shuttle could not return to its off-station landmark")
