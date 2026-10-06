// life_sweep adapter for the kernel's Life sequence (code/modules/mob/living/life/life_sequence.dm).

/proc/life_bench_scheduler()
	return "kernel (life sequence, LIFE_CYCLE [LIFE_CYCLE_DS] ds)"

/proc/life_bench_frames(list/mobs)
	return seq_frames(mobs, /datum/sequence/life)

/// The Life sweep's own cost: its work item's total (the pipeline's was the OM scheduler pass, SSbehaviours.bench_ms).
/proc/life_bench_ms()
	var/datum/sequence/S = sequence_def(/datum/sequence/life)
	return S.work.total_ms

/// The kernel's whole N..R span: the scheduler plus the native frame and the work items of those phases.
/proc/life_bench_pass_ms()
	return kernel().pass_ms_total

/// The Life sequence's counters since boot (frames, parks, wakes, breaches, step costs).
/proc/life_bench_diag()
	var/datum/sequence/S = sequence_def(/datum/sequence/life)
	return S.metrics()

/// TRUE while `L` is out of the Life sweep because every step sleeps.
/proc/life_bench_parked(mob/living/L)
	return seq_parked(L, /datum/sequence/life)
