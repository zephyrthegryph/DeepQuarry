// Declarative lifecycle: the per-type declaration table and the code that runs it
// (doc/rewrite/declarative_lifecycle.md, macros in code/__defines/lifecycle_decl.dm).
//
// A type's DECLARE_* lines each override declare_lifecycle() and add one entry on top of the
// parent's. lifecycle_decls_of() builds the table once per type (the first instance asks) in the
// `lifecycle_decls` shared cache (doc/rewrite/caching.md), so every lookup after the first is one
// list read. Built appearances live in the `decl_appearance` shared cache and binder singletons in
// `decl_binders`: the declaration runtime keeps no private cache. Nothing here allocates per
// instance except what the declarations create.
//
// Order (also in the define file's header and the doc, keep all three in step):
//   init:          starting occupants (owns_one / owns_many with starts =),
//                  gas, appearance
//   materialize:   registries, service members, binds, behaviours, periodic, declared periodic work (sys_periodic)
//   dematerialize: periodic stop, declared periodic stop, service leave, bind release
//   destroy:       phase 1 bind release; phase 4 children (their DECLARE_REF kind);
//                  phase 6 destroy effects

/// DECLARE_* plumbing. Every override adds to `decls` after calling ..().
/datum/proc/declare_lifecycle(datum/lifecycle_decls/decls)
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// The declaration table for D's type, or null when the type declares nothing.
/// Hot (every update_icon() asks), so a type with no declarations caches its table too (with
/// work = 0) rather than FALSE: a falsy entry would miss the cache's fast path.
/proc/lifecycle_decls_of(datum/D)
	RETURN_TYPE(/datum/lifecycle_decls)
	var/datum/lifecycle_decls/decls = CACHED_KEY(lifecycle_decls, D.type, D)
	return decls.work ? decls : null

/// Builder for lifecycle_decls: D is the first instance of its type to ask (finish() validates
/// the declarations against it). Keyed by type; a per-type table never goes stale.
/proc/build_lifecycle_decls(datum/D)
	var/datum/lifecycle_decls/decls = new /datum/lifecycle_decls(D.type)
	D.declare_lifecycle(decls)
	decls.finish(D)
	if(!decls.work)
		// Only the flag is read for a type with nothing to do: drop what it declared.
		return decls.emptied()
	return decls

DECLARE_SHARED_CACHE(lifecycle_decls, GLOBAL_PROC_REF(build_lifecycle_decls), SC_NEVER)

/// One type's declarations. Read-only after finish().
/datum/lifecycle_decls
	var/owner_type
	/// DECL_WORK_* bits: which lifecycle points have anything to do.
	var/work = 0

	/// list(var, volume, temperature, list(gas = kPa)), or null.
	var/list/gas
	// Appearance declarations: code/datums/sys/appearance.dm.
	/// Registry ids declared with DECLARE_REGISTRY that are conditional (joined at materialize).
	var/list/registries
	/// list of list(service GLOB name, join proc, leave proc).
	var/list/services
	/// /datum/decl_binder types.
	var/list/binders
	/// OM behaviour types.
	var/list/behaviours
	/// A periodic pipeline type, or null.
	var/periodic
	/// EXPIRY_ON_LAPSE: var name -> list(clock, proc_ref) (code/datums/sys/expiry.dm).
	var/list/expiry_hooks
	/// DECLARE_VERB: verb paths every instance has from init.
	var/list/verbs_always
	/// DECLARE_LOGIN_VERB: verb paths a mob has once a player had it.
	var/list/verbs_login
	/// DECLARE_VERB_IF: verb path -> the instance var that must be true.
	var/list/verbs_if
	/// DECLARE_VERB_HIDE: verb paths no instance has.
	var/list/verbs_hidden
	/// DECLARE_PERIODIC_WHILE / DECLARE_REPEAT: TRUE while declaring, then finish() resolves the
	/// type's /datum/sys_periodic_table (code/datums/sys/periodic.dm), or null.
	var/sys_periodic

