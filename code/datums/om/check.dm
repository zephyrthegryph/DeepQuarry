// Object-model core: checks (doc/rewrite/object_model_core.md section H).
//
// A check spec is any of:
//   /datum/om/check/powered                   a check type, no parameter
//   CHECK(/datum/om/check/in_range, 1)         a parameterised check
//   list(/datum/om/check/in_range = 1)         the same, as a plain list
//   "machine_usable"                           a named check from a bundle's `checks`
//   ALL_OF(a, b), ANY_OF(a, b), NOT_OF(a)      combinators over specs
// Every spec compiles once to a cached instance, keyed by value, so equal
// specs share one instance. A combinator's depends_on is the union of its parts.
//
// Single-entity checks read `target` when given, else `actor`. Actor-side
// checks (holding, wearing, stat_at_most, ...) always read the actor.

/proc/om_check_get(spec, datum/om/registry/reg)
	reg = reg || om_registry()
	if(isnull(spec))
		return null
	if(istype(spec, /datum/om/check))
		return spec
	var/key = om_spec_key(spec, reg)
	if(!key)
		return null
	var/datum/om/check/C = reg.checks_cache[key]
	if(C)
		return C
	if(istext(spec))
		if(!reg.named_checks.Find(spec))
			return null
		// Guard against a name referring to itself.
		reg.checks_cache[key] = new /datum/om/check/combinator
		C = om_check_get(reg.named_checks[spec], reg)
		reg.checks_cache -= key
		if(!C)
			return null
		reg.checks_cache[key] = C
		return C
	if(ispath(spec, /datum/om/check))
		C = new spec
	else if(islist(spec))
		var/list/L = spec
		if(length(L) && istext(L[1]) && (L[1] in list("all", "any", "not")))
			var/datum/om/check/combinator/combo = new
			combo.op = L[1]
			combo.parts = list()
			for(var/i in 2 to length(L))
				var/datum/om/check/part = om_check_get(L[i], reg)
				if(!part)
					return null
				combo.parts += part
				combo.depends_on |= part.depends_on
			if(!length(combo.parts) || (combo.op == "not" && length(combo.parts) != 1))
				return null
			C = combo
		else if(length(L) == 1 && ispath(L[1], /datum/om/check))
			var/path = L[1]
			C = new path
			C.arg = L[path]
		else
			return null
	else
		return null
	C.key = key
	reg.checks_cache[key] = C
	return C

/// A value key for a spec: equal specs get equal keys.
/proc/om_spec_key(spec, datum/om/registry/reg)
	if(istext(spec))
		return "name:[spec]"
	if(ispath(spec))
		return "[spec]"
	if(!islist(spec))
		return null
	var/list/L = spec
	if(length(L) && istext(L[1]) && (L[1] in list("all", "any", "not")))
		var/list/parts = list()
		for(var/i in 2 to length(L))
			var/part = om_spec_key(L[i], reg)
			if(!part)
				return null
			parts += part
		return "[L[1]]([jointext(parts, ",")])"
	if(length(L) == 1 && ispath(L[1]))
		var/arg = L[L[1]]
		return "[L[1]]=[islist(arg) ? json_encode(arg) : "[arg]"]"
	return null

/// Why `spec` fails for actor/target, or null if it passes.
/proc/om_why_not(spec, datum/actor, datum/target)
	var/datum/om/check/C = om_check_get(spec)
	if(!C)
		return "malformed check"
	return C.why_not(actor, target)

/proc/om_can(spec, datum/actor, datum/target)
	return isnull(om_why_not(spec, actor, target))

/datum/om/check/combinator
	var/op
	var/list/parts

/datum/om/check/combinator/why_not(datum/actor, datum/target)
	switch(op)
		if("all")
			for(var/datum/om/check/part as anything in parts)
				var/reason = part.why_not(actor, target)
				if(!isnull(reason))
					return reason
			return null
		if("any")
			var/first
			for(var/datum/om/check/part as anything in parts)
				var/reason = part.why_not(actor, target)
				if(isnull(reason))
					return null
				first = first || reason
			return first
		if("not")
			var/datum/om/check/part = parts[1]
			return isnull(part.why_not(actor, target)) ? "not allowed" : null
	return "malformed check"

/// The parameter, resolved against the actor (FROM_VAR etc).
/datum/om/check/proc/param(datum/actor)
	return om_read(actor, arg)

/// The one entity a single-entity check reads.
/datum/om/check/proc/subject(datum/actor, datum/target)
	return target || actor
