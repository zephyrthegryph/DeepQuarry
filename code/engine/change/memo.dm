// Declared lazy scalar outputs. Cells own no borrowed world objects: producers
// are weak handles and returned values are null, numbers or text only.
GLOBAL_LIST_EMPTY(memo_read_index)
GLOBAL_LIST_EMPTY(memo_lifetime_index)

/datum/rx_state
	var/list/memo_cells
	/// Real memo lifetime teardown boundary; flagged producers still exist before it.
	var/memo_lifetime_torn_down = FALSE

/datum/memo_cell
	var/holder_ref
	var/key
	var/handler
	var/list/watching
	var/list/identity_inputs
	var/input_state
	var/value
	var/valid = FALSE
	var/dirty = TRUE
	var/evaluating = FALSE
	var/sampling_inputs = FALSE
	var/computations = 0

/proc/memo(key, compute)
	return entry_make(ENTRY_MEMO, key, list("compute" = compute))

/datum/proc/generated_memo_reads(proc_name)
	return list()

/datum/proc/generated_memo_output_reads()
	return list()

/proc/memo_read_declared(datum/holder, key)
	if(findtext(key, "memo:") != 1)
		return FALSE
	for(var/datum/centry/C as anything in compiled_entries(table_of(holder), ENTRY_MEMO))
		var/datum/entry/entry = C.item
		if(memo_read_key(entry.key) == key)
			return TRUE
	return FALSE

/// The output key is real computed state, separate from every input's key.
/proc/memo_read_key(key)
	return "memo:[key]"

/proc/memo_cell_of(datum/holder, key)
	RETURN_TYPE(/datum/memo_cell)
	var/datum/rx_state/state = rx_of(holder)
	var/datum/memo_cell/cell = state.memo_cells?[key]
	if(cell)
		return cell
	var/compute
	for(var/datum/centry/C as anything in compiled_entries(table_of(holder), ENTRY_MEMO))
		var/datum/entry/entry = C.item
		if(entry.key == key)
			if(length(C.whens))
				CRASH("memo [holder.type].[key] cannot have activation conditions")
			compute = entry.args["compute"]
	if(!compute)
		CRASH("undeclared memo [holder.type].[key]")
	cell = new
	cell.holder_ref = entity_handle(holder)
	cell.key = key
	cell.handler = compute
	// Only framework bookkeeping runs outside a caller's pure evaluation.
	// The user's computation never runs with these guards suspended.
	var/prior_pure = GLOB.op_pure_depth
	var/prior_output = GLOB.derived_evaluating
	GLOB.op_pure_depth = 0
	GLOB.derived_evaluating = 0
	try
		rel_add(state, nameof(state.memo_cells), cell, key)
	catch(var/exception/fault)
		// The entry can have linked before its publication faulted. Teardown
		// releases any partial custody/indexes, preserving the original fault.
		try
			qdel(cell)
		catch(var/exception/cleanup_fault)
			dq_report_caught(cleanup_fault, "Memo cell cleanup failed while preserving its allocation fault")
		GLOB.op_pure_depth = prior_pure
		GLOB.derived_evaluating = prior_output
		throw fault
	GLOB.op_pure_depth = prior_pure
	GLOB.derived_evaluating = prior_output
	return cell

/proc/memo_value(datum/holder, key)
	READS_FROM(holder)
	if(!holder || QDELING(holder))
		return null
	return memo_cell_of(holder, key).read()

/datum/memo_cell/proc/watch(datum/producer, field)
	if(!producer || QDELING(producer))
		return
	var/index_key = "[REF(producer)]|[field]"
	var/list/cells = GLOB.memo_read_index[index_key]
	if(!cells)
		cells = list()
		GLOB.memo_read_index[index_key] = cells
	if(src in cells)
		return
	cells += src
	rx_watch_adjust(producer, field, 1)
	LAZYADD(watching, list(list(entity_handle(producer), field, index_key)))

