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
//   materialize:   registries, service members, binds, periodic, declared periodic work (sys_periodic)
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
	clear_presentation()
	registries = null
	services = null
	binders = null
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
	validate_presentation(D)
	validate_registries()
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
	if(verbs_login && !D.lifecycle_can_login())
		stack_trace("DECLARE_LOGIN_VERB([owner_type]): only mobs log in; dropped")
		verbs_login = null
	if(verbs_always || verbs_login || verbs_if || verbs_hidden)
		work |= DECL_WORK_VERBS
	if(has_presentation())
		work |= DECL_WORK_INIT | DECL_WORK_APPEARANCE
	if(gas || verbs_always || verbs_if || verbs_hidden)
		work |= DECL_WORK_INIT
	for(var/hook_var in expiry_hooks?.Copy())
		if(!(hook_var in D.vars))
			stack_trace("EXPIRY_ON_LAPSE([owner_type], \"[hook_var]\"): no such var; dropped")
			expiry_hooks -= hook_var
	if(!length(expiry_hooks))
		expiry_hooks = null
	validate_periodic(D)
	if(registries || services || binders || periodic || expiry_hooks || (sys_periodic && isatom(D)))
		work |= DECL_WORK_MATERIALIZE
	if(binders)
		work |= DECL_WORK_UNBIND

/// A declared value that may be a var name: the instance's value for a string.
/proc/lifecycle_decl_value(datum/D, value)
	if(istext(value))
		return D.vars[value]
	return value


/// Downstream presentation declarations validate and discard their own metadata.
/datum/lifecycle_decls/proc/clear_presentation()
	return

/datum/lifecycle_decls/proc/validate_presentation(datum/D)
	return

/datum/lifecycle_decls/proc/has_presentation()
	return FALSE

/datum/lifecycle_decls/proc/validate_registries()
	return

/datum/lifecycle_decls/proc/validate_periodic(datum/D)
	return

/datum/proc/lifecycle_can_login()
	return FALSE

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
