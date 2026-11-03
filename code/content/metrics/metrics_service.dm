// Server metrics: samples every /datum/metrics_source on a world lane, buffers the
// samples and events, and writes them in batches to the metric_* tables
// (SQL/metrics_schema.sql) through io_job, so nothing waits on the database.
// tools/admin-viewer reads them, rolls rounds up into metric_round and prunes old samples.
//
// Hooks never talk to the database: they call METRICS_EVENT() (or note_runtime() /
// note_overrun() for the two hot paths), and a new kind of measurement is a new
// /datum/metrics_source subtype (metrics_sources.dm), not an edit here.

SYSTEM_DEF(server_metrics)
	name = "Metrics"
	periodic_runlevels = RUNLEVELS_DEFAULT
	/// TRUE while a sample or flush that ran out of budget waits to resume.
	VAR_PRIVATE/resuming = FALSE
	/// REALTIMEOFDAY when the world booted; sample and event times are seconds since then.
	var/boot_realtime
	/// Whether samples are being recorded (config flag, a round id and the database); refreshed
	/// every sample. Events are buffered whenever metrics are enabled (wants_recording()), so
	/// one that comes before the first sample (the round start) isn't lost.
	var/recording = FALSE
	/// REALTIMEOFDAY of the previous sample, for each source's dt.
	var/last_sample_realtime
	/// Seconds since boot of the sample being collected.
	var/sample_t = 0
	/// Every metric name seen this process, so a name's metric_key row is only sent once.
	var/list/known_keys
	/// metric_key rows to create on the next flush: list(name, category, subcategory, unit).
	var/list/new_keys
	/// Buffered samples, flat: name, t, value, name, t, value, ...
	var/list/pending_samples
	/// Buffered events: list(t, kind, category, signature, ckey, message, payload_json).
	var/list/pending_events
	/// Runtimes since the last flush, by signature: list(count, where, error name, first t, proc, stack).
	var/list/runtime_buffer
	/// The worst overrun ticks since the last flush (Master's tick records), worst first.
	var/list/overrun_buffer
	/// Overrun ticks since the last sample (every one, not just the recorded few).
	var/overruns_since_sample = 0
	/// Events not recorded since the last sample because the buffer was full.
	var/events_dropped = 0
	var/samples_since_flush = 0
	/// The sources, one instance of each concrete /datum/metrics_source subtype.
	var/list/sources
	/// The source the sample being collected goes on with (continue_sample()), or 0 between samples.
	var/sample_index = 0
	/// Seconds since the previous sample, for the sample being collected.
	var/sample_dt = 0
	/// The flush being built (begin_flush()): the buffers it took and the statements built so far, or null.
	var/list/flush_plan
	/// What the last flush cost to build and send, ms; reported with the next sample.
	var/last_flush_ms

CAPABILITIES(/datum/system/server_metrics)
	owns_many(nameof(sources))

/datum/system/server_metrics/preinit()
	boot_realtime = REALTIMEOFDAY

/// One sample every METRICS_SAMPLE_INTERVAL on the background lane.
/datum/system/server_metrics/reactions()
	. = ..()
	. += every(METRICS_SAMPLE_INTERVAL, PROC_REF(sample_step), when = PROC_REF(work_ready), lane = LANE_BACKGROUND)

/datum/system/server_metrics/initialize()
	initialized = TRUE
	for(var/source_type in subtypesof(/datum/metrics_source))
		var/datum/metrics_source/source_proto = source_type
		if(initial(source_proto.abstract_type) == source_type)
			continue
		rel_add(src, nameof(sources), new source_type)
	return TRUE

