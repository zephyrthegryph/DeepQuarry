// Server metrics: samples every /datum/metrics_source on a world lane, buffers the
// samples and events, and writes them in batches to the metric_* tables
// (SQL/metrics_schema.sql) through om_io, so nothing waits on the database.
// tools/admin-viewer reads them, rolls rounds up into metric_round and prunes old samples.
//
// Hooks never talk to the database: they call METRICS_EVENT() (or note_runtime() /
// note_overrun() for the two hot paths), and a new kind of measurement is a new
// /datum/metrics_source subtype (metrics_sources.dm), not an edit here.

GLOBAL_DATUM_INIT(metrics_service, /datum/world_service/server_metrics, new)

/datum/world_service/server_metrics
	name = "Metrics"
	lane = /datum/om/behaviour/world/server_metrics
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

/datum/world_service/server_metrics/New()
	. = ..()
	boot_realtime = REALTIMEOFDAY

/datum/world_service/server_metrics/initialize()
	initialized = TRUE
	for(var/source_type in subtypesof(/datum/metrics_source))
		var/datum/metrics_source/source_proto = source_type
		if(initial(source_proto.abstract_type) == source_type)
			continue
		own_add(src, nameof(sources), new source_type)
	return TRUE

/// The server is going down (or rebooting): SSdbcore calls this from its Shutdown(), while the
/// database is still connected (world services shut down after it). The I/O lane won't run again,
/// so this one flush blocks.
/datum/world_service/server_metrics/proc/final_flush()
	if(!recording)
		return
	METRICS_EVENT(METRICS_EVENT_ROUND, "shutdown", "", "", "server shutdown", list("runtimes" = GLOB.total_runtimes))
	flush(blocking = TRUE)

/datum/world_service/server_metrics/service_step(resumed)
	if(!initialized)
		initialize()
	recording = CONFIG_GET(flag/metrics_enabled) && !isnull(GLOB.round_id) && SSdbcore?.IsConnected()
	if(!recording)
		return TRUE
	sample()
	if(++samples_since_flush >= METRICS_SAMPLES_PER_FLUSH)
		flush()
	return TRUE

/datum/world_service/server_metrics/stat_line()
	return "[recording ? "recording" : "idle"], [length(known_keys)] metrics, [length(pending_samples) / 3] samples / [length(pending_events)] events buffered"

/// Whether events should be buffered: recording, or enabled in config and waiting for the first sample.
/// Cheap when recording; otherwise a config read (events are rare while metrics are off).
/datum/world_service/server_metrics/proc/wants_recording()
	if(recording)
		return TRUE
	return config?.entries && CONFIG_GET(flag/metrics_enabled)

/// Seconds since boot, the time axis of every sample and event.
/datum/world_service/server_metrics/proc/now_t()
	return round((REALTIMEOFDAY - boot_realtime) / (1 SECONDS))

// ---------------------------------------------------------------- recording API

/// Records one value of metric `name` in the sample being collected. Called by sources.
/datum/world_service/server_metrics/proc/gauge(name, value, category, subcategory = "", unit = "")
	if(!LAZYACCESS(known_keys, name))
		LAZYSET(known_keys, name, TRUE)
		LAZYADD(new_keys, list(list(name, category, subcategory, unit)))
	LAZYINITLIST(pending_samples)
	pending_samples.Add(name, sample_t, value)

/// Records an event (use METRICS_EVENT()). `signature` groups repeats; `payload` is a list,
/// stored as JSON.
/datum/world_service/server_metrics/proc/event(kind, category = "", signature = "", ckey = "", message = "", list/payload)
	if(!wants_recording())
		return
	if(length(pending_events) >= METRICS_EVENT_CAP)
		events_dropped++
		return
	LAZYADD(pending_events, list(list(now_t(), kind, category || "", copytext("[signature]", 1, 64), ckey || "", copytext("[message]", 1, 512), payload ? json_encode(payload) : null)))

/// A runtime (from /world/Error): counted by signature, written once per flush with its count. The first
/// sighting in a flush keeps the proc and a trimmed call stack from the exception's desc.
/// Must stay cheap and must not runtime.
/datum/world_service/server_metrics/proc/note_runtime(exception/E, error_uid)
	if(!wants_recording())
		return
	var/signature = md5("[error_uid]")
	var/list/entry = LAZYACCESS(runtime_buffer, signature)
	if(entry)
		entry[1]++
		return
	var/proc_name = error_proc_name(E)
	LAZYSET(runtime_buffer, signature, list(1, E.file ? "[E.file]:[E.line]" : proc_name, E.name, now_t(), proc_name, metrics_runtime_stack(E.desc)))

