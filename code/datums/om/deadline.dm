// Legacy spellings and subtype paths retain compatibility; implementation lives in the engine.

/proc/om_deadline(datum/E, delay, B, sub = 0)
	return deadline_deadline(arglist(args))

/proc/om_cancel_after(datum/E, B, sub = 0)
	return deadline_cancel_after(arglist(args))

/proc/om_cancel_all_after(datum/E, B)
	return deadline_cancel_all_after(arglist(args))

/proc/om_deadline_pending(datum/E, B, sub = 0)
	return deadline_deadline_pending(arglist(args))

/proc/om_clock_reschedule(datum/om/rec/rec, cidx)
	return deadline_clock_reschedule(arglist(args))
