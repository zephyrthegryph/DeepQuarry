// Constraints (doc/rewrite/rules.md §3).
//
// A constraint is a declared P2 predicate attached to a slot, a holder or an
// item. Every check returns a reason ("too big: size 3 > size 2", "it only
// fits Teshari", "you need a jumpsuit first"), through the same path whether
// the caller is legacy storage, legacy equip code or a C1 slot.
//
// Where they attach:
//   Slots    /datum/relation_definition/slot.accepts (a predicate type) and, for holders that
//            declare their own, slot_def.holder_constraint (a CONSTRAINT_* kind
//            read from the holder). Equip slots: equip_slots.dm.
//   Holders  the hold_spec table on storage and holsters: what goes inside.
//            the suit_storage_spec table on suits: what the suit-storage slot takes.
//   Items    the fit_spec table: whose body it fits (the old species_restricted).
//            the equip_spec table: what it needs of its wearer, in any slot.
//
// Declaring. Set the type's table (TYPE_TABLE, systems.md section 7) to a spec
// (a list of REQ_* clauses), or null for none. The value is built once per
// type; the result is compiled and cached, so it must depend on the type only:
//
//   TYPE_TABLE(/obj/item/storage/pill_bottle, hold_spec, list( //       HOLD_ONLY(list(/obj/item/reagent_containers/pill, /obj/item/dice)), //       HOLD_MAX_SIZE(ITEMSIZE_TINY)))
//
// Changing one instance (a refitted suit, an exact-fit box) goes through
// set_constraint(), which installs a compiled override on that instance only.
//
// Reading:
//   dq_constraint(I, kind)                        the compiled predicate or null
//   dq_constraint_refusal(I, kind, thing, actor)  why `thing` is refused, or null
//   I.equip_refusal(M, slot, ...)                 why M can't equip I there, or null
//   S.insert_refusal(W, user)                     why storage S won't take W, or null

/obj/item
	/// CONSTRAINT_* -> this instance's compiled override (a /datum/predicate),
	/// or FALSE for "none". Null on almost every item.
	var/list/constraint_overrides

TRACKED(/obj/item, constraint_overrides)

// Overrides are immutable shared predicate or native plan entries, never owned.
/obj/item/acceptance_overrides()
	var/list/native
	for(var/channel in constraint_overrides)
		var/datum/entry/part/acceptance_plan/P = constraint_overrides[channel]
		if(istype(P))
			LAZYSET(native, channel, P)
	return native

/obj/item/acceptance_override_reads()
	return list(list(src, nameof(constraint_overrides)))

/obj/item/proc/set_native_constraint(kind, datum/entry/declaration)
	var/list/native = acceptance_override(src, null, kind, declaration)
	set_native_constraint_plan(kind, native[kind])

/obj/item/proc/set_native_constraint_plan(kind, datum/entry/part/acceptance_plan/plan)
	if(!istype(plan))
		CRASH("native constraint must be a resolved plan")
	var/list/next = constraint_overrides ? constraint_overrides.Copy() : list()
	next[kind] = plan
	set_constraint_overrides(next)

/proc/dq_constraint_has_legacy_override(obj/item/I, kind)
	READS_FROM(I)
	var/override = LAZYACCESS(I.constraint_overrides, kind)
	return !isnull(override) && !istype(override, /datum/entry/part/acceptance_plan)

/// The spec for constraint `kind` on this type. Called once per type.
/obj/item/proc/constraint_spec(kind)
	switch(kind)
		if(CONSTRAINT_HOLD)
			return TYPE_TABLE_GET(src, hold_spec)
		if(CONSTRAINT_SUIT_STORAGE)
			return TYPE_TABLE_GET(src, suit_storage_spec)
		if(CONSTRAINT_FIT)
			return TYPE_TABLE_GET(src, fit_spec)
		if(CONSTRAINT_EQUIP)
			return TYPE_TABLE_GET(src, equip_spec)
	CRASH("unknown constraint kind [kind]")

/// What this holder takes: a spec of clauses on PRED_TARGET, or null for anything.
TYPE_TABLE_DECLARE(/obj/item, hold_spec, null)

/// What a worn suit's suit-storage slot takes, or null for no suit storage.
/// PDAs and pens always fit a suit that has one.
TYPE_TABLE_DECLARE(/obj/item, suit_storage_spec, null)

/// Whose body this fits (PRED_ACTOR is the wearer), or null for anyone.
TYPE_TABLE_DECLARE(/obj/item, fit_spec, null)

