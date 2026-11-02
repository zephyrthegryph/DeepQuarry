/// gives us the stack trace from CRASH() without ending the current proc.
/// Do not call directly, use the [stack_trace] macro instead.
/proc/_stack_trace(message, file, line)
	READS_FROM()
	CRASH("[message][WORKAROUND_IDENTIFIER][json_encode(list(file, line))][WORKAROUND_IDENTIFIER]")

/// While a list, dq_report_caught() appends "context: name" here instead of
/// raising a runtime (unit tests that exercise a catch on purpose).
GLOBAL_VAR(dq_caught_capture)

/// The one way a try/catch reports what it caught: logs a context line, then
/// hands the exception to world/Error, so its file, line and stack reach the
/// runtime log and it counts as a runtime (a test run with one fails).
/// tools/ci/silent_catch_lint.py rejects a catch block that does neither this,
/// a rethrow, a stack_trace/CRASH, nor (outside the core dirs) a log call.
/proc/dq_report_caught(exception/E, context)
	var/exception/ex = E
	if(!istype(ex))
		ex = new /exception("non-exception thrown: [E]", "", 0)
	var/list/capture = GLOB.dq_caught_capture
	if(islist(capture))
		capture += "[context]: [ex.name]"
		return
	log_runtime("CAUGHT EXCEPTION ([context]): [ex.name] at [ex.file]:[ex.line]")
	world.Error(ex)
