// Web-shuttle configuration sanity.
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
