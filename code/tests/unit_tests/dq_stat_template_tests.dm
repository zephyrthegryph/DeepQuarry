/// Per-type stat templates (doc/rewrite/proposals/stat_templates.md): pipes made past their type's first instances take the template, and every stat
/// var they hold equals what a full recompute gives. The first instances of each type are checked both ways by the build itself (a mismatch is a
/// stack_trace); this test also checks instances the template served.
/datum/unit_test/dq_stat_template_pipes_match_recompute/Run()
	var/turf/T = test_floor()
	var/served_before = GLOB.stat_templates_served
	var/list/pipes = list()
	for(var/i in 1 to 6)
		pipes += allocate(/obj/machinery/atmospherics/pipe/simple/hidden/supply, T)
	TEST_ASSERT(GLOB.stat_templates_served > served_before, "pipes past the first ones take their type's template ([GLOB.stat_templates_served - served_before] served)")
	var/datum/stat_type_info/I = stat_type_of(pipes[1])
	var/list/todo = I.init_todo || stat_type_init_todo(I)
	for(var/obj/machinery/atmospherics/pipe/P as anything in pipes)
		for(var/datum/stat_def/def as anything in todo)
			var/held = stat_value_now(P, def, I.has_var[def.skey])
			var/computed = stat_compute(P, def, I, P.rx?.stats)
			TEST_ASSERT_EQUAL(held, computed, "[P.type] [def.name] holds what a recompute gives")

/// A pipe type is template-eligible: its init computes are plain stat vars and read nothing outside the pipe.
/datum/unit_test/dq_stat_template_pipe_is_eligible/Run()
	var/obj/machinery/atmospherics/pipe/simple/hidden/supply/P = allocate(/obj/machinery/atmospherics/pipe/simple/hidden/supply, test_floor())
	var/datum/stat_type_info/I = stat_type_of(P)
	var/list/todo = I.init_todo || stat_type_init_todo(I)
	var/why = ""
	for(var/datum/stat_def/def as anything in todo)
		why += " [def.name]: var [I.has_var[def.skey] ? 1 : 0] fast [def.fast ? 1 : 0] formula [def.is_formula ? 1 : 0] keyed [def.keyed ? 1 : 0] units [def.units ? 1 : 0];"
	TEST_ASSERT(stat_template_defs_ok(I, todo), "a pipe's init computes are template-eligible:[why]")
	TEST_ASSERT(stat_template_type_eligible(I), "a pipe reads nothing outside itself")
