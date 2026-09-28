// Declarative lifecycle: the per-type declaration table and the code that runs it
// (doc/rewrite/declarative_lifecycle.md, macros in code/__defines/lifecycle_decl.dm).
//
// A type's DECLARE_* lines each override declare_lifecycle() and add one entry on top of the
// parent's. lifecycle_decls_of() builds the table once per type (the first instance asks) and
// caches it; a type with no declarations caches FALSE, so every lookup after the first is one
// assoc read. Nothing here allocates per instance except what the declarations create.
//
// Order (also in the define file's header and the doc, keep all three in step):
//   init:          children, gas, reagents, appearance
//   materialize:   registries, service members, binds, behaviours, periodic, timers
//   dematerialize: periodic stop, service leave, bind release
//   destroy:       phase 1 bind release; phase 4 children (their DECLARE_REF kind);
//                  phase 6 destroy effects

/// DECLARE_* plumbing. Every override adds to `decls` after calling ..().
/datum/proc/declare_lifecycle(datum/lifecycle_decls/decls)
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// The declaration table for D's type, or null when the type declares nothing.
/proc/lifecycle_decls_of(datum/D)
	RETURN_TYPE(/datum/lifecycle_decls)
	var/static/list/cache = list()
	var/datum/lifecycle_decls/decls = cache[D.type]
	if(!isnull(decls))
		return decls || null
	decls = new /datum/lifecycle_decls(D.type)
	D.declare_lifecycle(decls)
	decls.finish(D)
	if(!decls.work)
		cache[D.type] = FALSE
		return null
	cache[D.type] = decls
	return decls

/// One type's declarations. Read-only after finish().
/datum/lifecycle_decls
	var/owner_type
	/// DECL_WORK_* bits: which lifecycle points have anything to do.
	var/work = 0

	/// var name -> default (type path, list of paths, list(path = count), or a var name).
	var/list/children
	/// list(var, volume, temperature, list(gas = kPa)), or null.
	var/list/gas
	/// A number or a var name; null: no declared reagents.
	var/reagent_volume
	/// list(id = amount), or null.
	var/list/reagent_contents
	var/reagent_holder_type
	/// Set color from the reagents after filling.
	var/reagent_tint = FALSE
	/// Appearance layers: state var name (APPEARANCE_ANY for a static layer) -> rows (key -> row).
	var/list/appearance_layers
	/// Combined key -> list(icon_state, color, list of overlay images, icon); built lazily.
	var/list/appearance_built
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
	/// list of list(delay, proc ref).
	var/list/timers

/datum/lifecycle_decls/New(owner_type)
	src.owner_type = owner_type

/datum/lifecycle_decls/proc/add_child(var_name, default)
	LAZYSET(children, var_name, default)

/datum/lifecycle_decls/proc/set_gas(var_name, volume, temperature, list/gases)
	gas = list(var_name, volume, temperature, gases)

/datum/lifecycle_decls/proc/set_reagents(volume, list/contents, holder_type, tint)
	if(!isnull(volume))
		reagent_volume = volume
	else if(isnull(reagent_volume))
		reagent_volume = 0 // contents with no holder declared anywhere up the chain
	if(length(contents))
		var/list/merged = reagent_contents ? reagent_contents.Copy() : list()
		for(var/id in contents)
			merged[id] += contents[id] || 1
		reagent_contents = merged
	if(holder_type)
		reagent_holder_type = holder_type
	if(tint)
		reagent_tint = TRUE

/datum/lifecycle_decls/proc/clear_reagents()
	reagent_volume = null
	reagent_contents = null
	reagent_holder_type = null
	reagent_tint = FALSE

/datum/lifecycle_decls/proc/set_appearance(state_var, list/rows)
	LAZYSET(appearance_layers, state_var || APPEARANCE_ANY, rows)
	appearance_built = null

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

/datum/lifecycle_decls/proc/add_timer(delay, proc_ref)
	LAZYADD(timers, list(list(delay, proc_ref)))

