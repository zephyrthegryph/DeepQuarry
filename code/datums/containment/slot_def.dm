// Slot definitions (doc/rewrite/containment.md §3, object_model_core.md).
//
// A slot is a relation (/datum/om/relation/slot) that also owns loc: linking a
// thing into a slot (a ledger move) links it to the holder by this same
// relation, so a slot gets everything an ordinary relation gets for free --
// declared view fields, `changes` channels on link/unlink, on_link/on_unlink
// for side effects, contributes/grants -- on top of what only a container
// needs: where the thing physically is, capacity, exposure and propagation.
//
// A slot decl is a shared singleton, subtyping /datum/om/relation/slot and
// declaring `holder` (a holder type, or list of them) instead of overriding
// /atom/proc/slot_def_types(). The registry (registry.dm) builds each holder
// type's slot list once, from every decl whose `holder` matches. It says what
// the slot accepts (a P2 predicate, evaluated with the inserted thing as
// PRED_TARGET and the mover as PRED_ACTOR), how much it holds, and what the
// base Destroy() does with its contents. The ledger (ledger.dm) keeps each
// holder's per-instance state.

/datum/om/relation/slot
	abstract_type = /datum/om/relation/slot
	/// CONTAINER_SLOT_* id, unique among one holder's slots. Distinct from the
	/// relation base's own numeric `id` (the registry's index into `relations`).
	var/slot_id
	name = "contents"
	/// The holder type this slot belongs to, or a list of holder types. The
	/// registry groups every decl sharing an entry here into one holder's slot
	/// list (dq_slot_defs_for()), replacing the old slot_def_types() override:
	/// a holder's own key (slot_holder_key(), by default its type) is matched
	/// against every declared holder type, most-derived match wins, same as a
	/// proc override would.
	var/holder
	/// Tie-break among a holder's slots when order matters (worn-protection
	/// layering caches, state serialization numbering): lower first. Ties fall
	/// back to registration order. Most holders don't need to set this.
	var/order = 0
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
	/// Keyed slot (J4): a thing's `slot_key()` is stored on its ledger entry
	/// at insert and indexed for O(1) `slot_lookup()`. A second thing with
	/// the same key is refused. Only keyed slots pay for the index.
	var/keyed = FALSE
	/// L1 (doc/rewrite/lifecycle.md §2 phase 0.5, §3): a TRANSFER slot whose
	/// contents must resolve in the destroy transaction's mind pre-order
	/// pass, before anything else -- while the mob tree is still fully
	/// registered and has a loc. Body plans declare this on the mind slot
	/// (DQ Medical, O2). Nothing else may set it.
	var/is_mind_slot = FALSE

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

/// SLOT_DROP_TRANSFER's destination (doc/rewrite/lifecycle.md §3). The
/// default reproduces the pre-L1 behaviour: the holder's own container, if
/// it has slots, else null (the caller falls back to spill). Override for
/// anything else: occupant ejection to a turf, mind transfer to a ghost or
/// MMI, a bellied mob to the predator's turf.
/datum/om/relation/slot/proc/drop_resolver(atom/holder, atom/movable/thing, atom/drop)
	if(holder.loc && dq_slot_defs_for(holder.loc))
		return holder.loc
	return null

/// SLOT_DROP_TO_LATENT's successor (doc/rewrite/lifecycle.md §3): the atom
/// whose ledger gets a latent entry for each thing dropped from this slot,
/// instead of the thing staying real. Null lets the entry go (debris/wreckage
/// declares this once it exists; until then TO_LATENT behaves like DELETE).
/datum/om/relation/slot/proc/latent_successor(atom/holder)
	return null

/// SLOT_DROP_KEEP_WITH's destination slot id on replace_with()'s successor
/// (doc/rewrite/lifecycle.md §3 and §5). Null names the successor's default
/// slot.
/datum/om/relation/slot/proc/keep_with_slot()
	return null

/// The singleton for a slot decl type: the registry's relation instance.
/proc/dq_slot_def(path)
	RETURN_TYPE(/datum/om/relation/slot)
	var/datum/om/relation/R = om_registry().relation(path)
	if(!istype(R, /datum/om/relation/slot))
		CRASH("[path] is not a /datum/om/relation/slot")
	return R

/// The slot decls a holder declares, in order, or null. Cached per key
/// (slot_holder_key()). Resolved from the registry's holder groups (built at
/// boot by /datum/om/registry/proc/build_slot_holders(), registry.dm), unless
/// the holder overrides slot_relation_overrides() to decide dynamically.
/proc/dq_slot_defs_for(atom/holder)
	var/static/list/cache = list()
	var/key = holder.slot_holder_key()
	. = cache[key]
	if(isnull(.))
		var/list/defs = holder.slot_relation_overrides()
		if(isnull(defs))
			defs = om_registry().slot_group_for(key)
		. = length(defs) ? defs : FALSE
		cache[key] = .
	return . || null

/// What a holder's slot set is cached by. A holder whose slots depend on more
/// than its own type (a mob's body plan) overrides this to return that type
/// instead -- the registry's holder groups (build_slot_holders()) are matched
/// against whatever this returns, not necessarily the holder's own type.
/atom/proc/slot_holder_key()
	return type

/// Escape hatch for a holder whose slot set can't be expressed as a static
/// per-type declaration (a decision that depends on more than the holder's
/// type or body plan, e.g. an instance flag). Returning null (the default)
/// means "use the registry's declared groups, keyed by slot_holder_key()".
/atom/proc/slot_relation_overrides()
	return null

/// The limit for this holder. Override for per-instance capacities.
/datum/om/relation/slot/proc/capacity_for(atom/holder)
	return capacity

/// What `thing` costs in this slot, in the capacity model's units.
/datum/om/relation/slot/proc/cost(atom/holder, atom/movable/thing)
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
/datum/om/relation/slot/proc/refusal(atom/holder, atom/movable/thing, mob/actor)
	if(accepts)
		var/datum/predicate/P = dq_predicate(accepts)
		. = P.why_not(actor, thing, null)
		if(.)
			return .
	if(holder_constraint && isitem(holder))
		return dq_constraint_refusal(holder, holder_constraint, thing, actor)
	return null

/// Why `thing` can't leave this slot on `holder`, or null. Default: it can.
/datum/om/relation/slot/proc/removal_refusal(atom/holder, atom/movable/thing, mob/actor)
	return null

/// Share of damage kind `kind` passing into this slot, before armour.
/datum/om/relation/slot/proc/damage_share(kind)
	var/list/shares = damage_transmission || dq_path_default_damage(exposure)
	return shares[kind]

/// Whether gas from the holder's surroundings reaches this slot.
/datum/om/relation/slot/proc/passes_gas()
	return exposure != SLOT_EXPOSURE_SEALED

/// Whether this slot is inside the holder's shell (the holder's own
/// insulation and armour cover it).
/datum/om/relation/slot/proc/is_inside()
	return exposure != SLOT_EXPOSURE_EXTERNAL

/// Capacity used by latent contents that have no atom (stock counts, C9).
/datum/om/relation/slot/proc/latent_used(atom/holder)
	return 0

/// Applies the drop policy to latent contents when the holder is destroyed:
/// materialize them at `drop` or let them go. The ledger then applies the
/// policy to the real contents. Default: there are none.
/datum/om/relation/slot/proc/drop_latent(atom/holder, atom/drop)
	return
