// Content lifecycle adapters: the generic declaration table lives in engine/declare/lifecycle.dm.
/datum/lifecycle_decls/clear_presentation()
	drop_appearance()

/datum/lifecycle_decls/validate_presentation(datum/D)
	finish_appearance(D)

/datum/lifecycle_decls/has_presentation()
	return appearance_draws || appearance_mask

/datum/lifecycle_decls/validate_registries()
	for(var/id in registries?.Copy())
		var/datum/registry/registry = get_registry(id)
		if(!registry?.conditional)
			registries -= id // an ordinary registry is joined by join_registries() already
	if(!length(registries))
		registries = null

/mob/lifecycle_can_login()
	return TRUE

// ---- init ----

/// Runs the init declarations on A. Called at the end of /atom/Initialize() and from
/// table_initialize(); a non-atom datum with declarations calls it from its own New().
/proc/lifecycle_decls_init(datum/D, mapload = FALSE)
	// Starting occupants first (the old step 1, default children): gas, reagents and a subtype's
	// Initialize() after `. = ..()` may read them. Every atom passes here (~500k at boot): the table read is the
	// shared cache's fast path, inlined, and the proc runs only for a type that declares one.
	var/datum/own_table/start_table = _CACHED_KEY_FAST(own_table, D.type, D)
	if(start_table.engine_hooks & ENGINE_HOOK_PREINIT)
		engine_holder_preinit(D, mapload)
	if(start_table.start_vars)
		own_init_starts(D, start_table)
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(D)
	if(!decls || !(decls.work & DECL_WORK_INIT))
		return
	if(decls.gas)
		decls.create_gas(D)
	if(decls.work & DECL_WORK_APPEARANCE)
		decls.init_appearance(D)
	if(decls.verbs_always || decls.verbs_if || decls.verbs_hidden)
		verb_store_apply_declared(D, decls)

/datum/lifecycle_decls/proc/create_gas(datum/D)
	var/var_name = gas[1]
	if(isdatum(D.vars[var_name]))
		return
	var/volume = lifecycle_decl_value(D, gas[2])
	var/temperature = lifecycle_decl_value(D, gas[3]) || T20C
	var/datum/gas_mixture/mix = new /datum/gas_mixture(volume)
	heat_set(mix, temperature)
	var/list/gases = gas[4]
	for(var/gas_id in gases)
		mix.adjust_gas(gas_id, gases[gas_id] * volume / (R_IDEAL_GAS_EQUATION * temperature))
	rel_set(D, var_name, mix) // the holder owns its mixture (its arena slot goes with it)


// ---- appearance: code/datums/sys/appearance.dm ----

// ---- materialize / dematerialize ----

/// Runs the materialize declarations. /atom/on_materialize() calls it last, after the
/// core registries, rules and OM start.
/proc/lifecycle_decls_materialize(atom/A, datum/lifecycle_decls/decls)
	for(var/id in decls.registries)
		registry_join(id, A)
	for(var/list/service in decls.services)
		var/datum/target = GLOB.vars[service[1]]
		if(target && service[2])
			call(target, service[2])(A)
	if(decls.binders)
		lifecycle_decls_bind(A, decls)
	for(var/hook_var in decls.expiry_hooks)
		expiry_arm(A, hook_var, A.vars[hook_var], TRUE)

/// The inverse, from /atom/on_dematerialize(). Registries, behaviours and timers are left by
/// the core (leave_registries(), entity_teardown_rest()).
/proc/lifecycle_decls_dematerialize(atom/A, datum/lifecycle_decls/decls)
	for(var/list/service in decls.services)
		var/datum/target = GLOB.vars[service[1]]
		if(target && service[3])
			call(target, service[3])(A)
	// A destroy already released them in phase 1; this covers collapse into a latent entry.
	if(decls.binders && !QDELING(A))
		lifecycle_decls_unbind(A)

// ---- binds ----

/// A binding to something outside DM (a Rust entity, a power node, a heat body). One singleton
/// per type (decl_binder()). Batched: during an SSatoms batch every materializing atom is
/// queued and bind_list() gets the whole batch once it ends (doc/rewrite/init_and_turfs.md 3.3
/// step 4). Subtypes override bind_list() with a bulk FFI call where one exists.
/datum/decl_binder

/// Binds every atom in `atoms` (never empty; members may have been deleted since queuing).
/datum/decl_binder/proc/bind_list(list/atoms)
	for(var/atom/A as anything in atoms)
		if(!QDELETED(A))
			bind(A)

/// Binds one atom. Default: nothing.
/datum/decl_binder/proc/bind(atom/A)
	return

/// Releases one atom's binding (destroy phase 1, or dematerialize). Must be safe to call on
/// an atom that was never bound, or already released.
/datum/decl_binder/proc/unbind(atom/A)
	return

/// The singleton for binder type `path`.
/proc/decl_binder(path)
	RETURN_TYPE(/datum/decl_binder)
	return CACHED(decl_binders, path)

/proc/build_decl_binder(path)
	return new path

DECLARE_SHARED_CACHE(decl_binders, GLOBAL_PROC_REF(build_decl_binder), SC_NEVER)

/datum/system/atoms
	/// While a batch initializes: binder type -> atoms queued for it. Null outside a batch.
	var/list/deferred_decl_binds

/proc/lifecycle_decls_bind(atom/A, datum/lifecycle_decls/decls)
	var/list/deferred = SSatoms?.deferred_decl_binds
	for(var/path in decls.binders)
		if(deferred)
			var/list/queue = deferred[path]
			if(!queue)
				queue = deferred[path] = list()
			queue[A] = TRUE
		else
			decl_binder(path).bind_list(list(A))

/// Releases A's declared binds (and drops it from a pending batch).
/proc/lifecycle_decls_unbind(datum/D)
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(D)
	if(!decls?.binders)
		return
	var/list/deferred = SSatoms?.deferred_decl_binds
	for(var/path in decls.binders)
		if(deferred)
			var/list/queue = deferred[path]
			queue?.Remove(D)
		decl_binder(path).unbind(D)

/// Binds everything a batch queued, one bind_list() per binder.
/datum/system/atoms/proc/flush_decl_binds()
	var/list/queued = deferred_decl_binds
	deferred_decl_binds = null
	for(var/path in queued)
		var/list/atoms = queued[path]
		if(length(atoms))
			decl_binder(path).bind_list(atoms)
