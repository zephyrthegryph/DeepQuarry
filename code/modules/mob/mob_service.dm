// The mob system (was SSmobs). Mob Life runs on object-model pipelines
// (code/modules/mob/living/life/life_om.dm; doc/rewrite/life_on_om.md). What is left here is death
// reporting and the two-minute Life profile summary, read from the core scheduler's stage profile
// and pipeline counters, run every 2 s by report_step. The mob hibernation / pipeline missed-wake audit runs from
// SSbehaviours (code/controllers/subsystems/behaviours.dm).

SYSTEM_DEF(mobs)
	name = "Mobs"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	var/list/death_list = list()
	/// Pipeline counters at the last summary (parks, unparks, missed wakes), for the deltas.
	var/list/last_counts = list(0, 0, 0)

/// Set on the first service step: the two-minute profile summary then repeats (dump_profile).
OM_FIELD(/datum/system/mobs, profiling, FALSE, CHANGE_DATUM_A)
DECLARE_REPEAT(/datum/system/mobs, 2 MINUTES, dump_profile, "profiling")

/datum/system/mobs/stat_entry(msg)
	var/datum/om/behaviour/life = om_registry().behaviour(/datum/om/pipeline/life)
	var/list/S = GLOB.om_live_sched?.stat_for(life.id)
	return "[..()]P: [REGISTRY_COUNT(REGISTRY_MOBS)] | parked: [om_pipeline_parked_count(/datum/om/pipeline/life)] | [S ? round(S[OM_STAT_MS], 1) : 0]ms | D: [length(death_list)]"

/datum/system/mobs/reactions()
	. = ..()
	. += every(2 SECONDS, PROC_REF(report_step), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/mobs/proc/report_step(dt)
	if(length(death_list)) // Don't contact DB if this list is empty
		var/list/batch = death_list
		death_list = list()
		insert_deaths(batch)
	if(!profiling)
		// This singleton is built at global-var init, before the object model exists, so its
		// declarations start here on the first step rather than from New().
		lifecycle_decls_init(src)
		set_profiling(TRUE)
	return STEP_DONE

/// The database insert sleeps, so the lane hands it off (the lane itself must not sleep).
/// Queues the batch as one om_io insert: returns at once, nothing here waits on SQL.
/datum/system/mobs/proc/insert_deaths(list/batch)
	if(!CONFIG_GET(flag/sql_enabled))
		return
	if(!SSdbcore.IsConnected())
		log_game("SQL ERROR during death reporting. Failed to connect.")
		return
	SSdbcore.mass_insert_io(null, format_table_name("death"), batch)

/// MOB_PROFILE lines (sampled cost per mob type and per stage, every Nth frame) and one
/// MOB_PARK_SUMMARY line, every two minutes.
/datum/system/mobs/proc/dump_profile()
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	if(!sched)
		return
	var/list/types = list()
	var/list/stages = list()
	for(var/key in sched.stage_cost)
		if(copytext(key, 1, 6) == "type:")
			types[copytext(key, 6)] = sched.stage_cost[key]
		else
			stages[key] = sched.stage_cost[key]
	sortTim(types, /proc/cmp_numeric_desc, TRUE)
	sortTim(stages, /proc/cmp_numeric_desc, TRUE)
	var/rank = 0
	for(var/mob_type in types)
		log_runtime("MOB_PROFILE type=[mob_type] estimated_cost_ms=[round(types[mob_type], 0.01)] estimated_calls=[sched.stage_calls["type:[mob_type]"]]")
		if(++rank >= 20)
			break
	rank = 0
	for(var/stage_type in stages)
		log_runtime("MOB_STAGE_PROFILE stage=[stage_type] estimated_cost_ms=[round(stages[stage_type], 0.01)] estimated_calls=[sched.stage_calls[stage_type]]")
		if(++rank >= 30)
			break
	sched.stage_cost.Cut()
	sched.stage_calls.Cut()
	var/datum/om/behaviour/life = om_registry().behaviour(/datum/om/pipeline/life)
	var/list/S = sched.stat_for(life.id)
	var/list/now = list(S[OM_STAT_PARKS], S[OM_STAT_UNPARKS], S[OM_STAT_MISSED])
	log_runtime("MOB_PARK_SUMMARY enabled=[GLOB.om_parking_enabled] parked=[om_pipeline_parked_count(life, sched)] parks=[now[1] - last_counts[1]] unparks=[now[2] - last_counts[2]] missed_wakes=[now[3] - last_counts[3]]")
	last_counts = now
