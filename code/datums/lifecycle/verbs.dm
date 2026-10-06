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
	var/atom/source = item.loc
	if(source?.release_refusal(item, actor))
		return FALSE
	// Held or worn: take it off the mob the way drop_from_inventory() did at
	// the call sites this replaces, so dropped() hooks, hand HUD and slowdown
	// update before the item goes (qdel alone gets there too, but later and
	// from inside the transaction).
	if(ismob(item.loc) && isitem(item))
		var/mob/holder = item.loc
		if(holder.inventory_slot_id(item))
			holder.drop_from_inventory(item)
			if(item.loc == holder)
				return FALSE
	ending_cause(item, END_CONSUMED, actor)
	qdel(item)
	return TRUE

// ---- replace_with() ----

/// Creates `path` at `original`'s loc (in its holder's slot, if it has one),
/// carries over its SLOT_DROP_KEEP_WITH contents (moved into the successor's
/// declared slots) and SLOT_DROP_TO_LATENT contents (folded into the
/// successor's latent entries), then destroys `original`. Replaces the
/// `new X(); qdel(src)` pattern (deconstruction debris, item transforms).
/// Returns the successor, or null if it couldn't be placed.
///
/// `path` may instead be a successor the caller already built (and set up
/// from the original's state: fingerprints, id tags, dir, pixel offsets):
/// it is then only placed and handed the original's slot and KEEP_WITH
/// contents, with no constructor args.
/proc/replace_with(atom/movable/original, path, ...)
	if(!original || QDELETED(original))
		return null
	var/atom/holder = original.loc
	var/slot_id
	var/datum/ledger/L = dq_ledger_peek(holder)
	if(L && dq_slot_defs_for(holder))
		var/list/entry = L.entries[original]
		if(entry)
			slot_id = entry[LEDGER_E_SLOT]
	// Built on the turf when the original sits in a slot (a mob's hand, a
	// bag): the constructor must not see a half-filled holder. Otherwise in
	// the original's own loc -- a turf, or a plain container without slots.
	var/atom/where = (slot_id || !holder || isturf(holder)) ? get_turf(original) : holder
	if(istype(path, /atom/movable))
		var/atom/movable/built = path
		if(QDELETED(built))
			return null
		original.lifecycle_successor = built
		om_handle_forward(original, built)
		ending_cause(original, END_REPLACED, built)
		qdel(original)
		if(slot_id && !QDELETED(holder) && !QDELETED(built))
			move_into(holder, slot_id, built)
		return built
	// arglist() can't be combined with a positional arg in the same call, so
	// the loc goes into the same list as the rest of the constructor args.
	var/list/ctor_args = list(where) + args.Copy(3)
	var/atom/movable/successor = new path(arglist(ctor_args))
	if(QDELETED(successor))
		return null
	original.lifecycle_successor = successor
	om_handle_forward(original, successor)
	ending_cause(original, END_REPLACED, successor)
	qdel(original)
	// Into the slot only once the original has left it: a one-item slot (a
	// hand) would refuse the successor while the original still filled it.
	// Best effort: the slot may refuse the successor (different accepts
	// predicate) -- it still exists on the turf either way.
	if(slot_id && !QDELETED(holder) && !QDELETED(successor))
		move_into(holder, slot_id, successor)
	return successor

// ---- lifetime / expire() ----

/// Deciseconds after Initialize() this atom self-destructs. 0: never (the
/// default). Set on the type or the instance; either way expire() arms the
/// timer once, from Initialize(). Named lifecycle_lifetime, not the shorter
/// `lifetime`, because a couple of existing effect types already declare
/// their own unrelated `lifetime` var and this must not collide with them.
/atom/movable/var/lifecycle_lifetime = 0
/// The armed self-destruct (an OM timer id on this atom), or null: kept so expire() can re-arm
/// with a new delay. The timer dies with the atom.
/atom/movable/var/tmp/lifecycle_lifetime_timer

/// Arms (or re-arms) this atom's self-destruct for `after` deciseconds from
/// now, cancelling any previous one. `expire(after)` with no
/// `lifecycle_lifetime` set is how a one-off timed delete (a thrown effect,
/// a spawner) declares it without a type-level lifetime var. The timer is
/// owned by this atom (an OM timer on src, not on the global qdel proc), so
/// deleting it first cancels the timer instead of leaving a queued strong
/// reference behind -- the hard-delete trap QDEL_IN() works around with a
/// handle. expire(null) only disarms (a ghost whose player came back).
/atom/movable/proc/expire(after)
	if(after_pending(src, "lifecycle_lifetime_timer"))
		cancel_after(src, "lifecycle_lifetime_timer")
	if(isnull(after) || QDELETED(src))
		return
	after(src, max(after, 0), PROC_REF(lifecycle_expire_now), key = "lifecycle_lifetime_timer")

/atom/movable/proc/lifecycle_expire_now()
	PRIVATE_PROC(TRUE)
	ending_cause(src, END_EXPIRED)
	qdel(src)

/atom/movable/proc/lifecycle_arm_lifetime()
	if(lifecycle_lifetime > 0)
		expire(lifecycle_lifetime)

// ---- slot_clear() / ledger_empty() ----

