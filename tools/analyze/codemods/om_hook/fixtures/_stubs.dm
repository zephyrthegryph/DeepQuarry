#define PROC_REF(X) (#X)
#define TYPE_PROC_REF(T, X) (#X)
#define SHOULD_NOT_SLEEP(x)
#define SHOULD_NOT_OVERRIDE(x)
#define EVENT_HANDLER SHOULD_NOT_SLEEP(TRUE)

/datum/om/event
	var/result

/datum/om/event/moved
	var/old_loc

/datum/om/event/qdeleting
	var/force

/datum/om/event/item_dropped
	var/user

/datum/om/event/living_revived
	var/source

/datum/om/event/before/dice_roll
	var/source

/datum/act
	var/datum/holder

/datum/act/notice
	parent_type = /datum/act
	var/datum/target

/datum/notice
	parent_type = /datum/act/notice

/datum/notice/moved
	var/old_loc

/datum/notice/qdeleting
	var/force

/datum/notice/item_dropped
	var/user

/datum/notice/living_revived
	var/source_

/proc/om_hook(datum/source, event_path, datum/listener, proc_ref)
	return 1

/proc/om_unhook(datum/source, event_path, datum/listener)
	return 1

/proc/om_unhook_all(datum/listener)
	return 1

/proc/observe(datum/source, trigger, datum/listener, handler)
	return 1

/proc/unobserve(datum/source, trigger, datum/listener)
	return 1

/proc/then(handler)
	return handler
