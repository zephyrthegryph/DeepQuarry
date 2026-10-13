// Atomic publication of a synchronous setter cohort. Values are written by
// their real setters; observers see the completed cohort at the outer boundary.
// Queue rows contain weak handles and scalar keys only, never datum receivers.
GLOBAL_VAR_INIT(state_batch_depth, 0)
GLOBAL_VAR_INIT(state_batch_flushing, FALSE)
GLOBAL_LIST_EMPTY(state_batch_pending)

/// Run one synchronous writer. Nested batches share the same publication queue.
/// A failed writer's completed mutations still publish before its fault propagates.
/proc/state_batch(datum/holder, writer, list/arguments = null)
	SHOULD_NOT_SLEEP(TRUE)
	OP_PURE_GUARD("a state publication batch began")
	if(!holder || QDELING(holder))
		return
	GLOB.state_batch_depth++
	try
		. = call(holder, writer)(arglist(arguments || list()))
	catch(var/exception/fault)
		try
			state_batch_end()
		catch(var/exception/delivery_fault)
			dq_report_caught(delivery_fault, "State batch publication failed while preserving its writer fault")
		throw fault
	state_batch_end()

/// Framework-only boundary paired by state_batch(); callers use the wrapper.
/proc/state_batch_end()
	if(GLOB.state_batch_depth <= 0)
		CRASH("unbalanced state publication batch")
	GLOB.state_batch_depth--
	if(!GLOB.state_batch_depth && !GLOB.state_batch_flushing)
		state_batch_flush()

/// Preserve the actual key and all its channel bits once per receiver/cohort.
/proc/state_batch_queue(datum/receiver, channel, key)
	var/handle = entity_handle(receiver)
	var/list/record = GLOB.state_batch_pending[handle]
	if(!record)
		record = list()
		GLOB.state_batch_pending[handle] = record
	var/token = isnull(key) ? "all" : "key:[key]"
	var/list/change = record[token]
	if(!change)
		change = list(key, 0)
		record[token] = change
	change[2] |= channel

/// Native producer publications share the atomic boundary but retain their
/// identity. They do not become stored-var writes or legacy state_changed calls.
/proc/state_batch_queue_native_key(datum/receiver, key)
	var/handle = entity_handle(receiver)
	var/list/record = GLOB.state_batch_pending[handle]
	if(!record)
		record = list()
		GLOB.state_batch_pending[handle] = record
	record["native:[key]"] = list(key, 0, TRUE)

/// Continue delivering the cohort after a receiver faults, then rethrow the
/// first fault with all framework flags restored. A nested writer queues the
/// next cohort; it never replaces the delivery currently being iterated.
/proc/state_batch_flush()
	SHOULD_NOT_SLEEP(TRUE)
	if(GLOB.state_batch_flushing || GLOB.state_batch_depth)
		return
	GLOB.state_batch_flushing = TRUE
	var/exception/first_fault
	while(length(GLOB.state_batch_pending))
		var/list/cohort = GLOB.state_batch_pending
		GLOB.state_batch_pending = list()
		for(var/handle in cohort)
			var/list/record = cohort[handle]
			for(var/token in record)
				var/datum/receiver = resolve_handle(handle)
				if(!receiver || QDELING(receiver))
					break
				var/list/change = record[token]
				var/prior_pure_depth = GLOB.op_pure_depth
				var/prior_output_depth = GLOB.derived_evaluating
				try
					if(length(change) >= 3 && change[3])
						publish_key_changed(receiver, change[1])
					else
						state_changed(receiver, change[2], change[1])
				catch(var/exception/fault)
					GLOB.op_pure_depth = prior_pure_depth
					GLOB.derived_evaluating = prior_output_depth
					if(first_fault)
						dq_report_caught(fault, "Additional state batch publication fault")
					else
						first_fault = fault
	GLOB.state_batch_flushing = FALSE
	if(first_fault)
		throw first_fault
