// Legacy type and global spellings forward to the actual time-engine foundation.

/datum/om/scheduler
	parent_type = /datum/time_scheduler

/datum/om/ring
	parent_type = /datum/cadence_ring

/proc/om_scheduler()
	RETURN_TYPE(/datum/om/scheduler)
	return time_scheduler(arglist(args))

/proc/om_test_begin()
	RETURN_TYPE(/datum/om/scheduler)
	return scheduler_test_begin(arglist(args))

/proc/om_test_end()
	return scheduler_test_end(arglist(args))

/proc/om_tick_now(datum/E, B, dt)
	return scheduler_tick_now(arglist(args))

/proc/om_throttled(datum/om/rec/rec, datum/om/behaviour/B, i, bits)
	return scheduler_throttled(arglist(args))

/proc/om_throttle_release(datum/om/rec/rec, datum/om/behaviour/B)
	return scheduler_throttle_release(arglist(args))

/proc/om_diagnostics(datum/om/scheduler/sched)
	return scheduler_diagnostics(arglist(args))

/datum/time_scheduler_factory/make()
	return new /datum/om/scheduler