/datum/lifecycle_decls/New(owner_type)
	src.owner_type = owner_type

/// A table with no work: every declaration list dropped (finish() found nothing to run).
/datum/lifecycle_decls/proc/emptied()
	gas = null
	drop_appearance()
	registries = null
	services = null
	binders = null
	behaviours = null
	periodic = null
	verbs_always = null
	verbs_login = null
	verbs_if = null
	verbs_hidden = null
	sys_periodic = null
	return src

/datum/lifecycle_decls/proc/set_gas(var_name, volume, temperature, list/gases)
	gas = list(var_name, volume, temperature, gases)


/datum/lifecycle_decls/proc/add_registry(id)
	LAZYOR(registries, id)

/datum/lifecycle_decls/proc/add_service(service, join, leave)
	LAZYADD(services, list(list(service, join, leave)))

/datum/lifecycle_decls/proc/add_binder(binder)
	LAZYOR(binders, binder)

/datum/lifecycle_decls/proc/add_behaviour(behaviour)
	LAZYOR(behaviours, behaviour)

/datum/lifecycle_decls/proc/set_periodic(pipeline)
	periodic = pipeline

/// DECLARE_VERB family: `how` is VERB_DECL_ALWAYS/LOGIN/HIDE or a var name (DECLARE_VERB_IF).
/// A later declaration of the same verb replaces the parent's.
/datum/lifecycle_decls/proc/add_verb_decl(verb_path, how)
	LAZYREMOVE(verbs_always, verb_path)
	LAZYREMOVE(verbs_login, verb_path)
	LAZYREMOVE(verbs_if, verb_path)
	LAZYREMOVE(verbs_hidden, verb_path)
	if(istext(how))
		LAZYSET(verbs_if, verb_path, how)
		return
	switch(how)
		if(VERB_DECL_ALWAYS)
			LAZYADD(verbs_always, verb_path)
		if(VERB_DECL_LOGIN)
			LAZYADD(verbs_login, verb_path)
		if(VERB_DECL_HIDE)
			LAZYADD(verbs_hidden, verb_path)

/datum/lifecycle_decls/proc/add_sys_periodic()
	sys_periodic = TRUE

/// `skip_unset`: an unset (0) value is not armed at materialize (nothing to lapse; EMP_DISABLE).
/datum/lifecycle_decls/proc/add_expiry_hook(var_name, clock, proc_ref, skip_unset = FALSE)
	LAZYSET(expiry_hooks, var_name, list(clock, proc_ref, skip_unset))

