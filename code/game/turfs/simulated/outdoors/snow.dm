/turf/simulated/floor/outdoors/snow
	name = "snow"
	icon_state = "snow"
	edge_blending_priority = 6
	movement_cost = 2
	initial_flooring = /datum/decl/flooring/snow
	var/list/crossed_dirs

TRACKED(/turf/simulated/floor/outdoors/snow, crossed_dirs)

/turf/simulated/floor/outdoors/snow/Entered(atom/A)
	if(isliving(A))
		var/mob/living/L = A
		if(dq_get_hovering(L) || stat_value(L, STAT_FLYING)) // Flying things shouldn't make footprints.
			if(stat_value(L, STAT_FLYING))
				L.adjust_nutrition(-0.5)
			return ..()
		var/mdir = "[A.dir]"
		if(LAZYACCESS(crossed_dirs, mdir) != 1)
			var/list/footprints = crossed_dirs ? crossed_dirs.Copy() : list()
			footprints[mdir] = 1
			set_crossed_dirs(footprints)
	. = ..()

/turf/simulated/floor/outdoors/snow/draw(datum/look/look)
	..()
	for(var/d in crossed_dirs)
		look.overlay(look_overlay_image('icons/turf/outdoors.dmi', "snow_footprints", dir = text2num(d)))

CAPABILITIES(/turf/simulated/floor/outdoors/snow)
	op("snow_shovel", item(/obj/item/shovel), label("Dig up"), begins(PROC_REF(shovel_begins)), wait(4 SECONDS), then(PROC_REF(attackby_tool_done)), on_interrupt(PROC_REF(attackby_tool_failed)))
	op("snow_scoop", hand(), ungated(), label("Scoop"), needs(req_adjacent()), begins(MSG(snow/scooping)), wait(1 SECOND), then(PROC_REF(scoop_done)))

/// A shovel clears the snow away.
/turf/simulated/floor/outdoors/snow/proc/shovel_begins(datum/act/op/A)
	return msg_text("You begin to remove \the [src] with your [A.held].")

/turf/simulated/floor/outdoors/snow/proc/attackby_tool_done(datum/act/op/A)
	to_chat(A.actor, span_notice("\The [src] has been dug up, and now lies in a pile nearby."))
	new /obj/item/stack/material/snow(src, 10)
	demote()

/turf/simulated/floor/outdoors/snow/proc/attackby_tool_failed(datum/act/op/A)
	to_chat(A.actor, span_notice("You decide to not finish removing \the [src]."))

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