/// Deletes everything currently in `slot_id` (null: every slot), right now.
/// Replaces a `for(var/x in slot_contents(id)) qdel(x)` loop. Returns how
/// many were deleted.
/atom/proc/slot_clear(slot_id)
	. = 0
	// DELETE never materializes a latent entry (lifecycle.md §3): drop them
	// as data.
	if(has_latent())
		var/datum/ledger/L = dq_ledger(src)
		for(var/datum/latent_entry/entry as anything in L?.latent_list(slot_id))
			. += entry.count
			L.latent_set_count(entry, 0)
	// A holder without declared slots owns its plain contents: slot_clear()
	// with no slot named deletes those, the loop this verb replaces.
	var/list/things = (isnull(slot_id) && !dq_slot_defs_for(src)) ? contents.Copy() : slot_contents(slot_id)
	for(var/atom/movable/thing as anything in things)
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
		var/list/slot_things = L.slots[def.slot_id]
		for(var/atom/movable/thing as anything in slot_things.Copy())
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

/// The sealed death pipeline (/mob/proc/death(), code/modules/mob/death.dm)
/// calls this as its final hook, after on_death() and every listener, so all
/// subtype remains and messages are already out (doc/rewrite/lifecycle.md §5,
/// §7). A no-op unless delete_on_death is set; skipped if the mob was revived
/// or deleted (gibbed) along the way.
/mob/living/proc/lifecycle_on_death_finalized()
	if(delete_on_death && stat == DEAD && !QDELETED(src))
		qdel(src)

// ---- destroy_effects (declared, phase 6) ----

/// Declared destruction effects (L3, doc/rewrite/lifecycle.md §2 phase 6,
/// §5): message, sound, debris and neighbour update, applied by
/// phase 6 of destroy_transaction() (transaction.dm) instead of a hand `visible_message()`/`playsound()`/
/// `new debris()` block in Destroy(). A type overrides destroy_effects()
/// (transaction.dm) to return one, built once as a proc-local static (same
/// pattern as slot_def singletons).
/datum/destroy_effects_data
	/// Shown with visible_message() at the destroyed atom's last turf, or null.
	/// "%SRC%" becomes "\The [atom]".
	var/message
	/// The message's span class.
	var/message_class = "warning"
	/// Played with playsound() at the same turf, or null.
	var/sound
	var/sound_volume = 50
	/// Debris type spawned at the same turf, or null.
	var/debris_type
	/// Whether atoms on the same turf get update_icon() afterwards.
	var/update_neighbors = FALSE
	/// After the atom has left its turf (apply_after()): atoms of this type
	/// within neighbor_range re-smooth -- structures update_connections() --
	/// and update_icon(). Walls, grilles, railings, lattices.
	var/neighbor_type
	var/neighbor_range = 1
	/// Whether neighbour structures also re-run update_connections().
	var/neighbor_reconnect = TRUE
	/// Debris as list(type = count, ...), spawned with debris_type (declarative_lifecycle.md).
	var/list/debris
	/// Move whatever is still in the atom's contents to its drop location (was a hand
	/// `for(var/atom/movable/A in contents) A.forceMove(loc)` in on_destroy()). Runs for every
	/// atom, even when a batch merges the rest of the effects per turf. Slot policies (phase 3)
	/// have already resolved slotted contents; this catches the rest.
	var/drop_contents = FALSE

/datum/destroy_effects_data/New(message, message_class, sound, sound_volume, debris_type, neighbor_type, neighbor_range, neighbor_reconnect, list/debris, drop_contents)
	if(!isnull(message))
		src.message = message
	if(!isnull(message_class))
		src.message_class = message_class
	if(!isnull(sound))
		src.sound = sound
	if(!isnull(sound_volume))
		src.sound_volume = sound_volume
	if(!isnull(debris_type))
		src.debris_type = debris_type
	if(!isnull(neighbor_type))
		src.neighbor_type = neighbor_type
	if(!isnull(neighbor_range))
		src.neighbor_range = neighbor_range
	if(!isnull(neighbor_reconnect))
		src.neighbor_reconnect = neighbor_reconnect
	if(!isnull(debris))
		src.debris = debris
	if(!isnull(drop_contents))
		src.drop_contents = drop_contents

/// Phase 6, per atom (before apply() and any batch merge): drop_contents.
/datum/destroy_effects_data/proc/apply_per_atom(datum/D)
	if(!drop_contents || !ismovable(D))
		return
	var/atom/movable/holder = D
	var/atom/drop = holder.drop_location()
	if(!drop || QDELETED(drop))
		return
	for(var/atom/movable/thing as anything in contents_of(holder).Copy())
		if(!QDELETED(thing))
			thing.forceMove(drop)

/// Phase 6, while the atom is still on its turf. Returns the turf, which
/// apply_after() gets once Destroy() has taken the atom off it.
/datum/destroy_effects_data/proc/apply(datum/D)
	if(!isatom(D))
		return
	var/atom/A = D
	var/turf/T = get_turf(A)
	if(!T)
		return
	if(message)
		T.visible_message("<span class='[message_class]'>[replacetext(message, "%SRC%", "\The [A]")]</span>")
	if(sound)
		playsound(T, sound, sound_volume, TRUE)
	if(debris_type)
		new debris_type(T)
	for(var/path in debris)
		for(var/i in 1 to max(1, debris[path]))
			new path(T)
	if(update_neighbors)
		for(var/atom/movable/AM in contents_of(T))
			AM.update_icon()
	return T

/// After Destroy(): neighbours that smooth against the atom see it gone.
/datum/destroy_effects_data/proc/apply_after(datum/D, turf/T)
	if(!neighbor_type || !T)
		return
	for(var/atom/N in range(neighbor_range, T))
		if(N == D || !istype(N, neighbor_type) || QDELETED(N))
			continue
		if(neighbor_reconnect && isstructure(N))
			var/obj/structure/S = N
			S.update_connections()
		N.update_icon()
