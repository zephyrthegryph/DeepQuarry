// Slot definitions (doc/rewrite/containment.md Ã‚Â§3, object_model_core.md).
//
// A slot is a relation (/datum/relation_definition/slot) that also owns loc: linking a
// thing into a slot (a ledger move) links it to the holder by this same
// relation, so a slot gets everything an ordinary relation gets for free --
// declared view fields, `changes` channels on link/unlink, on_link/on_unlink
// for side effects, contributes/grants -- on top of what only a container
// needs: where the thing physically is, capacity, exposure and propagation.
//
// A slot decl is a shared singleton, subtyping /datum/relation_definition/slot and
// declaring `holder` (a holder type, or list of them) instead of overriding
// /atom/proc/slot_def_types(). The registry (registry.dm) builds each holder
// type's slot list once, from every decl whose `holder` matches. It says what
// the slot accepts (a P2 predicate, evaluated with the inserted thing as
// PRED_TARGET and the mover as PRED_ACTOR), how much it holds, and what the
// base Destroy() does with its contents. The ledger (ledger.dm) keeps each
// holder's per-instance state.

/datum/relation_definition/slot
	parent_type = /datum/relation_definition
	abstract_type = /datum/relation_definition/slot
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
	/// L1 (doc/rewrite/lifecycle.md Ã‚Â§2 phase 0.5, Ã‚Â§3): a TRANSFER slot whose
	/// contents must resolve in the destroy transaction's mind pre-order
	/// pass, before anything else -- while the mob tree is still fully
	/// registered and has a loc. Body plans declare this on the mind slot
	/// (DQ Medical, O2). Nothing else may set it.
	var/is_mind_slot = FALSE

	// ---- Propagation (containment.md Ã‚Â§3.2, C2; paths.dm walks these) ----
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

	// ---- Operations (operations/routes.dm) ----
	/// AFF_* mask of what the holder can do through this slot (a hand: hold, manipulate,
	/// hold small, interface). ops_provider() picks the slot that gives an op's affordance.
	var/provides = NONE
	/// BAY_*: the compartment of the holder this slot sits in; paths cross that bay's boundary.
	var/at

/// SLOT_DROP_TRANSFER's destination (doc/rewrite/lifecycle.md Ã‚Â§3). The
/// default reproduces the pre-L1 behaviour: the holder's own container, if
/// it has slots, else null (the caller falls back to spill). Override for
/// anything else: occupant ejection to a turf, mind transfer to a ghost or
/// MMI, a bellied mob to the predator's turf.
/datum/relation_definition/slot/proc/drop_resolver(atom/holder, atom/movable/thing, atom/drop)
	if(holder.loc && dq_slot_defs_for(holder.loc))
		return holder.loc
	return null

/// SLOT_DROP_TO_LATENT's successor (doc/rewrite/lifecycle.md Ã‚Â§3): the atom
/// whose ledger gets a latent entry for each thing dropped from this slot,
/// instead of the thing staying real. Null lets the entry go (debris/wreckage
/// declares this once it exists; until then TO_LATENT behaves like DELETE).
/datum/relation_definition/slot/proc/latent_successor(atom/holder)
	return null

/// SLOT_DROP_KEEP_WITH's destination slot id on replace_with()'s successor
/// (doc/rewrite/lifecycle.md Ã‚Â§3 and Ã‚Â§5). Null names the successor's default
/// slot.
/datum/relation_definition/slot/proc/keep_with_slot()
	return null

/// The singleton for a slot decl type: the registry's relation instance.
/proc/dq_slot_def(path)
	RETURN_TYPE(/datum/relation_definition/slot)
	var/datum/relation_definition/R = definition_registry().relation(path)
	if(!istype(R, /datum/relation_definition/slot))
		CRASH("[path] is not a /datum/relation_definition/slot")
	return R

