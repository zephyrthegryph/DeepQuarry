// DQAdd — synchronous file-logger for diagnosing silent DD crashes.
//
// log_world() buffers; if DD segfaults, the last few seconds of output never reach
// runtime.log. text2file with append mode forces an immediate write per call, so the
// trail survives a hard crash.
//
// File: data/dq_debug.log. Rotates after ~1MB to avoid growing forever.
//
// IMPORTANT: synchronous disk writes are expensive. The flag below MUST stay FALSE in
// shipping builds — flipping it on streams ~1 write/sec per active editor on top of any
// explicit logging the dev wired up. Toggle live via the `dq_debug_log` admin verb when
// you need a trace window for repro, then flip it back.

GLOBAL_VAR_INIT(dq_debug_logging, FALSE)

/proc/dq_log(msg)
	if(!GLOB.dq_debug_logging)
		return
	var/static/list/header_written = list()
	var/path = "data/dq_debug.log"
	if(!header_written[path])
		header_written[path] = TRUE
		text2file("\n=== Session start [time_stamp()] ===\n", path)
	text2file("[time_stamp()] [msg]\n", path)

/client/proc/dq_debug_log_toggle()
	set name = "Toggle DQ Debug Log"
	set category = "Debug"
	set desc = "Flip the synchronous-file dq_log() flag on or off. Only use during repro."
	if(!check_rights(R_DEBUG))
		return
	GLOB.dq_debug_logging = !GLOB.dq_debug_logging
	to_chat(usr, span_notice("DQ debug logging is now [GLOB.dq_debug_logging ? "ON" : "OFF"]."))

// Client lifecycle tracing — chases the "crash happens after I close my client" theory.
// If the last dq_debug.log line is "client Del: <ckey>" and DD dies right after, the
// disconnect path is the suspect. Note: client/New is hooked elsewhere typically; we
// only intercept Del/Destroy here so the trace covers the death window.

/client/New()
	. = ..()
	dq_log("client New: [ckey] mob=[mob?.type]")

/client/Del()
	dq_log("client Del enter: [ckey] mob=[mob?.type]")
	. = ..()
	dq_log("client Del exit: [ckey]")

/client/Destroy()
	dq_log("client Destroy enter: [ckey]")
	. = ..()
	dq_log("client Destroy exit: [ckey]")
