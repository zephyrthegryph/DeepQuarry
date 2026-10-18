// The transaction API (doc/rewrite/containment.md Â§2, invariant 2).
//
//   move_into(holder, slot_id, thing, actor)          insert (slot_id null: the default slot)
//   holder.slot_remove(thing, destination, actor, flags)     take out, to a place that has no slots
//   holder.slot_transfer(thing, new_holder, slot_id, actor)   from one slot to another
//   holder.slot_empty(slot_id, destination, actor)    remove everything in a slot
//   holder.slot_item(slot_id)                         the one thing in a single-item slot, or null
//   holder.slot_lookup(slot_id, key)                  the thing keyed `key` in a keyed slot, or null
//   dq_ledger_refusal(thing, holder, slot_id, actor)  why a move would fail, or null
//
// The stated order of reasons (admission.md D2h): sanity (gone, inside itself, no such holder or slot, already there), release (the source's
// removal rules and /datum/act/remove needs), the slot's accepts (type list, then requirements), fits, a keyed duplicate, capacity (a replace policy
// may displace an occupant), then the insert action's needs(). The first refusal is the one a player sees.
//
// Each move checks both sides first: the thing can leave its current slot
// (the slot's removal_refusal() and /datum/act/check_remove), and it can enter
// the new one (the slot's acceptance predicate, capacity, a keyed slot's
// duplicate-key check, and /datum/act/check_insert). Nothing that can sleep
// runs in between: the check procs and the check hooks' handlers are
// synchronous typed action handlers. Then the move commits with one forceMove, whose
// bookkeeping (ledger.dm) fires /datum/notice/slot_removed and /datum/notice/slot_inserted and
// the thing's on_unslotted()/on_slotted() hooks. A refused move changes
// nothing.
//
// slot_remove() takes a LEDGER_MOVE_FORCED flag that skips both refusals and
// both pre signals but still runs the same commit bookkeeping (J2): used to
// spill or transfer a holder's contents while it is being destroyed, where
// the move must not be refusable.
//
// Drop policies: the destroy transaction (L1, doc/rewrite/lifecycle.md Â§2)
// resolves every slot's declared policy in its contents phase, before any
// leftover Destroy() runs, so no holder type decides what happens to its
// contents by hand (code/datums/containment/lifecycle.dm).

/// Why `thing` can't go into `slot_id` (null: the default slot) on `holder`,
/// or null if it can. Checks both sides; changes nothing. `check_removal = FALSE`
/// skips the source side, for a caller that asked the thing's current place
/// itself (the one-call transfer's release_refusal(), ownership/transfer.dm).
/// `units` (a quantity slot only): ask about that many units of `thing`, not everything it carries (a partial insert).
/proc/dq_ledger_refusal(atom/movable/thing, atom/holder, slot_id, mob/actor, check_removal = TRUE, units = null)
	if(!istype(thing) || QDELETED(thing))
		return "it is gone"
	if(!holder || QDELETED(holder))
		return "there is nowhere to put it"
	for(var/atom/A = holder; A; A = A.loc)
		if(A == thing)
			return "it can't go inside itself"
	var/datum/ledger/dest = dq_ledger(holder)
	if(!dest)
		return "[holder] can't hold anything"
	var/id = slot_id || dest.default_id
	var/datum/relation_definition/slot/def = dest.def_by_id(id)
	if(!def)
		return "[holder] has no [id]"
	var/list/entry = dest.entries[thing]
	if(entry && entry[LEDGER_E_SLOT] == id)
		return "it is already there"
	if(check_removal)
		. = dq_ledger_removal_refusal(thing, actor)
		if(.)
			return .
	// The slot's own answer may be a /datum/msg (a requirement's reason); this proc answers in text, like every other reason it gives.
	. = reason_text(def.refusal(holder, thing, actor))
	if(.)
		return .
	if(def.keyed)
		var/key = thing.slot_key()
		if(!isnull(key))
			var/atom/movable/existing = dest.slot_lookup(id, key)
			if(existing && existing != thing)
				return "[existing] already has that"
	if(def.capacity_model != SLOT_CAPACITY_NONE)
		var/limit = def.capacity_for(holder)
		if(limit != INFINITY)
			var/cost = (def.quantity && !isnull(units)) ? def.unit_cost(holder, thing) * units : def.cost(holder, thing)
			var/used_now = dest.current_used(id) + def.latent_used(holder)
			if(used_now + cost > limit)
				// A full slot with a replace policy gives up an occupant when that makes room, if the occupant may leave (its remove needs() apply).
				var/atom/movable/displaced = def.displaced_for(holder, thing)
				if(!displaced || used_now - def.cost(holder, displaced) + cost > limit)
					return "there's no room for it"
				. = dq_ledger_removal_refusal(displaced, actor)
				if(.)
					return .
	return reason_text(op_transfer_precheck(holder, /datum/act/insert, thing, id, actor))

