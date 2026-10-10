// Object-model core: DX-exec, the one executor for BYOND's blocking built-ins
// (doc/rewrite/object_model_core.md §4.12).
//
// winget() and client.MeasureText() are round trips to a player's client, and shell() waits on
// an OS process. Each suspends whatever proc calls it. Gameplay never waits, so callers don't
// call them: they ask this executor and get the answer in a callback, like an io_job job.
//
//	dx_winget(E, client, control_id, params, on_done, context...)
//	dx_winexists(E, client, control_id, on_done, context...)
//	dx_measure_text(E, client, text, style, width, on_done, context...)
//	dx_shell(E, command, on_done, context...)
//	dx_shelleo(E, command, on_done, context...)	// world.shelleo(): list(errorlevel, stdout, stderr)
//	// on_done(result, context...) runs later, on E
//
// E and every datum context arg are held weakly (OM handles; a client by its ckey), as after()
// holds them: the callback is dropped if any is gone when the answer arrives. E null means the
// global owner. The call itself runs in dx_exec_run(), the only proc here that may be
// suspended, so the only `set waitfor` for these built-ins in the codebase is in this file.
// A client that disconnects mid round trip answers null (BYOND returns null); the callback is
// then dropped because its client is gone.

#define DX_WINGET "winget"
#define DX_WINEXISTS "winexists"
#define DX_MEASURE_TEXT "measure_text"
#define DX_SHELL "shell"
#define DX_SHELLEO "shelleo"

/// Per-op counts for om_diagnostics(): started, answered, dropped.
GLOBAL_LIST_EMPTY(dx_exec_stats)

/// winget(client, control_id, params) for a callback: on_done(value, context...).
/proc/dx_winget(owner, client/C, control_id, params, on_done, ...)
	var/list/context = length(args) > 5 ? args.Copy(6) : null
	return dx_exec(owner, DX_WINGET, list(C, control_id, params), on_done, context)

/// winexists(client, control_id) for a callback: on_done(control_type or "", context...).
/proc/dx_winexists(owner, client/C, control_id, on_done, ...)
	var/list/context = length(args) > 4 ? args.Copy(5) : null
	return dx_exec(owner, DX_WINEXISTS, list(C, control_id), on_done, context)

/// client.MeasureText(text, style, width) for a callback: on_done("WxH", context...).
/proc/dx_measure_text(owner, client/C, text, style, width, on_done, ...)
	var/list/context = length(args) > 6 ? args.Copy(7) : null
	return dx_exec(owner, DX_MEASURE_TEXT, list(C, text, style, width), on_done, context)


/// world.shelleo(command) for a callback: on_done(list(errorlevel, stdout, stderr), context...).
/proc/dx_shelleo(owner, command, on_done, ...)
	var/list/context = length(args) > 3 ? args.Copy(4) : null
	return dx_exec(owner, DX_SHELLEO, list(command), on_done, context)

/// Queues one blocking built-in. Returns TRUE if it started (FALSE if the owner, a context
/// datum or the op's client is already gone).
/proc/dx_exec(owner, op, list/op_args, on_done, list/context)
	if(isnull(owner))
		owner = timer_global_owner()
	var/owner_ref = dx_exec_wrap(owner)
	if(isnull(owner_ref))
		return FALSE
	if(op != DX_SHELL && op != DX_SHELLEO)
		var/client/C = op_args[1]
		if(!istype(C))
			return FALSE
		op_args = op_args.Copy()
		op_args[1] = "ckey:[C.ckey]"
	var/list/wrapped_context
	if(length(context))
		wrapped_context = list()
		for(var/value in context)
			var/wrapped = dx_exec_wrap(value)
			if(isnull(wrapped) && !isnull(value))
				return FALSE
			wrapped_context += list(wrapped)
	dx_exec_stat(op, 1)
	dx_exec_run(owner_ref, op, op_args, on_done, wrapped_context)
	return TRUE

/proc/dx_exec_wrap(value)
	if(istype(value, /client))
		var/client/C = value
		return "ckey:[C.ckey]"
	if(isdatum(value))
		var/h = entity_handle(value)
		return h ? list("rerun_h" = h) : null
	return value

/proc/dx_exec_stat(op, index)
	var/list/S = GLOB.dx_exec_stats[op]
	if(!S)
		S = GLOB.dx_exec_stats[op] = list(0, 0, 0)
	S[index]++

/// Runs the built-in (suspending only this proc) and delivers the answer.
/proc/dx_exec_run(owner_ref, op, list/op_args, on_done, list/wrapped_context)
	set waitfor = FALSE // DX-exec: the one place BYOND's blocking built-ins (winget, MeasureText, shell) run // ALLOW(scheduler): DX-exec: the one executor for BYOND's blocking built-ins (winget, winexists, MeasureText, shell)
	var/result
	switch(op)
		if(DX_WINGET)
			var/client/C = rerun_unwrap(op_args[1])
			if(C)
				result = winget(C, op_args[2], op_args[3]) // ALLOW(scheduler): DX-exec itself: winget, winexists, MeasureText, shell run here and nowhere else
		if(DX_WINEXISTS)
			var/client/C = rerun_unwrap(op_args[1])
			if(C)
				result = winexists(C, op_args[2]) // ALLOW(scheduler): DX-exec itself: winget, winexists, MeasureText, shell run here and nowhere else
		if(DX_MEASURE_TEXT)
			var/client/C = rerun_unwrap(op_args[1])
			if(C)
				result = C.MeasureText(op_args[2], op_args[3], op_args[4]) // ALLOW(scheduler): DX-exec itself: winget, winexists, MeasureText, shell run here and nowhere else
		if(DX_SHELL)
			result = shell(op_args[1]) // ALLOW(scheduler): DX-exec itself: winget, winexists, MeasureText, shell run here and nowhere else
		if(DX_SHELLEO)
			result = world.shelleo(op_args[1])
	dx_exec_deliver(owner_ref, op, result, on_done, wrapped_context)

/// Resolves the owner and context (weakly held) and runs the callback, or drops it.
/proc/dx_exec_deliver(owner_ref, op, result, on_done, list/wrapped_context)
	var/owner = rerun_unwrap(owner_ref)
	var/list/call_args = list(result)
	for(var/wrapped in wrapped_context)
		var/value = rerun_unwrap(wrapped)
		if(isnull(value) && !isnull(wrapped))
			dx_exec_stat(op, 3)
			return
		call_args += list(value)
	if(!owner || !on_done)
		dx_exec_stat(op, 3)
		return
	dx_exec_stat(op, 2)
	try
		if(copytext("[on_done]", 1, 7) == "/proc/")
			call(on_done)(arglist(call_args))
		else
			call(owner, on_done)(arglist(call_args))
	catch(var/exception/e)
		stack_trace("dx_exec [op] callback [on_done] on [owner]: [e]")

#undef DX_WINGET
#undef DX_WINEXISTS
#undef DX_MEASURE_TEXT
#undef DX_SHELL
#undef DX_SHELLEO
