// Mobs subsystem. Mob Life runs on object-model pipelines (code/modules/mob/living/life/life_om.dm;
// doc/rewrite/life_on_om.md). What is left here is death reporting and the two-minute Life
// profile summary, read from the core scheduler's stage profile and pipeline counters.

SUBSYSTEM_DEF(mobs)
	name = "Mobs"
	priority = FIRE_PRIORITY_MOBS
	wait = 2 SECONDS
	flags = SS_NO_INIT
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	var/list/death_list = list()
	var/profile_next_dump = 0
	/// Pipeline counters at the last summary (parks, unparks, missed wakes), for the deltas.
	var/list/last_counts = list(0, 0, 0)

/datum/controller/subsystem/mobs/stat_entry(msg)
	var/datum/om/behaviour/life = om_registry().behaviour(/datum/om/pipeline/life)
	var/list/S = GLOB.om_live_sched?.stat_for(life.id)
	msg = "P: [length(GLOB.mob_list)] | parked: [om_pipeline_parked_count(/datum/om/pipeline/life)] | F: [S ? S[OM_STAT_FRAMES] : 0] | [S ? round(S[OM_STAT_MS], 1) : 0]ms | D: [length(death_list)]"
	return ..()

/datum/controller/subsystem/mobs/fire(resumed = 0)
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
		dump_profile()

/// MOB_PROFILE lines (sampled cost per mob type and per stage, every Nth frame) and one
/// MOB_PARK_SUMMARY line, every two minutes.
/datum/controller/subsystem/mobs/proc/dump_profile()
	profile_next_dump = world.time + 2 MINUTES
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