/// Validates the declarations against the first instance and works out the work bits.
/// A bad declaration is reported and dropped here, once per type, never mid-lifecycle.
/datum/lifecycle_decls/proc/finish(datum/D)
	if(gas && !(gas[1] in D.vars))
		stack_trace("DECLARE_GAS([owner_type], \"[gas[1]]\"): no such var; dropped")
		gas = null
	finish_appearance(D)
	for(var/id in registries?.Copy())
		var/datum/registry/registry = get_registry(id)
		if(!registry?.conditional)
			registries -= id // an ordinary registry is joined by join_registries() already
	if(!length(registries))
		registries = null
	var/list/declared_verbs = list()
	for(var/verb_path in verbs_always)
		declared_verbs |= verb_path
	for(var/verb_path in verbs_login)
		declared_verbs |= verb_path
	for(var/verb_path in verbs_hidden)
		declared_verbs |= verb_path
	for(var/verb_path in verbs_if)
		declared_verbs |= verb_path
	for(var/verb_path in declared_verbs)
		if(istext(verb_path) || !(findtext("[verb_path]", "/proc/") || findtext("[verb_path]", "/verb/")))
			stack_trace("DECLARE_VERB([owner_type], [verb_path]): not a verb path; dropped")
			LAZYREMOVE(verbs_always, verb_path)
			LAZYREMOVE(verbs_login, verb_path)
			LAZYREMOVE(verbs_if, verb_path)
			LAZYREMOVE(verbs_hidden, verb_path)
	for(var/verb_path in verbs_if?.Copy())
		if(!(verbs_if[verb_path] in D.vars))
			stack_trace("DECLARE_VERB_IF([owner_type], [verb_path], \"[verbs_if[verb_path]]\"): no such var; dropped")
			LAZYREMOVE(verbs_if, verb_path)
	if(verbs_login && !ismob(D))
		stack_trace("DECLARE_LOGIN_VERB([owner_type]): only mobs log in; dropped")
		verbs_login = null
	if(verbs_always || verbs_login || verbs_if || verbs_hidden)
		work |= DECL_WORK_VERBS
	if(appearance_draws || appearance_mask)
		work |= DECL_WORK_INIT | DECL_WORK_APPEARANCE
	if(gas || verbs_always || verbs_if || verbs_hidden)
		work |= DECL_WORK_INIT
	for(var/hook_var in expiry_hooks?.Copy())
		if(!(hook_var in D.vars))
			stack_trace("EXPIRY_ON_LAPSE([owner_type], \"[hook_var]\"): no such var; dropped")
			expiry_hooks -= hook_var
	if(!length(expiry_hooks))
		expiry_hooks = null
	if(sys_periodic)
		sys_periodic = sys_periodic_validated(D, sys_periodic_table_for(owner_type))
		var/datum/sys_periodic_table/table = sys_periodic
		if(table?.while_def && periodic)
			stack_trace("DECLARE_PERIODIC([owner_type]) and DECLARE_PERIODIC_WHILE on one type: the while-declaration wins; DECLARE_PERIODIC dropped")
			periodic = null
		if(sys_periodic && !isatom(D))
			work |= DECL_WORK_INIT // a non-atom starts it from New() (lifecycle_decls_init())
	if(registries || services || binders || behaviours || periodic || expiry_hooks || (sys_periodic && isatom(D)))
		work |= DECL_WORK_MATERIALIZE
	if(binders)
		work |= DECL_WORK_UNBIND

/// A declared value that may be a var name: the instance's value for a string.
/proc/lifecycle_decl_value(datum/D, value)
	if(istext(value))
		return D.vars[value]
	return value

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
	if(decls.sys_periodic && !isatom(D))
		sys_periodic_start(D, decls.sys_periodic)
	if(decls.gas)
		decls.create_gas(D)
	if(decls.work & DECL_WORK_APPEARANCE)
		decls.init_appearance(D)
	if(decls.verbs_always || decls.verbs_if || decls.verbs_hidden)
		verb_store_apply_declared(D, decls)

/**
 * Makes D's starting occupants (owns_one() / owns_many() with `starts =`): for each declared var, the var itself wins (a path in it, a map edit, is made; an
 * instance in it makes nothing), else the declared spec is made (a var name reads the instance's var, so
 * `starts = nameof(cell_type)` follows a map or subtype override). A list var takes a list of paths or
 * list(path = count). Children are created with `new type(D)` and adopted through rel_set() / rel_add().
 */
