// Item admission uses immutable native acceptance plans and pure requirements.
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
	var/mob/wearer = (kind == CONSTRAINT_FIT || kind == CONSTRAINT_EQUIP || kind == CONSTRAINT_SUIT_STORAGE) ? actor : null
	return acceptance_reason(I, kind, I, thing, wearer, mover || actor, wearer_is_actor = !isnull(wearer))

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
		parts += req_acceptance_type(types, because = "it doesn't take that")
	if(!isnull(max_size))
		parts += req_acceptance_max_size(max_size, PROP_UNIT_SIZE_CLASS)
	set_native_constraint(CONSTRAINT_HOLD, acceptance(CONSTRAINT_HOLD, parts, mode = length(parts) ? ACCEPTANCE_REPLACE : ACCEPTANCE_EMPTY))

/// Only an actual source constraint replaces the receiver's existing policy.
/obj/item/proc/adopt_constraint(kind, obj/item/source)
	if(acceptance_declared(source, kind))
		set_native_constraint_plan(kind, acceptance_plan_for(source, kind))

/// Null or an empty list explicitly removes a type's fitting restriction.
/obj/item/proc/restrict_fit(list/bodytypes)
	if(!length(bodytypes))
		set_native_constraint(CONSTRAINT_FIT, acceptance(CONSTRAINT_FIT, mode = ACCEPTANCE_EMPTY))
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
	var/mob/wearer = (kind == CONSTRAINT_FIT || kind == CONSTRAINT_EQUIP || kind == CONSTRAINT_SUIT_STORAGE) ? actor : null
	return acceptance_read_keys(I, kind, I, thing, wearer, mover || actor, wearer_is_actor = !isnull(wearer))
