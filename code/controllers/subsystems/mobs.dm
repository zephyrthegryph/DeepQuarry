//
// Mobs Subsystem - Process mob.Life()
//

// s - Contains temporary debugging code to diagnose extreme tick consumption.
//Revert file to Polaris version when done.

SUBSYSTEM_DEF(mobs)
	name = "Mobs"
	priority = FIRE_PRIORITY_MOBS
	// Preserve one Life() call per mob per two seconds, but distribute the
	// population across eight short slices instead of one large TiDi spike.
	wait = 0.25 SECONDS
	flags = SS_KEEP_TIMING|SS_NO_INIT
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	dependencies = list(
		/datum/controller/subsystem/atoms,
		/datum/controller/subsystem/points_of_interest,
		/datum/controller/subsystem/shuttles
	)

	var/list/currentrun = list()
	var/life_slices = 8
	var/slice_budget_remaining = 0
	/// Logical two-second Life cycle; unlike subsystem times_fired this does
	/// not advance once per distribution slice.
	var/life_cycle = 0
	var/log_extensively = FALSE
	var/list/timelog = list()

	var/slept_mobs = 0
	var/list/process_z = list()

	var/list/death_list = list()
	var/profile_sample_phase = 0
	var/profile_run_index = 0
	var/profile_sample_stride = 16
	var/list/profile_type_cost = list()
	var/list/profile_type_calls = list()
	/// Per life system (doc/mob_life_architecture.md §4.3): "[system type]" -> estimated ms.
	var/list/profile_system_cost = list()
	var/list/profile_system_calls = list()
	var/profile_next_dump = 0
	/// Mobs currently hibernating (no awake life systems) -> world.time they went to sleep.
	/// Maintained only by /mob/living/proc/life_hibernate() and life_wake().
	var/list/hibernating_mobs = list()
	/// Hibernations since the last summary.
	var/hibernations = 0
	/// Wakes of hibernating mobs since the last summary, and reason -> count.
	var/hibernation_wakes = 0
	var/list/hibernation_wake_reasons = list()
	/// Hibernation audit (doc/mob_life_architecture.md §4.9): next run, round-robin
	/// cursors, and totals since the last summary.
	var/next_hibernation_audit = 0
	var/hibernation_audit_cursor = 0
	var/hibernation_audit_awake_cursor = 0
	var/hibernation_audits = 0
	var/hibernation_audit_checked = 0
	var/hibernation_audit_missed = 0
	/// Set by the "Toggle Hibernation Audit" admin verb for the current round.
	var/hibernation_audit_forced = FALSE

/datum/controller/subsystem/mobs/stat_entry(msg)
	msg = "P: [length(GLOB.mob_list)] | S: [slept_mobs] | H: [length(hibernating_mobs)] | D: [length(death_list)]"
	return ..()

