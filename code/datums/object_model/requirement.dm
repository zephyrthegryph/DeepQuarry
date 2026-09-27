// Object-model requirements share P2 predicate semantics. A requirement may
// supply a P2 spec, or override check() for a domain-specific condition.
/datum/object_model/requirement
	var/list/predicate_spec
	var/list/depends_on
	/// Local tracked groups that can change this requirement. Zero means unknown.
	var/change_mask = 0
	var/failure_message = "The requirement is not met"
	var/datum/predicate/compiled_predicate
	var/list/errors

/datum/object_model/requirement/proc/compile()
	errors = list()
	if(predicate_spec)
		compiled_predicate = new
		compiled_predicate.name = "object-model requirement [type]"
		compiled_predicate.spec = predicate_spec
		if(!compiled_predicate.compile())
			errors += compiled_predicate.errors
			compiled_predicate = null
	if(!length(errors))
		errors = null
	return !errors

/// Null on success, otherwise a stable explanation for UI and task feedback.
/datum/object_model/requirement/proc/why_not(datum/source, mob/actor, atom/target, obj/item/held)
	if(compiled_predicate)
		return compiled_predicate.why_not(actor, target, held)
	return check(source, actor, target, held) ? null : failure_message

/datum/object_model/requirement/proc/check(datum/source, mob/actor, atom/target, obj/item/held)
	return TRUE

/// Shared DEF singleton; callers never mutate its authored configuration.
/proc/om_requirement(path)
	if(!ispath(path, /datum/object_model/requirement))
		return null
	var/static/list/cache = list()
	var/datum/object_model/requirement/result = cache[path]
	if(!result)
		result = new path
		if(!result.compile())
			CRASH("object-model requirement [path]: [jointext(result.errors, "; ")]")
		cache[path] = result
	return result

/// A synchronous check accumulator. Deferred work must rerun it at commit.
/datum/object_model/check
	var/failure
	var/list/dependencies

/datum/object_model/check/proc/require(condition, message, list/depends_on)
	if(failure)
		return FALSE
	if(depends_on)
		if(!dependencies)
			dependencies = list()
		dependencies |= depends_on
	if(!condition)
		failure = message || "The requirement is not met"
	return !failure

/datum/object_model/check/proc/require_type(path, datum/source, mob/actor, atom/target, obj/item/held)
	if(failure)
		return FALSE
	var/datum/object_model/requirement/R = om_requirement(path)
	if(!R)
		failure = "Unknown requirement [path]"
		return FALSE
	if(R.depends_on)
		if(!dependencies)
			dependencies = list()
		dependencies |= R.depends_on
	failure = R.why_not(source, actor, target, held)
	return !failure

/datum/object_model/check/proc/predicate(key, list/spec, mob/actor, atom/target, obj/item/held)
	if(failure)
		return FALSE
	var/datum/predicate/P = dq_predicate_for(key, spec, "object-model check [key]")
	if(!P)
		failure = "Invalid predicate"
		return FALSE
	failure = P.why_not(actor, target, held)
	return !failure

/datum/object_model/check/proc/adjacent(atom/a, atom/b)
	return require(a && b && a.z == b.z && get_dist(a, b) <= 1, "You must be adjacent")

/datum/object_model/check/proc/in_range(atom/a, atom/b, tiles)
	return require(a && b && a.z == b.z && isnum(tiles) && tiles >= 0 && get_dist(a, b) <= tiles, "That is out of range")

/datum/object_model/check/proc/same_z(atom/a, atom/b)
	return require(a && b && a.z == b.z, "That is on another level")

/datum/object_model/check/proc/holding(mob/user, obj/item/item)
	return require(user && item && (item in user.contents), "You are not holding that")

/datum/object_model/check/proc/hand_empty(mob/user)
	return require(user && !user.get_active_held_item(), "Your active hand must be empty")

/datum/object_model/check/proc/value_between(value, minimum, maximum)
	return require(isnum(value) && value >= minimum && value <= maximum, "Value is out of range")

/datum/object_model/check/proc/unchanged(datum/entity, revision)
	return require(entity && !QDELETED(entity) && entity.om_state?.revision == revision, "The target changed")
