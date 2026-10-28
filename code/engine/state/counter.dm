// Diagnostic counters: a cumulative count of something the engine did (actions taken, cache hits, every() runs), read by tests and diagnostics as deltas.
// A counter is declared as one (GLOBAL_COUNTER), not as a number: the unit-test state guard compares scalar globals before and after a test, and a plain number
// that sits at 0 or 1 early in a run reads as a flag the test left changed. A counter is a datum, so the guard never mistakes it for one, and a real global flag
// that flips is still reported.

/// A cumulative count. `n` moves up as the engine works; nothing restores it.
/datum/counter
	var/n = 0