/// What this needs of its wearer (PRED_ACTOR) in any equip slot, or null.
TYPE_TABLE_DECLARE(/obj/item, equip_spec, null)

/// The compiled constraint of `kind` for `I`: its instance override, else its
/// type's declaration. Null when there is none.
/proc/dq_constraint(obj/item/I, kind)
	READS_FROM(I)
	if(I.constraint_overrides)
		var/override = I.constraint_overrides[kind]
		if(istype(override, /datum/entry/part/acceptance_plan))
			return null
		if(!isnull(override))
			return override || null
	return CACHED_KEY(item_constraint, "[kind]|[I.type]", I, kind) || null

DECLARE_SHARED_CACHE(item_constraint, GLOBAL_PROC_REF(build_item_constraint), SC_NEVER)

/// Builder for dq_constraint(): `I` is any instance of the type being compiled.
/proc/build_item_constraint(obj/item/I, kind)
	var/list/spec = I.constraint_spec(kind)
	return length(spec) ? dq_predicate_for("constraint:[kind]|[I.type]", spec, "[I.type] [kind]") : FALSE

/// Why `I`'s constraint of `kind` refuses `thing` (moved or worn by `actor`), or
/// null if it passes or there is no constraint.
/proc/dq_constraint_refusal(obj/item/I, kind, atom/thing, mob/actor, mob/mover = null)
	var/datum/entry/part/acceptance_plan/native_plan = dq_constraint_has_legacy_override(I, kind) ? null : acceptance_plan_for(I, kind)
	if(native_plan)
		var/mob/wearer = (kind == CONSTRAINT_FIT || kind == CONSTRAINT_EQUIP || kind == CONSTRAINT_SUIT_STORAGE) ? actor : null
		return acceptance_reason(I, kind, I, thing, wearer, mover || actor, wearer_is_actor = !isnull(wearer))
	var/datum/predicate/P = dq_constraint(I, kind)
	return P?.why_not(actor, thing, null)

/// Replace this instance's constraint of `kind` with `spec` (null: none).
/// `key` names the spec's contents: equal keys must mean equal specs, since
/// the compiled predicate is shared by key.
/obj/item/proc/set_constraint(kind, list/spec, key)
	var/datum/predicate/P = FALSE
	if(length(spec))
		P = dq_predicate_for("override:[kind]:[key]", spec, "[type] [kind] ([key])")
	LAZYSET(constraint_overrides, kind, P) // ALLOW(ownership): values are interned predicates from the shared dq_predicate_for cache (shared by key, never owned); state_exclude(d)
	tracked_changed(src, nameof(constraint_overrides))

/// Go back to the type's declared constraint of `kind`.
/obj/item/proc/clear_constraint(kind)
	LAZYREMOVE(constraint_overrides, kind)
	tracked_changed(src, nameof(constraint_overrides))

/// The type's declared spec for `kind` with some clauses dropped: those that
/// constrain PROP_SIZE_CLASS (`drop_size`) and/or a HOLD_ONLY type list
/// (`drop_types`). For building instance overrides on top of the type.
/obj/item/proc/declared_spec_without(kind, drop_size, drop_types)
	. = list()
	for(var/list/clause as anything in constraint_spec(kind))
		if(drop_size && clause[1] == PRED_OP_CMP && clause[3] == PROP_SIZE_CLASS)
			continue
		if(drop_types && clause[1] == PRED_OP_BECAUSE)
			var/list/inner = clause[2]
			if(inner[1] == PRED_OP_TYPE)
				continue
		. += list(clause)

/// Change what this holder takes, keeping the rest of its type's constraint.
/// `types`: a new HOLD_ONLY list (null keeps the type's). `max_size`: a new
/// size limit (null keeps the type's).
/obj/item/proc/restrict_hold(list/types, max_size)
	var/datum/entry/part/acceptance_plan/native_plan = table_of(src).acceptance_channels?[CONSTRAINT_HOLD]
	if(native_plan)
		var/list/parts = list()
		for(var/datum/entry/part/req/R as anything in native_plan.children)
			if(!isnull(max_size) && istype(R, /datum/entry/part/req/acceptance_leaf/max_size))
				continue
			if(!isnull(types) && istype(R, /datum/entry/part/req/acceptance_leaf/type) && !R.args["exclude"])
				continue
			parts += R
		if(!isnull(types))
			parts += req_acceptance_type(types, because = "it doesn't take that")
		if(!isnull(max_size))
			parts += req_acceptance_max_size(SIZE_CLASS(max_size), PROP_UNIT_SIZE_CLASS)
		set_native_constraint(CONSTRAINT_HOLD, acceptance(CONSTRAINT_HOLD, parts, mode = ACCEPTANCE_REPLACE))
		return
	var/list/spec = declared_spec_without(CONSTRAINT_HOLD, !isnull(max_size), !isnull(types))
	var/list/key = list("[type]")
	if(!isnull(types))
		spec += list(HOLD_ONLY(types))
		for(var/path in types)
			key += "[path]"
	if(!isnull(max_size))
		spec += list(HOLD_MAX_SIZE(max_size))
		key += "size=[max_size]"
	set_constraint(CONSTRAINT_HOLD, spec, jointext(key, ","))

