/// Logging for loading and caching assets
/proc/log_asset(text, list/data)
	logger.Log(LOG_CATEGORY_DEBUG_ASSET, text, data)

/// Logging for config errors
/// Rarely gets called; just here in case the config breaks.
/proc/log_config(text, list/data)
	logger.Log(LOG_CATEGORY_CONFIG, text, data)
	SEND_TEXT(world.log, text)

/// Logging for mapping errors
/proc/log_mapping(text, skip_world_log)
#ifdef UNIT_TESTS
	GLOB.unit_test_mapping_logs += text
#endif
#ifdef MAP_TEST
	message_admins("Mapping: [text]")
#endif
	logger.Log(LOG_CATEGORY_DEBUG_MAPPING, text)
	if(skip_world_log)
		return
	SEND_TEXT(world.log, text)

/// Logging for game performance
/proc/log_perf(list/perf_info)
	. = "[perf_info.Join(",")]\n"
	WRITE_LOG_NO_FORMAT(GLOB.perf_log, .)

/// Logging for hard deletes
/proc/log_qdel(text, list/data)
	logger.Log(LOG_CATEGORY_QDEL, text, data)

/* Log to the logfile only. */
/proc/log_runtime(text, list/data)
	logger.Log(LOG_CATEGORY_RUNTIME, text, data)

/// Logging for DB errors
/proc/log_sql(text, list/data)
	logger.Log(LOG_CATEGORY_DEBUG_SQL, text, data)

/// Logging for world/Topic
/proc/log_topic(text, list/data)
	logger.Log(LOG_CATEGORY_GAME_TOPIC, text, data)

/// A log line that takes this long (ms) to write is traced (LOG_WORLD_SLOW).
#define LOG_WORLD_SLOW_MS 25

/// Log to both DD and the logfile.
/proc/log_world(text, list/data)
	var/static/noting = FALSE
	var/started = TICK_USAGE_REAL
#ifdef USE_CUSTOM_ERROR_HANDLER
	logger.Log(LOG_CATEGORY_RUNTIME, text, data)
#endif
	var/file_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	SEND_TEXT(world.log, text)
	var/total_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	// A write that blocks (the console, the log file, a scanner on the disk) stalls the whole tick whoever wrote the line: name which half was slow.
	if(total_ms >= LOG_WORLD_SLOW_MS && !noting)
		noting = TRUE
		log_world("LOG_WORLD_SLOW: a log line of [length(text)] characters took [round(total_ms, 0.1)] ms: runtime log file [round(file_ms, 0.1)] ms, world.log (dd.log) [round(total_ms - file_ms, 0.1)] ms; it began [copytext("[text]", 1, 80)]")
		noting = FALSE
