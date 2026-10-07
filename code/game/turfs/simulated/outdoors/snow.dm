/turf/simulated/floor/outdoors/snow
	name = "snow"
	icon_state = "snow"
	edge_blending_priority = 6
	movement_cost = 2
	initial_flooring = /datum/decl/flooring/snow
	var/list/crossed_dirs


/turf/simulated/floor/outdoors/snow/Entered(atom/A)
	if(isliving(A))
		var/mob/living/L = A
		if(dq_get_hovering(L) || L.flying) // Flying things shouldn't make footprints.
			if(L.flying)
				L.adjust_nutrition(-0.5)
			return ..()
		var/mdir = "[A.dir]"
		LAZYSET(crossed_dirs, mdir, 1)
		update_icon()
	. = ..()

DECLARE_APPEARANCE_PROC(/turf/simulated/floor/outdoors/snow, TYPE_PROC_REF(/atom, appearance_overlays), list())
/turf/simulated/floor/outdoors/snow/appearance_overlays()
	. = list()
	. += ..()
	for(var/d in crossed_dirs)
		. += image(icon = 'icons/turf/outdoors.dmi', icon_state = "snow_footprints", dir = text2num(d))

CAPABILITIES(/turf/simulated/floor/outdoors/snow)
	op("snow_shovel", item(/obj/item/shovel), label("Dig up"), then(PROC_REF(snow_shovel)))
	op("snow_scoop", hand(), ungated(), label("Scoop"), needs(req_adjacent()), begins(MSG(snow/scooping)), wait(1 SECOND), then(PROC_REF(scoop_done)))

/// Old attackby: shovel the snow away.
/turf/simulated/floor/outdoors/snow/proc/snow_shovel(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	use_tool(user, W, src, delay = 4 SECONDS, volume = 0, start_self = "You begin to remove \the [src] with your [W].", receiver = src, on_done = PROC_REF(attackby_tool_done), done_args = list(user), on_fail = PROC_REF(attackby_tool_failed), fail_args = list(user))
	return OP_PASS

/turf/simulated/floor/outdoors/snow/proc/attackby_tool_done(mob/user)
	to_chat(user, span_notice("\The [src] has been dug up, and now lies in a pile nearby."))
	new /obj/item/stack/material/snow(src, 10)
	demote()

/turf/simulated/floor/outdoors/snow/proc/attackby_tool_failed(mob/user)
	to_chat(user, span_notice("You decide to not finish removing \the [src]."))

MSG_DEF(snow/scooping, null, "%U% starts scooping up some snow.")

/turf/simulated/floor/outdoors/snow/proc/scoop_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/S = new /obj/item/stack/material/snow(user.loc)
	user.put_in_hands(S)
	act_message(user, null, others = "%U% scoops up a pile of snow.", blind = "You scoop up a pile of snow.")

/turf/simulated/floor/outdoors/ice
	name = "ice"
	icon_state = "ice"
	desc = "Looks slippery."
	edge_blending_priority = 0
	can_be_plated = FALSE
	wet = TURFSLIP_ICE


// Extra cold variants

