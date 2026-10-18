// Conditions of a transformation (doc/rewrite/proposals/transformations.md section 4, D11): reason-less booleans on the subject and its surroundings.
// A transformation is a world process, so a condition never refuses with a message; a rule that does not hold is simply not matched.
//
//   temperature_in(lo, hi)        the subject's temperature is within [lo, hi] (either end null: open). Also a watch band: the engine registers the
//                                 bounds on the subject's heat body and settles when one is crossed.
//   pressure_in(lo, hi)           the pressure of the air around the subject is within [lo, hi]; false when there is no air.
//   ambient_gas_over(gas, moles)  the air around the subject holds more than `moles` of the gas.   ambient_gas_under(gas, moles): fewer than.
//   subject_is(type)              the subject is the type (a slime extract): also an index key, so such a rule is only a candidate in that subject.
//   subject_var_over(name, n)     the subject's var `name` is above n (a slime extract with uses left). Read by name off the subject's atom; false when it has none.
//   appliance(flags)              the subject is a kitchen appliance of one of the types.
//   xform_all(c...), xform_any(c...), xform_not(c)    combinators.
//   TYPE_PROC_REF(/type, x)       a proc of the rule's type, called as x(subject), returning TRUE or FALSE (counted: a rule with one is not `plain`). A static block is
//                                 read in a global proc, so a plain PROC_REF(x) has no type to resolve against: name the type.
//
// These are not the op conditions of code/engine/parts/cond.dm (all_of(), any_of() read an op's act); a transformation has no act, so it has its own
// small set that reads a subject. Conditions never write.

/proc/xform_cond(kind, list/arguments = null, list/children = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_XCOND, kind, arguments, children)

/proc/temperature_in(lo = null, hi = null)
	RETURN_TYPE(/datum/entry)
	return xform_cond("temperature_in", list("lo" = lo, "hi" = hi))

/proc/pressure_in(lo = null, hi = null)
	RETURN_TYPE(/datum/entry)
	return xform_cond("pressure_in", list("lo" = lo, "hi" = hi))

/proc/ambient_gas_over(gas_id, moles)
	RETURN_TYPE(/datum/entry)
	return xform_cond("ambient_gas_over", list("gas" = gas_id, "moles" = moles))

/proc/ambient_gas_under(gas_id, moles)
	RETURN_TYPE(/datum/entry)
	return xform_cond("ambient_gas_under", list("gas" = gas_id, "moles" = moles))

/proc/subject_is(subject_type)
	RETURN_TYPE(/datum/entry)
	return xform_cond("subject_is", list("type" = subject_type))

/proc/subject_var_over(var_name, value)
	RETURN_TYPE(/datum/entry)
	return xform_cond("subject_var_over", list("var" = var_name, "value" = value))

/proc/appliance(flags)
	RETURN_TYPE(/datum/entry)
	return xform_cond("appliance", list("flags" = flags))

/proc/xform_all(...)
	RETURN_TYPE(/datum/entry)
	return xform_cond("all", null, entry_flatten(args))

/proc/xform_any(...)
	RETURN_TYPE(/datum/entry)
	return xform_cond("any", null, entry_flatten(args))

/proc/xform_not(condition)
	RETURN_TYPE(/datum/entry)
	return xform_cond("not", null, list(condition))

// ---- reading the subject ----

/// The physical thing a subject is: a reagents holder's atom, else the subject itself.
/proc/xform_atom_of(subject)
	if(istype(subject, /datum/reagents))
		var/datum/reagents/holder = subject
		return holder.my_atom
	return subject

/// The subject's temperature: a holder's (its atom's heat body), else the atom's.
/proc/xform_temperature_of(subject)
	if(istype(subject, /datum/reagents))
		var/datum/reagents/holder = subject
		return holder.get_temperature()
	var/atom/thing = subject
	return thing ? thing.get_temperature() : T20C

/// The air around the subject, or null.
/proc/xform_air_of(subject)
	var/atom/thing = xform_atom_of(subject)
	return thing?.return_air()

// ---- evaluating ----

/// TRUE when `ref` is a reference to a proc (TYPE_PROC_REF(/type, x), or the proc's name as text).
/proc/xform_is_proc_ref(ref)
	return istext(ref) || ispath(ref)

/// The name of the proc a reference names: `x` for TYPE_PROC_REF(/type, x) or for the text "x".
/proc/xform_proc_name(ref)
	if(isnull(ref))
		return null
	var/text = "[ref]"
	var/at = findlasttext(text, "/")
	return at ? copytext(text, at + 1) : text