/proc/own_init_starts(datum/D, datum/own_table/T)
	if(!T)
		T = own_table_of(D)
	var/list/starts = T.start_vars
	if(!starts)
		return
	for(var/var_name in starts)
		var/current = D.vars[var_name]
		var/default = starts[var_name]
		var/list/start_args = null
		if(istype(default, /datum/entry)) // pick_one(), when(), a proc, or starts_args = (code/engine/declare/relations.dm)
			var/list/resolved = starts_resolve(D, default)
			default = resolved[1]
			start_args = starts_args_resolve(D, resolved[2]) // OWNER is the holder (code/engine/lifeforms/contents.dm)
		else if(istext(default))
			if(default in D.vars)
				default = D.vars[default] // a var holding the type
			else
				// A PROC_REF decides everything: it is called with the var's current value and returns what the var starts with (a type, a
				// list of types, instances it made, or key = instance for an associative owns_many), which replaces that value.
				own_start_from_proc(D, var_name, call(D, default)(current))
				continue
		if(islist(current) || (isnull(current) && islist(default)))
			var/list/spec = islist(current) ? current : default
			D.vars[var_name] = null // ALLOW(api): starting-occupant plumbing replaces the spec with owned children
			for(var/datum/child as anything in lifecycle_decl_child_list(D, spec, start_args))
				lifecycle_decl_adopt_child(D, var_name, child, TRUE)
			continue
		if(isdatum(current))
			continue
		var/path = ispath(current) ? current : default
		if(ispath(path))
			D.vars[var_name] = null // ALLOW(api): the type path placeholder is replaced by the owned child
			lifecycle_decl_adopt_child(D, var_name, start_args ? new path(arglist(list(D) + start_args)) : new path(D), FALSE)

/// Adopts what a starts = PROC_REF returned: one value (a type or an instance) for a one var; for a many var a list of types and instances,
/// or an associative list of key = instance, adopted under the keys.
/proc/own_start_from_proc(datum/D, var_name, result)
	D.vars[var_name] = null // ALLOW(api): starting-occupant plumbing replaces the spec with owned children
	if(isnull(result))
		return
	if(!islist(result))
		var/datum/child = ispath(result) ? new result(D) : result
		if(isdatum(child))
			lifecycle_decl_adopt_child(D, var_name, child, FALSE)
		return
	for(var/entry in result)
		var/value = result[entry]
		if(isdatum(value)) // key = instance
			lifecycle_decl_adopt_child(D, var_name, value, TRUE, entry)
			continue
		var/list/one = list()
		one[entry] = value
		for(var/datum/child as anything in lifecycle_decl_child_list(D, one))
			lifecycle_decl_adopt_child(D, var_name, child, TRUE)

/// A list of children from `spec`: paths become new instances (a `path = count` entry makes
/// count of them), instances already in it are kept.
/proc/lifecycle_decl_child_list(datum/D, list/spec, list/start_args = null)
	var/list/made = list()
	for(var/entry in spec)
		if(ispath(entry))
			var/count = spec[entry]
			if(!isnum(count) || count < 1)
				count = 1
			for(var/i in 1 to count)
				made += start_args ? new entry(arglist(list(D) + start_args)) : new entry(D)
		else if(isdatum(entry))
			made += entry
	return made

/// Adopts a starting occupant through the declared write verbs (the var is declared owns_one / owns_many; a movable child in contents
/// may be CONTAINED), then wires the child's back relation when its type names one (default_child_backref()). `key` adopts it under
/// that key in an associative owns_many.
/proc/lifecycle_decl_adopt_child(datum/D, var_name, datum/child, as_list, key = null)
	if(as_list)
		rel_add(D, var_name, child, key)
	else
		rel_set(D, var_name, child)
	var/back = child.default_child_backref()
	if(back)
		rel_set(child, back, D)

/// The var (a REF) on a default child that names the holder that made it, or null.
/datum/proc/default_child_backref()
	return null

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
	for(var/behaviour in decls.behaviours)
		om_attach(A, behaviour)
	if(decls.periodic)
		om_task_periodic(A, decls.periodic)
	for(var/hook_var in decls.expiry_hooks)
		expiry_arm(A, hook_var, A.vars[hook_var], TRUE)
	if(decls.sys_periodic)
		sys_periodic_start(A, decls.sys_periodic)

/// The inverse, from /atom/on_dematerialize(). Registries, behaviours and timers are left by
/// the core (leave_registries(), om_teardown_rest()).
/proc/lifecycle_decls_dematerialize(atom/A, datum/lifecycle_decls/decls)
	if(decls.periodic)
		om_task_periodic_stop(A)
	if(decls.sys_periodic)
		sys_periodic_stop(A, decls.sys_periodic)
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