/datum/controller/subsystem/mobs/fire(resumed = 0)
	if (!resumed)
		if(!length(src.currentrun))
			src.currentrun = GLOB.mob_list.Copy()
			profile_run_index = 0
			life_cycle++
		slice_budget_remaining = max(1, CEILING(length(src.currentrun) / life_slices, 1))
		if(world.time >= next_hibernation_audit && hibernation_audit_enabled())
			next_hibernation_audit = world.time + MOB_HIBERNATION_AUDIT_INTERVAL
			audit_hibernation()
		process_z.len = length(GLOB.living_players_by_zlevel)
		slept_mobs = 0
		for(var/level in 1 to length(process_z))
			process_z[level] = length(GLOB.living_players_by_zlevel[level])
		// Lets handle all of these while we have time, should always remain extremely small...
		if(length(death_list)) // Don't contact DB if this list is empty
			if(CONFIG_GET(flag/sql_enabled))
				if(!SSdbcore.IsConnected())
					log_game("SQL ERROR during death reporting. Failed to connect.")
				else
					SSdbcore.MassInsert(format_table_name("death"), death_list)
			death_list.Cut()

	//cache for sanic speed (lists are references anyways)
	var/list/currentrun = src.currentrun
	while(length(currentrun) && slice_budget_remaining-- > 0)
		var/mob/M = currentrun[length(currentrun)]
		currentrun.len--

		if(!M || QDELETED(M))
			GLOB.mob_list -= M
			continue
		else if(M.low_priority && !(M.loc && get_z(M) && process_z[get_z(M)]))
			slept_mobs++
			continue
		// Enable pausing mobs (For transformation, holding until reformation, etc.)
		else if(!M.enabled)
			slept_mobs++
			continue
		else if(M.life_hibernating)
			slept_mobs++
			continue

		// Elapsed seconds since this mob's last Life(); systems scale by it.
		var/seconds = M.life_last_time ? (world.time - M.life_last_time) / (1 SECONDS) : LIFE_NOMINAL_SECONDS
		M.life_last_time = world.time

		profile_run_index++
		if(!((profile_run_index + profile_sample_phase) % profile_sample_stride))
			var/mob_type = "[M.type]"
			// Life() is legacy code and may sleep. Wall-clock timing attributes the
			// scheduler pause to the sampled mob; tick usage measures actual work.
			var/profile_start = TICK_USAGE
			M.Life(seconds, TRUE)
			profile_type_cost[mob_type] += TICK_DELTA_TO_MS(TICK_USAGE - profile_start) * profile_sample_stride
			profile_type_calls[mob_type] += profile_sample_stride
		else
			M.Life(seconds)

		if (MC_TICK_CHECK)
			return
	if(!length(currentrun))
		profile_sample_phase = (profile_sample_phase + 1) % profile_sample_stride
	if(!profile_next_dump)
		profile_next_dump = world.time + 2 MINUTES
	else if(world.time >= profile_next_dump)
		dump_type_profile()

/datum/controller/subsystem/mobs/proc/dump_type_profile()
	var/list/sorted_cost = profile_type_cost.Copy()
	sortTim(sorted_cost, /proc/cmp_numeric_desc, TRUE)
	var/rank = 0
	for(var/mob_type in sorted_cost)
		log_runtime("MOB_PROFILE type=[mob_type] estimated_cost_ms=[round(profile_type_cost[mob_type], 0.01)] estimated_calls=[profile_type_calls[mob_type]]")
		if(++rank >= 20)
			break
	profile_type_cost.Cut()
	profile_type_calls.Cut()
	var/list/sorted_systems = profile_system_cost.Copy()
	sortTim(sorted_systems, /proc/cmp_numeric_desc, TRUE)
	rank = 0
	for(var/system_type in sorted_systems)
		log_runtime("MOB_SYSTEM_PROFILE system=[system_type] estimated_cost_ms=[round(profile_system_cost[system_type], 0.01)] estimated_calls=[profile_system_calls[system_type]]")
		if(++rank >= 30)
			break
	profile_system_cost.Cut()
	profile_system_calls.Cut()
	dump_hibernation_summary()
	profile_next_dump = world.time + 2 MINUTES

/// One MOB_HIBERNATE_SUMMARY line per profile dump: always on, one line per two minutes.
/datum/controller/subsystem/mobs/proc/dump_hibernation_summary()
	var/list/reasons = list()
	var/list/sorted_reasons = hibernation_wake_reasons.Copy()
	sortTim(sorted_reasons, /proc/cmp_numeric_desc, TRUE)
	for(var/reason in sorted_reasons)
		reasons += "[reason]=[sorted_reasons[reason]]"
		if(length(reasons) >= 12)
			break
	log_runtime("MOB_HIBERNATE_SUMMARY enabled=[GLOB.mob_hibernation_enabled] hibernating=[length(hibernating_mobs)] hibernations=[hibernations] wakes=[hibernation_wakes] audits=[hibernation_audits] audited=[hibernation_audit_checked] missed_wakes=[hibernation_audit_missed] wake_reasons=[jointext(reasons, ",")]")
	hibernations = 0
	hibernation_wakes = 0
	hibernation_wake_reasons.Cut()
	hibernation_audits = 0
	hibernation_audit_checked = 0
	hibernation_audit_missed = 0

