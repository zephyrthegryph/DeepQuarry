// Unit-aware property conditions for simulation rules.
// Unit-aware simulation conditions. No library/content/provider subclass references.
#define SIM_COMPARE_GT ">"
#define SIM_COMPARE_GTE ">="
#define SIM_COMPARE_LT "<"
#define SIM_COMPARE_LTE "<="
#define SIM_COMPARE_EQ "=="
#define SIM_COMPARE_NE "!="
#define SIM_CONDITION_MEASURE "measure"
#define SIM_CONDITION_COMPARE "compare"
#define SIM_CONDITION_BAND "band"
#define SIM_CONDITION_GROUP "group"

// Immutable flyweights: declarations own no temporary leaves.
#define SIM_ENTRY_KIND "simulation_property_condition"
/proc/cond_measure(property, compare, value, unit, subject = "holder")
	return entry_make(SIM_ENTRY_KIND, null, list("leaf_kind" = SIM_CONDITION_MEASURE, "subject" = subject, "property" = property, "compare" = compare, "value" = value, "unit" = unit))
/proc/cond_compare(property, compare, other_property)
	return entry_make(SIM_ENTRY_KIND, null, list("leaf_kind" = SIM_CONDITION_COMPARE, "subject" = "holder", "property" = property, "compare" = compare, "other_property" = other_property))
/proc/cond_band(property, lo, lo_unit, hi, hi_unit)
	return entry_make(SIM_ENTRY_KIND, null, list("leaf_kind" = SIM_CONDITION_BAND, "subject" = "holder", "property" = property, "lo" = lo, "lo_unit" = lo_unit, "hi" = hi, "hi_unit" = hi_unit))

// Immutable compiled nodes. The compiled root owns every child; declarations
// are interned entries shared by declarations and are never deleted.
/datum/simulation_condition
	var/list/children
	var/any = FALSE
	var/kind
	var/property
	var/compare
	var/value
	var/other_property
	var/lo
	var/hi
	var/outside = FALSE
	var/datum/property_registry/registry_static

CAPABILITIES(/datum/simulation_condition)
	owns_many(nameof(children))
	ref_one(nameof(registry_static), /datum/property_registry)

/datum/simulation_condition/proc/holds(datum/holder)
	if(!registry_static || QDELETED(registry_static))
		return FALSE
	if(kind == SIM_CONDITION_GROUP)
		for(var/datum/simulation_condition/C as anything in children)
			var/held = C.holds(holder)
			if(any && held)
				return TRUE
			if(!any && !held)
				return FALSE
		return !any
	if(!holder)
		return FALSE
	var/current = registry_static.read_value(holder, property)
	if(isnull(current))
		return FALSE
	if(kind == SIM_CONDITION_BAND)
		return (current >= lo && current <= hi) != outside
	var/level = value
	if(kind == SIM_CONDITION_COMPARE)
		level = registry_static.read_value(holder, other_property)
		if(isnull(level))
			return FALSE
	return simulation_compare(current, compare, level)

// Complete metadata traversal is independent of short-circuit evaluation.
// The rule compiler may visit these same nodes; no second declaration parser.
/datum/simulation_condition/proc/leaves()
	if(kind != SIM_CONDITION_GROUP)
		return list(src)
	. = list()
	for(var/datum/simulation_condition/C as anything in children)
		. += C.leaves()

/proc/simulation_compare(a, compare, b)
	switch(compare)
		if(SIM_COMPARE_GT)
			return a > b
		if(SIM_COMPARE_GTE)
			return a >= b
		if(SIM_COMPARE_LT)
			return a < b
		if(SIM_COMPARE_LTE)
			return a <= b
		if(SIM_COMPARE_EQ)
			return a == b
		if(SIM_COMPARE_NE)
			return a != b
	return FALSE

/proc/simulation_invert_compare(compare)
	switch(compare)
		if(SIM_COMPARE_GT)
			return SIM_COMPARE_LTE
		if(SIM_COMPARE_GTE)
			return SIM_COMPARE_LT
		if(SIM_COMPARE_LT)
			return SIM_COMPARE_GTE
		if(SIM_COMPARE_LTE)
			return SIM_COMPARE_GT
		if(SIM_COMPARE_EQ)
			return SIM_COMPARE_NE
		if(SIM_COMPARE_NE)
			return SIM_COMPARE_EQ
	return null

/datum/simulation_condition_compiler
	var/datum/property_registry/registry_static
	var/list/errors

