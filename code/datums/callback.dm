/*
	USAGE:

		var/datum/callback/C = new(object|null, /proc/type/path|"procstring", arg1, arg2, ... argn)
		Deferred calls are om_after(owner, delay, proc, args...), not callbacks.

		Note: proc strings can only be given for datum proc calls, global procs must be proc paths
		Also proc strings are strongly advised against because they don't compile error if the proc stops existing
		See the note on proc typepath shortcuts

	INVOKING THE CALLBACK:
		var/result = C.Invoke(args, to, add) //additional args are added after the ones given when the callback was created
		OR
		var/result = C.InvokeAsync(args, to, add) //Sleeps will not block, returns . on the first sleep (then continues on in the "background" after the sleep/block ends), otherwise operates normally.
		OR
		INVOKE_ASYNC(<CALLBACK args>) to immediately create and call InvokeAsync

	PROC TYPEPATH SHORTCUTS (these operate on paths, not types, so to these shortcuts, datum is NOT a parent of atom, etc...)

		global proc while in another global proc:
			.procname
			Example:
				CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(some_proc_here))

		proc defined on current(src) object (when in a /proc/ and not an override) OR overridden at src or any of it's parents:
			.procname
			Example:
				CALLBACK(src, PROC_REF(some_proc_here))

		when the above doesn't apply:
			PROC_REF(procname)
			Example:
				CALLBACK(src,

		proc defined on a parent of a some type:
			Example: TYPE_PROC_REF(/some/type, some_proc_here))

		Other wise you will have to do the full typepath of the proc (/type/of/thing/proc/procname)
*/

/datum/callback
	/// What to call: GLOBAL_PROC, or the OM handle of the datum (a turf's or client's handle
	/// works too). Read with target_object(); a deleted target reads null and nothing is called.
	var/datum/object = GLOBAL_PROC
	var/delegate
	var/list/arguments
	var/user

/datum/callback/New(thingtocall, proctocall, ...)
	if (thingtocall)
		rel_set(src, "object", thingtocall == GLOBAL_PROC ? GLOBAL_PROC : om_handle(thingtocall))
	delegate = proctocall
	if (length(args) > 2)
		arguments = args.Copy(3)
	if(usr)
		user = om_handle(usr)

/world/proc/ImmediateInvokeAsync(thingtocall, proctocall, ...)
	set waitfor = FALSE // ALLOW(scheduler): INVOKE_ASYNC primitive (goes with the last INVOKE_ASYNC caller)

	if (!thingtocall)
		return

	var/list/calling_arguments = length(args) > 2 ? args.Copy(3) : null

	if (thingtocall == GLOBAL_PROC)
		call(proctocall)(arglist(calling_arguments))
	else
		call(thingtocall, proctocall)(arglist(calling_arguments))

/datum/callback/proc/Invoke(...)
	if(!usr)
		var/W = user
		if(W)
			var/mob/M = om_resolve(W)
			if(M)
				return world.PushUsr(M, src)

	var/object = target_object()
	if (!object)
		return

	var/list/calling_arguments = arguments
	if (length(args))
		if (length(arguments))
			calling_arguments = calling_arguments + args //not += so that it creates a new list so the arguments list stays clean
		else
			calling_arguments = args
	if (object == GLOBAL_PROC)
		return call(delegate)(arglist(calling_arguments))
	return call(object, delegate)(arglist(calling_arguments))

//copy and pasted because fuck proc overhead
/datum/callback/proc/InvokeAsync(...)
	set waitfor = FALSE // ALLOW(scheduler): InvokeAsync primitive (goes with the last async caller)

	if(!usr)
		var/W = user
		if(W)
			var/mob/M = om_resolve(W)
			if(M)
				return world.PushUsr(M, src)

	var/object = target_object()
	if (!object)
		return

	var/list/calling_arguments = arguments
	if (length(args))
		if (length(arguments))
			calling_arguments = calling_arguments + args //not += so that it creates a new list so the arguments list stays clean
		else
			calling_arguments = args
	if (object == GLOBAL_PROC)
		return call(delegate)(arglist(calling_arguments))
	return call(object, delegate)(arglist(calling_arguments))

// Makes a call in the context of a different usr
// Use sparingly
/world/proc/PushUsr(mob/M, datum/callback/CB)
	var/temp = usr
	usr = M
	. = CB.Invoke()
	usr = temp

/// GLOBAL_PROC, the datum this callback calls, or null once that datum is deleted.
/datum/callback/proc/target_object()
	if(object == GLOBAL_PROC)
		return GLOBAL_PROC
	return object
