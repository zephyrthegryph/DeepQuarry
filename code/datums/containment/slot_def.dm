// Slot definitions (doc/rewrite/containment.md §3).
//
// A slot definition is a shared singleton, declared per holder type by
// overriding /atom/proc/slot_def_types(). It says what the slot accepts (a P2
// predicate, evaluated with the inserted thing as PRED_TARGET and the mover as
// PRED_ACTOR), how much it holds, and what the base Destroy() does with its
// contents. The ledger (ledger.dm) keeps each holder's per-instance state.

/datum/slot_def
	/// CONTAINER_SLOT_* id, unique among one holder's slots.
	var/id
	var/name = "contents"
	/// SLOT_EXPOSURE_*.
	var/exposure = SLOT_EXPOSURE_INTERNAL
	/// SLOT_CAPACITY_*.
	var/capacity_model = SLOT_CAPACITY_NONE
	/// Limit in the capacity model's units. See capacity_for().
	var/capacity = 0
	/// /datum/predicate subtype the inserted thing must pass, or null for anything.
	var/accepts
	/// SLOT_DROP_*.
	var/drop_policy = SLOT_DROP_SPILL
	/// Legacy moves into the holder (forceMove, new(holder)) land in the
	/// default slot. The first declared slot is the default unless another
	/// sets this.
	var/is_default = FALSE

/// The singleton for a slot definition type.
/proc/dq_slot_def(path)
	var/static/list/cache = list()
	. = cache[path]
	if(!.)
		var/datum/slot_def/def = new path
		if(!def.id)
			CRASH("slot definition [path] has no id")
		cache[path] = def
		. = def

/// The slot definitions a holder type declares, in order, or null. Cached per type.
/proc/dq_slot_defs_for(atom/holder)
	var/static/list/cache = list()
	var/key = holder.type
	. = cache[key]
	if(isnull(.))
		var/list/defs = list()
		for(var/path in holder.slot_def_types())
			defs += dq_slot_def(path)
		. = length(defs) ? defs : FALSE
		cache[key] = .
	return . || null

/// Override on a holder type to declare its slots: a list of /datum/slot_def
/// paths. Return a proc-local static list. Must depend on the type only.
/atom/proc/slot_def_types()
	return null

/// The limit for this holder. Override for per-instance capacities.
/datum/slot_def/proc/capacity_for(atom/holder)
	return capacity

/// What `thing` costs in this slot, in the capacity model's units.
/datum/slot_def/proc/cost(atom/holder, atom/movable/thing)
	switch(capacity_model)
		if(SLOT_CAPACITY_NONE)
			return 0
		if(SLOT_CAPACITY_COUNT)
			return 1
		if(SLOT_CAPACITY_SIZE)
			return PROPERTY(thing, PROP_SIZE_CLASS) || 0
		if(SLOT_CAPACITY_MASS)
			return PROPERTY(thing, PROP_MASS) || 0
	return 1

/// Why `thing` can't go in this slot on `holder`, not counting capacity, or null.
/datum/slot_def/proc/refusal(atom/holder, atom/movable/thing, mob/actor)
	if(!accepts)
		return null
	var/datum/predicate/P = dq_predicate(accepts)
	return P.why_not(actor, thing, null)

/// Why `thing` can't leave this slot on `holder`, or null. Default: it can.
/datum/slot_def/proc/removal_refusal(atom/holder, atom/movable/thing, mob/actor)
	return null
