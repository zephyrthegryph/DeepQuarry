/// Logging for loading and caching assets
/proc/log_asset(text, list/data)
	logger.Log(LOG_CATEGORY_DEBUG_ASSET, text, data)

/// Lines written to world.log itself before a running server moves its world-log lines to the async writer: boot output and the first
/// warnings stay on the console and in dd.log, where the people watching a boot look for them.
#define WORLD_LOG_DIRECT_LINES 200
GLOBAL_VAR_INIT(world_log_direct_left, WORLD_LOG_DIRECT_LINES)

/// One line for the world log. world.log is BYOND's own stream (console and dd.log) and a write to it blocks the tick, so on a running
/// server a line goes to the async writer's dd_async.log in the round's log directory once the first WORLD_LOG_DIRECT_LINES have been
/// written to world.log. `always` (runtime errors: rare, silenced by the error cooldown, and what an operator watches the console for)
/// writes to world.log as well as the async file. A unit-test world (its harness reads the console) always writes to world.log. No line is dropped.
/proc/world_log_line(text, always = FALSE)
#ifndef UNIT_TESTS
	if(GLOB.log_directory)
		log_file_append("[GLOB.log_directory]/dd_async.log", "[text]\n", FALSE)
		if(!always)
			if(GLOB.world_log_direct_left <= 0)
				return
			GLOB.world_log_direct_left--
#endif
	SEND_TEXT(world.log, text)

/// Logging for config errors
/// Rarely gets called; just here in case the config breaks.
/proc/log_config(text, list/data)
	logger.Log(LOG_CATEGORY_CONFIG, text, data)
	world_log_line(text)

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
	world_log_line(text)

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

/// What the runtime log's entry spent, ms, since the last LOG_WORLD_SLOW line: the file-exists checks (a syscall on the tick, once per file per
/// LOG_FILE_RECHECK_INTERVAL), building the entry (timestamp, json), and the ring. Filled by code/content/logging/log_category.dm.
GLOBAL_VAR_INIT(log_exists_ms, 0)
GLOBAL_VAR_INIT(log_exists_max_ms, 0)
GLOBAL_VAR_INIT(log_exists_calls, 0)
GLOBAL_VAR_INIT(log_entry_build_ms, 0)

/// Log to both DD and the logfile.
/proc/log_world(text, list/data)
	var/static/noting = FALSE
	var/started = TICK_USAGE_REAL
#ifdef USE_CUSTOM_ERROR_HANDLER
	logger.Log(LOG_CATEGORY_RUNTIME, text, data)
#endif
	var/file_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	world_log_line(text)
	var/total_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	// A write that blocks (the console, the log file, a scanner on the disk) stalls the whole tick whoever wrote the line: name which half was slow.
	if(total_ms >= LOG_WORLD_SLOW_MS && !noting)
		noting = TRUE
		log_world("LOG_WORLD_SLOW: a log line of [length(text)] characters took [round(total_ms, 0.1)] ms: runtime log file [round(file_ms, 0.1)] ms (of the logger's own work since the last such line: [GLOB.log_exists_calls] file-exists check(s) [round(GLOB.log_exists_ms, 0.1)] ms, the slowest [round(GLOB.log_exists_max_ms, 0.1)] ms; building entries [round(GLOB.log_entry_build_ms, 0.1)] ms), world.log (dd.log) [round(total_ms - file_ms, 0.1)] ms; it began [copytext("[text]", 1, 80)]")
		GLOB.log_exists_ms = 0
		GLOB.log_exists_max_ms = 0
		GLOB.log_exists_calls = 0
		GLOB.log_entry_build_ms = 0
		noting = FALSE
