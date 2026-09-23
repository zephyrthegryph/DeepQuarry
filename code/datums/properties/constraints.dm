// Constraints (doc/rewrite/rules.md §3).
//
// A constraint is a declared P2 predicate attached to a slot, a holder or an
// item. Every check returns a reason ("too big: size 3 > size 2", "it only
// fits Teshari", "you need a jumpsuit first"), through the same path whether
// the caller is legacy storage, legacy equip code or a C1 slot.
//
// Where they attach:
//   Slots    /datum/slot_def.accepts (a predicate type) and, for holders that
//            declare their own, slot_def.holder_constraint (a CONSTRAINT_* kind
//            read from the holder). Equip slots: equip_slots.dm.
//   Holders  hold_constraint() on storage and holsters: what goes inside.
//            suit_storage_constraint() on suits: what the suit-storage slot takes.
//   Items    fit_constraint(): whose body it fits (the old species_restricted).
//            equip_constraint(): what it needs of its wearer, in any slot.
//
// Declaring. Override the proc on the type and return a spec (a list of REQ_*
// clauses), or null for none. The proc runs once per type; the result is
// compiled and cached, so it must depend on the type only:
//
//   /obj/item/storage/pill_bottle/hold_constraint()
//       var/list/holds = list(/obj/item/reagent_containers/pill, /obj/item/dice)
//       return list(HOLD_ONLY(holds), HOLD_MAX_SIZE(ITEMSIZE_TINY))
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

/// The spec for constraint `kind` on this type. Called once per type.
/obj/item/proc/constraint_spec(kind)
	switch(kind)
		if(CONSTRAINT_HOLD)
			return hold_constraint()
		if(CONSTRAINT_SUIT_STORAGE)
			return suit_storage_constraint()
		if(CONSTRAINT_FIT)
			return fit_constraint()
		if(CONSTRAINT_EQUIP)
			return equip_constraint()
	CRASH("unknown constraint kind [kind]")

/// What this holder takes: a spec of clauses on PRED_TARGET, or null for anything.
/obj/item/proc/hold_constraint()
	return null

/// What a worn suit's suit-storage slot takes, or null for no suit storage.
/// PDAs and pens always fit a suit that has one.
/obj/item/proc/suit_storage_constraint()
	return null

/// Whose body this fits (PRED_ACTOR is the wearer), or null for anyone.
/obj/item/proc/fit_constraint()
	return null

/// What this needs of its wearer (PRED_ACTOR) in any equip slot, or null.
/obj/item/proc/equip_constraint()
	return null

/// The compiled constraint of `kind` for `I`: its instance override, else its
/// type's declaration. Null when there is none.
/proc/dq_constraint(obj/item/I, kind)
	if(I.constraint_overrides)
		var/override = I.constraint_overrides[kind]
		if(!isnull(override))
			return override || null
	var/static/list/cache = list()
	var/key = "[kind]|[I.type]"
	. = cache[key]
	if(isnull(.))
		var/list/spec = I.constraint_spec(kind)
		. = length(spec) ? dq_predicate_for("constraint:[key]", spec, "[I.type] [kind]") : FALSE
		cache[key] = .
	return . || null

/// Why `I`'s constraint of `kind` refuses `thing` (moved or worn by `actor`), or
/// null if it passes or there is no constraint.
/proc/dq_constraint_refusal(obj/item/I, kind, atom/thing, mob/actor)
	var/datum/predicate/P = dq_constraint(I, kind)
	return P?.why_not(actor, thing, null)

/// Replace this instance's constraint of `kind` with `spec` (null: none).
/// `key` names the spec's contents: equal keys must mean equal specs, since
/// the compiled predicate is shared by key.
/obj/item/proc/set_constraint(kind, list/spec, key)
	var/datum/predicate/P = FALSE
	if(length(spec))
		P = dq_predicate_for("override:[kind]:[key]", spec, "[type] [kind] ([key])")
	LAZYSET(constraint_overrides, kind, P)

/// Go back to the type's declared constraint of `kind`.
/obj/item/proc/clear_constraint(kind)
	LAZYREMOVE(constraint_overrides, kind)

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
	var/datum/predicate/P = dq_constraint(source, kind)
	if(P)
		LAZYSET(constraint_overrides, kind, P)

/// Refit this item for `bodytypes` (the REQ_FITS_BODYTYPES list form), or
/// null to fit anyone.
/obj/item/proc/restrict_fit(list/bodytypes)
	if(!length(bodytypes))
		set_constraint(CONSTRAINT_FIT, null, "none")
		return
	set_constraint(CONSTRAINT_FIT, list(REQ_FITS_BODYTYPES(bodytypes)), jointext(bodytypes, ","))

/// The body-type list `I`'s fit constraint was declared with, or null when it
/// fits anyone. For refit tools and the worn-sprite test.
/proc/dq_fit_bodytypes(obj/item/I)
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
