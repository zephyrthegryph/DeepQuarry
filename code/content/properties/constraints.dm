// Item admission uses immutable native acceptance plans and pure requirements.
//
// What an item type declares about its holders and wearers (admission.md wave 8: content names what it means; the channel is the engine's):
//	fits_as(FIT_X)          who can wear it: a fit category (fit_categories.dm)
//	fits_anyone()           anyone can wear it (clears an inherited fit)
//	suit_storage(list(...)) what a suit's storage slot takes
//	no_suit_storage()       a suit with no suit storage (clears an inherited one)
//	holder_takes(reqs...)   what a holster, gripper or holder takes
/obj/item
	/// CONSTRAINT_* -> an immutable instance-specific native plan; null inherits.
	var/list/constraint_overrides

/obj/item/acceptance_overrides()
	return constraint_overrides

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

/// A query retains the wearer independently from the actual mover.
/proc/dq_constraint_refusal(obj/item/I, kind, atom/thing, mob/actor, mob/mover = null)
	var/mob/wearer = (kind == CONSTRAINT_FIT || kind == CONSTRAINT_SUIT_STORAGE) ? actor : null
	return reason_text(acceptance_reason(I, kind, I, thing, wearer, mover || actor))

/obj/item/proc/clear_constraint(kind)
	remove_constraint_overrides(kind)

/// Override the type's holder admission while retaining its other requirements.
/obj/item/proc/restrict_hold(list/types, max_size)
	var/datum/entry/part/acceptance_plan/native_plan = table_of(src).acceptance_channels?[CONSTRAINT_HOLD]
	var/list/parts = list()
	for(var/datum/entry/part/req/R as anything in native_plan?.children)
		if(!isnull(max_size) && istype(R, /datum/entry/part/req/acceptance_leaf/max_size))
			continue
		if(!isnull(types) && istype(R, /datum/entry/part/req/acceptance_leaf/type) && !R.args["exclude"])
			continue
		parts += R
	if(!isnull(types))
		parts += req_type(types, because = MSG(slot/doesnt_take))
	if(!isnull(max_size))
		parts += req_max_size(max_size, PROP_UNIT_SIZE_CLASS)
	set_native_constraint(CONSTRAINT_HOLD, holder_takes(parts))

/// Only an actual source constraint replaces the receiver's existing policy.
/obj/item/proc/adopt_constraint(kind, obj/item/source)
	if(acceptance_declared(source, kind))
		set_native_constraint_plan(kind, acceptance_plan_for(source, kind))

/// Null or an empty list explicitly removes a type's fitting restriction.
/obj/item/proc/restrict_fit(list/bodytypes)
	if(!length(bodytypes))
		set_native_constraint(CONSTRAINT_FIT, fits_anyone())
		return
	set_native_constraint(CONSTRAINT_FIT, acceptance(CONSTRAINT_FIT, fits((bodytypes[1] == "exclude") ? bodytypes.Copy(2) : bodytypes, exclude = bodytypes[1] == "exclude"), mode = ACCEPTANCE_REPLACE))

/proc/dq_fit_bodytypes(obj/item/I)
	READS_FROM(I)
	var/datum/entry/part/acceptance_plan/native_plan = acceptance_plan_for(I, CONSTRAINT_FIT)
	for(var/datum/entry/part/req/acceptance_leaf/fit/F as anything in native_plan?.children)
		var/list/bodytypes = F.args["bodytypes"]
		var/list/result = bodytypes ? bodytypes.Copy() : list()
		if(F.args["exclude"])
			result.Insert(1, "exclude")
		return length(result) ? result : null
	return null

/proc/dq_constraint_present(obj/item/I, kind)
	return acceptance_declared(I, kind)

/proc/dq_constraint_read_keys(obj/item/I, kind, atom/movable/thing, mob/actor, mob/mover = null)
	var/mob/wearer = (kind == CONSTRAINT_FIT || kind == CONSTRAINT_SUIT_STORAGE) ? actor : null
	return acceptance_read_keys(I, kind, I, thing, wearer, mover || actor)

/// Who can wear this item type: one fit category (fit_categories.dm). Replaces any inherited fit.
/proc/fits_as(category)
	RETURN_TYPE(/datum/entry)
	return acceptance(CONSTRAINT_FIT, fits_category(category), mode = ACCEPTANCE_REPLACE)

/// Anyone can wear this item type: clears an inherited fit.
/proc/fits_anyone()
	RETURN_TYPE(/datum/entry)
	return acceptance(CONSTRAINT_FIT, mode = ACCEPTANCE_EMPTY)

/// What this suit type's storage slot takes: a type list (refused with "it doesn't take that"). Replaces an inherited one.
/proc/suit_storage(types)
	RETURN_TYPE(/datum/entry)
	return acceptance(CONSTRAINT_SUIT_STORAGE, req_type(types, because = MSG(slot/doesnt_take)), mode = ACCEPTANCE_REPLACE)

/// This suit type has no suit storage: clears an inherited one.
/proc/no_suit_storage()
	RETURN_TYPE(/datum/entry)
	return acceptance(CONSTRAINT_SUIT_STORAGE, mode = ACCEPTANCE_EMPTY)

/// What this holder type (a holster, a gripper) takes: requirements, all of which must pass. Replaces an inherited rule.
/proc/holder_takes(p1, p2, p3, p4, p5, p6)
	RETURN_TYPE(/datum/entry)
	var/list/parts = entry_flatten(list(p1, p2, p3, p4, p5, p6))
	return acceptance(CONSTRAINT_HOLD, parts, mode = length(parts) ? ACCEPTANCE_REPLACE : ACCEPTANCE_EMPTY)