/// Validates the declarations against the first instance and works out the work bits.
/// A bad declaration is reported and dropped here, once per type, never mid-lifecycle.
/datum/lifecycle_decls/proc/finish(datum/D)
	if(length(children))
		var/list/link_table = dq_lifecycle_link_table(D)
		for(var/var_name in children.Copy())
			if(!(var_name in D.vars))
				stack_trace("DECLARE_DEFAULT_CHILD([owner_type], \"[var_name]\"): no such var; dropped")
				children -= var_name
				continue
			var/declared = FALSE
			for(var/kind in list(REFKIND_OWNED, REFKIND_OWNED_LIST, REFKIND_HELD, REFKIND_SPILL, REFKIND_SPILL_LIST))
				var/list/names = link_table[kind]
				if(names && (var_name in names))
					declared = TRUE
					break
			if(!declared)
				stack_trace("DECLARE_DEFAULT_CHILD([owner_type], \"[var_name]\"): the var needs a DECLARE_REF of kind OWNED, OWNED_LIST, HELD, SPILL or SPILL_LIST; dropped")
				children -= var_name
		if(!length(children))
			children = null
	if(gas && !(gas[1] in D.vars))
		stack_trace("DECLARE_GAS([owner_type], \"[gas[1]]\"): no such var; dropped")
		gas = null
	if(!isnull(reagent_volume) && !isatom(D))
		stack_trace("DECLARE_REAGENTS([owner_type]): only atoms have reagents; dropped")
		clear_reagents()
	for(var/layer_var in appearance_layers?.Copy())
		if(layer_var != APPEARANCE_ANY && !(layer_var in D.vars))
			stack_trace("DECLARE_APPEARANCE([owner_type], \"[layer_var]\"): no such var; dropped")
			appearance_layers -= layer_var
	if(!length(appearance_layers))
		appearance_layers = null
	for(var/id in registries?.Copy())
		var/datum/registry/registry = get_registry(id)
		if(!registry?.conditional)
			registries -= id // an ordinary registry is joined by join_registries() already
	if(!length(registries))
		registries = null
	if(children || gas || !isnull(reagent_volume) || appearance_layers)
		work |= DECL_WORK_INIT
	if(appearance_layers)
		work |= DECL_WORK_APPEARANCE
	if(registries || services || binders || behaviours || periodic || timers)
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
/proc/lifecycle_decls_init(datum/D)
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(D)
	if(!decls || !(decls.work & DECL_WORK_INIT))
		return
	if(decls.children)
		decls.create_children(D)
	if(decls.gas)
		decls.create_gas(D)
	if(!isnull(decls.reagent_volume))
		decls.create_reagents_on(D)
	if(decls.appearance_layers)
		decls.apply_appearance(D)

/datum/lifecycle_decls/proc/create_children(datum/D)
	for(var/var_name in children)
		var/current = D.vars[var_name]
		var/default = children[var_name]
		if(istext(default))
			default = D.vars[default]
		if(islist(current) || (isnull(current) && islist(default)))
			D.vars[var_name] = lifecycle_decl_child_list(D, islist(current) ? current : default) // ALLOW(api): declared-child plumbing writes the declared var
			continue
		if(isdatum(current))
			continue
		var/path = ispath(current) ? current : default
		if(ispath(path))
			D.vars[var_name] = new path(D) // ALLOW(api): declared-child plumbing writes the declared var

/// A list of children from `spec`: paths become new instances (a `path = count` entry makes
/// count of them), instances already in it are kept.
/proc/lifecycle_decl_child_list(datum/D, list/spec)
	var/list/made = list()
	for(var/entry in spec)
		if(ispath(entry))
			var/count = spec[entry]
			if(!isnum(count) || count < 1)
				count = 1
			for(var/i in 1 to count)
				made += new entry(D)
		else if(isdatum(entry))
			made += entry
	return made

/datum/lifecycle_decls/proc/create_gas(datum/D)
	var/var_name = gas[1]
	if(isdatum(D.vars[var_name]))
		return
	var/volume = lifecycle_decl_value(D, gas[2])
	var/temperature = lifecycle_decl_value(D, gas[3]) || T20C
	var/datum/gas_mixture/mix = new /datum/gas_mixture(volume)
	mix.set_temperature(temperature)
	var/list/gases = gas[4]
	for(var/gas_id in gases)
		mix.adjust_gas(gas_id, gases[gas_id] * volume / (R_IDEAL_GAS_EQUATION * temperature))
	D.vars[var_name] = mix // ALLOW(api): declared gas plumbing writes the declared var

