//Solar tracker

//Machine that tracks the sun and reports it's direction to the solar controllers
//As long as this is working, solar panels on same powernet will track automatically

/obj/machinery/power/tracker
	name = "solar tracker"
	desc = "A solar directional tracker."
	icon = 'icons/obj/power.dmi'
	icon_state = "tracker"
	anchored = TRUE
	density = TRUE
	use_power = USE_POWER_OFF
	var/glass_type = /obj/item/stack/material/glass

	var/id = 0
	var/sun_angle = 0		// sun angle as set by sun datum
	var/tmp/obj/machinery/power/solar_control/control
	var/SOLAR_MAX_DIST = 60 // ition // ours are >40 away

/obj/machinery/power/tracker/Initialize(mapload, glass_type)
	. = ..()
	update_icon()

/// `connect_to_network()` needs `vg_entity` bound, which only happens once
/// `on_materialize()`'s `vg_bind()` runs -- see the base class override's
/// docs (`code/modules/power/power.dm`).
/obj/machinery/power/tracker/on_materialize()
	. = ..()
	connect_to_network()

//set the control of the tracker to a given computer if closer than SOLAR_MAX_DIST
/obj/machinery/power/tracker/proc/set_control(obj/machinery/power/solar_control/SC)
	if(SC && (get_dist(src, SC) > SOLAR_MAX_DIST))
		return 0
	rel_set(src, "control", SC)
	return 1

//set the control of the tracker to null and removes it from the previous control computer if needed
/obj/machinery/power/tracker/proc/unset_control()
	if(control())
		rel_clear(control(), "connected_tracker")
	rel_clear(src, "control")

//updates the tracker icon and the facing angle for the control computer
/obj/machinery/power/tracker/proc/set_angle(angle)
	sun_angle = angle

	//set icon dir to show sun illumination
	set_dir(turn(NORTH, -angle - 22.5))	// 22.5 deg bias ensures, e.g. 67.5-112.5 is EAST

	if(power_region && (power_region == control().power_region)) //update if we're still in the same grid
		control().cdir = angle

/obj/machinery/power/tracker/crowbar_act(mob/user, obj/item/W)
	playsound(src, 'sound/machines/click.ogg', 50, 1)
	user.visible_message(span_notice("[user] begins to take the glass off the solar tracker."))
	om_task_timed(user, 5 SECONDS, src, src, PROC_REF(remove_glass_done), list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/tracker/proc/remove_glass_done(mob/user)
	var/obj/item/solar_assembly/S = new(loc)
	S.tracker = TRUE
	S.anchored = TRUE
	playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
	user.visible_message(span_notice("[user] takes the glass off the tracker."))
	replace_with(src, glass_type, 2)

// Tracker Electronic

/obj/item/tracker_electronics

	name = "tracker electronics"
	icon = 'icons/obj/doors/door_assembly.dmi'
	icon_state = "door_electronics"
	w_class = ITEMSIZE_SMALL

/// the control this refers to: a relation view, null once that is deleted.
/obj/machinery/power/tracker/proc/control() as /obj/machinery/power/solar_control
	return control
