// Unit-aware native operation requirements. Sources are explicit action roles.
/proc/req_measure(property, compare, value, unit, of = ON_TARGET, because = null, datum/property_registry/registry = null)
	return req_numeric_make(property, compare, value, unit, of, null, null, null, null, null, FALSE, because, registry)

/proc/req_property_compare(property, compare, other_property, of = ON_TARGET, other_of = ON_HELD, because = null, datum/property_registry/registry = null)
	return req_numeric_make(property, compare, null, null, of, other_property, other_of, null, null, null, FALSE, because, registry)

/proc/req_band(property, lo, lo_unit, hi, hi_unit, of = ON_TARGET, outside = FALSE, because = null, datum/property_registry/registry = null)
	return req_numeric_make(property, null, null, lo_unit, of, null, null, lo, hi, hi_unit, outside, because, registry)

/proc/req_numeric_make(property, compare, value, unit, of, other_property, other_of, lo, hi, hi_unit, outside, because, datum/property_registry/registry)
	if(!isnull(because) && !istext(because) && !ispath(because, /datum/msg) && !istype(because, /datum/msg))
		CRASH("numeric requirement because must be text or a refusal message")
	if(!registry)
		registry = dq_property_registry()
	if(QDELETED(registry))
		CRASH("numeric requirement registry was deleted")
	var/datum/property_def/D = registry.defs[property]
	if(!D || D.kind != PROP_KIND_MEASURE)
		CRASH("numeric requirement needs a known measure property")
	if(!(of in list(ON_HOLDER, ON_ACTOR, ON_TARGET, ON_HELD, ON_WEARER, ON_MOVER, ON_DESTINATION)))
		CRASH("numeric requirement has an unsupported source role")
	if(other_property)
		var/datum/property_def/E = registry.defs[other_property]
		if(!E || E.kind != PROP_KIND_MEASURE || D.unit != E.unit || !(other_of in list(ON_HOLDER, ON_ACTOR, ON_TARGET, ON_HELD, ON_WEARER, ON_MOVER, ON_DESTINATION)))
			CRASH("numeric comparison must use compatible measure units and valid source roles")
	else if(!isnull(lo))
		if(!isnum(lo) || !isnum(hi) || unit != D.unit || hi_unit != D.unit || lo > hi)
			CRASH("numeric band requires ordered bounds with explicit matching units")
	else if(!isnum(value) || unit != D.unit)
		CRASH("numeric comparison requires a numeric value and explicit matching unit")
	if(isnull(lo) && !(compare in list(SIM_COMPARE_LT, SIM_COMPARE_LTE, SIM_COMPARE_GT, SIM_COMPARE_GTE, SIM_COMPARE_EQ, SIM_COMPARE_NE)))
		CRASH("numeric requirement comparison is unknown")
	var/datum/entry/part/req/numeric/R = part_make(/datum/entry/part/req/numeric, list("property" = property, "compare" = compare, "value" = value, "unit" = D.unit, "of" = of, "other_property" = other_property, "other_of" = other_of, "lo" = lo, "hi" = hi, "outside" = outside, "because" = because, "registry_identity" = REF(registry)))
	if(R.registry_static != registry)
		rel_set(R, nameof(R.registry_static), registry)
	return R

/datum/entry/part/req/numeric
	part_name = "req_numeric"
	var/datum/property_registry/registry_static

CAPABILITIES(/datum/entry/part/req/numeric)
	ref_one(nameof(registry_static), /datum/property_registry)

/datum/entry/part/req/numeric/check(datum/act/op/A)
	var/reason = numeric_check(A)
	if(!isnull(reason) && !isnull(src.args["because"]))
		return req_reason_value(A, src.args["because"])
	return reason