/datum/lifecycle_decls/proc/create_reagents_on(atom/A)
	var/volume = lifecycle_decl_value(A, reagent_volume)
	if(!isnum(volume))
		volume = 0
	A.create_reagents(volume, reagent_holder_type || /datum/reagents)
	if(!length(reagent_contents))
		return
	var/total = 0
	for(var/id in reagent_contents)
		var/amount = reagent_contents[id] || 1
		total += amount
		A.reagents.add_reagent(id, amount)
	if(reagent_tint)
		A.color = A.reagents.get_color()
	if(total > volume)
		WARNING("[A]([A.type]) declares more reagents ([total]) than its volume ([volume])")

// ---- appearance ----

/atom
	/// The DECLARE_APPEARANCE row key applied last (its overlays are the ones to swap out).
	var/tmp/decl_appearance_key

/// A's combined appearance key: each layer's row key ("[value]", or the layer's "*" row, or
/// nothing when neither exists), joined. Layers are in declaration order.
/datum/lifecycle_decls/proc/appearance_key(atom/A)
	var/key = ""
	for(var/layer_var in appearance_layers)
		var/list/rows = appearance_layers[layer_var]
		var/row_key = APPEARANCE_ANY
		if(layer_var != APPEARANCE_ANY)
			row_key = "[A.vars[layer_var]]"
			if(!rows[row_key])
				row_key = APPEARANCE_ANY
		if(!rows[row_key])
			row_key = ""
		key += "[row_key]|"
	return key

/// The built appearance for a combined key, shared by every instance: list(icon_state, color,
/// overlay images, icon). Later layers win for icon_state, color and icon; overlays add up.
/datum/lifecycle_decls/proc/appearance_row(atom/A, key)
	var/list/built = appearance_built?[key]
	if(built)
		return built
	var/list/row_keys = splittext(key, "|")
	var/state
	var/tint
	var/row_icon
	var/list/images
	var/i = 0
	for(var/layer_var in appearance_layers)
		i++
		var/row_key = row_keys[i]
		if(!row_key)
			continue
		var/list/row = appearance_layers[layer_var][row_key]
		if(row[APPEARANCE_ICON])
			row_icon = row[APPEARANCE_ICON]
		if(!isnull(row[APPEARANCE_ICON_STATE]))
			state = row[APPEARANCE_ICON_STATE]
		if(!isnull(row[APPEARANCE_COLOR]))
			tint = row[APPEARANCE_COLOR]
		for(var/overlay in row[APPEARANCE_OVERLAYS])
			if(istext(overlay))
				LAZYADD(images, image(row[APPEARANCE_ICON] || initial(A.icon), overlay))
			else
				LAZYADD(images, overlay)
	built = list(state, tint, images, row_icon)
	LAZYSET(appearance_built, key, built)
	return built

/// Applies the appearance for A's current state; swaps out the overlays the previous one added.
/datum/lifecycle_decls/proc/apply_appearance(atom/A)
	var/key = appearance_key(A)
	if(key == A.decl_appearance_key)
		return
	var/list/row = appearance_row(A, key)
	if(A.decl_appearance_key)
		var/list/old = appearance_row(A, A.decl_appearance_key)
		if(old[3])
			A.cut_overlay(old[3])
	A.decl_appearance_key = key
	if(row[4])
		A.icon = row[4]
	if(!isnull(row[1]))
		A.icon_state = row[1]
	if(!isnull(row[2]))
		A.color = row[2]
	if(row[3])
		A.add_overlay(row[3])

/// Re-applies A's declared appearance after a state var changed. The base /atom/update_icon()
/// calls it, so a declared type only needs update_icon() (or ..() from its own override).
/atom/proc/decl_appearance_apply()
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(src)
	if(decls?.appearance_layers)
		decls.apply_appearance(src)

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
	for(var/list/timer in decls.timers)
		om_after(A, lifecycle_decl_value(A, timer[1]), timer[2])

/// The inverse, from /atom/on_dematerialize(). Registries, behaviours and timers are left by
/// the core (leave_registries(), om_teardown_rest()).
/proc/lifecycle_decls_dematerialize(atom/A, datum/lifecycle_decls/decls)
	if(decls.periodic)
		om_task_periodic_stop(A)
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
	var/static/list/singletons = list()
	var/datum/decl_binder/binder = singletons[path]
	if(!binder)
		binder = new path
		singletons[path] = binder
	return binder

/datum/controller/subsystem/atoms
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
/datum/controller/subsystem/atoms/proc/flush_decl_binds()
	var/list/queued = deferred_decl_binds
	deferred_decl_binds = null
	for(var/path in queued)
		var/list/atoms = queued[path]
		if(length(atoms))
			decl_binder(path).bind_list(atoms)
