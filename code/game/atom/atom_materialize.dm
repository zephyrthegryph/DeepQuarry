// Lifecycle split (state.md section 6, roadmap L2).
//
// Initialize() sets up the object's own state and declares its slots and
// generators. It must not register with the world.
//
// on_materialize() registers with the world when the object becomes a real,
// live atom: global lists, radio and network joins, processing and reactor
// subscriptions, global signal registrations, lighting and radiation updates.
// SSatoms.InitAtom() runs it right after Initialize() (and after an immediate
// after_init()), so creation in the world, map load and a latent entry
// becoming real all go through it.
//
// on_dematerialize() is its exact inverse. /atom/Destroy() runs it, and a
// collapse into a latent entry runs it before the object is deleted.
//
// Both must be safe to call on any initialized atom, and the pair must leave
// the world exactly as it found it (dq_lifecycle_sandbox checks this for every
// latent-safe type). Call materialize()/dematerialize(), never the hooks
// directly: the wrappers keep ATOM_MATERIALIZED honest.

/// While positive, SSatoms.InitAtom() initializes atoms without materializing
/// them. Only the sandbox helpers below change it.
/datum/system/atoms
	var/materialize_suppressed = 0

/// Enter the live world. Does nothing if already materialized.
/// A movable brings along initialized contents that are not yet live (parts a
/// sandboxed Initialize() created, like a casing's bullet). Turfs don't: map
/// load materializes their contents one by one as each finishes Initialize().
/atom/proc/materialize()
	SHOULD_NOT_OVERRIDE(TRUE)
	if(flags & ATOM_MATERIALIZED)
		return FALSE
	flags |= ATOM_MATERIALIZED
	on_materialize()
	// A refresh raised while it was latent (appearance_queue()) runs now that it is live.
	if(appearance_queued == APPEARANCE_PENDING_LATENT)
		appearance_queued = FALSE
		appearance_queue(src)
	// A ledger built while sandboxed skipped the latency sweep; join it now.
	if(containment_ledger() && latent_contents_enabled())
		dq_latency_sweep_register(src)
	if(ismovable(src))
		for(var/atom/movable/content as anything in contents)
			if((content.flags & (ATOM_INITIALIZED|ATOM_MATERIALIZED)) == ATOM_INITIALIZED && !QDELING(content))
				content.materialize()
	return TRUE

/// Leave the live world. Does nothing if not materialized. A movable takes
/// its live contents with it, children first.
/atom/proc/dematerialize()
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!(flags & ATOM_MATERIALIZED))
		return FALSE
	if(ismovable(src))
		for(var/atom/movable/content as anything in contents)
			if(content.flags & ATOM_MATERIALIZED)
				content.dematerialize()
	flags &= ~ATOM_MATERIALIZED
	on_dematerialize()
	// The inverse of materialize(): a refresh it had queued waits again until it is live.
	if(appearance_queued == TRUE && ismovable(src))
		GLOB.appearance_queue -= src
		appearance_queued = APPEARANCE_PENDING_LATENT
	dq_latency_sweep_unregister(src) // left the live world: no longer a sweep candidate
	return TRUE

/// World registration. See the top of this file.
/atom/proc/on_materialize()
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	// One type-table lookup (atom_type_table.dm) says which of the three this type needs.
	var/table = atom_type_table(src)
	if(table & TYPE_TABLE_JOINS_REGISTRIES)
		join_registries() // L3: code/__defines/registries.dm
	// Rules (code/datums/rules/): subscribe the type's rules, if it has any.
	if(table & TYPE_TABLE_HAS_RULES)
		dq_rules_on_materialize(src)
	// Object model: attach the type's declared behaviours (code/datums/om/entity.dm).
	if(table & TYPE_TABLE_HAS_OM)
		om_start(src)
	// Declared registries, service members, binds, behaviours, periodic work, timers
	// (code/datums/lifecycle/declarations.dm), after the core joins above.
	if(table & TYPE_TABLE_HAS_DECLS)
		lifecycle_decls_materialize(src, lifecycle_decls_of(src))
	// Keyed relation views (REL_KEYED / KEYED_TARGET, doc/rewrite/ownership.md §4.1).
	if(own_table_of(src).materialize_work)
		rel_keyed_materialize(src)

/// The exact inverse of on_materialize(). See the top of this file.
/atom/proc/on_dematerialize()
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	var/table = atom_type_table(src)
	if(own_table_of(src).materialize_work)
		rel_keyed_dematerialize(src)
	if(table & TYPE_TABLE_HAS_DECLS)
		lifecycle_decls_dematerialize(src, lifecycle_decls_of(src))
	if(table & TYPE_TABLE_HAS_REGISTRIES)
		leave_registries() // L3: code/__defines/registries.dm
	if(rule_binding)
		dq_rules_on_dematerialize(src)
	if(om_rec)
		om_teardown_rest(src)

/// Creates `path` at `loc` and runs its Initialize() without materializing it.
/// Extra arguments go to Initialize(). The result is a sandboxed object: it has
/// its own state but no world registrations. Call materialize() to make it live.
/proc/new_unmaterialized(path, loc, ...)
	SSatoms.materialize_suppressed++
	var/list/arguments = args.Copy(2)
	try
		. = new path(arglist(arguments))
	catch(var/exception/error)
		SSatoms.materialize_suppressed--
		throw error
	SSatoms.materialize_suppressed--
