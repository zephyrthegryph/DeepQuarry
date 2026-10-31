// Every var that declares a value schema (SCHEMA / TRACKED_SCHEMA) starts at a value the schema accepts (doc/rewrite/proposals/typed_values.md
// section 5). The analyzer checks assigned path literals and trusts calls; a plain write is not checked at run time, so this test is the check on
// defaults.
//
// initial(D.vars[name]) on a type path returns null (the vars list of a path is not readable), so a default is read off a shared prototype
// instance (dq_proto()): the declaring type, then (for atoms) a bounded sample of its subtypes. Nothing here knows which subtypes override the var, so the
// sample is evenly spaced through typesof() and capped; turfs and areas are skipped because making one outside the map is not safe. Instantiating
// every subtype of /atom or /mob would cost far more than the test is worth.
#define SCHEMA_FIT_SUBTYPE_SAMPLE 6

/datum/unit_test/dq_typed_values_defaults_fit

/proc/schema_fit_make(typepath)
	return new typepath()

/datum/unit_test/dq_typed_values_defaults_fit/Run()
	if(!GLOB.schemas_built)
		schemas_build()
	var/checked = 0
	var/skipped = 0
	for(var/declared_type in GLOB.schemas)
		var/list/by_var = GLOB.schemas[declared_type]
		var/list/types = list(declared_type)
		var/list/subtypes = list()
		for(var/type in subtypesof(declared_type))
			if(!ispath(declared_type, /atom) || ispath(type, /turf) || ispath(type, /area)) // only atom subtypes are sampled: other datums register watches and timers when made
				continue
			subtypes += type
		if(length(subtypes) <= SCHEMA_FIT_SUBTYPE_SAMPLE)
			types += subtypes
		else
			for(var/i in 1 to SCHEMA_FIT_SUBTYPE_SAMPLE)
				types += subtypes[round(i * length(subtypes) / SCHEMA_FIT_SUBTYPE_SAMPLE)]
		if(ispath(declared_type, /turf) || ispath(declared_type, /area))
			types = list() // the declaring type itself cannot be made safely; its vars are covered by the analyzer's literal check
		for(var/type in types)
			var/datum/result/made = safe_call(GLOBAL_PROC_REF(schema_fit_make), type) // a type whose constructor needs arguments cannot be sampled
			var/datum/proto = made.value
			if(!made.ok || !proto)
				skipped++
				continue
			for(var/var_name in by_var)
				if(!(var_name in proto.vars))
					continue
				var/datum/schema/S = by_var[var_name]
				var/value = initial(proto.vars[var_name])
				if(isnull(value))
					continue
				var/list/problem = schema_check(S, value)
				checked++
				TEST_ASSERT(problem[1] != SCHEMA_REJECT, "[type]::[var_name] starts at [value], which its schema refuses ([problem[2]])")
			qdel(proto, force = TRUE)
	TEST_ASSERT(checked > 0, "at least one schema'd default was checked")
	log_test("dq_typed_values_defaults_fit: checked [checked] non-null schema'd defaults, skipped [skipped] types that need constructor arguments")

#undef SCHEMA_FIT_SUBTYPE_SAMPLE
