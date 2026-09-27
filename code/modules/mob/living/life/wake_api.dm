// Typed producer API for Life wakes. The numeric bits remain an implementation
// detail of the scheduler; these type paths describe what changed.
/datum/life_wake_event
/datum/life_wake_event/body
/datum/life_wake_event/status
/datum/life_wake_event/moved
/datum/life_wake_event/equipment
/datum/life_wake_event/upkeep
/datum/life_wake_event/all

/// Wake the concerns affected by a semantic change, or one Life family.
/// Both forms are type paths, so producer call sites need no numeric masks.
/mob/living/proc/wake_life(event_or_family, reason)
	var/static/list/event_bits = list(
		/datum/life_wake_event/body = LIFE_WAKE_BODY,
		/datum/life_wake_event/status = LIFE_WAKE_STATUS,
		/datum/life_wake_event/moved = LIFE_WAKE_MOVED,
		/datum/life_wake_event/equipment = LIFE_WAKE_EQUIPMENT,
		/datum/life_wake_event/upkeep = LIFE_SYS_UPKEEP,
		/datum/life_wake_event/all = LIFE_SYS_ALL,
	)
	var/bits
	if(ispath(event_or_family, /datum/life_wake_event))
		bits = event_bits[event_or_family]
	else if(ispath(event_or_family, /datum/life_system))
		var/datum/life_system/S = get_life_system(event_or_family)
		bits = S?.bit
	if(!bits)
		stack_trace("wake_life() requires a declared event or Life family path, got [event_or_family]")
		return FALSE
	life_wake(bits, reason)
	return TRUE
