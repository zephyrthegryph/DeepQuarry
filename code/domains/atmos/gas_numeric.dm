// Actual committed numeric gas producers. Preparation is effectful; lookups and value reads are pure.
READ_LOOKUP(/proc/gas_numeric_lookup, registry = GLOBAL_PROC_REF(gas_numeric_registry), key = GLOBAL_PROC_REF(gas_numeric_identity_key), argument = 1, result = /datum/gas_numeric_source)
GLOBAL_DATUM_INIT(gas_numeric_registry, /datum/gas_numeric_registry, new)

CAPABILITY_TYPE(gas_numeric_read, CAP_GAS_NUMERIC_READ, /datum/capability/lib/gas_numeric_read, key = air, air = null)

/datum/capability/lib/gas_numeric_read
	holder_hooks = HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY | HOLDER_HOOK_RELATION

/datum/capability/lib/gas_numeric_read/cap_data_type()
	return /datum/cap_data/gas_numeric_read

/datum/capability/lib/gas_numeric_read/on_holder_init(datum/act/eval/A)
	rearm(A)

/datum/capability/lib/gas_numeric_read/on_holder_relation_changed(datum/act/eval/A, relation_var)
	if(relation_var == air)
		rearm(A)

/datum/capability/lib/gas_numeric_read/on_holder_destroy(datum/act/eval/A)
	var/datum/activation/activation = cap_activation(A.holder, CAP_GAS_NUMERIC_READ, air, FALSE)
	var/datum/cap_data/gas_numeric_read/data = activation?.data
	if(data)
		gas_numeric_detach(data)

/datum/capability/lib/gas_numeric_read/proc/rearm(datum/act/eval/A)
	var/datum/activation/activation = cap_activation(A.holder, CAP_GAS_NUMERIC_READ, air, TRUE)
	var/datum/cap_data/gas_numeric_read/data = activation_data(activation)
	state_batch(gas_numeric_registry(), TYPE_PROC_REF(/datum/gas_numeric_registry, rearm), list(data, gas_air_of(A.holder, air)))

/datum/gas_numeric_registry/proc/rearm(datum/cap_data/gas_numeric_read/data, datum/gas_mixture/mixture)
	gas_numeric_detach(data)
	if(!mixture || QDELETED(mixture))
		return
	rel_set(data, nameof(data.mixture), mixture)
	rel_add(mixture, nameof(mixture.numeric_readers), data)
	gas_numeric_attach(data)

/datum/cap_data/gas_numeric_read
	var/datum/gas_mixture/mixture
	var/datum/gas_numeric_source/source

CAPABILITIES(/datum/cap_data/gas_numeric_read)
	ref_one(nameof(mixture), /datum/gas_mixture)
	ref_one(nameof(source), /datum/gas_numeric_source)

/datum/gas_mixture
	var/list/numeric_readers

CAPABILITIES(/datum/gas_mixture)
	ref_many(nameof(numeric_readers), /datum/cap_data/gas_numeric_read)

// Native identity writes are committed by the generated binding boundary, which captures the prior actual value.
SETTER(/datum/gas_mixture, _extools_pointer_gasmixture)

/datum/gas_mixture/proc/set__extools_pointer_gasmixture(value, previous = null, native_commit = FALSE)
	var/old = native_commit ? previous : _extools_pointer_gasmixture
	if(TRACKED_UNCHANGED(old, value))
		// A retired slot may be reused with the same number. Retirement delivery removed its old producer first.
		if(native_commit)
			for(var/datum/cap_data/gas_numeric_read/data as anything in numeric_readers?.Copy())
				if(!data.source || QDELETED(data.source))
					gas_numeric_attach(data)
		return FALSE
	// Opaque handle registration is common during map load; an identity with no reader has nothing to publish.
	if(!length(numeric_readers) && !READERS(src, nameof(_extools_pointer_gasmixture)))
		_extools_pointer_gasmixture = value
		return TRUE
	if(!GLOB.state_batch_depth)
		return state_batch(src, PROC_REF(set__extools_pointer_gasmixture), list(value, previous, native_commit))
	_extools_pointer_gasmixture = value
	tracked_changed(src, nameof(_extools_pointer_gasmixture))
	for(var/datum/cap_data/gas_numeric_read/data as anything in numeric_readers?.Copy())
		gas_numeric_detach_source(data)
		gas_numeric_attach(data)
	return TRUE

READS_AS(/datum/gas_mixture/proc/arena_id, "_extools_pointer_gasmixture")
READ_LOOKUP_ARGUMENT(/datum/gas_mixture/proc/arena_id, reads = list(nameof(_extools_pointer_gasmixture)))

/datum/gas_numeric_source
	var/id
	var/pressure_kpa = 0
	var/datum/native_watch/gas_numeric/watch
	var/list/consumers

TRACKED(/datum/gas_numeric_source, pressure_kpa)

CAPABILITIES(/datum/gas_numeric_source)
	owns_one(nameof(watch), /datum/native_watch/gas_numeric)
	ref_many(nameof(consumers), /datum/cap_data/gas_numeric_read)
	on_ending(PROC_REF(ending))

/datum/gas_numeric_source/proc/committed(datum/native_watch/gas_numeric/W, mixture_id, present, pressure)
	if(W != watch || id != mixture_id)
		return
	if(!present)
		set_pressure_kpa(0)
		gas_numeric_registry().drop(src)
		return
	set_pressure_kpa(pressure)

