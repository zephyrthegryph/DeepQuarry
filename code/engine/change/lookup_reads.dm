// Declared lookups bind real argument, registry-identity and result producers.
// Cache/evaluation consumers own their scopes; bindings never retain pooled acts.
GLOBAL_LIST_EMPTY(lookup_read_index)
GLOBAL_DATUM(lookup_read_scope_frame, /datum/lookup_read_scope)

/datum/proc/generated_lookup_reads(proc_name = null)
	return list()

/datum/proc/generated_lookup_output_reads()
	return list()

/datum/rx_state
	var/datum/lookup_read_scope/lookup_scope

/datum/lookup_read_scope
	var/list/bindings
	var/list/participants

CAPABILITIES(/datum/lookup_read_scope)
	owns_many(nameof(bindings), /datum/lookup_read_binding)
	ref_many(nameof(participants), /datum, on_other_deleted = OTHER_DELETE_ME)

/datum/lookup_read_scope/proc/ensure(datum/reader, datum/root, list/spec)
	READS_FROM()
	var/key = "[entity_handle(reader)]|[spec["key"]]|[root ? entity_handle(root) : "literal"]"
	var/datum/lookup_read_binding/existing = bindings?[key]
	if(existing)
		return existing
	if(OP_PURE_ACTIVE)
		CRASH("lookup [spec["key"]] was not prepared before pure evaluation")
	var/datum/lookup_read_binding/binding = new
	rel_add(src, nameof(bindings), binding, key)
	rel_add(src, nameof(participants), reader)
	if(root)
		rel_add(src, nameof(participants), root)
	binding.bind(reader, root, spec)
	return binding

/proc/lookup_static_scope(datum/holder)
	READS_FROM()
	var/datum/rx_state/state = rx_of(holder)
	if(!state.lookup_scope)
		if(OP_PURE_ACTIVE)
			CRASH("lookup state of [holder.type] was not prepared before pure evaluation")
		var/datum/lookup_read_scope/scope = new
		rel_set(state, nameof(state.lookup_scope), scope)
	return state.lookup_scope

/// Resolve an explicit context root; never substitute holder for absent actor/target.
/proc/lookup_read_root(datum/holder, datum/act/A, root)
	READS_FROM()
	if(root == "holder")
		return holder
	var/datum/act/action/action = A
	var/datum/act/eval/eval = A
	var/datum/act/notice/notice = A
	switch(root)
		if("actor")
			return istype(action) ? action.actor : (istype(eval) ? eval.actor : null)
		if("target")
			return istype(action) ? action.target : (istype(notice) ? notice.target : null)
		if("held")
			return istype(action) ? action.held : null
		if("authority")
			var/datum/authority = istype(action) ? action.authority : (istype(eval) ? eval.authority : null)
			return istype(authority) ? authority : null
	if(istext(root) && findtext(root, "system:") == 1)
		return stat_system_singleton(copytext(root, 8))
	return null

/// Actual generated keys and their consumer-owned bindings, before cached evaluation.
/proc/lookup_reads_for(datum/holder, proc_name = null, datum/act/A = null, datum/lookup_read_scope/scope = null)
	READS_FROM()
	. = list()
	if(!holder || QDELING(holder))
		return
	var/list/definitions = holder.generated_lookup_reads(proc_name)
	for(var/list/spec as anything in definitions)
		var/contextual = spec["root"] in list("actor", "target", "held", "authority")
		if(contextual && !A)
			continue
		var/datum/root = lookup_read_root(holder, A, spec["root"])
		if(!spec["is_literal"] && !root)
			continue
		var/datum/lookup_read_scope/consumer = contextual ? scope : lookup_static_scope(holder)
		if(!consumer && istype(A, /datum/act/op))
			var/datum/act/op/op = A
			consumer = op.pending?.lookup_scope
		if(!consumer && A)
			consumer = GLOB.lookup_read_scope_frame
		// A one-shot click has no cached contextual result to retain. Static
		// holder/literal dependencies belong to the real holder record instead.
		if(!consumer && contextual)
			continue
		if(!consumer)
			consumer = lookup_static_scope(holder)
		consumer.ensure(holder, root, spec)
		. |= list(spec["key"])

/proc/lookup_reads_prepare(datum/holder, datum/act/A = null, datum/lookup_read_scope/scope = null)
	READS_FROM()
	if(OP_PURE_ACTIVE)
		return // outer preparation covers transitive callback definitions
	lookup_reads_for(holder, null, A, scope)

/datum/lookup_read_binding
	var/reader_ref
	var/root_ref
	var/list/spec
	var/list/watching
	var/rebinding = FALSE

