// Migration bridge: one scheduled Behaviour owns the ordered Life frame.
// Existing life_system flyweights still supply content and intra-frame order.
/datum/object_model/behaviour/living_life_frame
	run_period = LIFE_NOMINAL_SECONDS SECONDS
	run_priority = SCHEDULE_PRIORITY_VITAL
	run_max_lateness = 0.5 SECONDS
	run_cost_hint_ms = 4
	run_shared_cadence = TRUE
	run_set = /datum/object_model/schedule_set/biology
	preserve_deadline_on_wake = TRUE

/datum/object_model/behaviour/living_life_frame/on_run(datum/source, seconds, list/config)
	var/mob/living/M = source
	if(!M || QDELETED(M))
		return 0
	if(!Master || Master.current_runlevel < 1 || !(SSmobs.runlevels & (1 << (Master.current_runlevel - 1))) || !SSmobs.can_fire)
		return run_period
	if(!M.enabled)
		M.life_discard_elapsed_biology()
		return run_period
	if(M.low_priority && !(M.loc && get_z(M) && length(GLOB.living_players_by_zlevel[get_z(M)])))
		M.life_discard_elapsed_biology()
		return run_period
	M.life_frame_running = TRUE
	if(M.life_timer_at && M.life_timer_at <= world.time)
		M.life_timer_fired()
	var/biology_before = M.biological_cycle
	var/profile = !(++SSmobs.life_profile_index % SSmobs.profile_sample_stride)
	var/profile_start = profile ? TICK_USAGE : 0
	M.Life(seconds > 0 ? seconds : LIFE_NOMINAL_SECONDS, profile)
	if(!QDELETED(M))
		om_behaviour_report_work(M, type, M.biological_cycle - biology_before)
	if(profile && !QDELETED(M))
		var/mob_type = "[M.type]"
		SSmobs.profile_type_cost[mob_type] += TICK_DELTA_TO_MS(TICK_USAGE - profile_start) * SSmobs.profile_sample_stride
		SSmobs.profile_type_calls[mob_type] += SSmobs.profile_sample_stride
	if(!QDELETED(M))
		M.life_frame_running = FALSE
	if(QDELETED(M) || M.life_hibernating)
		if(!QDELETED(M))
			var/datum/object_model/behaviour_runtime/R = M.om_state?.behaviour_runtime
			R?.cancel_deadline(type)
			if(M.life_timer_at)
				R?.schedule_at(type, M.life_timer_at)
		return 0
	return null
