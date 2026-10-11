// Immutable acceptance plans and pooled evaluation contexts.

// Unkeyed entries deliberately survive parent/child table compilation in order.
// The channel compiler applies explicit replacement; generic extend cannot erase history.
/proc/acceptance(channel, ENTRY_SLOTS, mode = ACCEPTANCE_APPEND, list/metadata = null)
	if(!istext(channel) || !length(channel))
		CRASH("acceptance channel needs a nonempty name")
	if(!(mode in list(ACCEPTANCE_APPEND, ACCEPTANCE_REPLACE, ACCEPTANCE_EMPTY)))
		CRASH("invalid acceptance mode [mode]")
	return entry_make(ENTRY_ACCEPTANCE, null, list("channel" = channel, "mode" = mode, "metadata" = metadata ? metadata.Copy() : null), entry_flatten(ENTRY_SLOT_LIST))

/datum/act/op/acceptance
	parent_type = /datum/act/admission_query
/datum/act/op/acceptance/held_provider()
	var/obj/object = target
	return istype(object) ? object : null

// Override maps hold immutable resolved plan entries, compiled by the library setter.
// Library stores this through TRACKED setters; null means inherit, EMPTY remains explicit.
/proc/acceptance_override(datum/declarer, list/current, channel, datum/entry/declaration)
	if(!istype(declaration) || declaration.kind != ENTRY_ACCEPTANCE || declaration.args["channel"] != channel)
		CRASH("acceptance override must be a declaration for [channel]")
	var/list/next = current ? current.Copy() : list()
	var/datum/entry/part/acceptance_plan/base = table_of(declarer).acceptance_channels?[channel]
	next[channel] = acceptance_compile(list(declaration), base)
	return next
/proc/acceptance_inherit(list/current, channel)
	var/list/next = current ? current.Copy() : list()
	next -= channel
	return length(next) ? next : null

// Engine hook: library overrides on the relevant base holder and uses its tracked var.
// No item types, body types, legacy predicate compiler or registry names enter this file.
/datum/proc/acceptance_overrides()
	return null
/datum/proc/acceptance_override_reads()
	return null

/datum/type_table
	var/list/acceptance_channels

// Invoked at table_compile's end, after entries/extends settle; no per-evaluation allocation.
/proc/acceptance_compile_table(datum/type_table/T)
	var/list/by_channel = list()
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_ACCEPTANCE))
		var/datum/entry/E = C.item
		var/channel = E.args["channel"]
		if(!by_channel[channel])
			by_channel[channel] = list()
		var/list/entries = by_channel[channel]
		if(length(C.whens) || C.owner)
			CRASH("conditional/capability-owned acceptance channel [channel] needs an activation-aware compiler")
		entries += E
	T.acceptance_channels = null
	for(var/channel in by_channel)
		LAZYSET(T.acceptance_channels, channel, acceptance_compile(by_channel[channel]))

/datum/entry/part/acceptance_plan
	part_name = "acceptance_plan"

/proc/acceptance_compile(list/entries, datum/entry/part/acceptance_plan/base = null)
	var/list/base_requirements = base?.children
	var/list/base_metadata = base?.args["metadata"]
	var/list/requirements = base_requirements ? base_requirements.Copy() : list()
	var/list/metadata = base_metadata ? base_metadata.Copy() : list()
	var/declared = base ? base.args["declared"] : FALSE
	var/explicit_empty = base ? base.args["empty"] : FALSE
	for(var/datum/entry/E as anything in entries)
		declared = TRUE
		var/mode = E.args["mode"]
		if(mode == ACCEPTANCE_REPLACE || mode == ACCEPTANCE_EMPTY)
			requirements.Cut()
			metadata.Cut()
		explicit_empty = mode == ACCEPTANCE_EMPTY
		if(explicit_empty)
			continue
		for(var/child in E.children)
			if(!istype(child, /datum/entry/part/req))
				CRASH("acceptance requires native requirements")
			requirements += child
		if(E.args["metadata"])
			metadata += list(E.args["metadata"])
	return part_make(/datum/entry/part/acceptance_plan, list("declared" = declared, "empty" = explicit_empty, "metadata" = metadata), requirements)

/proc/acceptance_plan_for(datum/declarer, channel)
	READS_FROM(declarer)
	var/list/overrides = declarer.acceptance_overrides()
	var/datum/entry/part/acceptance_plan/override = LAZYACCESS(overrides, channel)
	return override ? override : table_of(declarer).acceptance_channels?[channel]

/datum/entry/part/acceptance_plan/proc/check(datum/act/op/A)
	op_menu_record_reads(read_keys(A))
	for(var/datum/entry/part/req/R as anything in children)
		var/why = op_req_check(A, R)
		if(!isnull(why))
			return why
	return null
/datum/entry/part/acceptance_plan/proc/read_keys(datum/act/op/A)
	. = list()
	for(var/datum/entry/part/req/R as anything in children)
		for(var/list/pair as anything in R.read_keys(A))
			if(length(pair) != 2 || !isdatum(pair[1]))
				continue
			var/datum/read_owner = pair[1]
			if(!QDELETED(read_owner))
				. += list(pair.Copy())
	for(var/list/pair as anything in A.holder.acceptance_override_reads())
		if(length(pair) != 2 || !isdatum(pair[1]))
			continue
		var/datum/read_owner = pair[1]
		if(!QDELETED(read_owner))
			. += list(pair.Copy())

