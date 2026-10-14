// Engine side: the contexts, and helper procs a body may call.
/datum/act
	var/datum/holder
	var/datum/source

/datum/act/action
	var/datum/target
	var/mob/actor

/datum/act/op
	parent_type = /datum/act/action
	var/obj/item/cell/held
	var/list/args

/datum/act/eval
	var/dt

/proc/tracked_changed(datum/E, name)
	return TRUE

/proc/publish_change(datum/E, key)
	return TRUE

/mob
	var/stat = 0
	var/obj/item/cell/pocket
	var/hands_busy = FALSE

TRACKED(/mob, stat)
REL(/mob, pocket)

/obj/item/cell
	var/charge = 0
	var/maxcharge = 100
	var/rating = 5

TRACKED(/obj/item/cell, charge)

/datum/world_service/nightshift
	var/nightshift_active = FALSE

SYSTEM_ACCESSOR(nightshift, night_shift_active, nameof(nightshift_active))

/proc/night_shift_active()
	return GLOB_NIGHT.nightshift_active

/var/datum/world_service/nightshift/GLOB_NIGHT = new
