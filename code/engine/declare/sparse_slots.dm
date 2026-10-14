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

/datum
	/// Sparse slots of this instance (sparse()): slot name -> value. Null while every slot is unset.
	var/tmp/list/sparse_slots
	/// Cooldowns of a base type (cooldowns()): name -> world.time it ends. Null while none ever started.
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
