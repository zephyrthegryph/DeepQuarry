/**
 * # SSbehaviours
 *
 * Runs the live object-model scheduler (doc/rewrite/object_model_core.md): deadlines,
 * wakes, derived values and cadence rings, each lane with a guaranteed share of the
 * budget Master gives this subsystem. All state lives in the scheduler, so a fire that
 * runs out of budget simply continues next fire; nothing here pauses mid-loop.
 */
SUBSYSTEM_DEF(behaviours)
	name = "Behaviours"
	wait = 1 // SS_TICKER: in ticks
	priority = FIRE_PRIORITY_BEHAVIOURS
	flags = SS_TICKER|SS_KEEP_TIMING
	runlevels = RUNLEVEL_LOBBY|RUNLEVELS_DEFAULT
	var/last_done = TRUE
	/// Milliseconds spent in fire() since boot (benchmarks: life_sweep).
	var/bench_ms = 0
	/// The pipeline missed-wake audit (pipeline.dm): next run, and the admin verb's switch.
	EXPIRY_DECLARE(next_audit)
	var/audit_forced = FALSE

/datum/controller/subsystem/behaviours/Initialize()
	om_registry()
	om_scheduler()
	// World services' periodic lanes on the global owner (machines, mobs; world_lanes.dm).
	_om_start_world_lanes() // ALLOW(om_internal): SSbehaviours is the scheduler core that boots the world lanes
	return SS_INIT_SUCCESS

/datum/controller/subsystem/behaviours/fire(resumed)
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	if(!sched)
		return
	var/start = TICK_USAGE
	last_done = sched.run_pass(Master.current_ticklimit)
	bench_ms += TICK_USAGE_TO_MS(start)
	if(EXPIRY_EXPIRED(src, next_audit, CLOCK_WORLD) && audit_enabled())
		EXPIRY_SET(src, next_audit, OM_AUDIT_INTERVAL, CLOCK_WORLD)
		om_pipeline_audit(sched, OM_AUDIT_PARKED_SAMPLE, OM_AUDIT_AWAKE_SAMPLE)
		om_sleeper_audit(64, TRUE)

/// The audit runs in unit test and TESTING builds always; on servers only with the
/// OM_PIPELINE_AUDIT config flag or the admin verb (it is a debugging aid, not a feature).
/datum/controller/subsystem/behaviours/proc/audit_enabled()
#if defined(UNIT_TESTS) || defined(TESTING)
	return TRUE
#else
	return audit_forced || CONFIG_GET(flag/om_pipeline_audit)
#endif

/datum/controller/subsystem/behaviours/stat_entry(msg)
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	if(sched)
		msg = "[round(sched.last_run_ms, 0.01)]ms[last_done ? "" : " (behind)"] E:[length(sched.errors)]"
	return ..()

/datum/controller/subsystem/behaviours/Recover()
	last_done = SSbehaviours.last_done

ADMIN_VERB(toggle_pipeline_audit, R_DEBUG, "Toggle Pipeline Audit", "Turns the object-model pipeline missed-wake audit (mobs, machines) on or off for this round.", ADMIN_CATEGORY_DEBUG_MISC)
	SSbehaviours.audit_forced = !SSbehaviours.audit_forced
	log_admin("[key_name(user)] turned the pipeline audit [SSbehaviours.audit_forced ? "on" : "off"] for this round.")
	message_admins("[key_name_admin(user)] turned the pipeline audit [SSbehaviours.audit_forced ? "on" : "off"] for this round.")
