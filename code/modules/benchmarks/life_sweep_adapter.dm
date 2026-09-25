// life_sweep adapter for the SSmobs Life scheduler (benchmark baseline: quota fixed, fires
// every tick; code/controllers/subsystems/mobs.dm).

/proc/life_bench_scheduler()
	return "SSmobs (fixed quota, every tick, [LIFE_NOMINAL_SECONDS] s cycle)"

/proc/life_bench_frames()
	return SSmobs.bench_life_calls

/proc/life_bench_ms()
	return SSmobs.bench_ms

/// No scheduler counters on this side.
/proc/life_bench_diag()
	return null
