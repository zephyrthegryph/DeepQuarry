// Legacy type and global spellings forward to the actual time-engine foundation.

/datum/om/scheduler
	parent_type = /datum/time_scheduler

/datum/om/ring
	parent_type = /datum/cadence_ring








/datum/time_scheduler_factory/make()
	return new /datum/om/scheduler
