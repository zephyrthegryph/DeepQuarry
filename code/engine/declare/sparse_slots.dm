// Sparse slots and cooldown tables (doc/rewrite/proposals/base_vars.md; final_api.html "Sparse slots and cooldowns").
//
// A base type (/atom, /obj/item, /mob, ...) carries no var for state that only a few instances ever hold. That state is a sparse slot:
//
//   sparse(/mob, special_voice, type = text)       declares the slot (a declaration line like TRACKED; it expands to nothing)
//   sparse_get(M, special_voice)                   its value, or null when unset (sparse_get_or(M, x, 0) for another default)
//   sparse_set(M, special_voice, "Bob")            writes it; null (or the default given) clears it
//
// Every slot of an instance lives in one lazy assoc list, /datum/var/sparse_slots, null until the first slot is set, so an instance with none
// costs nothing. A per-type default (what a GLOB type table used to hold) is a trait block, not a slot.
//
// A slot that names another datum is a weak slot, declared `sparse(/mob, teleop, type = weak)`. It holds ref_token() of its target, so it pins nothing, a
// self value is fine (no link, no reverse index, nothing to cycle), and it reads null once the target is gone:
//
//   sparse_ref(M, teleop)                          the live target, or null (a slot whose target is gone is cleared as it is found)
//   sparse_ref_set(M, teleop, target)              points it at `target` (a datum, the holder itself included); null clears it
//
// A reader that must react to the target's death declares a link or a ref_one instead: a weak slot runs nothing when its target goes.
//
// Cooldowns on a base type are a cooldown table: one lazy list of name -> world.time the cooldown ends.
//
//   cooldowns(next_move, resist_cooldown)          in the type's CAPABILITIES block: declares the names (expands to nothing)
//   cooldown_start(M, next_move, 2 SECONDS)        starts (or restarts) it
//   cooldown_ready(M, next_move)                   TRUE once it ran out (or never started)
//   cooldown_left(M, next_move)                    deciseconds left, 0 when ready
//   cooldown_end(M, next_move)                     the world.time it ends, 0 when never started
//   cooldown_started(M, next_move) / cooldown_reset(M, next_move)
//
// COOLDOWN_DECLARE on a base type is banned (base_vars lint); a subtype's own COOLDOWN_DECLARE stays a var.
//
// Stamps share that table: stamps(last_bumped) declares, STAMP(M, last_bumped, CLOCK_WORLD) writes, STAMP_ELAPSED(M, last_bumped, CLOCK_WORLD) reads.

/datum
	/// Sparse slots of this instance (sparse()): slot name -> value. Null while every slot is unset.
	var/tmp/list/sparse_slots
	/// Cooldowns (cooldowns(): name -> world.time it ends) and stamps (stamps(): name -> a point on a clock) of a base type. Null while none is set.
	var/tmp/list/cooldown_table



/proc/_sparse_get(datum/D, name, default = null)
	var/value = D?.sparse_slots?[name]
	return isnull(value) ? default : value

/// Writes slot `name`; a null value (or one equal to `default`) clears it, and the list goes when its last slot does. Returns the value.
/proc/_sparse_set(datum/D, name, value, default = null)
	if(!D)
		return value
	if(isnull(value) || value == default)
		if(D.sparse_slots)
			D.sparse_slots -= name
			if(!length(D.sparse_slots))
				D.sparse_slots = null
		return value
	if(!D.sparse_slots)
		D.sparse_slots = list()
	D.sparse_slots[name] = value
	return value

/// The live target of weak slot `name` (sparse(T, name, type = weak)), or null when unset or gone. A gone target's token is dropped as it is found.
/proc/_sparse_ref(datum/D, name)
	var/token = D?.sparse_slots?[name]
	if(isnull(token))
		return null
	var/datum/target = resolve_token(token)
	if(!target)
		_sparse_set(D, name, null)
	return target

/// Points weak slot `name` at `target` (any datum, the holder too), or clears it with null. Returns `target`, or null when refused (not a datum, or being deleted).
/proc/_sparse_ref_set(datum/D, name, datum/target)
	if(!D)
		return null
	if(isnull(target))
		_sparse_set(D, name, null)
		return null
	if(!isdatum(target) || QDELETED(target))
		return null
	_sparse_set(D, name, ref_token(target))
	return target

/proc/_cooldown_start(datum/D, name, duration)
	return _cooldown_set(D, name, world.time + duration)

/proc/_cooldown_set(datum/D, name, at)
	if(!at)
		if(D.cooldown_table)
			D.cooldown_table -= name
			if(!length(D.cooldown_table))
				D.cooldown_table = null
		return 0
	if(!D.cooldown_table)
		D.cooldown_table = list()
	D.cooldown_table[name] = at
	return at


/// Writes stamp `name` (a point on a clock; 0 is a valid point, so it is stored rather than clearing). Returns the point.
/proc/_stamp_set(datum/D, name, point)
	if(!D)
		return point
	if(!D.cooldown_table)
		D.cooldown_table = list()
	D.cooldown_table[name] = point
	return point

/proc/_stamp_clear(datum/D, name)
	if(D?.cooldown_table)
		D.cooldown_table -= name
		if(!length(D.cooldown_table))
			D.cooldown_table = null