/datum/memo_cell/proc/watch_identity(datum/producer)
	if(!producer)
		return
	var/datum/rx_state/state = producer.rx
	if(QDELING(producer))
		// A warm binding can follow native phase changes while the real
		// reaction record and weak handle still exist. Never resurrect them.
		if(!state || state.memo_lifetime_torn_down || !entity_handle_of(producer))
			return
	else
		state = rx_of(producer)
		entity_handle(producer)
	if(state.memo_lifetime_torn_down)
		return
	var/index_key = REF(producer)
	var/list/cells = GLOB.memo_lifetime_index[index_key]
	if(!cells)
		cells = list()
		GLOB.memo_lifetime_index[index_key] = cells
	if(src in cells)
		return
	cells += src
	LAZYADD(identity_inputs, index_key)

/datum/memo_cell/proc/capture(value)
	return memo_input_state(value, null, src)

/datum/memo_cell/proc/unbind()
	for(var/list/read as anything in watching)
		var/datum/producer = resolve_handle(read[1])
		if(producer?.rx)
			rx_watch_adjust(producer, read[2], -1)
		var/list/cells = GLOB.memo_read_index[read[3]]
		cells -= src
		if(!length(cells))
			GLOB.memo_read_index -= read[3]
	watching = null
	for(var/index_key in identity_inputs)
		var/list/cells = GLOB.memo_lifetime_index[index_key]
		cells -= src
		if(!length(cells))
			GLOB.memo_lifetime_index -= index_key
	identity_inputs = null

/// Capture input values without retaining list containers or borrowed datums.
/// Membership order and associative values are actual inputs, not revision IDs.
/proc/memo_input_state(value, list/ancestors = null, datum/memo_cell/cell = null)
	if(isdatum(value))
		var/datum/D = value
		cell?.watch_identity(D)
		return QDELING(D) ? null : "datum:[entity_handle(D)]"
	if(ispath(value))
		return "path:[value]"
	if(islist(value))
		var/list/L = value
		if(ancestors?.Find(L))
			CRASH("memo input contains a cyclic list")
		var/list/next_ancestors = ancestors ? ancestors.Copy() : list()
		next_ancestors += list(L)
		var/list/snapshot = list()
		for(var/i in 1 to length(L))
			var/member = L[i]
			var/associated = isnum(member) || isnull(member) || islist(member) ? null : L[member]
			snapshot += list(list(memo_input_state(member, next_ancestors, cell), memo_input_state(associated, next_ancestors, cell)))
		return snapshot
	return value

/// Follow actual fields and each actual member of a declared collection.
/// Observe every traversed edge, including the edge whose current value is null.
/datum/memo_cell/proc/index_selector(list/selector)
	if(selector["is_literal"])
		return list(TRUE, selector["literal"])
	var/datum/holder = resolve_handle(holder_ref)
	var/datum/root = lookup_read_root(holder, null, selector["root"])
	var/argument = root
	for(var/name in selector["path"])
		if(QDELETED(root))
			return list(FALSE, null)
		if(!(name in root.vars))
			CRASH("memo [key] needs actual index selector field [root.type].[name]")
		watch(root, name)
		argument = root.vars[name]
		root = isdatum(argument) ? argument : null
	return list(TRUE, argument)

