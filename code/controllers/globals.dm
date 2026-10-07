// See initialization order in /code/game/world.dm
GLOBAL_REAL(GLOB, /datum/controller/global_vars)

/datum/controller/global_vars
	name = "Global Variables"

	var/static/list/gvars_datum_protected_varlist
	var/list/gvars_datum_in_built_vars
	var/list/gvars_datum_init_order

/datum/controller/global_vars/New()
	if(GLOB)
		CRASH("Multiple instances of global variable controller created")
	GLOB = src

	var/datum/controller/exclude_these = new
	// I know this is dumb but the nested vars list hangs a ref to the datum. This fixes that
	// I have an issue report open, lummox has not responded. It might be a FeaTuRE
	// Sooo we gotta be dumb
	var/list/controller_vars = exclude_these.vars.Copy()
	controller_vars["vars"] = null
	gvars_datum_in_built_vars = controller_vars + list(NAMEOF(src, gvars_datum_protected_varlist), NAMEOF(src, gvars_datum_in_built_vars), NAMEOF(src, gvars_datum_init_order))

	after(exclude_these, 0, TYPE_PROC_REF(/datum, om_qdel_batch_self)) //signal logging isn't ready

	Initialize()

// Protected GLOB holder; never runs the parent chain (admin var-edit exploit).
/datum/controller/global_vars/Destroy(force)
	// This is done to prevent an exploit where admins can get around protected vars
	SHOULD_CALL_PARENT(FALSE)
	return QDEL_HINT_IWILLGC

/datum/controller/global_vars/stat_entry(msg)
	msg = "Edit"
	return msg

/datum/controller/global_vars/vv_edit_var(var_name, var_value)
	if(gvars_datum_protected_varlist[var_name])
		return FALSE
	return ..()

// ALLOW(init/FRAMEWORK): the global vars controller runs every global's init proc here
/datum/controller/global_vars/Initialize()
	gvars_datum_init_order = list()
	gvars_datum_protected_varlist = list(NAMEOF(src, gvars_datum_protected_varlist) = TRUE)
	var/list/global_procs = typesof(/datum/controller/global_vars/proc)
	var/expected_len = vars.len - gvars_datum_in_built_vars.len
	if(global_procs.len != expected_len)
		WARNING("Unable to detect all global initialization procs! Expected [expected_len] got [global_procs.len]!")
		if(global_procs.len)
			var/list/expected_global_procs = vars - gvars_datum_in_built_vars
			for(var/I in global_procs)
				expected_global_procs -= replacetext("[I]", "InitGlobal", "")
			log_world("Missing procs: [expected_global_procs.Join(", ")]")

	for(var/I in global_procs)
		var/start_tick = world.time
#if defined(BENCHMARK) || defined(SPACEMAN_DMM)
		var/started = REALTIMEOFDAY
		var/mb_before = benchmark_early_private_mb()
#endif
		call(src, I)()
#if defined(BENCHMARK) || defined(SPACEMAN_DMM)
		benchmark_early_note("global [replacetext("[I]", "/datum/controller/global_vars/proc/InitGlobal", "")]", REALTIMEOFDAY - started, mb_before)
#endif
		var/end_tick = world.time
		if(end_tick - start_tick)
			WARNING("Global [replacetext("[I]", "InitGlobal", "")] slept during initialization!")

#if defined(BENCHMARK) || defined(SPACEMAN_DMM)
/// Early boot notes for the memory breakdown (init_and_turfs.md §0.4): list(name, ds, MB
/// before, MB after) for every step that took time or memory. A real global rather than a GLOB
/// var because GLOB may not exist yet when the first note is taken; created on first use.
GLOBAL_REAL_VAR(list/benchmark_early_notes)

/// DreamDaemon's private MB from the bench sampler's file (null outside a bench).
/proc/benchmark_early_private_mb()
	if(!fexists("data/bench/process.json"))
		return null
	var/text = file2text("data/bench/process.json")
	if(!length(text))
		return null
	var/list/decoded = json_decode(text)
	return decoded?["private_mb"]

/proc/benchmark_early_note(name, ds, mb_before)
	var/mb_after = benchmark_early_private_mb()
	if(ds >= 1 || (isnum(mb_before) && isnum(mb_after) && mb_after - mb_before >= 2))
		var/list/notes = benchmark_early_notes || (benchmark_early_notes = list())
		notes += list(list(name, ds, mb_before, mb_after))
#endif