/// Why `thing` can't leave the slot it is in now, or null. Things not in a
/// slot can always leave.
/proc/dq_ledger_removal_refusal(atom/movable/thing, mob/actor)
	var/atom/source = thing.loc
	var/datum/ledger/from = dq_ledger(source)
	var/list/entry = from?.entries[thing]
	if(!entry)
		return null
	var/datum/relation_definition/slot/def = from.def_by_id(entry[LEDGER_E_SLOT])
	. = reason_text(def.removal_refusal(source, thing, actor))
	if(.)
		return .
	return reason_text(op_transfer_precheck(source, /datum/act/remove, thing, entry[LEDGER_E_SLOT], actor))

/// Commits a checked move. Returns TRUE if the thing ended up in the slot.
/// `flags` (LEDGER_MOVE_*) reaches note_enter()/reslot() and, through them,
/// on_slotted()/on_unslotted() (J6).
/proc/dq_ledger_commit(atom/movable/thing, atom/holder, slot_id, flags = 0)
	var/datum/ledger/dest = holder.containment_ledger()
	var/id = slot_id || dest.default_id
	dq_ledger_make_room(thing, holder, id)
	if(thing.loc == holder)
		dest.reslot(thing, id, flags)
		return TRUE
	dest.pending_thing = thing
	dest.pending_slot = id
	dest.pending_flags = flags
	var/datum/ledger/source = dq_ledger_peek(thing.loc)
	if(source)
		source.pending_exit_flags = flags
	thing.containment_move(holder)
	if(dest.pending_thing == thing)
		dest.pending_thing = null
		dest.pending_slot = null
		dest.pending_flags = null
	var/list/entry = dest.entries?[thing]
	return entry && entry[LEDGER_E_SLOT] == id

/// A slot with a replace policy that is full gives up the occupant its policy names so `thing` fits (the refusal check already asked whether it may
/// leave). It goes to where `thing` came from when that is a floor or another holder, else to the holder's turf. Nothing happens for a slot that
/// refuses when full or has room.
/proc/dq_ledger_make_room(atom/movable/thing, atom/holder, id)
	var/datum/ledger/dest = dq_ledger(holder)
	var/datum/relation_definition/slot/def = dest?.def_by_id(id)
	if(!def || def.replace == REFUSE || def.capacity_model == SLOT_CAPACITY_NONE)
		return
	var/limit = def.capacity_for(holder)
	if(limit == INFINITY || dest.current_used(id) + def.latent_used(holder) + def.cost(holder, thing) <= limit)
		return
	var/atom/movable/displaced = def.displaced_for(holder, thing)
	if(!displaced)
		return
	var/atom/where = thing.loc
	if(!isturf(where) && !(where && where != holder && dq_slot_defs_for(where)))
		where = get_turf(holder)
	log_world("SLOT_REPLACE: [displaced] leaves [holder] ([id]) for [thing]; it goes to [where || "nullspace"]")
	holder.slot_remove(displaced, where, null, LEDGER_MOVE_FORCED | LEDGER_MOVE_DISPLACED)

/// Take `thing` out of this holder's slots to `destination`. A destination
/// with slots makes this a transfer into its default slot. `flags` may carry
/// LEDGER_MOVE_FORCED (J2): both refusals and pre signals are skipped, but
/// the commit bookkeeping still runs, same as any other move. LEDGER_MOVE_DESTROYING
/// (L1) always accompanies FORCED when the destroy transaction is the mover.
/atom/proc/slot_remove(atom/movable/thing, atom/destination, mob/actor, flags = 0)
	var/datum/ledger/L = dq_ledger(src)
	if(!L?.entries[thing] || !destination || QDELETED(destination))
		return FALSE
	if(flags & LEDGER_MOVE_FORCED)
		return dq_ledger_force_move(thing, destination, flags)
	if(dq_slot_defs_for(destination)) // the ledger's own checked commit: the place releases through here, so it can't go through move_into()
		if(dq_ledger_refusal(thing, destination, null, actor))
			return FALSE
		return dq_ledger_commit(thing, destination, null)
	for(var/atom/A = destination; A; A = A.loc)
		if(A == thing)
			return FALSE
	if(dq_ledger_removal_refusal(thing, actor))
		return FALSE
	thing.containment_move(destination)
	return thing.loc == destination