/datum/memo_cell/proc/follow(datum/producer, list/path, position, field, expected_type = null, conservative = FALSE)
	if(!producer)
		return null
	// A native lifetime descriptor remains readable at the marking boundary:
	// the exact flag is meaningful before the producer's teardown begins.
	if(position > length(path) && field == "lifetime:deleted")
		if(expected_type && !istype(producer, expected_type))
			if(conservative)
				return "different possible lifetime receiver"
			CRASH("memo [key] expected [expected_type], got [producer.type]")
		watch_identity(producer)
		return producer.gc_destroyed
	if(QDELING(producer))
		return null
	if(position > length(path))
		if(expected_type && !istype(producer, expected_type))
			if(conservative)
				return "different possible index receiver"
			CRASH("memo [key] expected [expected_type], got [producer.type]")
		if(findtext(field, "memo:") == 1)
			if(!memo_read_declared(producer, field))
				return "undeclared memo dependency"
			watch(producer, field)
			var/datum/memo_cell/child = memo_cell_of(producer, copytext(field, 6))
			// A dependency declaration includes untaken branches. Do not force
			// a child computation here (or invent cycles in unused branches).
			if(child == src)
				return "self memo dependency"
			var/datum/child_holder = resolve_handle(child.holder_ref)
			return list(child.valid, child.dirty, child.value, child_holder && !QDELING(child_holder) ? child.inputs(child_holder) : null)
		if(!(field in producer.vars))
			CRASH("memo [key] needs an actual tracked field [producer.type].[field]")
		watch(producer, field)
		return capture(producer.vars[field])
	var/hop = path[position]
	var/list/indexed = islist(hop) ? hop : null
	var/each = !indexed && copytext(hop, max(1, length(hop) - 1)) == "[]"
	var/name = indexed ? indexed["name"] : (each ? copytext(hop, 1, length(hop) - 1) : hop)
	if(!(name in producer.vars))
		if(conservative)
			return "different possible index path"
		CRASH("memo [key] needs an actual relation [producer.type].[name]")
	watch(producer, name)
	var/next = producer.vars[name]
	if(!each && !indexed)
		var/datum/child = isdatum(next) ? next : null
		return list(capture(next), follow(child, path, position + 1, field, expected_type, conservative))
	var/list/members = next
	var/list/states = list(capture(members))
	if(indexed)
		var/list/selector = indexed["selector"]
		if(selector)
			var/list/selection = index_selector(selector)
			states += list(capture(selection[2]))
			if(!selection[1] || isnull(selection[2]) || !members)
				return states
			var/selected = members[selection[2]]
			var/datum/selected_member = isdatum(selected) ? selected : null
			states += list(follow(selected_member, path, position + 1, field, expected_type, conservative))
			return states
		// A selector from a loop/composed expression has no single runtime
		// binding. Follow actual possible indexed values, typed at the leaf;
		// both positional keys and associative values are genuine candidates.
		var/list/candidates
		for(var/member_key in members)
			if(isdatum(member_key))
				LAZYOR(candidates, member_key)
			if(!isnum(member_key) && !isnull(member_key) && !islist(member_key))
				var/associated = members[member_key]
				if(isdatum(associated))
					LAZYOR(candidates, associated)
		for(var/datum/member as anything in candidates)
			states += list(follow(member, path, position + 1, field, expected_type, TRUE))
		return states
	// A ForList iteration follows actual list elements/keys, not map values.
	for(var/datum/member as anything in members)
		if(isdatum(member))
			states += list(follow(member, path, position + 1, field, expected_type, conservative))
	return states

/datum/memo_cell/proc/inputs(datum/holder)
	// Declarations include untaken branches, so a dependency-graph cycle is
	// a stable signature marker, not a forced callback or a runtime cycle.
	if(sampling_inputs)
		return "memo dependency cycle [REF(src)]"
	sampling_inputs = TRUE
	try
		. = collect_inputs(holder)
	catch(var/exception/fault)
		sampling_inputs = FALSE
		throw fault
	sampling_inputs = FALSE

/datum/memo_cell/proc/collect_inputs(datum/holder)
	unbind()
	var/list/states = list()
	for(var/list/spec as anything in holder.generated_memo_reads(handler))
		var/list/lookup = spec["lookup"]
		if(lookup)
			var/argument = lookup["literal"]
			var/datum/root = lookup_read_root(holder, null, lookup["root"])
			var/resolved = TRUE
			if(!lookup["is_literal"])
				var/list/argument_path = lookup["path"]
				for(var/name in argument_path)
					if(!root || QDELING(root))
						resolved = FALSE
						break
					if(!(name in root.vars))
						CRASH("memo lookup [key] needs actual argument field [root.type].[name]")
					watch(root, name)
					argument = root.vars[name]
					root = isdatum(argument) ? argument : null
			if(!resolved)
				states += list("missing lookup root")
				continue
			states += list(capture(argument))
			var/datum/registry = call(lookup["registry"])()
			watch(registry, call(lookup["identity_key"])(argument))
			var/datum/selected = call(lookup["lookup"])(argument)
			states += list(capture(selected), follow(selected, list(), 1, lookup["field"]))
		else
			var/datum/root = lookup_read_root(holder, null, spec["root"])
			states += list(follow(root, spec["path"], 1, spec["field"], spec["owner"]))
	return json_encode(states)

