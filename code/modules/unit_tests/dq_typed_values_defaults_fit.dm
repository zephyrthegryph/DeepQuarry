// Every var that declares a value schema (SCHEMA / TRACKED_SCHEMA) starts at a value the schema accepts, on its declaring type and on every subtype
// that overrides the default (doc/rewrite/proposals/typed_values.md section 5). The analyzer checks assigned path literals and trusts calls; a plain
// write is not checked at run time, so this test is the check on defaults.
/datum/unit_test/dq_typed_values_defaults_fit

/datum/unit_test/dq_typed_values_defaults_fit/Run()
	if(!GLOB.schemas_built)
		schemas_build()
	var/checked = 0
	for(var/declared_type in GLOB.schemas)
		var/list/by_var = GLOB.schemas[declared_type]
		for(var/var_name in by_var)
			var/datum/schema/S = by_var[var_name]
			for(var/type in typesof(declared_type))
				var/datum/D = type
				if(!(var_name in D.vars))
					continue
				var/value = initial(D.vars[var_name])
				if(isnull(value))
					continue
				var/list/problem = schema_check(S, value)
				checked++
				TEST_ASSERT(problem[1] != SCHEMA_REJECT, "[type]::[var_name] starts at [value], which its schema refuses ([problem[2]])")
	TEST_ASSERT(checked > 0, "at least one schema'd default was checked")
