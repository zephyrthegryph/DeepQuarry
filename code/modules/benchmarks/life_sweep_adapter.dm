// life_sweep adapter for the object-model Life scheduler (code/modules/mob/living/life/life_om.dm).

/proc/life_bench_scheduler()
	return "object model (life behaviour, LIFE_CYCLE [LIFE_CYCLE_DS] ds)"

/proc/life_bench_frames()
	return GLOB.life_frames

/proc/life_bench_ms()
	return SSbehaviours.bench_ms
