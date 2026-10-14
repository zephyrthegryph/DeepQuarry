// The server metrics system's API (code/modules/metrics/metrics_service.dm declares the system).
//
//   SSserver_metrics.event(kind, category, signature, ckey, message, payload)   a buffered event (use METRICS_EVENT())
//   SSserver_metrics.note_runtime(exception, error_uid)                          a runtime, counted by signature
//   SSserver_metrics.note_overrun(tick_record)                                   an overrun tick, kept if among the worst
//   SSserver_metrics.round_started()                                             the round has started
//   SSserver_metrics.final_flush()                                               the server is going down: one blocking flush

/// The server is going down (or rebooting): SSdbcore calls this from its Shutdown(), while the
/// database is still connected (world services shut down after it). The I/O lane won't run again,
/// so this one flush blocks.
/datum/system/server_metrics/proc/final_flush()
	if(!recording)
		return
	METRICS_EVENT(METRICS_EVENT_ROUND, "shutdown", "", "", "server shutdown", list("runtimes" = GLOB.total_runtimes))
	flush(blocking = TRUE)

/// Records an event (use METRICS_EVENT()). `signature` groups repeats; `payload` is a list,
/// stored as JSON.
/datum/system/server_metrics/proc/event(kind, category = "", signature = "", ckey = "", message = "", list/payload)
	if(!wants_recording())
		return
	if(length(pending_events) >= METRICS_EVENT_CAP)
		events_dropped++
		return
	LAZYADD(pending_events, list(list(now_t(), kind, category || "", copytext("[signature]", 1, 64), ckey || "", copytext("[message]", 1, 512), payload ? json_encode(payload) : null)))

/// A runtime (from /world/Error): counted by signature, written once per flush with its count. The first
/// sighting in a flush keeps the proc and a trimmed call stack from the exception's desc.
/// Must stay cheap and must not runtime.
/datum/system/server_metrics/proc/note_runtime(exception/E, error_uid)
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
/datum/system/server_metrics/proc/note_overrun(list/tick_record)
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

/// The round has started (SSticker): records the map, build and who is on.
/datum/system/server_metrics/proc/round_started()
	METRICS_EVENT(METRICS_EVENT_ROUND, "start", "", "", "round started", list(
		"map" = using_map?.name,
		"commit" = GLOB.revdata?.commit,
		"players" = length(GLOB.clients),
		"byond" = "[world.byond_version].[world.byond_build]",
#ifdef UNIT_TESTS
		"test" = TRUE,
#endif
	))
	profile_round_start()
