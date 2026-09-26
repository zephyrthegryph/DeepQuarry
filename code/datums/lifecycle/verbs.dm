// L3: the verbs that replace direct qdel() call sites (roadmap L track,
// doc/rewrite/lifecycle.md §5). `qdel()` remains the engine underneath every
// one of these; what they add is the checked, declarative intent a hand
// `qdel(x)` site doesn't carry (was this removal allowed? does something get
// carried over? is this timed or death-driven?), so the destroy transaction
// (L1) and links framework (L2) have something to work from.

// ---- consume() ----

/// Removes `item` from wherever it is (checked and refusable, same as any
/// other player-facing take-out) and destroys it. Replaces the common
/// `drop_from_inventory(item); qdel(item)` pattern, and matches interaction
/// `item_use`/`CONSTRUCTION_ITEM_DELETE`. `qdel(item)` alone would delete it
/// regardless of whether taking it out is currently allowed (stuck,
/// handcuffed, ...); this checks first.
/proc/consume(atom/movable/item, mob/actor)
	if(!item || QDELETED(item))
		return FALSE
	if(dq_ledger_removal_refusal(item, actor))
		return FALSE
	qdel(item)
	return TRUE

// ---- replace_with() ----

/// Creates `path` at `original`'s loc (in its holder's slot, if it has one),
/// carries over its SLOT_DROP_KEEP_WITH contents (moved into the successor's
/// declared slots) and SLOT_DROP_TO_LATENT contents (folded into the
/// successor's latent entries), then destroys `original`. Replaces the
/// `new X(); qdel(src)` pattern (deconstruction debris, item transforms).
/// Returns the successor, or null if it couldn't be placed.
/proc/replace_with(atom/movable/original, path, ...)
	if(!original || QDELETED(original))
		return null
	var/atom/holder = original.loc
	var/list/entry
	var/datum/ledger/L = dq_ledger_peek(holder)
	if(L)
		entry = L.entries[original]
	// arglist() can't be combined with a positional arg in the same call, so
	// the turf goes into the same list as the rest of the constructor args.
	var/list/ctor_args = list(get_turf(original)) + args.Copy(3)
	var/atom/movable/successor = new path(arglist(ctor_args))
	if(QDELETED(successor))
		return null
	original.lifecycle_successor = successor
	if(entry && dq_slot_defs_for(holder))
		var/slot_id = entry[LEDGER_E_SLOT]
		// Best effort: the slot may refuse the successor (different accepts
		// predicate) -- it still exists on the turf either way.
		successor.move_into(holder, slot_id)
	qdel(original)
	return successor

// ---- lifetime / expire() ----

/// Deciseconds after Initialize() this atom self-destructs. 0: never (the
/// default). Set on the type or the instance; either way expire() arms the
/// timer once, from Initialize(). Named lifecycle_lifetime, not the shorter
/// `lifetime`, because a couple of existing effect types already declare
/// their own unrelated `lifetime` var and this must not collide with them.
/atom/movable/var/lifecycle_lifetime = 0
/// The armed self-destruct timer, or null. Cancelled if something else
/// qdels this first (the timer target is weak-refd and Destroy() cancels
/// timers already; this var exists so expire() itself can be called again
/// to re-arm with a new delay).
/atom/movable/var/tmp/lifecycle_lifetime_timer

/// Arms (or re-arms) this atom's self-destruct for `after` deciseconds from
/// now, cancelling any previous one. `expire(after)` with no
/// `lifecycle_lifetime` set is how a one-off timed delete (a thrown effect,
/// a spawner) declares it without a type-level lifetime var.
/atom/movable/proc/expire(after)
	if(lifecycle_lifetime_timer)
		deltimer(lifecycle_lifetime_timer)
	lifecycle_lifetime_timer = addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(qdel), src), after, TIMER_STOPPABLE)

/atom/movable/proc/lifecycle_arm_lifetime()
	if(lifecycle_lifetime > 0)
		expire(lifecycle_lifetime)

// ---- slot_clear() / ledger_empty() ----