/// An overrun tick (from the MC): counted, and kept in full if among the worst this flush.
/datum/world_service/server_metrics/proc/note_overrun(list/tick_record)
	if(!wants_recording())
		return
	overruns_since_sample++
	var/usage = tick_record["usage"]
	if(usage >= METRICS_SPIKE_USAGE)
		spike_seen(tick_record)
	var/count = length(overrun_buffer)
	if(count >= METRICS_OVERRUNS_PER_FLUSH)
		var/list/least = overrun_buffer[count]
		if(usage <= least["usage"])
			return
		overrun_buffer.Cut(count)
	var/list/record = tick_record.Copy()
	record["t"] = now_t()
	LAZYINITLIST(overrun_buffer)
	for(var/i in 1 to length(overrun_buffer))
		var/list/other = overrun_buffer[i]
		if(usage > other["usage"])
			overrun_buffer.Insert(i, null)
			overrun_buffer[i] = record
			return
	overrun_buffer += list(record)

// ---------------------------------------------------------------- sampling

/datum/world_service/server_metrics/proc/sample()
	var/now = REALTIMEOFDAY
	var/dt = last_sample_realtime ? max((now - last_sample_realtime) / (1 SECONDS), 0.1) : METRICS_SAMPLE_INTERVAL / (1 SECONDS)
	last_sample_realtime = now
	sample_t = now_t()
	for(var/datum/metrics_source/source as anything in sources)
		source.collect(src, dt)
	gauge("server/overruns", overruns_since_sample, METRICS_CAT_SERVER, "tick", "ticks")
	gauge("metrics/events_dropped", events_dropped, METRICS_CAT_IO, "metrics", "events")
	overruns_since_sample = 0
	events_dropped = 0

// ---------------------------------------------------------------- writing

/// Most sample rows per INSERT statement.
#define METRICS_ROWS_PER_STATEMENT 400

/// Writes everything buffered: new metric keys, then samples (resolved to key ids in SQL),
/// then events. Fire-and-forget through om_io (failures go to the SQL log), or, with `blocking`
/// (server shutdown only), right away in order.
/datum/world_service/server_metrics/proc/flush(blocking = FALSE)
	samples_since_flush = 0
	var/round_id = text2num(GLOB.round_id)
	if(!round_id || !SSdbcore?.IsConnected())
		return
	var/flush_t = now_t()
	collect_buffered_events()

	var/list/sample_statements = list()
	var/list/samples = pending_samples
	pending_samples = null
	var/values_per_statement = METRICS_ROWS_PER_STATEMENT * 3 // samples are name, t, value triples
	for(var/start in 1 to length(samples) step values_per_statement)
		sample_statements += list(sample_statement(samples, start, min(start + values_per_statement - 1, length(samples)), round_id, flush_t))

	var/list/event_statement = length(pending_events) ? event_statement(pending_events, round_id, flush_t) : null
	pending_events = null

	var/list/key_statement = length(new_keys) ? key_statement(new_keys) : null
	new_keys = null
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
		om_io(null, /datum/om/io/sql, key_statement[1], key_statement[2], /proc/metrics_keys_written, sample_statements)
	else
		metrics_write_statements(sample_statements)
	if(event_statement)
		om_sql_write(event_statement[1], event_statement[2])

/// Turns the runtime and overrun buffers into events.
/datum/world_service/server_metrics/proc/collect_buffered_events()
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

/datum/world_service/server_metrics/proc/key_statement(list/keys)
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
/datum/world_service/server_metrics/proc/sample_statement(list/samples, first, last, round_id, flush_t)
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

/datum/world_service/server_metrics/proc/event_statement(list/events, round_id, flush_t)
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

/// om_io callback: the new metric keys exist, so the samples that use them can go.
/proc/metrics_keys_written(list/result, error, list/sample_statements)
	if(error)
		log_sql("metrics: writing metric keys failed: [error]")
	metrics_write_statements(sample_statements)

/proc/metrics_write_statements(list/statements)
	for(var/list/statement as anything in statements)
		om_sql_write(statement[1], statement[2])

/// Runs the statements now, in order, waiting for each: the shutdown flush only, when the I/O
/// lane has stopped.
/proc/metrics_write_statements_now(list/statements)
	for(var/list/statement as anything in statements)
		var/datum/db_query/query = SSdbcore.NewQuery(statement[1], statement[2])
		if(!query.Execute(async = FALSE))
			log_sql("metrics: shutdown flush failed: [query.ErrorMsg()]")
		// ALLOW(lifecycle): a db_query is a plain datum; no lifecycle verb applies
		qdel(query)

// ---------------------------------------------------------------- lane

/datum/om/behaviour/world/server_metrics
	name = "world: metrics"
	every = METRICS_SAMPLE_INTERVAL
	lane = LANE_BACKGROUND
	runlevels = RUNLEVELS_DEFAULT

/datum/om/behaviour/world/server_metrics/service()
	return GLOB.metrics_service