/// The slot decls a holder declares, in order, or null. Cached per key
/// (slot_holder_key()). Resolved from the registry's holder groups (built at
/// boot by /datum/definition_registry/proc/build_slot_holders(), registry.dm), unless
/// the holder overrides slot_relation_overrides() to decide dynamically.
/proc/dq_slot_defs_for(atom/holder)
	var/key = holder.slot_holder_key()
	return CACHED_KEY(slot_defs_for, key, holder, key) || null

DECLARE_SHARED_CACHE(slot_defs_for, GLOBAL_PROC_REF(build_slot_defs_for), SC_NEVER)

/// Builder for dq_slot_defs_for(): `holder` is any instance answering `key`. The registry's relation decls first, then the slots the holder's
/// CAPABILITIES declare (slot() entries, and the slot each construction or deployment graph puts its parts in).
/proc/build_slot_defs_for(atom/holder, key)
	var/list/defs = holder.slot_relation_overrides()
	if(isnull(defs))
		defs = definition_registry().slot_group_for(key)
	var/list/declared = declared_slot_defs(holder, defs)
	if(length(declared))
		defs = (defs || list()) + declared
	return length(defs) ? defs : FALSE

// ---- slots declared as entries ----

/// A ledger slot made from a declaration, not a relation type of its own: a slot(SLOT_X, ...) entry of the holder's CAPABILITIES, or the slot a
/// state graph's put_in(SLOT_X) puts its parts in (the APC's board in SLOT_CONSTRUCTION). One shared instance per holder type and slot id
/// (declared_slot_def()); the ledger moves link things under this one registered relation type.
/// The declared slots of `holder` that its relation decls (`defs`) do not already give, in declaration order: its slot() entries, then each
/// graph's put_in() slots. Built once per holder type (dq_slot_defs_for() caches the list).
/proc/declared_slot_defs(atom/holder, list/defs)
	. = list()
	var/list/taken = list()
	for(var/datum/relation_definition/slot/S as anything in defs)
		taken[S.slot_id] = TRUE
	var/datum/type_table/T = table_of(holder)
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_SLOT))
		var/datum/entry/E = C.item
		var/id = E.args["id"]
		if(isnull(id) || taken[id] || (istext(id) && (id in holder.vars)))
			continue
		taken[id] = TRUE
		var/capacity = E.args["capacity"]
		. += declared_slot_def(holder.type, id, isnum(capacity) ? capacity : 0, E.args["at"], E.args["accepts"], !length(defs) && !length(.), E.args["exposure"])
	var/list/graph_slots = holder.construction_slot_declarations(taken, defs, length(.))
	if(length(graph_slots))
		. += graph_slots

/// The shared declared slot of holder type `holder_type` with id `id`: `capacity` things (0: no limit), in space `at`, of type `accepts`. An
/// `exposure` of SLOT_EXPOSURE_SEALED makes it a sealed slot (an occupant pod's): what is inside lives in the holder's shell.
/proc/declared_slot_def(holder_type, id, capacity, at, accepts, is_default, exposure = null)
	RETURN_TYPE(/datum/relation_definition/slot)
	var/static/list/made = list()
	var/cache_key = "[holder_type]|[id]"
	var/datum/relation_definition/slot/S = made[cache_key]
	if(S)
		return S
	S = containment_slot_factory().create(exposure)
	S.holder = holder_type
	S.slot_id = id
	S.name = "[id]"
	S.capacity_model = capacity ? SLOT_CAPACITY_COUNT : SLOT_CAPACITY_NONE
	S.capacity = capacity
	S.at = at
	S.set_declared_accepts(accepts)
	S.is_default = is_default
	made[cache_key] = S
	return S

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
/datum/relation_definition/slot/proc/capacity_for(atom/holder)
	return capacity

/// What `thing` costs in this slot, in the capacity model's units.
/datum/relation_definition/slot/proc/cost(atom/holder, atom/movable/thing)
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
/datum/relation_definition/slot/proc/refusal(atom/holder, atom/movable/thing, mob/actor)
	if(accepts)
		var/datum/predicate/P = dq_predicate(accepts)
		. = P.why_not(actor, thing, null)
		if(.)
			return .
	if(holder_constraint)
		return holder.containment_constraint_refusal(holder_constraint, thing, actor)
	return null