// Direct fields use the existing bounded pooled act contract.
/proc/acceptance_act(datum/declarer, datum/destination, atom/movable/candidate, mob/wearer = null, mob/mover = null, slot_id = null, list/options = null, wearer_is_actor = FALSE, query_type = /datum/act/op/acceptance)
	return query_admission_query(declarer, candidate, wearer_is_actor ? wearer : mover, wearer, mover, destination, slot_id, null, options, query_type)

// One immutable precompiled plan and one pooled query. Every evaluation path releases it.
// Consumer needs presence separately because empty suit-storage is NOT unconstrained storage.
/proc/acceptance_declared(datum/declarer, channel)
	var/datum/entry/part/acceptance_plan/P = acceptance_plan_for(declarer, channel)
	return P && P.args["declared"] && !P.args["empty"]
/proc/acceptance_reason(datum/declarer, channel, datum/destination, atom/movable/candidate, mob/wearer = null, mob/mover = null, slot_id = null, list/options = null, wearer_is_actor = FALSE)
	var/datum/entry/part/acceptance_plan/P = acceptance_plan_for(declarer, channel)
	var/datum/act/op/acceptance/A
	var/previous_pure_depth = GLOB.op_pure_depth
	try
		A = query_admission_query(declarer, candidate, wearer_is_actor ? wearer : mover, wearer, mover, destination, slot_id, channel, options, /datum/act/op/acceptance)
		op_pure_begin()
		op_menu_record_reads(declarer.acceptance_override_reads())
		. = P ? P.check(A) : null
	catch(var/exception/fault)
		// Unwind the query and any nested requirement guard that faulted.
		GLOB.op_pure_depth = previous_pure_depth
		acceptance_act_release(A)
		throw fault
	op_pure_end()
	acceptance_act_release(A)
/proc/acceptance_read_keys(datum/declarer, channel, datum/destination, atom/movable/candidate, mob/wearer = null, mob/mover = null, slot_id = null, list/options = null, wearer_is_actor = FALSE)
	var/datum/entry/part/acceptance_plan/P = acceptance_plan_for(declarer, channel)
	var/datum/act/op/acceptance/A
	var/previous_pure_depth = GLOB.op_pure_depth
	try
		A = query_admission_query(declarer, candidate, wearer_is_actor ? wearer : mover, wearer, mover, destination, slot_id, channel, options, /datum/act/op/acceptance)
		op_pure_begin()
		. = P ? P.read_keys(A) : declarer.acceptance_override_reads()
	catch(var/exception/fault)
		// Unwind the query and any nested requirement guard that faulted.
		GLOB.op_pure_depth = previous_pure_depth
		acceptance_act_release(A)
		throw fault
	op_pure_end()
	acceptance_act_release(A)

// Native null-or-reason evaluation under the same purity bracket as holds/refusal.
/proc/op_req_check(datum/act/op/A, datum/entry/part/req/R)
	var/previous_pure_depth = GLOB.op_pure_depth
	op_pure_begin()
	try
		. = R.check(A)
	catch(var/exception/fault)
		GLOB.op_pure_depth = previous_pure_depth
		throw fault
	op_pure_end()

/proc/acceptance_act_release(datum/act/op/acceptance/A)
	if(A)
		A.release()

// Evaluate an already-compiled slot plan without changing holder overrides or publishing.
/proc/acceptance_plan_query(datum/entry/part/acceptance_plan/P, datum/declarer, channel, datum/destination, atom/movable/candidate, mob/wearer = null, mob/mover = null, slot_id = null, wearer_is_actor = FALSE, reads_only = FALSE)
	var/datum/act/op/acceptance/A
	var/previous_pure_depth = GLOB.op_pure_depth
	try
		A = query_admission_query(declarer, candidate, wearer_is_actor ? wearer : mover, wearer, mover, destination, slot_id, channel, null, /datum/act/op/acceptance)
		op_pure_begin()
		. = reads_only ? P.read_keys(A) : P.check(A)
	catch(var/exception/fault)
		GLOB.op_pure_depth = previous_pure_depth
		acceptance_act_release(A)
		throw fault
	op_pure_end()
	acceptance_act_release(A)

/// Validate already compiled native acceptance plans; constructors validate schema when a type is first compiled.
/proc/acceptance_validate_cached()
	. = list()
	var/list/cache = type_table_cache()
	for(var/path in cache)
		var/datum/type_table/T = cache[path]
		for(var/channel in T.acceptance_channels)
			var/datum/entry/part/acceptance_plan/P = T.acceptance_channels[channel]
			if(!istype(P))
				. += "[path] [channel] has no resolved acceptance plan"
				continue
			for(var/datum/entry/child as anything in P.children)
				if(!istype(child, /datum/entry/part/req))
					. += "[path] [channel] contains a non-requirement child"
