// Native immutable item admission declarations and per-instance overrides.

/obj/item
	/// CONSTRAINT_* -> immutable native override plans; null means inherit.
	var/list/constraint_overrides

TRACKED(/obj/item, constraint_overrides)

// Overrides are immutable shared native plan entries, never owned.
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

/// Null allows; the original ordered native refusal is otherwise retained.
/proc/dq_constraint_refusal(obj/item/I, kind, atom/thing, mob/actor, mob/mover = null)
	var/mob/wearer = (kind == CONSTRAINT_FIT || kind == CONSTRAINT_EQUIP || kind == CONSTRAINT_SUIT_STORAGE) ? actor : null
	return acceptance_reason(I, kind, I, thing, wearer, isnull(mover) ? actor : mover, wearer_is_actor = !isnull(wearer))

/// Clearing an instance override restores the inherited declaration.
/obj/item/proc/clear_constraint(kind)
	var/list/next = constraint_overrides ? constraint_overrides.Copy() : list()
	next -= kind
	set_constraint_overrides(length(next) ? next : null)

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
	var/list/new_parts = list()
	if(!isnull(types))
		new_parts += req_acceptance_type(types, because = "it doesn't take that")
	if(!isnull(max_size))
		new_parts += req_acceptance_max_size(SIZE_CLASS(max_size), PROP_UNIT_SIZE_CLASS)
	set_native_constraint(CONSTRAINT_HOLD, acceptance(CONSTRAINT_HOLD, new_parts, mode = ACCEPTANCE_REPLACE))

/// Snapshot the source's immutable declared plan; an absent source remains a no-op.
/obj/item/proc/adopt_constraint(kind, obj/item/source)
	if(acceptance_declared(source, kind))
		set_native_constraint_plan(kind, acceptance_plan_for(source, kind))

/obj/item/proc/restrict_fit(list/bodytypes)
	if(!length(bodytypes))
		set_native_constraint(CONSTRAINT_FIT, acceptance(CONSTRAINT_FIT, mode = ACCEPTANCE_EMPTY))
		return
	set_native_constraint(CONSTRAINT_FIT, acceptance(CONSTRAINT_FIT, fits((bodytypes[1] == "exclude") ? bodytypes.Copy(2) : bodytypes, exclude = bodytypes[1] == "exclude"), mode = ACCEPTANCE_REPLACE))

/// The body-type list `I`'s fit constraint was declared with, or null when it
/// fits anyone. For refit tools and the worn-sprite test.
/proc/dq_fit_bodytypes(obj/item/I)
	READS_FROM(I)
	var/datum/entry/part/acceptance_plan/native_plan = acceptance_plan_for(I, CONSTRAINT_FIT)
	if(native_plan)
		for(var/datum/entry/part/req/acceptance_leaf/fit/F as anything in native_plan.children)
			var/list/bodytypes = F.args["bodytypes"]
			var/list/result = bodytypes ? bodytypes.Copy() : list()
			if(F.args["exclude"])
				result.Insert(1, "exclude")
			return length(result) ? result : null
		return null
	return null

/// Explicit empty stays distinct from an inherited declaration, including suit-storage presence.
/proc/dq_constraint_present(obj/item/I, kind)
	return acceptance_declared(I, kind)

/proc/dq_constraint_read_keys(obj/item/I, kind, atom/movable/thing, mob/actor, mob/mover = null)
	var/mob/wearer = (kind == CONSTRAINT_FIT || kind == CONSTRAINT_EQUIP || kind == CONSTRAINT_SUIT_STORAGE) ? actor : null
	return acceptance_read_keys(I, kind, I, thing, wearer, isnull(mover) ? actor : mover, wearer_is_actor = !isnull(wearer))
