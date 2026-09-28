MATERIAL_MIX(/obj/item/motiontracker, list(MAT_STEEL = 30,MAT_GLASS = 20))
/obj/item/motiontracker
	name = "Motion Tracker"
	desc = "The \"Vibromaster V1.7\", a handheld motion tracker. Often picks up nearby vibrations as motion however."
	icon = 'icons/obj/device_alt.dmi'
	icon_state = "pinoff"
	item_state = "analyzer"
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_BELT
	throwforce = 5
	throw_speed = 4
	throw_range = 20


	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/motiontracker/Initialize(mapload)
	om_hook(GLOB.motiontracker_service, /datum/om/event/movable_motiontracker, src, PROC_REF(handle_motion_tracking))
	. = ..()
	if(ismob(loc))
		var/mob/M = loc
		M.motiontracker_subscribe()

// its holder stops receiving motion pings.
/obj/item/motiontracker/on_destroy(force)
	if(ismob(loc))
		var/mob/M = loc
		M.motiontracker_unsubscribe()
	..()

/obj/item/motiontracker/proc/handle_motion_tracking(datum/source, datum/om/event/movable_motiontracker/event)
	EVENT_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	var/atom/echo_source = om_resolve(event.handle)
	var/atom/scan_pos = src
	if(!isturf(loc))
		scan_pos = loc
	if(!echo_source || get_dist(scan_pos,echo_source) > GLOB.motiontracker_service.max_range || scan_pos.z != echo_source.z)
		return
	flick("pinondirect",src)

/obj/item/motiontracker/Moved(atom/old_loc, direction, forced, movetime)
	. = ..()
	if(ismob(old_loc))
		var/mob/M = old_loc
		M.motiontracker_unsubscribe()
	if(ismob(loc))
		var/mob/M = loc
		M.motiontracker_subscribe()