/datum/gas_numeric_source/proc/ending(cause, by)
	gas_numeric_registry()?.forget(src)

/datum/native_watch/gas_numeric
	var/mixture_id

/datum/native_watch/gas_numeric/register()
	return vg_gas_numeric_pressure_subscribe(mixture_id, handle)

/datum/native_watch/gas_numeric/unregister()
	vg_gas_numeric_pressure_unsubscribe(handle)

/datum/gas_numeric_registry
	var/alist/by_id
	var/list/sources

CAPABILITIES(/datum/gas_numeric_registry)
	owns_many(nameof(sources), /datum/gas_numeric_source)

/proc/gas_numeric_registry()
	RETURN_TYPE(/datum/gas_numeric_registry)
	return GLOB?.gas_numeric_registry

/proc/gas_numeric_identity_key(id)
	return "gas_numeric:[num2text(id, 20)]"

/proc/gas_numeric_lookup(id)
	RETURN_TYPE(/datum/gas_numeric_source)
	return isnull(id) ? null : gas_numeric_registry()?.by_id?[id]

/// Pure pressure accessor: all preparation was declared by gas_numeric_read() before evaluation.
/proc/gas_numeric_pressure(datum/gas_mixture/mixture)
	READS_FROM(mixture)
	if(!mixture)
		return 0
	var/datum/gas_numeric_source/source = gas_numeric_lookup(mixture.arena_id())
	return source?.pressure_kpa || 0

/proc/gas_numeric_attach(datum/cap_data/gas_numeric_read/data)
	var/datum/gas_mixture/mixture = data.mixture
	if(!mixture || QDELETED(mixture))
		return
	var/id = mixture.arena_id()
	if(isnull(id))
		return
	var/datum/gas_numeric_registry/registry = gas_numeric_registry()
	var/datum/gas_numeric_source/source = gas_numeric_lookup(id)
	if(!source)
		source = new
		source.id = id
		var/datum/native_watch/gas_numeric/W = new(source, TYPE_PROC_REF(/datum/gas_numeric_source, committed))
		W.mixture_id = id
		rel_set(source, nameof(source.watch), W)
		var/initial_pressure = W.register()
		if(isnull(initial_pressure))
			destroyed(source, registry, cause = "gas numeric identity unavailable")
			return
		source.set_pressure_kpa(initial_pressure)
		if(!registry.by_id)
			registry.by_id = alist()
		rel_add(registry, nameof(registry.sources), source)
		registry.by_id[id] = source
		tracked_changed(registry, gas_numeric_identity_key(id))
	rel_set(data, nameof(data.source), source)
	rel_add(source, nameof(source.consumers), data)

/proc/gas_numeric_detach_source(datum/cap_data/gas_numeric_read/data)
	var/datum/gas_numeric_source/source = data.source
	rel_clear(data, nameof(data.source))
	if(source && !QDELETED(source))
		rel_take(source, nameof(source.consumers), data)
		if(!length(source.consumers))
			gas_numeric_registry()?.drop(source)

/proc/gas_numeric_detach(datum/cap_data/gas_numeric_read/data)
	gas_numeric_detach_source(data)
	var/datum/gas_mixture/mixture = data.mixture
	if(mixture && !QDELETED(mixture))
		rel_take(mixture, nameof(mixture.numeric_readers), data)
	rel_clear(data, nameof(data.mixture))

/datum/gas_numeric_registry/proc/forget(datum/gas_numeric_source/source)
	if(by_id?[source.id] == source)
		by_id -= source.id
		tracked_changed(src, gas_numeric_identity_key(source.id))
	rel_take(src, nameof(sources), source)

/datum/gas_numeric_registry/proc/drop(datum/gas_numeric_source/source)
	forget(source)
	rel_take(src, nameof(sources), source)
	lifeform_end(source, END_SCOPE)

/// Generated mutation bindings enter one publication boundary before calling Rust.
/proc/gas_numeric_run_binding(writer, list/arguments)
	var/datum/gas_numeric_registry/registry = gas_numeric_registry()
	if(!registry || !length(registry.sources))
		return call(writer)(arglist(arguments))
	return state_batch(registry, TYPE_PROC_REF(/datum/gas_numeric_registry, run_binding), list(writer, arguments))

/// Before a binding's identity rearm, retire old actual subscriptions while the outer publication batch remains open.
/proc/gas_numeric_flush_binding_commits()
	gas_numeric_registry()?.flush_commits()

/datum/gas_numeric_registry/proc/run_binding(writer, list/arguments)
	try
		. = call(writer)(arglist(arguments))
	catch(var/exception/fault)
		try
			flush_commits()
		catch(var/exception/delivery_fault)
			dq_report_caught(delivery_fault, "Native pressure commit delivery failed while preserving its mutation fault")
		throw fault
	flush_commits()

/datum/gas_numeric_registry/proc/flush_commits()
	if(!length(sources))
		return
	var/list/commits = vg_take_gas_numeric_pressure_commits()
	for(var/index in 1 to length(commits) step 4)
		var/datum/native_watch/gas_numeric/W = kernel_native_native_watch_of(commits[index])
		if(istype(W) && W.mixture_id == commits[index + 1])
			W.fire(list(commits[index + 1], commits[index + 2], commits[index + 3]))