/datum/memo_cell/proc/read()
	if(evaluating)
		CRASH("memo cycle at [key]")
	var/datum/holder = resolve_handle(holder_ref)
	if(!holder || QDELING(holder))
		return null
	evaluating = TRUE
	var/prior_pure = GLOB.op_pure_depth
	var/prior_output = GLOB.derived_evaluating
	try
		var/current_inputs = inputs(holder)
		if(!valid || dirty || current_inputs != input_state)
			var/datum/act/eval/A = present_eval_context(holder, null)
			var/prior_violations = length(GLOB.op_pure_violations)
			op_pure_begin()
			var/result
			try
				result = call(holder, handler)(A)
			catch(var/exception/fault)
				GLOB.op_pure_depth = prior_pure
				try
					A.release()
				catch(var/exception/cleanup_fault)
					dq_report_caught(cleanup_fault, "Memo evaluation cleanup failed while preserving its computation fault")
				throw fault
			GLOB.op_pure_depth = prior_pure
			A.release()
			if(length(GLOB.op_pure_violations) != prior_violations)
				CRASH("memo [holder.type].[key] wrote state during pure computation")
			computations++
			if(!isnull(result) && !isnum(result) && !istext(result))
				CRASH("memo [holder.type].[key] returns a borrowed datum or mutable container; only scalar outputs are supported")
			value = result
			valid = TRUE
			dirty = FALSE
			// A computed child can have been populated by this callback. Record
			// its actual resulting state without running untaken branches.
			input_state = inputs(holder)
		. = value
	catch(var/exception/fault)
		valid = FALSE
		dirty = TRUE
		evaluating = FALSE
		GLOB.op_pure_depth = prior_pure
		GLOB.derived_evaluating = prior_output
		throw fault
	evaluating = FALSE
	GLOB.op_pure_depth = prior_pure
	GLOB.derived_evaluating = prior_output

/datum/memo_cell/proc/invalidate()
	if(dirty)
		return
	var/datum/holder = resolve_handle(holder_ref)
	if(holder && !QDELING(holder))
		// A direct reader can have recomputed between the synchronous write
		// and its deferred publication. Do not dirty that current result twice.
		if(valid && inputs(holder) == input_state)
			return
		dirty = TRUE
		state_changed(holder, 0, memo_read_key(key))

/// Runs before publication is deferred by state_batch, so a synchronous reader
/// is current while reactions and presentation still observe the whole cohort.
/proc/memo_inputs_changed(datum/producer, field)
	if(!GLOB?.memo_read_index)
		return
	var/list/cells = GLOB.memo_read_index["[REF(producer)]|[field]"]
	for(var/datum/memo_cell/cell as anything in cells?.Copy())
		cell.invalidate()

/// The native deletion flag is a lifecycle input. Marking a batch member doomed
/// invalidates its subscribers before any destruction phase can read a memo.
/proc/memo_lifetime_changed(datum/producer)
	memo_source_gone(producer)

/proc/memo_source_gone(datum/producer)
	if(!GLOB?.memo_lifetime_index || !GLOB.memo_read_index)
		return
	var/prefix = "[REF(producer)]|"
	var/list/identity_cells = GLOB.memo_lifetime_index[REF(producer)]
	var/list/cells = identity_cells?.Copy()
	for(var/index_key in GLOB.memo_read_index)
		if(findtext(index_key, prefix) == 1)
			for(var/datum/memo_cell/cell as anything in GLOB.memo_read_index[index_key])
				LAZYOR(cells, cell)
	for(var/datum/memo_cell/cell as anything in cells)
		cell.invalidate()
	if(producer.rx?.memo_lifetime_torn_down)
		// A dirty cell need not resample during invalidation. Detach its
		// retired-source edges anyway; no weak identity index may outlive
		// the real producer record merely because a result was already dirty.
		GLOB.memo_lifetime_index -= REF(producer)
		for(var/datum/memo_cell/cell as anything in cells)
			if(cell.identity_inputs)
				cell.identity_inputs -= REF(producer)
			for(var/list/read as anything in cell.watching?.Copy())
				if(findtext(read[3], prefix) == 1)
					rx_watch_adjust(producer, read[2], -1)
					cell.watching -= list(read)
		for(var/index_key in GLOB.memo_read_index.Copy())
			if(findtext(index_key, prefix) == 1)
				GLOB.memo_read_index -= index_key

/datum/memo_cell/lifecycle_unbind()
	unbind()
	. = ..()
