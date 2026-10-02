// Engine side: the context types (the fields each hook form sets), the action calls, a standard output base.
/datum/act
	var/datum/holder
	var/datum/capability/cap
	var/datum/source

/datum/act/action
	var/datum/target
	var/mob/actor
	var/outcome

/datum/act/op
	parent_type = /datum/act/action
	var/obj/item/held
	var/list/args

/datum/act/eval
	var/dt

/datum/act/notice
	var/datum/target

/datum/act/timer
	var/dt
	var/list/args

/datum/act/request
	var/datum/request/request

/datum/act/fall
	parent_type = /datum/act/action
	var/turf/landing

/datum/act/hit
	parent_type = /datum/act/action

/datum/capability
	var/name = "cap"

/datum/look
	var/state = ""

/datum/act/proc/snapshot()
	return list()

/proc/act_try(datum/holder, act_type, ...)
	return null

/proc/act_done(datum/act/A)
	return TRUE

/proc/act_cancel(datum/act/A)
	return TRUE

/proc/after(delay, proc_ref, with = null)
	return TRUE

/proc/to_chat(target, text)
	return TRUE

/proc/tracked_changed(datum/E, name)
	return TRUE

/atom/proc/draw(datum/look/look)
	return
