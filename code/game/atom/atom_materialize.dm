// Lifecycle split (state.md section 6, roadmap L2).
//
// Initialize() sets up the object's own state and declares its slots and
// generators. It must not register with the world.
//
// on_materialize() registers with the world when the object becomes a real,
// live atom: global lists, radio and network joins, processing and reactor
// subscriptions, global signal registrations, lighting and radiation updates.
// SSatoms.InitAtom() runs it right after Initialize() (and after an immediate
// LateInitialize()), so creation in the world, map load and a latent entry
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
/datum/controller/subsystem/atoms
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
	return TRUE

/// World registration. See the top of this file.
/atom/proc/on_materialize()
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	// Rules (code/datums/rules/): subscribe the type's rules, if it has any.
	if(dq_rules_for_type(type))
		dq_rules_on_materialize(src)

/// The exact inverse of on_materialize(). See the top of this file.
/atom/proc/on_dematerialize()
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	dq_rules_on_dematerialize(src)

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