/// Use `source`'s constraint of `kind` on this instance too (a rig's chest
/// piece takes what the rig's suit storage takes). No-op if it has none.
/obj/item/proc/adopt_constraint(kind, obj/item/source)
	var/datum/entry/part/acceptance_plan/native_plan = dq_constraint_has_legacy_override(source, kind) ? null : acceptance_plan_for(source, kind)
	if(native_plan)
		if(acceptance_declared(source, kind))
			set_native_constraint_plan(kind, native_plan)
		return
	var/datum/predicate/P = dq_constraint(source, kind)
	if(P)
		LAZYSET(constraint_overrides, kind, P) // ALLOW(ownership): the source item's interned predicate, shared by key from the dq_predicate_for cache
		tracked_changed(src, nameof(constraint_overrides))

/// Refit this item for `bodytypes` (the REQ_FITS_BODYTYPES list form), or
/// null to fit anyone.
/obj/item/proc/restrict_fit(list/bodytypes)
	if(!length(bodytypes))
		set_native_constraint(CONSTRAINT_FIT, acceptance(CONSTRAINT_FIT, mode = ACCEPTANCE_EMPTY))
		return
	set_native_constraint(CONSTRAINT_FIT, acceptance(CONSTRAINT_FIT, fits((bodytypes[1] == "exclude") ? bodytypes.Copy(2) : bodytypes, exclude = bodytypes[1] == "exclude"), mode = ACCEPTANCE_REPLACE))

/// The body-type list `I`'s fit constraint was declared with, or null when it
/// fits anyone. For refit tools and the worn-sprite test.
/proc/dq_fit_bodytypes(obj/item/I)
	READS_FROM(I)
	var/datum/entry/part/acceptance_plan/native_plan = dq_constraint_has_legacy_override(I, CONSTRAINT_FIT) ? null : acceptance_plan_for(I, CONSTRAINT_FIT)
	if(native_plan)
		for(var/datum/entry/part/req/acceptance_leaf/fit/F as anything in native_plan.children)
			var/list/bodytypes = F.args["bodytypes"]
			var/list/result = bodytypes ? bodytypes.Copy() : list()
			if(F.args["exclude"])
				result.Insert(1, "exclude")
			return length(result) ? result : null
		return null
	var/datum/predicate/P = dq_constraint(I, CONSTRAINT_FIT)
	if(!P)
		return null
	var/datum/pred_node/fits/node = P.root
	return istype(node) ? node.bodytypes : null

/// Two specs as one (either may be null): for overrides that add to the
/// parent's constraint, `return dq_spec_join(..(), list(REQ_...))`.
/proc/dq_spec_join(list/a, list/b)
	. = list()
	if(a)
		. += a
	if(b)
		. += b

/// Native presence wins even when explicitly empty; fallback only for unmigrated channels.
/proc/dq_constraint_present(obj/item/I, kind)
	var/datum/entry/part/acceptance_plan/P = dq_constraint_has_legacy_override(I, kind) ? null : acceptance_plan_for(I, kind)
	if(P)
		return acceptance_declared(I, kind)
	return !isnull(dq_constraint(I, kind))

/// Complete native dependencies; legacy fallback remains only until its table migrates.
/proc/dq_constraint_read_keys(obj/item/I, kind, atom/movable/thing, mob/actor, mob/mover = null)
	var/datum/entry/part/acceptance_plan/P = dq_constraint_has_legacy_override(I, kind) ? null : acceptance_plan_for(I, kind)
	if(P)
		var/mob/wearer = (kind == CONSTRAINT_FIT || kind == CONSTRAINT_EQUIP || kind == CONSTRAINT_SUIT_STORAGE) ? actor : null
		return acceptance_read_keys(I, kind, I, thing, wearer, mover || actor, wearer_is_actor = !isnull(wearer))
	return list(list(I, nameof(I.constraint_overrides)))