/// Adds one sampled system run (tick usage delta) to the per-system profile.
/datum/controller/subsystem/mobs/proc/record_system_cost(datum/life_system/S, tick_delta)
	var/key = "[S.type]"
	profile_system_cost[key] += TICK_DELTA_TO_MS(tick_delta) * profile_sample_stride
	profile_system_calls[key] += profile_sample_stride

/// Counts one wake of a hibernating mob. Called by /mob/living/proc/life_wake().
/datum/controller/subsystem/mobs/proc/note_wake(reason)
	hibernation_wakes++
	hibernation_wake_reasons[reason || "unspecified"]++

/// The safety net for missed wakes. Samples hibernating mobs (and some awake mobs with
/// sleeping systems) and re-checks every sleeping system's sleep rule. A rule that no longer
/// holds means some producer changed the mob without calling life_wake(): log it loudly and
/// wake the mob, so the gap shows up in the logs instead of as a frozen mob.
/datum/controller/subsystem/mobs/proc/audit_hibernation()
	hibernation_audits++
	var/list/sample = list()
	var/count = length(hibernating_mobs)
	if(count)
		var/take = min(count, MOB_HIBERNATION_AUDIT_SAMPLE)
		for(var/i in 1 to take)
			hibernation_audit_cursor = (hibernation_audit_cursor % count) + 1
			sample += hibernating_mobs[hibernation_audit_cursor]
	var/mob_count = length(GLOB.mob_list)
	if(mob_count)
		var/take = min(mob_count, MOB_HIBERNATION_AUDIT_AWAKE_SAMPLE)
		for(var/i in 1 to take)
			hibernation_audit_awake_cursor = (hibernation_audit_awake_cursor % mob_count) + 1
			var/mob/living/L = GLOB.mob_list[hibernation_audit_awake_cursor]
			if(istype(L) && !L.life_hibernating && (L.life_awake | LIFE_SYS_GATE) != LIFE_SYS_ALL)
				sample += L
	for(var/mob/living/L as anything in sample)
		if(QDELETED(L))
			continue
		audit_mob(L)

/// The audit runs in unit test and TESTING builds always; on servers only with the
/// MOB_HIBERNATION_AUDIT config flag or the admin verb (it is a debugging aid, not a feature).
/datum/controller/subsystem/mobs/proc/hibernation_audit_enabled()
#if defined(UNIT_TESTS) || defined(TESTING)
	return TRUE
#else
	return hibernation_audit_forced || CONFIG_GET(flag/mob_hibernation_audit)
#endif

/// Audits one mob. Returns the system that should have been woken, or null. `expected` is for
/// the audit's own test, which misses a wake on purpose.
/datum/controller/subsystem/mobs/proc/audit_mob(mob/living/L, expected = FALSE)
	hibernation_audit_checked++
	var/datum/life_system/S = L.life_missed_wake()
	if(!S)
		return null
	hibernation_audit_missed++
	var/message = "MOB_HIBERNATE_AUDIT: MISSED WAKE [key_name(L)] ([L.type]) [L.life_hibernating ? "hibernating since [DisplayTimeText(world.time - hibernating_mobs[L])] ago" : "awake bits [L.life_awake]"]: system [S.type] ([S.name], bit [S.bit]) has work but was asleep. Woken by: [S.woken_by || "undeclared"]. A producer changed this mob without life_wake()."
	log_runtime(message)
	log_world(message)
#if defined(UNIT_TESTS)
	if(!expected)
		// A missed wake is a bug: fail the run, not just the log.
		stack_trace(message)
		if(GLOB.current_test)
			GLOB.current_test.Fail(message, __FILE__, __LINE__)
		else
			GLOB.failed_any_test = TRUE
#endif
	L.life_wake(S.bit, "audit: [S.name]")
	return S

