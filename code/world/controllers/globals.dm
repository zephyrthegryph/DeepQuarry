// See initialization order in /code/game/world.dm
GLOBAL_REAL(GLOB, /datum/controller/global_vars)

/datum/controller/global_vars
	name = "Global Variables"

	var/static/list/gvars_datum_protected_varlist
	var/list/gvars_datum_in_built_vars
	var/list/gvars_datum_init_order

/// world.timeofday when global initialisation began and ended (boot timing: the bench reads them against the spawn stamp, launch_tod).
GLOBAL_REAL_VAR(boot_globals_started_tod)
GLOBAL_REAL_VAR(boot_globals_done_tod)
/// Set by global initialization when the InitGlobal procs do not match the declared globals; the boot gate fails the run on it (the WARNING is logged before the gate's own counters exist).
GLOBAL_REAL_VAR(globals_init_mismatch)

/datum/controller/global_vars/New()
	boot_globals_started_tod = world.timeofday
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

	Initialize()
	boot_globals_done_tod = world.timeofday

	// Disposal arms the scheduler, so finish global initialization before it can build the registry.
	exclude_these.expire(0) //signal logging isn't ready

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

/datum/controller/global_vars/Initialize()
	gvars_datum_init_order = list()
	gvars_datum_protected_varlist = list(NAMEOF(src, gvars_datum_protected_varlist) = TRUE)
	// The proc namespace also holds other generated procs of the controller (a SCHEMA() on a global declares __schema_<var>), so only the
	// InitGlobal<var> procs are the initializers to count and call.
	var/list/global_procs = list()
	for(var/I in typesof(/datum/controller/global_vars/proc))
		if(findtext(replacetext("[I]", "/datum/controller/global_vars/proc/", ""), "InitGlobal") == 1)
			global_procs += I
	var/expected_len = vars.len - gvars_datum_in_built_vars.len
	if(global_procs.len != expected_len)
		globals_init_mismatch = "Expected [expected_len] got [global_procs.len]"
		WARNING("Unable to detect all global initialization procs! [globals_init_mismatch]!")
		var/list/missing_global_procs = vars - gvars_datum_in_built_vars
		var/list/unmatched_global_procs = list()
		for(var/I in global_procs)
			var/global_name = replacetext(replacetext("[I]", "/datum/controller/global_vars/proc/", ""), "InitGlobal", "")
			if(global_name in missing_global_procs)
				missing_global_procs -= global_name
			else
				unmatched_global_procs += "[I]"
		log_world("Globals without an InitGlobal proc: [missing_global_procs.Join(", ")]")
		log_world("InitGlobal procs without a global: [unmatched_global_procs.Join(", ")]")

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

// The globals that hold a reference to a datum or atom are declared relations of the GLOB holder: a deleted target leaves its global by
// itself, and every write goes through rel_set()/rel_add()/rel_remove()/rel_clear() on GLOB (doc/rewrite/proposals/reference_storage.md).
CAPABILITIES(/datum/controller/global_vars)
	ref_one(nameof(ore_silo_default))
	ref_one(nameof(global_announcer))
	ref_one(nameof(click_catcher))
	ref_one(nameof(ai_camera_room_landmark))
	ref_one(nameof(blackbox))
	ref_one(nameof(sleevemate_mob))
	ref_one(nameof(vendor_account))
	ref_one(nameof(station_account))
	ref_one(nameof(sdql2_vv_statobj))
	ref_one(nameof(character_directory))
	ref_many(nameof(projectile_hits))
	ref_one(nameof(map_load_active))
	ref_one(nameof(act_next_actor))
	ref_one(nameof(changelog_tgui))
	ref_many(nameof(adminfaxes))
	ref_many(nameof(admin_ranks))
	ref_many(nameof(protected_ranks))
	ref_many(nameof(admin_laws))
	ref_many(nameof(player_laws))
	ref_many(nameof(affliction_triggers_all))
	// Keyed many: an alist, key -> member (the ckey, or the level as text); a member that is deleted takes its keys with it.
	ref_many(nameof(mannequins))
	ref_many(nameof(tgs_waiting_senders))
	ref_many(nameof(map_sectors))
