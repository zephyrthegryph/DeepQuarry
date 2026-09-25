// Mobs subsystem. Mob Life runs on the object model (the life behaviour,
// code/modules/mob/living/life/life_om.dm; doc/rewrite/life_on_om.md). What is left here is
// the bookkeeping around it: death reporting, the two-minute profile and hibernation
// summaries, and the missed-wake audit.

SUBSYSTEM_DEF(mobs)
	name = "Mobs"
	priority = FIRE_PRIORITY_MOBS
	wait = 2 SECONDS
	flags = SS_NO_INIT
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	var/list/death_list = list()
	/// Per-system and per-mob-type profile: every profile_sample_stride-th frame is timed
	/// (GLOB.life_frames, a global counter, so no mob or type is sampled more than another).
	var/profile_sample_stride = 16
	var/list/profile_type_cost = list()
	var/list/profile_type_calls = list()
	/// Per life system (doc/mob_life_architecture.md §4.3): "[system type]" -> estimated ms.
	var/list/profile_system_cost = list()
	var/list/profile_system_calls = list()
	var/profile_next_dump = 0
	/// Hibernations since the last summary.
	var/hibernations = 0
	/// Wakes of hibernating mobs since the last summary, and reason -> count.
	var/hibernation_wakes = 0
	var/list/hibernation_wake_reasons = list()
	/// Hibernation audit: next run, round-robin cursors, and totals since the last summary.
	var/next_hibernation_audit = 0
	var/hibernation_audit_cursor = 0
	var/hibernation_audit_awake_cursor = 0
	var/hibernation_audits = 0
	var/hibernation_audit_checked = 0
	var/hibernation_audit_missed = 0
	/// Set by the "Toggle Hibernation Audit" admin verb for the current round.
	var/hibernation_audit_forced = FALSE

/datum/controller/subsystem/mobs/stat_entry(msg)
	var/datum/om/behaviour/life = om_registry().behaviour(/datum/om/behaviour/life)
	var/list/S = GLOB.om_live_sched?.stat_for(life.id)
	msg = "P: [length(GLOB.mob_list)] | H: [length(GLOB.life_hibernating_mobs)] | F: [GLOB.life_frames] | [S ? round(S[OM_STAT_MS], 1) : 0]ms | D: [length(death_list)]"
	return ..()

/datum/controller/subsystem/mobs/fire(resumed = 0)
	if(world.time >= next_hibernation_audit && hibernation_audit_enabled())
		next_hibernation_audit = world.time + MOB_HIBERNATION_AUDIT_INTERVAL
		audit_hibernation()
	if(length(death_list)) // Don't contact DB if this list is empty
		if(CONFIG_GET(flag/sql_enabled))
			if(!SSdbcore.IsConnected())
				log_game("SQL ERROR during death reporting. Failed to connect.")
			else
				SSdbcore.MassInsert(format_table_name("death"), death_list)
		death_list.Cut()
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
	log_runtime("MOB_HIBERNATE_SUMMARY enabled=[GLOB.mob_hibernation_enabled] hibernating=[length(GLOB.life_hibernating_mobs)] hibernations=[hibernations] wakes=[hibernation_wakes] audits=[hibernation_audits] audited=[hibernation_audit_checked] missed_wakes=[hibernation_audit_missed] wake_reasons=[jointext(reasons, ",")]")
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

/// Adds one sampled frame (tick usage delta) to the per-mob-type profile.
/datum/controller/subsystem/mobs/proc/record_mob_cost(mob/living/L, tick_delta)
	var/key = "[L.type]"
	profile_type_cost[key] += TICK_DELTA_TO_MS(tick_delta) * profile_sample_stride
	profile_type_calls[key] += profile_sample_stride

/// Counts one wake of a hibernating mob. Called by /mob/living/proc/life_resume().
/datum/controller/subsystem/mobs/proc/note_wake(reason)
	hibernation_wakes++
	hibernation_wake_reasons[reason || "unspecified"]++

/// The safety net for missed wakes. Samples hibernating mobs (and some awake mobs with
/// sleeping systems) and re-checks every sleeping system's sleep rule. A rule that no longer
/// holds means some producer changed the mob without raising its channel: log it loudly and
/// wake the mob, so the gap shows up in the logs instead of as a frozen mob.
/datum/controller/subsystem/mobs/proc/audit_hibernation()
	hibernation_audits++
	var/list/sample = list()
	var/list/hibernating = GLOB.life_hibernating_mobs
	var/count = length(hibernating)
	if(count)
		var/take = min(count, MOB_HIBERNATION_AUDIT_SAMPLE)
		for(var/i in 1 to take)
			hibernation_audit_cursor = (hibernation_audit_cursor % count) + 1
			sample += hibernating[hibernation_audit_cursor]
	var/mob_count = length(GLOB.mob_list)
	if(mob_count)
		var/take = min(mob_count, MOB_HIBERNATION_AUDIT_AWAKE_SAMPLE)
		for(var/i in 1 to take)
			hibernation_audit_awake_cursor = (hibernation_audit_awake_cursor % mob_count) + 1
			var/mob/living/L = GLOB.mob_list[hibernation_audit_awake_cursor]
			if(istype(L) && !L.life_hibernating && L.life_asleep_total)
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
	var/message = "MOB_HIBERNATE_AUDIT: MISSED WAKE [key_name(L)] ([L.type]) [L.life_hibernating ? "hibernating since [DisplayTimeText(world.time - L.life_hibernated_at)] ago" : "awake, some systems asleep"]: system [S.type] ([S.name], wake_on [S.wake_on]) has work but was asleep. Woken by: [S.woken_by || "undeclared"]. A producer changed this mob without raising its channel (om_changed)."
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
	if(L.life_hibernating)
		L.life_resume("audit: [S.name]")
	else
		L.life_changed(CHANGE_EXPLICIT)
	return S

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