/**
 * The slot-link form: `thing` stops holding the slot it is in and is filed under this holder's default slot, without being moved. A machine whose
 * occupant came out as remains (a gibbed synthetic's wreck) keeps them physically inside, but they are no longer "the occupant": the occupant slot
 * empties, its occupancy is published and the slot hooks of both slots run, as for any other reslot. Returns TRUE when the thing was released; FALSE
 * when it is not in this holder, or already is in the default slot.
 */
/atom/proc/slot_release(atom/movable/thing)
	var/datum/ledger/L = dq_ledger_peek(src)
	var/list/entry = L?.entries[thing]
	if(!entry || thing.loc != src || entry[LEDGER_E_SLOT] == L.default_id)
		return FALSE
	L.reslot(thing, L.default_id, LEDGER_MOVE_FORCED)
	return TRUE

/// LEDGER_MOVE_FORCED's move: straight to the commit, no refusal checked and
/// no pre signal sent on either side. If `destination` has slots, `thing`
/// lands in `slot_id` (null: its default slot); otherwise this is a plain
/// forced forceMove. Either way doMove()'s bookkeeping (note_exit/note_enter,
/// the slot_* OM events, on_unslotted()/on_slotted()) runs as normal, carrying
/// `flags` to the hooks. L1's contents phase (lifecycle.dm) is the only
/// caller that ever names an explicit `slot_id` (KEEP_WITH).
/proc/dq_ledger_force_move(atom/movable/thing, atom/destination, flags = 0, slot_id = null)
	for(var/atom/A = destination; A; A = A.loc)
		if(A == thing)
			return FALSE
	if(dq_slot_defs_for(destination))
		dq_ledger(destination)
		return dq_ledger_commit(thing, destination, slot_id, flags)
	var/datum/ledger/source = dq_ledger_peek(thing.loc)
	if(source)
		source.pending_exit_flags = flags
	thing.containment_move(destination)
	return thing.loc == destination

/**
 * Move `thing` from one of this holder's slots into `new_holder`'s slot (`slot_id`, null: its default slot). A transfer is a remove and an
 * insert and always runs both as world actions, with their hooks (ACT_TRY of /datum/act/remove on this holder, then /datum/act/insert on
 * `new_holder`, each carrying `actor`): a belly's consent requirement or a bay's accepts is a needs() hook that refuses it like any other
 * move, an instead() takes it over, and the notices of both go out when it lands. Then both ledger checks run (dq_ledger_refusal()) and the move
 * commits. A refused or taken-over transfer changes nothing. Returns TRUE when it landed; slot_transfer_reason() answers why it did not.
 *
 * `authority` is an AUTH_* mask; only AUTH_ADMIN forces the transfer: the needs() hooks and both ledger refusals are skipped, the actions, their
 * instead()/adjusts() hooks and notices and the commit bookkeeping still run. There is no other bypass.
 */
/atom/proc/slot_transfer(atom/movable/thing, atom/new_holder, slot_id, mob/actor, authority = null)
	return isnull(slot_transfer_reason(thing, new_holder, slot_id, actor, authority))