/// One sample every METRICS_SAMPLE_INTERVAL and, every METRICS_SAMPLES_PER_FLUSH samples, a flush. Both are
/// spread: the step yields between sources and between built statements when the tick is used up, so
/// measuring the server never makes a tick of its own run over.
/datum/system/server_metrics/proc/sample_step(dt)
	var/resumed = resuming
	resuming = FALSE
	if(!resumed)
		recording = CONFIG_GET(flag/metrics_enabled) && !isnull(GLOB.round_id) && SSdbcore?.IsConnected()
		if(!recording)
			return STEP_DONE
		begin_sample()
	if(sample_index)
		if(!continue_sample(TRUE))
			resuming = TRUE
			return STEP_YIELD
		finish_sample()
		maybe_profile_steady()
		if(++samples_since_flush >= METRICS_SAMPLES_PER_FLUSH)
			begin_flush()
	if(flush_plan)
		if(!continue_flush(TRUE))
			resuming = TRUE
			return STEP_YIELD
		send_flush()
	return STEP_DONE

/datum/system/server_metrics/stat_entry(msg)
	return "[msg][recording ? "recording" : "idle"], [length(known_keys)] metrics, [length(pending_samples) / 3] samples / [length(pending_events)] events buffered"

/// Whether events should be buffered: recording, or enabled in config and waiting for the first sample.
/// Cheap when recording; otherwise a config read (events are rare while metrics are off).
/datum/system/server_metrics/proc/wants_recording()
	if(recording)
		return TRUE
	return config?.entries && CONFIG_GET(flag/metrics_enabled)

/// Seconds since boot, the time axis of every sample and event.
/datum/system/server_metrics/proc/now_t()
	return round((REALTIMEOFDAY - boot_realtime) / (1 SECONDS))

// ---------------------------------------------------------------- recording API

/// Records one value of metric `name` in the sample being collected. Called by sources.
/datum/system/server_metrics/proc/gauge(name, value, category, subcategory = "", unit = "")
	if(!LAZYACCESS(known_keys, name))
		LAZYSET(known_keys, name, TRUE)
		LAZYADD(new_keys, list(list(name, category, subcategory, unit)))
	LAZYINITLIST(pending_samples)
	pending_samples.Add(name, sample_t, value)

// ---------------------------------------------------------------- sampling

/// Takes a whole sample at once (tests; the lane spreads it with begin/continue/finish_sample()).
/datum/system/server_metrics/proc/sample()
	begin_sample()
	continue_sample(FALSE)
	finish_sample()

/datum/system/server_metrics/proc/begin_sample()
	var/now = REALTIMEOFDAY
	sample_dt = last_sample_realtime ? max((now - last_sample_realtime) / (1 SECONDS), 0.1) : METRICS_SAMPLE_INTERVAL / (1 SECONDS)
	last_sample_realtime = now
	sample_t = now_t()
	sample_index = 1

/// Runs the sources from sample_index on, timing each (finish_sample() reports what each cost). `budgeted`
/// stops at the tick limit and returns FALSE; the next call carries on with the next source.
/datum/system/server_metrics/proc/continue_sample(budgeted)
	while(sample_index <= length(sources))
		var/datum/metrics_source/source = sources[sample_index++]
		var/started = TICK_USAGE
		source.collect(src, sample_dt)
		source.cost_ms += TICK_USAGE_TO_MS(started)
		if(budgeted && sample_index <= length(sources) && KERNEL_OVER_BUDGET)
			return FALSE
	return TRUE

/// The service's own figures, after the sources: overruns, dropped events and what each source and the last
/// flush cost (the metrics' own overhead, so it can be kept small).
/datum/system/server_metrics/proc/finish_sample()
	sample_index = 0
	gauge("server/overruns", overruns_since_sample, METRICS_CAT_SERVER, "tick", "ticks")
	gauge("metrics/events_dropped", events_dropped, METRICS_CAT_IO, "metrics", "events")
	var/total = 0
	for(var/datum/metrics_source/source as anything in sources)
		total += source.cost_ms
		gauge("metrics/source/[source.metric_name()]/ms", source.cost_ms, METRICS_CAT_IO, "metrics", "ms")
		source.cost_ms = 0
	gauge("metrics/sample/ms", total, METRICS_CAT_IO, "metrics", "ms")
	if(!isnull(last_flush_ms))
		gauge("metrics/flush/ms", last_flush_ms, METRICS_CAT_IO, "metrics", "ms")
		last_flush_ms = null
	overruns_since_sample = 0
	events_dropped = 0

// ---------------------------------------------------------------- writing

