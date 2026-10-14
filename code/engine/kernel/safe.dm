// Faults and parsing (doc/rewrite/final_api.html, section 2 "Faults, parsing and boot"; section 19 "E6").
//
//     var/datum/result/R = safe_call(PROC_REF(parse_it), text)       // a proc of the caller (src), or GLOBAL_PROC_REF(x)
//     if(R.ok) use(R.value) else log(R.error)
//
// safe_call() runs a proc and returns a /datum/result (ok, value, error) instead of letting a runtime escape. It is for code at a
// boundary that can fail by design (untrusted text, a file that may be absent, a call into a vendored library). The runtime is
// not logged: the caller decides what a failure means. Raw try/catch lives only inside the kernel, where it isolates a faulting
// handler; everything else calls this. try_parse_json() returns the parsed value, or null for malformed text.

/// What safe_call() returns.
/datum/result
	/// TRUE when the call returned; FALSE when it runtimed.
	var/ok = TRUE
	/// What the call returned.
	var/value
	/// The runtime's message ("name (file:line)") when it did not return.
	var/error

/// Calls `proc_ref` (a PROC_REF on the caller, or a GLOBAL_PROC_REF) with the remaining arguments and returns a /datum/result.
/proc/safe_call(proc_ref, ...)
	RETURN_TYPE(/datum/result)
	var/datum/result/R = new
	var/list/call_args = args.Copy(2)
	var/datum/target
	if(istext(proc_ref))
		var/callee/frame = callee?.caller
		target = frame?.src
		if(!target)
			CRASH("safe_call([proc_ref]): a PROC_REF needs a calling proc with a src; use GLOBAL_PROC_REF for a global proc")
	try
		if(target)
			R.value = call(target, proc_ref)(arglist(call_args))
		else
			R.value = call(proc_ref)(arglist(call_args))
	catch(var/exception/fault) // ALLOW(silent_catch): safe_call hands the fault back as a /datum/result: the caller decides what it means
		R.ok = FALSE
		R.value = null
		R.error = "[fault.name] ([fault.file]:[fault.line])"
	return R

/// The parsed value of JSON `text`, or null when it is malformed (or empty).
/proc/try_parse_json(text)
	if(!istext(text) || !length(text))
		return null
	try
		return json_decode(text)
	catch(var/exception/fault) // ALLOW(silent_catch): malformed text is the expected failure: null says so
		return null