/datum/entry/part/req/numeric/proc/numeric_check(datum/act/op/A)
	if(!registry_static || QDELETED(registry_static))
		return "numeric requirement registry unavailable"
	var/datum/thing = op_subject(A, src.args["of"])
	if(!thing)
		return numeric_requirement_missing_role(src.args["of"])
	var/property = src.args["property"]
	var/datum/property_def/D = registry_static.defs[property]
	var/current = registry_static.read_value(thing, property)
	if(isnull(current))
		return "[lowertext(D.name || D.id)] unknown"
	var/allowed
	var/limit = src.args["value"]
	if(!isnull(src.args["lo"]))
		allowed = (current >= src.args["lo"] && current <= src.args["hi"]) != !!src.args["outside"]
	else
		if(src.args["other_property"])
			var/datum/other = op_subject(A, src.args["other_of"])
			if(!other)
				return numeric_requirement_missing_role(src.args["other_of"])
			limit = registry_static.read_value(other, src.args["other_property"])
			if(isnull(limit))
				return "[lowertext(D.name || D.id)] unknown"
		allowed = simulation_compare(current, src.args["compare"], limit)
	if(allowed)
		return null
	var/role = src.args["of"]
	if(!isnull(src.args["lo"]))
		var/range = "[dq_format_measure(src.args["lo"], D.unit)] to [dq_format_measure(src.args["hi"], D.unit)]"
		if(src.args["outside"])
			return "[lowertext(D.name || D.id)] must be outside [range], is [dq_format_measure(current, D.unit)]"
		return "[numeric_requirement_extreme_text(D, role, current > src.args["hi"])]: [dq_format_measure(current, D.unit)], must be [range]"
	return numeric_requirement_comparison_reason(D, role, current, src.args["compare"], limit)

/datum/entry/part/req/numeric/holds(datum/act/op/A)
	return isnull(check(A))
/datum/entry/part/req/numeric/refusal(datum/act/op/A)
	return check(A)

/datum/entry/part/req/numeric/read_keys(datum/act/op/A)
	// ref_one clears and publishes this real field when the borrowed registry dies.
	. = list(list(src, nameof(registry_static)))
	if(!registry_static || QDELETED(registry_static))
		return
	var/datum/thing = op_subject(A, src.args["of"])
	if(thing)
		. += registry_static.requirement_read_keys(thing, src.args["property"])
	if(src.args["other_property"])
		var/datum/other = op_subject(A, src.args["other_of"])
		if(other)
			. += registry_static.requirement_read_keys(other, src.args["other_property"])

/datum/property_registry/proc/requirement_read_keys(datum/thing, property)
	. = list()
	var/datum/property_provider/base = base_provider(thing.type, property)
	if(base)
		. += base.requirement_read_keys(thing)
	for(var/datum/property_provider/P as anything in contributors[property])
		if(istype(thing, P.applies_to))
			. += P.requirement_read_keys(thing)

/datum/property_provider/proc/requirement_read_keys(datum/thing)
	CRASH("property provider [type] needs its actual native dependency reader")

/proc/numeric_requirement_extreme_text(datum/property_def/D, role, high)
	var/word = high ? D.high_word : D.low_word
	if(word)
		if(role == ON_ACTOR)
			return "you are too [word]"
		if(role == ON_HELD)
			return "the held item is too [word]"
		return "too [word]"
	var/name = lowertext(D.name || D.id)
	var/direction = high ? "high" : "low"
	if(role == ON_ACTOR)
		return "your [name] is too [direction]"
	if(role == ON_HELD)
		return "the held item's [name] is too [direction]"
	return "[name] too [direction]"

/proc/numeric_requirement_comparison_reason(datum/property_def/D, role, current, compare, limit)
	var/shown = dq_format_measure(current, D.unit)
	var/bound = dq_format_measure(limit, D.unit)
	if(compare == SIM_COMPARE_EQ)
		return "[lowertext(D.name || D.id)] must be [bound], is [shown]"
	if(compare == SIM_COMPARE_NE)
		return "[lowertext(D.name || D.id)] must not be [bound]"
	var/high = compare == SIM_COMPARE_LT || compare == SIM_COMPARE_LTE
	var/prefix = numeric_requirement_extreme_text(D, role, high)
	if(current == limit)
		return "[prefix]: [shown], must be [high ? "below" : "above"] [bound]"
	return "[prefix]: [shown] [current > limit ? ">" : "<"] [bound]"

/// Invert the comparison rather than wrapping holds(): absent values still refuse.
/proc/req_measure_not(property, compare, value, unit, of = ON_TARGET, because = null, datum/property_registry/registry = null)
	return req_measure(property, simulation_invert_compare(compare), value, unit, of, because, registry)

/proc/numeric_requirement_missing_role(role)
	switch(role)
		if(ON_WEARER)
			return "needs a wearer"
		if(ON_MOVER)
			return "needs a mover"
		if(ON_DESTINATION)
			return "needs a destination"
	return "needs something in hand"
