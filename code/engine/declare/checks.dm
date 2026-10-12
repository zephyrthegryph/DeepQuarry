// Object-model core: checks (doc/rewrite/object_model_core.md section H).
//
// A check spec is any of:
//   /datum/requirement_definition/powered                   a check type, no parameter
//   CHECK(/datum/requirement_definition/in_range, 1)         a parameterised check
//   list(/datum/requirement_definition/in_range = 1)         the same, as a plain list
//   "machine_usable"                           a named check from a bundle's `checks`
//   ALL_OF(a, b), ANY_OF(a, b), NOT_OF(a)      combinators over specs
// Every spec compiles once to a cached instance, keyed by value, so equal
// specs share one instance. A combinator's depends_on is the union of its parts.
//
// Single-entity checks read `target` when given, else `actor`. Actor-side
// checks (holding, wearing, stat_at_most, ...) always read the actor.

/proc/definition_check_get(spec, datum/definition_registry/reg)
	reg = reg || definition_registry()
	if(isnull(spec))
		return null
	if(istype(spec, /datum/requirement_definition))
		return spec
	var/key = definition_spec_key(spec, reg)
	if(!key)
		return null
	var/datum/requirement_definition/C = reg.checks_cache[key]
	if(C)
		return C
	if(istext(spec))
		if(!reg.named_checks.Find(spec))
			return null
		// Guard against a name referring to itself.
		reg.checks_cache[key] = new /datum/requirement_definition/combinator
		C = definition_check_get(reg.named_checks[spec], reg)
		reg.checks_cache -= key
		if(!C)
			return null
		reg.checks_cache[key] = C
		return C
	if(ispath(spec, /datum/requirement_definition))
		C = new spec
	else if(islist(spec))
		var/list/L = spec
		if(length(L) && istext(L[1]) && (L[1] in list("all", "any", "not")))
			var/datum/requirement_definition/combinator/combo = new
			combo.op = L[1]
			combo.parts = list()
			for(var/i in 2 to length(L))
				var/datum/requirement_definition/part = definition_check_get(L[i], reg)
				if(!part)
					return null
				combo.parts += part
				combo.depends_on |= part.depends_on
			if(!length(combo.parts) || (combo.op == "not" && length(combo.parts) != 1))
				return null
			C = combo
		else if(length(L) == 1 && ispath(L[1], /datum/requirement_definition))
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
/proc/definition_spec_key(spec, datum/definition_registry/reg)
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
			var/part = definition_spec_key(L[i], reg)
			if(!part)
				return null
			parts += part
		return "[L[1]]([jointext(parts, ",")])"
	if(length(L) == 1 && ispath(L[1]))
		var/arg = L[L[1]]
		return "[L[1]]=[islist(arg) ? json_encode(arg) : "[arg]"]"
	return null

/// Why `spec` fails for actor/target, or null if it passes.
/proc/definition_why_not(spec, datum/actor, datum/target)
	var/datum/requirement_definition/C = definition_check_get(spec)
	if(!C)
		return "malformed check"
	return C.why_not(actor, target)

/proc/definition_can(spec, datum/actor, datum/target)
	return isnull(definition_why_not(spec, actor, target))

/datum/requirement_definition/combinator
	var/op
	var/list/parts

/// A narrow synchronous pooled context; endpoints are datums, never acting mobs.
/datum/act/eval/endpoint_query
	var/datum/target

/// Generated rows are mandatory: a proven constant callback has a rank-only row.
/datum/requirement_definition/proc/endpoint_query(datum/source, datum/target, list/pairs)
	var/list/row = GLOB.generated_reads_table["[type]::endpoint_reason"]
	if(!row)
		CRASH("[type] has no validated endpoint requirement descriptor")
	var/datum/act/eval/endpoint_query/A = take(/datum/act/eval/endpoint_query)
	A.holder = src
	A.source = source
	A.target = target
	var/previous_pure_depth = GLOB.op_pure_depth
	op_pure_begin()
	try
		pairs += native_query_read_pairs(row, list("holder" = src, "source" = source, "target" = target))
		. = endpoint_reason(A)
		if(!isnull(.))
			. = req_refusal_value(.)
	catch(var/exception/fault)
		GLOB.op_pure_depth = previous_pure_depth
		try
			A.release()
		catch(var/exception/cleanup_fault)
			dq_report_caught(cleanup_fault, "Endpoint context release failed while preserving its query fault")
		throw fault
	op_pure_end()
	A.release()

/datum/requirement_definition/combinator/endpoint_query(datum/source, datum/target, list/pairs)
	// Evaluate every part so a short-circuit cannot omit later dependency sources.
	var/list/reasons = list()
	for(var/datum/requirement_definition/part as anything in parts)
		reasons += list(part.endpoint_query(source, target, pairs))
	switch(op)
		if("all")
			for(var/reason in reasons)
				if(!isnull(reason))
					return reason
			return null
		if("any")
			for(var/reason in reasons)
				if(isnull(reason))
					return null
			return length(reasons) ? reasons[1] : null
		if("not")
			if(length(reasons) != 1)
				return "malformed check"
			return isnull(reasons[1]) ? "not allowed" : null
	return "malformed check"
/datum/requirement_definition/combinator/why_not(datum/actor, datum/target)
	switch(op)
		if("all")
			for(var/datum/requirement_definition/part as anything in parts)
				var/reason = part.why_not(actor, target)
				if(!isnull(reason))
					return reason
			return null
		if("any")
			var/first
			for(var/datum/requirement_definition/part as anything in parts)
				var/reason = part.why_not(actor, target)
				if(isnull(reason))
					return null
				first = first || reason
			return first
		if("not")
			var/datum/requirement_definition/part = parts[1]
			return isnull(part.why_not(actor, target)) ? "not allowed" : null
	return "malformed check"

/// The parameter, resolved against the actor (FROM_VAR etc).
/datum/requirement_definition/proc/param(datum/actor)
	return definition_read(actor, arg)

/// The one entity a single-entity check reads.
/datum/requirement_definition/proc/subject(datum/actor, datum/target)
	return target || actor
