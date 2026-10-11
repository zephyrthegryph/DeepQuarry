/obj/item/stack/cable_coil/heavyduty
	name = "heavy cable coil"
	icon = 'icons/obj/power.dmi'
	icon_state = "wire"

/obj/structure/cable/heavyduty
	icon = 'icons/obj/power_cond_heavy.dmi'
	name = "large power cable"
	desc = "This cable is tough. It cannot be cut with simple hand tools."
	plane = PLATING_PLANE
	layer = PIPES_LAYER - 0.05 //Just below pipes
	color = null
	var/static/allow_cutting = TRUE // Allows heavy cables to be cut by welder, up to server preference or admin vv during round. Changing it on one changes them all!

/obj/structure/cable/heavyduty/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	to_chat(user, span_notice("These cables are too tough to be cut with those [W.name]."))
	return OP_OK

/// The cable is cut only where the plating is bare (a welder elsewhere does nothing).
/obj/structure/cable/heavyduty/proc/on_bare_plating(datum/act/op/A)
	var/turf/T = read_once(loc)
	return istype(T) && read_once(T.is_plating())

/obj/structure/cable/heavyduty/proc/cut_refusal(datum/act/op/A)
	return read_once(allow_cutting) ? null : "something in these cables makes them too strong to cut"

/obj/structure/cable/heavyduty/proc/cut_started(datum/act/op/A)
	playsound(src, sounds_of(A.held).use, 50, TRUE)

/obj/structure/cable/heavyduty/proc/welder_act_tool_done(datum/act/op/A)
	var/mob/user = A.actor
	var/turf/T = loc
	var/obj/item/stack/cable_coil/heavyduty/CC
	if(src.d1)
		CC = new/obj/item/stack/cable_coil/heavyduty(T, 2, color)
	else
		CC = new/obj/item/stack/cable_coil/heavyduty(T, 1, color)

	src.add_fingerprint(user)
	src.transfer_fingerprints_to(CC)
	for(var/mob/O in viewers(src, null))
		O.show_message(span_warning("[user] cuts the cable."), 1)

	replace_with(src, CC)

MSG_DEF_SELF(heavy_cable/needs_heavier, "you will need heavier cables to connect to these")

CAPABILITIES(/obj/structure/cable/heavyduty)
	op("heavy_coil", item(/obj/item/stack/cable_coil), priority(OP_PRIORITY_DEFAULT - 1), label("Connect cable"), needs(req(PROC_REF(heavy_coil_holds))), then(PROC_REF(heavyduty_interaction_item)))
	op("use_welder", lit_welder(fuel = 2), label("Cut the cable"), when(PROC_REF(on_bare_plating)), needs(req(PROC_REF(cut_refusal))), starts(PROC_REF(cut_started)), wait(25 SECONDS), then(PROC_REF(welder_act_tool_done)))

/// Old attackby: only heavy-duty coil connects (the requirement); it then falls through to the cable's own coil handling.
/obj/structure/cable/heavyduty/proc/heavyduty_interaction_item(datum/act/op/A)
	return OP_DECLINE

/obj/item/stack/cable_coil/heavyduty/turf_place(turf/simulated/F, mob/user)
	if(istype(F, /turf/simulated/open))
		to_chat(user, span_infoplain("\The [src] isn't flexible enough to do this!"))
		return
	. = ..()

/obj/structure/cable/heavyduty/cableColor(colorC)
	return

/obj/structure/cable/heavyduty/proc/heavy_coil_holds(datum/act/op/A)
	return (istype(A.held, /obj/item/stack/cable_coil/heavyduty)) ? null : MSG(heavy_cable/needs_heavier)
