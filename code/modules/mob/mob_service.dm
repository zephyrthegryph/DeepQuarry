// The mob system (was SSmobs). Mob Life runs on object-model pipelines
// (code/modules/mob/living/life/life_om.dm; doc/rewrite/life_on_om.md). What is left here is death
// reporting and the two-minute Life profile summary, read from the core scheduler's stage profile
// and pipeline counters, run every 2 s by report_step. The mob hibernation / pipeline missed-wake audit runs from
// SSbehaviours (code/controllers/subsystems/behaviours.dm).

SYSTEM_DEF(mobs)
	name = "Mobs"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	var/list/death_list = list()
	/// ckey -> the /datum/respawn_timer of a player who may not respawn yet (the system owns them).
	var/list/respawn_timers
	/// Pipeline counters at the last summary (parks, unparks, missed wakes), for the deltas.
	var/list/last_counts = list(0, 0, 0)

CAPABILITIES(/datum/system/mobs)
	owns_many(nameof(respawn_timers), /datum/respawn_timer)

/// How long a player must wait to respawn, counted from when it was set.
/datum/respawn_timer
	var/duration = 0
	EXPIRY_DECLARE(started_at)

/// Starts (or restarts) the respawn wait of `ckey`.
/datum/system/mobs/proc/set_respawn_wait(ckey, duration)
	var/datum/respawn_timer/timer = new
	timer.duration = duration
	STAMP(timer, started_at, CLOCK_WORLD)
	rel_add(src, nameof(respawn_timers), timer, key = ckey)

/// The ckeys that are still waiting to respawn.
/datum/system/mobs/proc/respawn_waiters()
	return assoc_to_keys(respawn_timers)

/// Lets `ckey` respawn now.
/datum/system/mobs/proc/clear_respawn_wait(ckey)
	var/datum/respawn_timer/timer = LAZYACCESS(respawn_timers, ckey)
	if(timer)
		rel_remove(src, nameof(respawn_timers), timer)

/datum/system/mobs/stat_entry(msg)
	var/datum/sequence/life = sequence_def(/datum/sequence/life)
	return "[..()]P: [REGISTRY_COUNT(REGISTRY_MOBS)] | parked: [members_total(life.parked_key)] | frames: [life.frames] | D: [length(death_list)]"

/datum/system/mobs/reactions()
	. = ..()
	. += every(2 SECONDS, PROC_REF(report_step), when = PROC_REF(work_ready), lane = LANE_SIMULATION)
	. += every(2 MINUTES, PROC_REF(dump_profile), when = PROC_REF(work_ready), lane = LANE_BACKGROUND)

/datum/system/mobs/proc/report_step(dt)
	if(length(death_list)) // Don't contact DB if this list is empty
		var/list/batch = death_list
		death_list = list()
		insert_deaths(batch)
	return STEP_DONE

/// The database insert sleeps, so the lane hands it off (the lane itself must not sleep).
/// Queues the batch as one io_job insert: returns at once, nothing here waits on SQL.
/datum/system/mobs/proc/insert_deaths(list/batch)
	if(!CONFIG_GET(flag/sql_enabled))
		return
	if(!SSdbcore.IsConnected())
		log_game("SQL ERROR during death reporting. Failed to connect.")
		return
	SSdbcore.mass_insert_io(null, format_table_name("death"), batch)

/// MOB_STEP_PROFILE lines (sampled cost per Life step, every LIFE_PROFILE_STRIDEth frame) and one MOB_PARK_SUMMARY
/// line, every two minutes.
/datum/system/mobs/proc/dump_profile(dt)
	var/datum/sequence/life = sequence_def(/datum/sequence/life)
	var/list/steps = list()
	for(var/i in 1 to length(life.slot_keys))
		steps[life.slot_keys[i]] = life.step_ms[i]
	sortTim(steps, /proc/cmp_numeric_desc, TRUE)
	var/rank = 0
	for(var/key in steps)
		var/i = life.slot_of[key]
		log_runtime("MOB_STEP_PROFILE step=[key] estimated_cost_ms=[round(steps[key], 0.01)] estimated_calls=[life.step_calls[i]]")
		if(++rank >= 30)
			break
	for(var/i in 1 to length(life.slot_keys))
		life.step_ms[i] = 0
		life.step_calls[i] = 0
	var/list/now = list(life.parks, life.unparks, life.missed)
	log_runtime("MOB_PARK_SUMMARY parked=[members_total(life.parked_key)] parks=[now[1] - last_counts[1]] unparks=[now[2] - last_counts[2]] missed_wakes=[now[3] - last_counts[3]]")
	last_counts = now
	return STEP_DONE