/// Most sample rows per INSERT statement: one statement is built per slice of a spread flush, so this bounds the slice.
#define METRICS_ROWS_PER_STATEMENT 100

/// Writes everything buffered: new metric keys, then samples (resolved to key ids in SQL),
/// then events. Fire-and-forget through io_job (failures go to the SQL log), or, with `blocking`
/// (server shutdown only), right away in order. All at once; the lane spreads it instead
/// (begin_flush(), continue_flush(), send_flush()).
/datum/system/server_metrics/proc/flush(blocking = FALSE)
	if(!begin_flush())
		return
	continue_flush(FALSE)
	send_flush(blocking)

/// Takes the buffers into a flush plan (flush_plan). FALSE when there is nowhere to write them.
/datum/system/server_metrics/proc/begin_flush()
	samples_since_flush = 0
	var/round_id = text2num(GLOB.round_id)
	if(!round_id || !SSdbcore?.IsConnected())
		return FALSE
	var/started = TICK_USAGE
	collect_buffered_events()
	flush_plan = list(
		"round_id" = round_id,
		"flush_t" = now_t(),
		"samples" = pending_samples || list(),
		"next" = 1,
		"sample_statements" = list(),
		"events" = pending_events,
		"keys" = new_keys,
		"ms" = 0,
	)
	pending_samples = null
	pending_events = null
	new_keys = null
	flush_plan["ms"] += TICK_USAGE_TO_MS(started)
	return TRUE

/// Builds the plan's sample statements, METRICS_ROWS_PER_STATEMENT rows each. `budgeted` stops at the tick
/// limit between statements and returns FALSE; the next call carries on.
/datum/system/server_metrics/proc/continue_flush(budgeted)
	var/list/plan = flush_plan
	var/started = TICK_USAGE
	var/list/samples = plan["samples"]
	var/values_per_statement = METRICS_ROWS_PER_STATEMENT * 3 // samples are name, t, value triples
	while(plan["next"] <= length(samples))
		var/start = plan["next"]
		var/last = min(start + values_per_statement - 1, length(samples))
		plan["next"] = last + 1
		plan["sample_statements"] += list(sample_statement(samples, start, last, plan["round_id"], plan["flush_t"]))
		if(budgeted && plan["next"] <= length(samples) && KERNEL_OVER_BUDGET)
			plan["ms"] += TICK_USAGE_TO_MS(started)
			return FALSE
	plan["ms"] += TICK_USAGE_TO_MS(started)
	return TRUE

/// Sends the built plan: the keys first (the samples join against them), then the samples and events.
/datum/system/server_metrics/proc/send_flush(blocking = FALSE)
	var/list/plan = flush_plan
	flush_plan = null
	if(!plan)
		return
	var/started = TICK_USAGE
	var/list/sample_statements = plan["sample_statements"]
	var/list/events = plan["events"]
	var/list/keys = plan["keys"]
	var/list/event_statement = length(events) ? event_statement(events, plan["round_id"], plan["flush_t"]) : null
	var/list/key_statement = length(keys) ? key_statement(keys) : null
	if(blocking)
		var/list/statements = list()
		if(key_statement)
			statements += list(key_statement)
		statements += sample_statements
		if(event_statement)
			statements += list(event_statement)
		metrics_write_statements_now(statements)
		return
	if(key_statement)
		// Samples join against metric_key, so the keys go first; the samples follow in the callback.
		io_job(null, /datum/io_backend/sql, key_statement[1], key_statement[2], /proc/metrics_keys_written, sample_statements)
	else
		metrics_write_statements(sample_statements)
	if(event_statement)
		sql_write(event_statement[1], event_statement[2])
	last_flush_ms = plan["ms"] + TICK_USAGE_TO_MS(started)