/// slot_transfer() that answers why: null when `thing` landed, else the refusal reason (text or a /datum/msg).
/atom/proc/slot_transfer_reason(atom/movable/thing, atom/new_holder, slot_id, mob/actor, authority = null)
	var/datum/ledger/L = dq_ledger(src)
	var/list/entry = L?.entries[thing]
	if(!entry)
		return "it isn't in [src]"
	if(!new_holder || QDELETED(new_holder))
		return "there is nowhere to put it"
	if(istype(authority, /datum/authority_grant))
		var/datum/authority_grant/granted = authority
		log_world("SLOT_TRANSFER: authority [granted.reason || "unstated"] granted by [granted.granted_by]")
		authority = granted.mask
	if(!isnull(authority) && !isnum(authority))
		stack_trace("slot_transfer(): authority is an AUTH_* mask or a /datum/authority_grant, got [authority]")
		return "the transfer's authority is malformed"
	var/forced = !!(authority & AUTH_ADMIN)
	var/from_slot = entry[LEDGER_E_SLOT]
	GLOB.act_next_actor = actor
	GLOB.act_next_authority = authority
	var/leaving = ACT_ATTEMPT(src, remove, thing, from_slot)
	GLOB.act_next_actor = null
	GLOB.act_next_authority = null
	if(ACT_REFUSED_BY(leaving))
		var/datum/act_refusal/kept = leaving
		log_world("SLOT_TRANSFER: [thing] out of [src] ([from_slot]) refused or taken over ([reason_text(kept.reason)])")
		return kept.reason || /datum/msg/op/not_available
	GLOB.act_next_actor = actor
	GLOB.act_next_authority = authority
	var/entering = ACT_ATTEMPT(new_holder, insert, thing, slot_id)
	GLOB.act_next_actor = null
	GLOB.act_next_authority = null
	if(ACT_REFUSED_BY(entering))
		var/datum/act_refusal/refused = entering
		act_cancel(leaving)
		log_world("SLOT_TRANSFER: [thing] into [new_holder] ([slot_id || "default"]) refused or taken over ([reason_text(refused.reason)])")
		return refused.reason || /datum/msg/op/not_available
	var/datum/act/insert/entered = entering
	var/into_slot = ACT_FINAL(entered, slot_id, slot_id)
	var/landed = FALSE
	var/failed_for = null
	if(forced)
		log_world("SLOT_TRANSFER: FORCED [thing] from [src] ([from_slot]) to [new_holder] ([into_slot || "default"]) by [actor ? key_name(actor) : "the game"]")
		landed = dq_ledger_force_move(thing, new_holder, LEDGER_MOVE_FORCED, into_slot)
	else
		failed_for = dq_ledger_refusal(thing, new_holder, into_slot, actor)
		if(!failed_for)
			landed = dq_ledger_commit(thing, new_holder, into_slot)
	if(!landed)
		act_cancel(entering)
		act_cancel(leaving)
		return failed_for || "it won't go into [new_holder]"
	TEST_REC_TRANSFER(thing, src, new_holder, into_slot)
	act_done(leaving)
	act_done(entering)
	return null

/// An authority a caller is granted for one transfer: who granted it (a log name, never a reference), why, and which AUTH_* bits it carries.
/// slot_transfer(authority =) takes this or a bare mask; the grant is logged. (admission.md D2j: the datum replaces forced/silent flags; a `quiet`
/// field arrives with the first feedback path that reads it.)
/datum/authority_grant
	var/mask = AUTH_ADMIN
	var/granted_by = "the game"
	var/reason

/// A grant of admin authority: `actor` forces a transfer for `reason`.
/proc/admin_authority(mob/actor, reason, mask = AUTH_ADMIN)
	RETURN_TYPE(/datum/authority_grant)
	var/datum/authority_grant/granted = new
	granted.mask = mask
	if(actor)
		granted.granted_by = key_name(actor)
	granted.reason = reason
	return granted

/// Remove everything in `slot_id` (null: every slot) to `destination`.
/// Returns how many things left.
/atom/proc/slot_empty(slot_id, atom/destination, mob/actor)
	. = 0
	// Pulling things out materializes them (C5).
	latent_materialize_all(slot_id)
	for(var/atom/movable/thing as anything in slot_contents(slot_id))
		if(slot_remove(thing, destination, actor))
			.++

