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
	/// CONSTRAINT_* kind the holder declares for this slot (P3), such as
	/// CONSTRAINT_HOLD for storage: checked after `accepts`, for holders whose
	/// acceptance varies by type. Null for none.
	var/holder_constraint
	/// SLOT_DROP_*.
	var/drop_policy = SLOT_DROP_SPILL
	/// Legacy moves into the holder (forceMove, new(holder)) land in the
	/// default slot. The first declared slot is the default unless another
	/// sets this.
	var/is_default = FALSE

	// ---- Propagation (containment.md §3.2, C2; paths.dm walks these) ----
	/// SLOT_LAYER_*: order among this holder's layered slots, higher is further
	/// out. Everything in a layer further out covers what is in this one.
	var/layer = SLOT_LAYER_NONE
	/// Fraction of heat that crosses this slot's own boundary, before the
	/// holder's insulation (internal and sealed slots) and outer layers.
	var/heat_transmission = 1
	/// Fraction of radiation that crosses this slot's own boundary, before the
	/// holder's radiation armour and outer layers.
	var/radiation_transmission = 1
	/// Share of each damage kind (DAMAGE_* order) that passes from a hit on the
	/// holder to this slot's contents, before armour. Null: the exposure's
	/// default (dq_path_default_damage()).
	var/list/damage_transmission
	/// Whether living things in this slot take the heat and damage paths. Off:
	/// mobs get heat from their environment (H2) and hits through their own
	/// occupant rules (C8).
	var/reaches_mobs = FALSE

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
	var/key = holder.slot_def_key()
	. = cache[key]
	if(isnull(.))
		var/list/defs = list()
		for(var/path in holder.slot_def_types())
			defs += dq_slot_def(path)
		. = length(defs) ? defs : FALSE
		cache[key] = .
	return . || null

/// Override on a holder type to declare its slots: a list of /datum/slot_def
/// paths. Return a proc-local static list. The result must depend only on
/// slot_def_key(), which is the holder's type unless overridden.
/atom/proc/slot_def_types()
	return null

/// What a holder's slot set is cached by. Holders whose slots depend on more
/// than their type (a mob's body plan) return a key covering that too, e.g.
/// "[type]|[body.plan.type]"; slot_def_types() must then return the set for it.
/atom/proc/slot_def_key()
	return type

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
	if(accepts)
		var/datum/predicate/P = dq_predicate(accepts)
		. = P.why_not(actor, thing, null)
		if(.)
			return .
	if(holder_constraint && isitem(holder))
		return dq_constraint_refusal(holder, holder_constraint, thing, actor)
	return null

/// Why `thing` can't leave this slot on `holder`, or null. Default: it can.
/datum/slot_def/proc/removal_refusal(atom/holder, atom/movable/thing, mob/actor)
	return null

/// Share of damage kind `kind` passing into this slot, before armour.
/datum/slot_def/proc/damage_share(kind)
	var/list/shares = damage_transmission || dq_path_default_damage(exposure)
	return shares[kind]

/// Whether gas from the holder's surroundings reaches this slot.
/datum/slot_def/proc/passes_gas()
	return exposure != SLOT_EXPOSURE_SEALED

/// Whether this slot is inside the holder's shell (the holder's own
/// insulation and armour cover it).
/datum/slot_def/proc/is_inside()
	return exposure != SLOT_EXPOSURE_EXTERNAL

/// Capacity used by latent contents that have no atom (stock counts, C9).
/datum/slot_def/proc/latent_used(atom/holder)
	return 0

/// Applies the drop policy to latent contents when the holder is destroyed:
/// materialize them at `drop` or let them go. The ledger then applies the
/// policy to the real contents. Default: there are none.
/datum/slot_def/proc/drop_latent(atom/holder, atom/drop)
	return
