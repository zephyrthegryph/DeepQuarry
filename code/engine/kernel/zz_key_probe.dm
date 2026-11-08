// TEMP (perf/stall-in-play, never landed): times the build of the timer keys; any build over 50 ms is logged as KEY_STALL.
GLOBAL_REAL_VAR(__key_t0) = 0
GLOBAL_REAL_VAR(__key_builds) = 0
/proc/__key_timed_start()
	__key_t0 = TICK_USAGE_REAL
	return 0

/proc/__key_timed_end(label, key)
	__key_builds++
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - __key_t0)
	if(ms > 50)
		log_runtime("KEY_STALL [label] [round(ms, 0.1)] ms (build #[__key_builds]) key=[key]")
	return key