/// A copy of what is in `slot_id` (null: every slot, in slot order).
/atom/proc/slot_contents(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return list()
	if(isnull(slot_id))
		return L.ordered()
	var/list/things = L.slots[slot_id]
	return things ? things.Copy() : list()

/// Capacity used in `slot_id`, in its capacity model's units.
/atom/proc/slot_used(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return 0
	var/id = slot_id || L.default_id
	var/datum/relation_definition/slot/def = L.def_by_id(id)
	return (L.used[id] || 0) + (def ? def.latent_used(src) : 0)

/// How many things are in `slot_id` (null: the default slot) right now. The occupancy count a requirement may read: the ledger writes it (move_into()
/// and every release land in note_enter/note_exit) and publishes SLOT_OCCUPANCY_KEY, which this accessor stands for (READS_AS below).
/atom/proc/slot_occupancy(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return 0
	var/list/things = L.slots[slot_id || L.default_id]
	return length(things)

READS_AS(/atom/proc/slot_occupancy, SLOT_OCCUPANCY_KEY)

/**
 * The types of what `slot_id` (null: the default slot) holds that are a `type`: a real thing by its own type, a latent one by its entry's type, once each.
 * Nothing is materialized and no generator is rolled: a holder that has not yet declared its generator answers from the declared lines (the types it
 * will hold), one with a ledger from the ledger. A look draw reads it through look.contents_of(), which stands for SLOT_OCCUPANCY_KEY.
 */
/atom/proc/slot_kinds(slot_id, type = /atom/movable)
	RETURN_TYPE(/list)
	. = list()
	var/datum/ledger/L = containment_ledger()
	if(!L && latent_contents_enabled() && !latent_is_declared())
		var/list/generator = latent_generator()
		if(length(generator))
			for(var/path in generator)
				if(ispath(path, type))
					for(var/n in 1 to dq_latent_spawn_count(generator[path]))
						. += path
			return
	if(!L)
		L = dq_ledger(src)
		if(!L)
			return
	var/id = slot_id || L.default_id
	for(var/atom/movable/thing as anything in L.slots[id])
		if(istype(thing, type))
			. += thing.type
	for(var/datum/latent_entry/entry as anything in L.latent_list(id))
		if(ispath(entry.path, type))
			for(var/n in 1 to entry.count)
				. += entry.path

READS_AS(/atom/proc/slot_kinds, SLOT_OCCUPANCY_KEY)

/// How many units of `thing` fit into `slot_id` (null: the default slot) of this holder now: INFINITY when the slot has no limit, 0 when it is full or
/// there is no such slot. A thing carries one unit unless it is a quantity (slot_units()); the answer is whole units of it. A producer asks this
/// before it makes or takes anything, then move_into()s that many (move_into(amount =)).
/atom/proc/slot_room(atom/movable/thing, slot_id)
	var/datum/ledger/L = dq_ledger(src)
	var/datum/relation_definition/slot/def = L?.def_by_id(slot_id || L.default_id)
	if(!def)
		return 0
	return def.room_for(src, thing)

/// How many units this thing carries: 1, unless it is a quantity (a stack: its amount). What a quantity slot costs it by.
/atom/movable/proc/slot_units()
	return 1

/// A new thing carrying `units` of this one's units, made out of it (this one keeps the rest), not yet anywhere; null when it cannot be split.
/// A quantity thing overrides this and slot_unsplit().
/atom/movable/proc/slot_split(units)
	return null

/// Puts back what slot_split() took: `part` (a split-off piece that did not land) goes back into this one.
/atom/movable/proc/slot_unsplit(atom/movable/part)
	return FALSE

/// The limit of `slot_id` on this holder, or null when it has none.
/atom/proc/slot_capacity(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	var/datum/relation_definition/slot/def = L?.def_by_id(slot_id || L.default_id)
	if(!def || def.capacity_model == SLOT_CAPACITY_NONE)
		return null
	return def.capacity_for(src)

/// The one thing in `slot_id` (null: the default slot), or null if it holds
/// none. For a single-item slot (organ, equipment): the whole point of
/// slot_item() over slot_contents() is not building a copied list to read
/// one entry (J8).
/atom/proc/slot_item(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return null
	var/id = slot_id || L.default_id
	var/list/things = L.slots[id]
	return length(things) ? things[1] : null

/// The thing keyed `key` in `slot_id` on this holder, or null (J4). O(1).
/atom/proc/slot_lookup(slot_id, key)
	var/datum/ledger/L = dq_ledger(src)
	return L?.slot_lookup(slot_id, key)

/// Aggregate of measure `id` over everything in this holder, nested holders
/// included. Null when empty or when this holds no slots.
/atom/proc/contents_property(id)
	var/datum/ledger/L = dq_ledger(src)
	return L?.aggregate(id)

/// Whether anything in this holder, nested holders included, has `tag`.
/atom/proc/contents_has_tag(tag)
	var/datum/ledger/L = dq_ledger(src)
	return L ? L.has_tag(tag) : FALSE

/// The entry id of `thing` in this holder ("interior#12"), or null.
/atom/proc/slot_entry_id(atom/movable/thing)
	var/datum/ledger/L = dq_ledger(src)
	return L?.entry_id(thing)

/// The thing an entry id names, or null if the id is stale.
/atom/proc/slot_find_entry(entry_id)
	var/datum/ledger/L = dq_ledger(src)
	return L?.find_entry(entry_id)

// The destroy transaction's contents phase (L1, doc/rewrite/lifecycle.md Â§2-3)
// replaces what used to live here (ledger_apply_drop_policies(),
// ledger_drop_latent()): see code/datums/containment/lifecycle.dm.
