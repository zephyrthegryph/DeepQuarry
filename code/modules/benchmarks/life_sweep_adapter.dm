// life_sweep adapter for the object-model Life pipelines (code/modules/mob/living/life/life_om.dm).

/proc/life_bench_scheduler()
	return "object model (life pipeline, LIFE_CYCLE [LIFE_CYCLE_DS] ds)"

/proc/life_bench_frames()
	return om_pipeline_frames(/datum/om/pipeline/life)

/proc/life_bench_ms()
	return SSbehaviours.bench_ms

/// The life pipeline's scheduler counters since boot (runs, deferrals, breaches, lateness).
/proc/life_bench_diag()
	var/list/diagnostics = om_diagnostics(GLOB.om_live_sched)
	var/list/types = diagnostics["types"]
	var/datum/om/behaviour/life = om_registry().behaviour(/datum/om/pipeline/life)
	return types[life.name]

/// TRUE while `L` is off the Life ring because every stage is idle.
/proc/life_bench_parked(mob/living/L)
	return om_pipe_parked(L, /datum/om/pipeline/life)