/datum/simulation_condition_compiler/New(datum/property_registry/registry)
	..()
	rel_set(src, nameof(registry_static), registry ? registry : dq_property_registry())

/datum/simulation_condition_compiler/proc/error(text)
	LAZYADD(errors, text)

/datum/simulation_condition_compiler/proc/measure(property)
	if(!registry_static || QDELETED(registry_static))
		error("property registry is unavailable")
		return null
	var/datum/property_def/D = LAZYACCESS(registry_static.defs, property)
	if(!D)
		error("unknown property [property]")
		return null
	if(D.kind != PROP_KIND_MEASURE)
		error("[property] is a tag, not a measure")
		return null
	return D

/datum/simulation_condition_compiler/proc/unit_matches(datum/property_def/D, value, unit)
	if(!isnum(value))
		error("compares [D.id] with [value], which is not a number")
		return FALSE
	if(unit != D.unit)
		error("compares [D.id] ([D.unit]) with [value] [isnull(unit) ? "(no unit)" : unit]")
		return FALSE
	return TRUE

/datum/simulation_condition_compiler/proc/compile(spec, negate = FALSE)
	if(islist(spec))
		var/list/L = spec
		if(!length(L))
			error("empty simulation condition group")
			return null
		var/form = L[1]
		if(form == "not")
			if(length(L) != 2)
				error("cond_not needs one condition")
				return null
			return compile(L[2], !negate)
		if(!(form in list("all", "any")))
			error("unsupported simulation condition group [form]")
			return null
		var/datum/simulation_condition/G = new
		rel_set(G, nameof(G.registry_static), registry_static)
		G.any = (form == "any") != negate
		// Explicit group kind preserves empty AND/OR without an allocated owned list.
		G.kind = SIM_CONDITION_GROUP
		for(var/i in 2 to length(L))
			var/datum/simulation_condition/C = compile(L[i], negate)
			if(!C)
				qdel(G)
				return null
			rel_add(G, nameof(G.children), C)
		return G
	if(!istype(spec, /datum/entry))
		error("simulation conditions need structured property leaves, not opaque callbacks")
		return null
	var/datum/entry/S = spec
	if(S.kind != SIM_ENTRY_KIND)
		error("simulation conditions need structured property leaves")
		return null
	if(S.args["subject"] != "holder")
		error("clauses must read the object; a rule has no actor or held item")
		return null
	var/datum/property_def/D = measure(S.args["property"])
	if(!D)
		return null
	var/datum/simulation_condition/C = new
	rel_set(C, nameof(C.registry_static), registry_static)
	C.kind = S.args["leaf_kind"]
	C.property = S.args["property"]
	if(S.args["leaf_kind"] == SIM_CONDITION_BAND)
		if(!unit_matches(D, S.args["lo"], S.args["lo_unit"]) || !unit_matches(D, S.args["hi"], S.args["hi_unit"]))
			qdel(C)
			return null
		if(S.args["lo"] > S.args["hi"])
			error("condition band on [D.id] has its bounds reversed")
			qdel(C)
			return null
		C.lo = S.args["lo"]
		C.hi = S.args["hi"]
		C.outside = negate
		return C
	if(isnull(simulation_invert_compare(S.args["compare"])))
		error("unknown comparison [S.args["compare"]]")
		qdel(C)
		return null
	C.compare = negate ? simulation_invert_compare(S.args["compare"]) : S.args["compare"]
	if(S.args["leaf_kind"] == SIM_CONDITION_MEASURE)
		if(!unit_matches(D, S.args["value"], S.args["unit"]))
			qdel(C)
			return null
		C.value = S.args["value"]
		return C
	if(S.args["leaf_kind"] == SIM_CONDITION_COMPARE)
		var/datum/property_def/B = measure(S.args["other_property"])
		if(!B)
			qdel(C)
			return null
		if(B.unit != D.unit)
			error("compares [D.id] ([D.unit]) with [B.id] ([B.unit])")
			qdel(C)
			return null
		C.other_property = S.args["other_property"]
		return C
	error("unknown simulation condition leaf [S.args["leaf_kind"]]")
	qdel(C)
	return null


CAPABILITIES(/datum/simulation_condition_compiler)
	ref_one(nameof(registry_static), /datum/property_registry)

/datum/simulation_condition/proc/dependency_properties()
	. = list()
	for(var/datum/simulation_condition/N as anything in leaves())
		. |= N.property
		if(N.kind == SIM_CONDITION_COMPARE)
			. |= N.other_property