/// Turns the runtime and overrun buffers into events.
/datum/system/server_metrics/proc/collect_buffered_events()
	for(var/signature in runtime_buffer)
		var/list/entry = runtime_buffer[signature]
		var/list/payload = list("count" = entry[1], "where" = entry[2], "proc" = entry[5])
		if(length(entry[6]))
			payload["stack"] = entry[6]
		LAZYADD(pending_events, list(list(entry[4], METRICS_EVENT_RUNTIME, "", signature, "", copytext("[entry[3]]", 1, 512), json_encode(payload))))
	runtime_buffer = null
	for(var/list/record as anything in overrun_buffer)
		LAZYADD(pending_events, list(list(record["t"], METRICS_EVENT_OVERRUN, "[record["cause"] || record["top_subsystem"]]", "", "", "[round(record["usage"], 0.1)]% tick", json_encode(record))))
	overrun_buffer = null

/datum/system/server_metrics/proc/key_statement(list/keys)
	var/list/rows = list()
	var/list/arguments = list()
	var/i = 0
	for(var/list/key as anything in keys)
		i++
		rows += "(:n[i], :c[i], :s[i], :u[i])"
		arguments["n[i]"] = key[1]
		arguments["c[i]"] = key[2]
		arguments["s[i]"] = key[3]
		arguments["u[i]"] = key[4]
	return list("INSERT IGNORE INTO [format_table_name("metric_key")] (name, category, subcategory, unit) VALUES [jointext(rows, ", ")]", arguments)

/// One INSERT of samples[first..last] (flat triples). Names resolve to key ids by a join,
/// and each row's timestamp is the flush time less its age.
/datum/system/server_metrics/proc/sample_statement(list/samples, first, last, round_id, flush_t)
	var/list/rows = list()
	var/list/arguments = list("round" = round_id, "now_t" = flush_t)
	var/i = 0
	for(var/index in first to last step 3)
		i++
		rows += (i == 1) ? "SELECT :n[i] AS name, :t[i] AS t, :v[i] AS value" : "SELECT :n[i], :t[i], :v[i]"
		arguments["n[i]"] = samples[index]
		arguments["t[i]"] = samples[index + 1]
		arguments["v[i]"] = samples[index + 2]
	var/sql = {"INSERT INTO [format_table_name("metric_sample")] (round_id, key_id, t, ts, value)
		SELECT :round, k.id, v.t, NOW() - INTERVAL (:now_t - v.t) SECOND, v.value
		FROM ([jointext(rows, " UNION ALL ")]) v JOIN [format_table_name("metric_key")] k ON k.name = v.name
		ON DUPLICATE KEY UPDATE value = VALUES(value)"}
	return list(sql, arguments)

/datum/system/server_metrics/proc/event_statement(list/events, round_id, flush_t)
	var/list/rows = list()
	var/list/arguments = list("round" = round_id, "now_t" = flush_t)
	var/i = 0
	for(var/list/event as anything in events)
		i++
		rows += "(:round, :t[i], NOW() - INTERVAL (:now_t - :t[i]) SECOND, :k[i], :c[i], :s[i], :ck[i], :m[i], :p[i])"
		arguments["t[i]"] = event[1]
		arguments["k[i]"] = event[2]
		arguments["c[i]"] = event[3]
		arguments["s[i]"] = event[4]
		arguments["ck[i]"] = event[5]
		arguments["m[i]"] = event[6]
		arguments["p[i]"] = event[7]
	return list("INSERT INTO [format_table_name("metric_event")] (round_id, t, ts, kind, category, signature, ckey, message, payload) VALUES [jointext(rows, ", ")]", arguments)

#undef METRICS_ROWS_PER_STATEMENT

/// io_job callback: the new metric keys exist, so the samples that use them can go.
/proc/metrics_keys_written(list/result, error, list/sample_statements)
	if(error)
		log_sql("metrics: writing metric keys failed: [error]")
	metrics_write_statements(sample_statements)

/proc/metrics_write_statements(list/statements)
	for(var/list/statement as anything in statements)
		sql_write(statement[1], statement[2])

/// Runs the statements now, in order, waiting for each: the shutdown flush only, when the I/O
/// lane has stopped.
/proc/metrics_write_statements_now(list/statements)
	for(var/list/statement as anything in statements)
		if(isnull(db_query_now(statement[1], statement[2])))
			log_sql("metrics: shutdown flush failed: [SSdbcore.ErrorMsg()]")