/// Deletes everything currently in `slot_id` (null: every slot), right now.
/// Replaces a `for(var/x in slot_contents(id)) qdel(x)` loop. Returns how
/// many were deleted.
/atom/proc/slot_clear(slot_id)
	. = 0
	latent_materialize_all(slot_id)
	for(var/atom/movable/thing as anything in slot_contents(slot_id))
		if(QDELETED(thing))
			continue
		qdel(thing)
		.++

/// Applies drop `policy` (a SLOT_DROP_* id) to `slot_id`'s (null: every
/// slot's) current contents right now, regardless of what each slot's own
/// declared policy is. Gib is `ledger_empty(SLOT_DROP_SPILL)` on the part
/// slots, then `qdel(the body)` -- the disposition is a one-off choice made
/// at the point of gibbing, not a change to what the slot normally does.
/// Returns how many things were affected.
/atom/proc/ledger_empty(policy, slot_id)
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return 0
	var/atom/drop = drop_location()
	var/list/defs = isnull(slot_id) ? L.defs : list(L.def_by_id(slot_id))
	. = 0
	for(var/datum/om/relation/slot/def as anything in defs)
		if(!def)
			continue
		for(var/atom/movable/thing as anything in L.slots[def.id].Copy())
			if(QDELETED(thing))
				continue
			dq_lifecycle_apply_policy_now(src, def, thing, policy, drop)
			.++

/// Shared by ledger_empty(): applies `policy` (which may differ from `def`'s
/// own declared drop_policy) to one thing, through the same forced-move
/// machinery the destroy transaction's contents phase uses (L1,
/// code/datums/containment/lifecycle.dm).
/proc/dq_lifecycle_apply_policy_now(atom/movable/holder, datum/om/relation/slot/def, atom/movable/thing, policy, atom/drop)
	var/flags = LEDGER_MOVE_FORCED
	if(policy == SLOT_DROP_DELETE)
		qdel(thing)
		return
	if(policy == SLOT_DROP_TRANSFER)
		var/atom/target = def.drop_resolver(holder, thing, drop)
		if(target && !QDELETED(target) && dq_ledger_force_move(thing, target, flags))
			return
	if(drop && !QDELETED(drop))
		dq_ledger_force_move(thing, drop, flags)
	if(thing.loc == holder)
		qdel(thing)

// ---- delete_on_death ----

/// This mob deletes itself when it dies (spores, shades), subscribed to the
/// final hook of DQ Medical's ordered death pipeline (O5) -- never to a stat
/// change. The destroy transaction never calls death() itself; this is the
/// one place "dying" and "being destroyed" connect, and only for the types
/// that opt in.
/mob/living/var/delete_on_death = FALSE

/// DQ Medical's O5 death pipeline calls this as its final hook, for every
/// mob (doc/rewrite/lifecycle.md §5, §7). A no-op unless delete_on_death is set.
/mob/living/proc/lifecycle_on_death_finalized()
	if(delete_on_death)
		qdel(src)

// ---- destroy_effects (declared, phase 6) ----

/// Declared destruction effects (L3, doc/rewrite/lifecycle.md §2 phase 6,
/// §5): message, sound, debris and neighbour update, applied by
/// dq_lifecycle_effects() instead of a hand `visible_message()`/`playsound()`/
/// `new debris()` block in Destroy(). A type overrides destroy_effects()
/// (transaction.dm) to return one, built once as a proc-local static (same
/// pattern as slot_def singletons).
/datum/destroy_effects_data
	/// Shown with visible_message() at the destroyed atom's last turf, or null.
	var/message
	/// Played with playsound() at the same turf, or null.
	var/sound
	/// Debris type spawned at the same turf, or null.
	var/debris_type
	/// Whether neighbouring atoms get update_icon()/queue_smooth() afterwards.
	var/update_neighbors = FALSE

/datum/destroy_effects_data/proc/apply(datum/D)
	if(!isatom(D))
		return
	var/atom/A = D
	var/turf/T = get_turf(A)
	if(!T)
		return
	if(message)
		T.visible_message(message)
	if(sound)
		playsound(T, sound, 50, TRUE)
	if(debris_type)
		new debris_type(T)
	if(update_neighbors)
		for(var/atom/movable/AM in T)
			AM.update_icon()
