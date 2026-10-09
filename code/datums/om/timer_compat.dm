// Legacy spellings forward to the time engine; timer state and execution live there.









































/datum/om/global_owner
	parent_type = /datum/timer_owner

// Legacy carriers still declare relations on this concrete owner subtype.
/datum/time_scheduler/make_timer_owner()
	return new /datum/om/global_owner


/mob/living/timer_clock()
	return CLOCK_BIO

/datum/om/behaviour/internal/timers
	parent_type = /datum/scheduled_behaviour/internal/timers
	abstract_type = /datum/om/behaviour/internal/timers
