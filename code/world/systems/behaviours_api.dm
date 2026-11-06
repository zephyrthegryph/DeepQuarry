// The behaviours system's API (code/controllers/subsystems/behaviours.dm declares the system).
//
//   SSbehaviours.profile_fire_cost() / profile_ticks() / profile_tick_overrun()   reads for the time-track log

/datum/system/behaviours/proc/profile_fire_cost()
	return fire_cost

/datum/system/behaviours/proc/profile_ticks()
	return ticks

/datum/system/behaviours/proc/profile_tick_overrun()
	return tick_overrun
