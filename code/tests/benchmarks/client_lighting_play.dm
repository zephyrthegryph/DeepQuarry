// Client lighting in play against the DM corner lighting: the same door flips and light moves in both modes, timed through
// the light pass, plus the mask rebuilds they cause (each rebuild is one appearance change sent to viewers: the bandwidth
// stand-in), against the same play with the per-client glow holder (client_glow_holder.dm) and what its copies cost.
//   tools/build/build.sh bench --scenario=client_lighting_play [--arg rounds=20] [--arg doors=40]

/datum/benchmark/client_lighting_play
	id = "client_lighting_play"
	description = "Client lighting vs DM lighting: door flips and moving lights through the light pass"
	/// The light-move share of the last play() (the rest is door flips).
	var/last_move_ms = 0

/datum/benchmark/client_lighting_play/proc/doors(n)
	. = list()
	for(var/obj/machinery/door/airlock/A in world)
		if(A.opacity && isturf(A.loc))
			. += A
			if(length(.) >= n)
				return

/// One round: every door flips opacity twice (close/open as sight sees it) and every moved light steps east and back.
/datum/benchmark/client_lighting_play/proc/play(list/doors, list/lights, rounds)
	var/start = REALTIMEOFDAY
	var/move_ds = 0
	for(var/r in 1 to rounds)
		for(var/obj/machinery/door/airlock/A as anything in doors)
			A.set_opacity(FALSE)
		SSlighting.light_step(0, TRUE)
		for(var/obj/machinery/door/airlock/A as anything in doors)
			A.set_opacity(TRUE)
		SSlighting.light_step(0, TRUE)
		var/move_start = REALTIMEOFDAY
		for(var/obj/O as anything in lights)
			var/turf/T = get_turf(O)
			var/turf/E = locate(T.x + 1, T.y, T.z)
			if(E)
				O.abstract_move(E)
				SSlighting.light_step(0, TRUE)
				O.abstract_move(T)
				SSlighting.light_step(0, TRUE)
		move_ds += REALTIMEOFDAY - move_start
	last_move_ms = move_ds * 100
	return (REALTIMEOFDAY - start) * 100

/datum/benchmark/client_lighting_play/proc/contents_loop_ms()
	var/start = REALTIMEOFDAY
	var/n = 0
	for(var/turf/T as anything in block(locate(1, 1, 1), locate(world.maxx, world.maxy, world.maxz)))
		for(var/atom/movable/AM in T)
			n++
	return list((REALTIMEOFDAY - start) * 100, n)

/datum/benchmark/client_lighting_play/Run()
	var/rounds = param("rounds", 20)
	var/list/doors = doors(param("doors", 40))
	var/list/lights = list()
	for(var/obj/machinery/light/L in world)
		if(L.light && isturf(L.loc))
			lights += L
			if(length(lights) >= 10)
				break
	metric("client_play_doors", length(doors), "doors", "none")
	metric("client_play_lights_moved", length(lights), "lights", "none")

	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)
	var/dm_ms = play(doors, lights, rounds)
	var/dm_move_ms = last_move_ms
	var/list/dm_loop = contents_loop_ms()

	// Client lighting with no viewer holding a copy (the glow bounds stay off: section 4 of the holder brief).
	GLOB.client_glow_bounds = FALSE
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	var/list/nobounds_loop = contents_loop_ms()
	var/nobounds_ms = play(doors, lights, rounds)
	var/nobounds_move_ms = last_move_ms

	// The same with the per-client glow holder: one viewer per moved light, its eye ten turfs west, so that light is held
	// off screen and every door flip or move near it updates the copy.
	var/list/holders = list()
	for(var/obj/O as anything in lights)
		var/turf/T = get_turf(O)
		var/datum/client_glow_holder/H = new
		H.view_at(client_glow_test_eye(T), 7, 7)
		holders += H
	var/held = 0
	for(var/datum/client_glow_holder/H as anything in holders)
		held += LAZYLEN(H.held)
	var/builds = GLOB.client_glow_mask_builds
	var/reconsiders = GLOB.client_glow_reconsiders
	var/made = GLOB.client_glow_holder_made
	var/updated = GLOB.client_glow_holder_updated
	var/dropped = GLOB.client_glow_holder_dropped
	begin_window() // a profiled run (--profile) dumps the proc profile of the holder play
	var/client_ms = play(doors, lights, rounds)
	end_window("client_play")
	var/client_move_ms = last_move_ms
	builds = GLOB.client_glow_mask_builds - builds
	reconsiders = GLOB.client_glow_reconsiders - reconsiders
	made = GLOB.client_glow_holder_made - made
	updated = GLOB.client_glow_holder_updated - updated
	dropped = GLOB.client_glow_holder_dropped - dropped
	var/list/holder_loop = contents_loop_ms()
	for(var/datum/client_glow_holder/H as anything in holders)
		spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

	metric("client_play_dm_ms", dm_ms, "ms")
	metric("client_play_dm_move_ms", dm_move_ms, "ms")
	metric("client_play_client_move_ms", client_move_ms, "ms")
	metric("client_play_client_ms", client_ms, "ms")
	metric("client_play_client_nobounds_ms", nobounds_ms, "ms")
	metric("client_play_client_nobounds_move_ms", nobounds_move_ms, "ms")
	metric("client_play_holder_viewers", length(holders), "viewers", "none")
	metric("client_play_holder_lights_held", held, "lights", "none")
	metric("client_play_holder_images_made", made, "copies", "none")
	metric("client_play_holder_images_updated", updated, "updates", "none")
	metric("client_play_holder_images_dropped", dropped, "drops", "none")
	metric("client_play_holder_updates_per_round", rounds ? (made + updated + dropped) / rounds : 0, "updates", "none")
	metric("client_play_mask_builds", builds, "builds", "none")
	metric("client_play_mask_builds_per_door_flip", length(doors) ? builds / (rounds * length(doors) * 2) : 0, "builds", "none")
	metric("client_play_opacity_redraws", reconsiders, "redraws", "none")
	metric("contents_loop_dm_ms", dm_loop[1], "ms")
	metric("contents_loop_holder_ms", holder_loop[1], "ms")
	metric("contents_loop_nobounds_ms", nobounds_loop[1], "ms")
	metric("contents_loop_dm_entries", dm_loop[2], "entries", "none")
	metric("contents_loop_holder_entries", holder_loop[2], "entries", "none")
	metric("contents_loop_nobounds_entries", nobounds_loop[2], "entries", "none")