/// Whether `cond` holds for `subject`. `X` is the rule asking (its type's procs answer a PROC_REF condition). A null condition holds.
/proc/xform_cond_holds(datum/xform/X, subject, cond)
	if(isnull(cond))
		return TRUE
	if(xform_is_proc_ref(cond))
		return !!call(X.owner_of(), xform_proc_name(cond))(subject)
	var/datum/entry/E = cond
	switch(E.key)
		if("temperature_in")
			var/temperature = xform_temperature_of(subject)
			var/lo = E.args["lo"]
			var/hi = E.args["hi"]
			return !((!isnull(lo) && temperature < lo) || (!isnull(hi) && temperature > hi))
		if("pressure_in")
			var/datum/gas_mixture/air = xform_air_of(subject)
			if(!air)
				return FALSE
			var/pressure = air.return_pressure()
			var/lo = E.args["lo"]
			var/hi = E.args["hi"]
			return !((!isnull(lo) && pressure < lo) || (!isnull(hi) && pressure > hi))
		if("ambient_gas_over")
			var/datum/gas_mixture/air = xform_air_of(subject)
			if(!air)
				return FALSE
			return LINDA_GAS_AMT(air, E.args["gas"]) > E.args["moles"]
		if("ambient_gas_under")
			var/datum/gas_mixture/air = xform_air_of(subject)
			if(!air)
				return FALSE
			return LINDA_GAS_AMT(air, E.args["gas"]) < E.args["moles"]
		if("subject_is")
			return istype(xform_atom_of(subject), E.args["type"])
		if("subject_var_over")
			var/atom/thing = xform_atom_of(subject)
			if(!thing || !(E.args["var"] in thing.vars))
				return FALSE
			return thing.vars[E.args["var"]] > E.args["value"]
		if("appliance")
			var/atom/thing = xform_atom_of(subject)
			if(!thing || !("appliancetype" in thing.vars))
				return FALSE
			return !!(thing.vars["appliancetype"] & E.args["flags"])
		if("all")
			for(var/child in E.children)
				if(!xform_cond_holds(X, subject, child))
					return FALSE
			return TRUE
		if("any")
			for(var/child in E.children)
				if(xform_cond_holds(X, subject, child))
					return TRUE
			return FALSE
		if("not")
			return !xform_cond_holds(X, subject, E.children[1])
	CRASH("unknown transformation condition [E.key]")

// ---- reading a condition at compile ----

/// Every temperature_in() bound of a condition, as list(lo, hi) rows: what the engine registers as watch bands.
/proc/xform_cond_bands(cond, list/into = null)
	. = into || list()
	if(isnull(cond) || xform_is_proc_ref(cond))
		return
	var/datum/entry/E = cond
	if(E.key == "temperature_in")
		. += list(list(E.args["lo"], E.args["hi"]))
		return
	for(var/child in E.children)
		xform_cond_bands(child, .)

/// The subject type a condition pins (a subject_is() at the top or under xform_all()), or null: the index key of a typed subject.
/proc/xform_cond_subject_type(cond)
	if(isnull(cond) || xform_is_proc_ref(cond))
		return null
	var/datum/entry/E = cond
	if(E.key == "subject_is")
		return E.args["type"]
	if(E.key == "all")
		for(var/child in E.children)
			var/found = xform_cond_subject_type(child)
			if(found)
				return found
	return null

/// TRUE when the condition (or any part) is a PROC_REF: such a rule is not `plain` (the closed-form fixed point may not take it).
/proc/xform_cond_calls_proc(cond)
	if(isnull(cond))
		return FALSE
	if(xform_is_proc_ref(cond))
		return TRUE
	var/datum/entry/E = cond
	for(var/child in E.children)
		if(xform_cond_calls_proc(child))
			return TRUE
	return FALSE

/// `a` and `b` as one condition holding when both do (a rule's `when` over its parent's).
/proc/xform_cond_and(a, b)
	if(isnull(a))
		return b
	if(isnull(b))
		return a
	return xform_all(a, b)

/// The air a rule's conditions need around its subject, as list(require_gas, rejects_gas, minimum_pressure, maximum_pressure), null where there is no
/// such condition: what a test atom builds before it settles the rule.
/proc/xform_cond_ambient(cond, list/into = null)
	. = into || list(null, null, null, null)
	if(isnull(cond) || xform_is_proc_ref(cond))
		return
	var/datum/entry/E = cond
	switch(E.key)
		if("ambient_gas_over")
			.[1] = E.args["gas"]
		if("ambient_gas_under")
			.[2] = E.args["gas"]
		if("pressure_in")
			.[3] = E.args["lo"]
			.[4] = E.args["hi"]
	for(var/child in E.children)
		xform_cond_ambient(child, .)
