// Busy work: the replacement of task_hold_busy() / task_release_busy() / task_busy() for a thing that is occupied for a while and is not an op's actor
// (a slot machine spinning, a cataloguer flashing, a bot at its job, a brain holding its next decision). Being busy is a timed hold of STAT_BUSY_WORK by
// SRC_BUSY_WORK; the end of the work (the hold running out, or release_busy()) calls the optional `on_end` proc of the holder once.
//
//	if(work_busy(src)) return
//	hold_busy(src, 5 SECONDS, TYPE_PROC_REF(/atom, update_icon))
//
// A player's timed action is an op with wait() and claims(), not this.

/// TRUE while `E` is busy.
/proc/work_busy(datum/E)
	READS_FROM(E)
	return !!stat_value(E, STAT_BUSY_WORK)

/// `E` is busy for `duration`, then `on_end` (a proc of E) runs. Returns TRUE, or "busy" when it already is.
/proc/hold_busy(datum/E, duration, on_end = null)
	if(!E || QDELETED(E))
		return "gone"
	if(work_busy(E))
		return "busy"
	hold(E, STAT_BUSY_WORK, TRUE, SRC_BUSY_WORK, lasts = max(duration, 1 TICK))
	if(on_end)
		after(E, max(duration, 1 TICK), GLOBAL_PROC_REF(busy_ended), key = "busy_end", with = list(E, on_end))
	return TRUE

/// The work stops early: `E` is free and `on_end` (the proc hold_busy() was given) runs. TRUE when it was busy.
/proc/release_busy(datum/E, on_end = null)
	if(!E || QDELETED(E) || !work_busy(E))
		return FALSE
	release(E, STAT_BUSY_WORK, SRC_BUSY_WORK)
	cancel_after(E, "busy_end")
	if(on_end)
		call(E, on_end)()
	return TRUE

/// The timer of hold_busy(): the hold has run out; the holder is told once.
/proc/busy_ended(datum/E, on_end)
	if(!E || QDELETED(E) || !on_end)
		return
	call(E, on_end)()
