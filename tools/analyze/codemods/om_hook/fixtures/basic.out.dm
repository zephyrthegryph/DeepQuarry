/datum/holder
	var/datum/other

/datum/holder/proc/setup(datum/thing, datum/cell)
	observe(thing, /datum/notice/item_dropped, src, then(PROC_REF(dropped)))
	observe(thing, /datum/notice/moved, src, then(PROC_REF(moved_to)))
	observe(cell, /datum/notice/living_revived, src, then(TYPE_PROC_REF(/datum/holder, revived)))
	var/ok = observe(thing, /datum/notice/qdeleting, src, then(PROC_REF(quiet)))
	// a string and a comment that name it stay as they are
	var/note = "om_hook(thing, /datum/om/event/moved, src, PROC_REF(moved_to))"
	// om_hook(thing, /datum/om/event/moved, src, PROC_REF(moved_to)) is documented here
	return ok

/datum/holder/proc/dropped(datum/act/notice/A)
	EVENT_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE)
	var/datum/source = A.target
	var/datum/notice/item_dropped/event = A
	// source is the thing, event.user the dropper
	var/datum/who = event.user
	return source

/datum/holder/proc/moved_to(datum/act/notice/A)
	EVENT_HANDLER
	var/datum/notice/moved/event = A
	return event?.old_loc

/datum/holder/proc/revived(datum/act/notice/A)
	var/datum/notice/living_revived/event = A
	return event.source_

/datum/holder/proc/quiet(datum/act/notice/A)
	return TRUE