/datum/controller/subsystem/mobs/proc/log_recent()
	var/msg = "Debug output from the [name] subsystem:\n"
	msg += "- This subsystem is processed tail-first -\n"
	if(!currentrun || !GLOB.mob_list)
		msg += "ERROR: A critical list [currentrun ? "mob_list" : "currentrun"] is gone!"
		log_game(msg)
		log_world(msg)
		return
	msg += "Lists: currentrun: [length(currentrun)], mob_list: [length(GLOB.mob_list)]\n"

	if(!length(currentrun))
		msg += "!!The subsystem just finished the mob_list list, and currentrun is empty (or has never run).\n"
		msg += "!!The info below is the tail of mob_list instead of currentrun.\n"

	var/datum/D = length(currentrun) ? currentrun[length(currentrun)] : GLOB.mob_list[length(GLOB.mob_list)]
	msg += "Tail entry: [describeThis(D)] (this is likely the item AFTER the problem item)\n"

	var/position = GLOB.mob_list.Find(D)
	if(!position)
		msg += "Unable to find context of tail entry in mob_list list.\n"
	else
		if(position != length(GLOB.mob_list))
			var/additional = GLOB.mob_list.Find(D, position+1)
			if(additional)
				msg += "WARNING: Tail entry found more than once in mob_list list! Context is for the first found.\n"
		var/start = clamp(position-2,1,length(GLOB.mob_list))
		var/end = clamp(position+2,1,length(GLOB.mob_list))
		msg += "2 previous elements, then tail, then 2 next elements of mob_list list for context:\n"
		msg += "---\n"
		for(var/i in start to end)
			msg += "[describeThis(GLOB.mob_list[i])][i == position ? " << TAIL" : ""]\n"
		msg += "---\n"
	log_game(msg)
	log_world(msg)

/datum/controller/subsystem/mobs/proc/report_death(mob/living/L)
	if(!L)
		return
	if(!L.key || !L.mind)
		return
	if(!SSticker || !SSticker.mode)
		return
	SSticker.mode.check_win()

	// Don't bother with the rest if we've not got a DB to do anything with
	if(!CONFIG_GET(flag/enable_stat_tracking) || !CONFIG_GET(flag/sql_enabled))
		return

	var/area/placeofdeath = get_area(L)
	var/podname = placeofdeath ? placeofdeath.name : "Unknown area"

	var/laname = ""
	var/lakey = ""
	var/mob/lastattacker = L.lastattacker
	if(istype(lastattacker))
		laname = lastattacker.real_name
		lakey = lastattacker.key

	var/list/data = list(
	"name" = "[L.real_name]",
	"byondkey" = "[L.key]",
	"job" = "[L.mind.assigned_role]",
	"special" = "[L.mind.special_role]",
	"pod" = podname,
	"tod" = time2text(world.realtime, "YYYY-MM-DD hh:mm:ss"),
	"laname" = laname,
	"lakey" = lakey,
	"gender" = L.gender,
	"bruteloss" = L.injury_load(INJURY_CATEGORY_PHYSICAL),
	"fireloss" = L.injury_load(INJURY_CATEGORY_THERMAL),
	"brainloss" = L.injury_load(INJURY_CATEGORY_NEURAL),
	"oxyloss" = L.oxygen_debt(),
	"coord" = "[L.x], [L.y], [L.z]"
	)
	death_list += list(data)

ADMIN_VERB(toggle_hibernation_audit, R_DEBUG, "Toggle Hibernation Audit", "Turns the mob hibernation missed-wake audit on or off for this round.", ADMIN_CATEGORY_DEBUG_MISC)
	SSmobs.hibernation_audit_forced = !SSmobs.hibernation_audit_forced
	log_admin("[key_name(user)] turned the mob hibernation audit [SSmobs.hibernation_audit_forced ? "on" : "off"] for this round.")
	message_admins("[key_name_admin(user)] turned the mob hibernation audit [SSmobs.hibernation_audit_forced ? "on" : "off"] for this round.")
