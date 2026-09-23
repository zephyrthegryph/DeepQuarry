/**
 * Register to listen for a signal from the passed in target
 *
 * This sets up a listening relationship such that when the target object emits a signal
 * the source datum this proc is called upon, will receive a callback to the given proctype
 * Use PROC_REF(procname), TYPE_PROC_REF(type,procname) or GLOBAL_PROC_REF(procname) macros to validate the passed in proc at compile time.
 * PROC_REF for procs defined on current type or it's ancestors, TYPE_PROC_REF for procs defined on unrelated type and GLOBAL_PROC_REF for global procs.
 * Return values from procs registered must be a bitfield
 *
 * Arguments:
 * * datum/target The target to listen for signals from
 * * signal_type A signal name
 * * proctype The proc to call back when the signal is emitted
 * * override If a previous registration exists you must explicitly set this
 */
/datum/proc/RegisterSignal(datum/target, signal_type, proctype, override = FALSE)
	if(QDELETED(src) || QDELETED(target))
		return

	if (islist(signal_type))
		var/static/list/known_failures = list()
		var/list/signal_type_list = signal_type
		var/message = "([target.type]) is registering [signal_type_list.Join(", ")] as a list, the older method. Change it to RegisterSignals."

		if (!(message in known_failures))
			known_failures[message] = TRUE
			stack_trace("[target] [message]")

		RegisterSignals(target, signal_type, proctype, override)
		return

	var/list/procs = (_signal_procs ||= list())
	var/list/target_procs = (procs[target] ||= list())
	var/list/lookup = (target._listen_lookup ||= list())

	var/exists = target_procs[signal_type]
	target_procs[signal_type] = proctype

	if(exists)
		if(!override)
			var/override_message = "[signal_type] overridden. Use override = TRUE to suppress this warning.\nTarget: [target] ([target.type]) Proc: [proctype]"
			//log_signal(override_message) // We don't have log_signal
			log_world(override_message)
			stack_trace(override_message)
		return

	var/list/looked_up = lookup[signal_type]

	if(isnull(looked_up)) // Nothing has registered here yet
		lookup[signal_type] = src
	else if(!islist(looked_up)) // One other thing registered here
		lookup[signal_type] = list(looked_up, src)
	else // Many other things have registered here
		looked_up += src

/// Registers multiple signals to the same proc.
/datum/proc/RegisterSignals(datum/target, list/signal_types, proctype, override = FALSE)
	for (var/signal_type in signal_types)
		RegisterSignal(target, signal_type, proctype, override)

/**
 * Stop listening to a given signal from target
 *
 * Breaks the relationship between target and source datum, removing the callback when the signal fires
 *
 * Doesn't care if a registration exists or not
 *
 * Arguments:
 * * datum/target Datum to stop listening to signals from
 * * sig_typeor_types Signal string key or list of signal keys to stop listening to specifically
 */
/datum/proc/UnregisterSignal(datum/target, sig_type_or_types)
	var/list/lookup = target._listen_lookup
	if(!_signal_procs || !_signal_procs[target] || !lookup)
		return
	if(!islist(sig_type_or_types))
		sig_type_or_types = list(sig_type_or_types)
	for(var/sig in sig_type_or_types)
		if(!_signal_procs[target][sig])
			if(!istext(sig))
				stack_trace("We're unregistering with something that isn't a valid signal \[[sig]\], you fucked up")
			continue
		switch(length(lookup[sig]))
			if(2)
				lookup[sig] = (lookup[sig]-src)[1]
			if(1)
				stack_trace("[target] ([target.type]) somehow has single length list inside _listen_lookup")
				if(src in lookup[sig])
					lookup -= sig
					if(!length(lookup))
						target._listen_lookup = null
						break
			if(0)
				if(lookup[sig] != src)
					continue
				lookup -= sig
				if(!length(lookup))
					target._listen_lookup = null
					break
			else
				lookup[sig] -= src

	_signal_procs[target] -= sig_type_or_types
	if(!_signal_procs[target].len)
		_signal_procs -= target

/**
 * Internal proc to handle most all of the signaling procedure
 *
 * Will runtime if used on datums with an empty lookup list
 *
 * Use the [SEND_SIGNAL] define instead
 */
/datum/proc/_SendSignal(sigtype, list/arguments)
	var/target = _listen_lookup[sigtype]
	if(!length(target))
		var/datum/listening_datum = target
		return NONE | call(listening_datum, listening_datum._signal_procs[src][sigtype])(arglist(arguments))
	. = NONE
	// Snapshot every receiver and its proc first, so that even if one receiver
	// unregisters another, every receiver gets the signal this final time.
	// AKA: No you can't cancel the signal reception of another object by doing an unregister in the same signal.
	// The snapshot is a flat (receiver, proc) list taken from a pool instead of
	// allocated per send. Handlers can send signals themselves, so each nested
	// send takes its own buffer; one lost to a runtime is simply not returned.
	var/static/list/free_buffers = list()
	var/list/queued_calls
	var/free_count = length(free_buffers)
	if(free_count)
		queued_calls = free_buffers[free_count]
		free_buffers.len = free_count - 1
	else
		queued_calls = list()
	for(var/datum/listening_datum as anything in target)
		queued_calls += listening_datum
		queued_calls += listening_datum._signal_procs[src][sigtype]
	for(var/i in 1 to length(queued_calls) step 2)
		. |= call(queued_calls[i], queued_calls[i + 1])(arglist(arguments))
	queued_calls.Cut()
	free_buffers.len++
	free_buffers[free_buffers.len] = queued_calls

#ifdef SIGNAL_ARG_CHECKS
/// SEND_SIGNAL in debug builds: checks the argument count against
/// signal_arg_counts(), then dispatches like the release macro.
/proc/_checked_send_signal(datum/target, sigtype, list/arguments)
	var/static/list/declared_counts = signal_arg_counts()
	var/declared = declared_counts[sigtype]
	if(!isnull(declared) && declared != length(arguments) - 1)
		stack_trace("[sigtype] sent with [length(arguments) - 1] argument\s; signal_arg_counts() declares [declared].")
	if(!target._listen_lookup?[sigtype])
		return NONE
	return target._SendSignal(sigtype, arguments)
#endif
