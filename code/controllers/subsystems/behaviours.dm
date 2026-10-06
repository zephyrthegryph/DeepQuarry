/**
 * # SSbehaviours
 *
 * Dissolved into the kernel (code/controllers/kernel/kernel.dm): it no longer fires. The kernel tick runs the live
 * object-model scheduler's pass (deadlines, wakes, derived values, cadence rings, work items), the pipeline audit
 * and the bench counter. What is left here is its boot (the registry, the scheduler, the world lanes), the audit
 * switch, and the counters the profiler and benchmarks read (`bench_ms`, `last_done`, `cost`), which the kernel feeds.
 */
SYSTEM_DEF(behaviours)
	name = "Behaviours"
	init_stage = INITSTAGE_MAIN
	periodic_runlevels = RUNLEVEL_LOBBY|RUNLEVELS_DEFAULT
	var/last_done = TRUE
	/// Milliseconds the kernel spent in scheduler passes since boot (benchmarks: life_sweep).
	var/bench_ms = 0
	// Its cost is charged to the systems whose behaviours it runs (the scheduler does that as work finishes), and
	// what no behaviour owns lands on om_core, so it is never charged as one lump.
	/// The pipeline missed-wake audit's admin switch (the audit itself is a kernel work item, controllers/kernel/sched_items.dm).
	var/audit_forced = FALSE

/datum/system/behaviours/initialize()
	om_registry()
	om_scheduler()

/// The audit (pipelines and sequences, sched_items.dm audit_step()) runs in unit test and TESTING builds always; on
/// servers only with the OM_PIPELINE_AUDIT config flag or the admin verb (it is a debugging aid, not a feature).
/datum/system/behaviours/proc/audit_enabled()
#if defined(UNIT_TESTS) || defined(TESTING)
	return TRUE
#else
	return audit_forced || CONFIG_GET(flag/om_pipeline_audit)
#endif

/datum/system/behaviours/stat_entry(msg)
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	if(sched)
		msg = "[round(sched.last_run_ms, 0.01)]ms[last_done ? "" : " (behind)"] E:[length(sched.errors)]"
	return msg


ADMIN_VERB(toggle_pipeline_audit, R_DEBUG, "Toggle Pipeline Audit", "Turns the missed-wake audit of object-model pipelines and kernel sequences (mobs, machines) on or off for this round.", ADMIN_CATEGORY_DEBUG_MISC)
	SSbehaviours.audit_forced = !SSbehaviours.audit_forced
	log_admin("[key_name(user)] turned the pipeline audit [SSbehaviours.audit_forced ? "on" : "off"] for this round.")
	message_admins("[key_name_admin(user)] turned the pipeline audit [SSbehaviours.audit_forced ? "on" : "off"] for this round.")

/// The pipeline and sequence missed-wake audits, on their interval while the audit is enabled.
/datum/system/behaviours/reactions()
	. = ..()
	. += every(OM_AUDIT_INTERVAL, PROC_REF(audit_step), when = PROC_REF(audit_ready), phase = KERNEL_PHASE_G, lane = LANE_BACKGROUND)

/datum/system/behaviours/proc/audit_ready()
	return initialized && audit_enabled()

/datum/system/behaviours/proc/audit_step(dt)
	var/datum/om/scheduler/sched = Kernel?.sched
	if(!sched)
		return STEP_DONE
	// The audit is kernel work, outside every behaviour's slot, so nothing charged it: its cost (about 0.18 ms per
	// sampled parked mob) was tick usage no system owned. It is charged to the OM core, where the scheduler's own
	// bookkeeping lands, so a spike in the tick record names it instead of leaving it unexplained.
	var/started = TICK_USAGE
	om_pipeline_audit(sched, OM_AUDIT_PARKED_SAMPLE, OM_AUDIT_AWAKE_SAMPLE)
	seq_audit(SEQ_AUDIT_PARKED_SAMPLE, SEQ_AUDIT_AWAKE_SAMPLE)
	sleep_audit(64, TRUE)
	km_meter().charge(KM_SYS_OM_CORE, TICK_USAGE_TO_MS(started))
	return STEP_DONE