/// Why `thing` can't leave this slot on `holder`, or null. Default: it can.
/datum/relation_definition/slot/proc/removal_refusal(atom/holder, atom/movable/thing, mob/actor)
	return null

/// Share of damage kind `kind` passing into this slot, before armour.
/datum/relation_definition/slot/proc/damage_share(kind)
	var/list/shares = damage_transmission || dq_path_default_damage(exposure)
	return shares[kind]

/// Whether gas from the holder's surroundings reaches this slot.
/datum/relation_definition/slot/proc/passes_gas()
	return exposure != SLOT_EXPOSURE_SEALED

/// Whether this slot is inside the holder's shell (the holder's own
/// insulation and armour cover it).
/datum/relation_definition/slot/proc/is_inside()
	return exposure != SLOT_EXPOSURE_EXTERNAL

/// Capacity used by latent contents that have no atom (stock counts, C9).
/datum/relation_definition/slot/proc/latent_used(atom/holder)
	return 0

/// Applies the drop policy to latent contents when the holder is destroyed:
/// materialize them at `drop` or let them go. The ledger then applies the
/// policy to the real contents. Default: there are none.
/datum/relation_definition/slot/proc/drop_latent(atom/holder, atom/drop)
	return

/atom/proc/construction_slot_declarations(list/taken, list/defs, existing_count)
	return null

/atom/proc/containment_constraint_refusal(kind, atom/movable/thing, mob/actor)
	return null

/atom/proc/containment_ambient_temperature()
	return T20C

GLOBAL_DATUM(containment_slot_factory, /datum/containment_slot_factory)

/datum/containment_slot_factory

/datum/containment_slot_factory/proc/create(exposure)
	RETURN_TYPE(/datum/relation_definition/slot)
	return canonical_create(exposure)

/datum/containment_slot_factory/proc/canonical_create(exposure)
	RETURN_TYPE(/datum/relation_definition/slot/declared)
	return exposure == SLOT_EXPOSURE_SEALED ? new /datum/relation_definition/slot/declared/sealed : new /datum/relation_definition/slot/declared

/datum/relation_definition/slot/proc/set_declared_accepts(accepts)
	CRASH("Not a declared containment slot")

/datum/relation_definition/slot/declared
	name = "declared slot"
	capacity_model = SLOT_CAPACITY_COUNT
	drop_policy = SLOT_DROP_SPILL
	/// A slot() entry's accepts: the type a thing must be, or a list of them.
	var/accepts_type

/datum/relation_definition/slot/declared/refusal(atom/holder, atom/movable/thing, mob/actor)
	. = declared_slot_type_refusal(accepts_type, thing)
	if(.)
		return .
	return ..()

/// A declared slot that is sealed (slot(..., exposure = SLOT_EXPOSURE_SEALED)): what is inside lives in the holder's shell, as a pod's patient
/// does: no gas reaches them, no heat or blast crosses it (containment.md section 10). Spilled onto the floor when the holder is destroyed.
/datum/relation_definition/slot/declared/sealed
	name = "sealed slot"
	exposure = SLOT_EXPOSURE_SEALED
	reaches_mobs = TRUE
	heat_transmission = 0
	radiation_transmission = 1
	damage_transmission = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)



/datum/relation_definition/slot/declared/set_declared_accepts(accepts)
	accepts_type = accepts

/proc/declared_slot_type_refusal(accepts_type, atom/movable/thing)
	// A declared slot accepts either one type or a list of types.
	if(accepts_type && !(islist(accepts_type) ? is_type_in_list(thing, accepts_type) : istype(thing, accepts_type)))
		return "\The [thing] doesn't go there."
	return null

/proc/containment_slot_factory()
	RETURN_TYPE(/datum/containment_slot_factory)
	if(!GLOB.containment_slot_factory)
		GLOB.containment_slot_factory = new /datum/containment_slot_factory
	return GLOB.containment_slot_factory