/datum/lookup_read_binding/proc/bind(datum/reader, datum/root, list/definition)
	READS_FROM()
	reader_ref = entity_handle(reader)
	root_ref = root ? entity_handle(root) : null
	spec = definition
	rebind()

/datum/lookup_read_binding/proc/add_read(datum/producer, key)
	READS_FROM()
	if(!producer || QDELING(producer) || !istext(key))
		return
	var/index_key = "[REF(producer)]|[key]"
	var/list/readers = GLOB.lookup_read_index[index_key]
	if(!readers)
		readers = list()
		GLOB.lookup_read_index[index_key] = readers
	if(src in readers)
		return
	readers += src
	rx_watch_adjust(producer, key, 1)
	LAZYADD(watching, list(list(entity_handle(producer), key, index_key)))

/datum/lookup_read_binding/proc/unbind()
	READS_FROM()
	for(var/list/read as anything in watching)
		var/datum/producer = resolve_handle(read[1])
		if(producer?.rx)
			rx_watch_adjust(producer, read[2], -1)
		var/list/readers = GLOB.lookup_read_index[read[3]]
		readers -= src
		if(!length(readers))
			GLOB.lookup_read_index -= read[3]
	watching = null

/datum/lookup_read_binding/proc/rebind()
	READS_FROM()
	if(rebinding)
		return
	rebinding = TRUE
	unbind()
	var/datum/reader = resolve_handle(reader_ref)
	if(!reader || QDELING(reader))
		rebinding = FALSE
		return
	var/argument = spec["literal"]
	var/resolved = TRUE
	if(!spec["is_literal"])
		var/datum/walk = resolve_handle(root_ref)
		var/list/path = spec["path"]
		argument = walk
		for(var/name in path)
			if(!walk || QDELING(walk))
				resolved = FALSE
				break // a missing/deleted relation target is followed through its prior live hop
			if(!(name in walk.vars))
				rebinding = FALSE
				CRASH("lookup [spec["key"]] requires actual field [walk.type].[name]; virtual/getter arguments need a typed read descriptor")
			add_read(walk, name)
			argument = walk.vars[name]
			walk = isdatum(argument) ? argument : null
	if(!resolved)
		rebinding = FALSE
		return // do not watch an invented null registry identity for an absent relation path
	var/datum/registry = call(spec["registry"])()
	if(registry && !QDELING(registry))
		add_read(registry, call(spec["identity_key"])(argument))
	var/datum/selected = call(spec["lookup"])(argument)
	if(selected && !QDELING(selected))
		add_read(selected, spec["field"])
	rebinding = FALSE

/datum/lookup_read_binding/proc/changed()
	READS_FROM()
	var/datum/reader = resolve_handle(reader_ref)
	if(!reader || QDELING(reader))
		unbind()
		return
	rebind()
	tracked_changed(reader, spec["key"])

/datum/lookup_read_binding/lifecycle_unbind()
	unbind()
	. = ..()

/proc/lookup_reads_published(datum/producer, key)
	READS_FROM()
	var/list/readers = GLOB.lookup_read_index["[REF(producer)]|[key]"]
	for(var/datum/lookup_read_binding/binding as anything in readers?.Copy())
		binding.changed()

/proc/lookup_reads_source_gone(datum/producer)
	READS_FROM()
	var/list/all_bindings
	var/prefix = "[REF(producer)]|"
	for(var/key in GLOB.lookup_read_index)
		if(findtext(key, prefix) != 1)
			continue
		for(var/datum/lookup_read_binding/binding as anything in GLOB.lookup_read_index[key])
			LAZYOR(all_bindings, binding)
	for(var/datum/lookup_read_binding/binding as anything in all_bindings)
		binding.changed()

/proc/op_menu_cache_clear()
	READS_FROM()
	for(var/key in GLOB.op_menu_cache)
		var/list/entry = GLOB.op_menu_cache[key]
		var/datum/lookup_read_scope/scope = length(entry) >= 4 ? entry[4] : null
		if(scope && !QDELETED(scope))
			END_SCOPE(scope)
	GLOB.op_menu_cache.Cut()

/proc/lookup_read_declared(datum/holder, key)
	READS_FROM()
	for(var/list/spec as anything in holder.generated_lookup_reads())
		if(spec["key"] == key)
			return TRUE
	return FALSE

/// Exact keys with live bound-read consumers on this registry. This is framework
/// demand metadata for a system's write step, not a requirement's state dependency.
/proc/lookup_registry_watched_keys(datum/registry)
	READS_FROM()
	. = list()
	if(!registry || QDELING(registry))
		return
	var/prefix = "[REF(registry)]|"
	for(var/index_key in GLOB.lookup_read_index)
		if(findtext(index_key, prefix) == 1 && length(GLOB.lookup_read_index[index_key]))
			. |= list(copytext(index_key, length(prefix) + 1))
