/datum/holder
	var/datum/other

/datum/holder/proc/setup(datum/thing, datum/cell)
	om_hook(thing, /datum/om/event/item_dropped, src, PROC_REF(dropped))
	om_hook(thing, /datum/om/event/moved, src, PROC_REF(moved_to))
	om_hook(cell, /datum/om/event/living_revived, src, TYPE_PROC_REF(/datum/holder, revived))
	var/ok = om_hook(thing, /datum/om/event/qdeleting, src, PROC_REF(quiet))
	// a string and a comment that name it stay as they are
	var/note = "om_hook(thing, /datum/om/event/moved, src, PROC_REF(moved_to))"
	// om_hook(thing, /datum/om/event/moved, src, PROC_REF(moved_to)) is documented here
	return ok

/datum/holder/proc/dropped(datum/source, datum/om/event/item_dropped/event)
	EVENT_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE)
	// source is the thing, event.user the dropper
	var/datum/who = event.user
	return source

/datum/holder/proc/moved_to(datum/source, datum/om/event/moved/event)
	EVENT_HANDLER
	return event?.old_loc

/datum/holder/proc/revived(atom/movable/source, datum/om/event/living_revived/event)
	return event.source

/datum/holder/proc/quiet(datum/source, datum/om/event/qdeleting/event)
	return TRUE
