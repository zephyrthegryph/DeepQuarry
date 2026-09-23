#define OUTLET_SCREWED 0
#define OUTLET_UNSCREWED 1

// the disposal outlet machine
/obj/structure/disposaloutlet
	name = "disposal outlet"
	desc = "An outlet for the pneumatic disposal system."
	icon = 'icons/obj/pipes/disposal.dmi'
	icon_state = "outlet"
	density = TRUE
	anchored = TRUE
	var/active = FALSE // Code appendix.
	var/turf/target // this will be where the output objects are 'thrown' to.
	var/mode = 0
	var/start_eject = 0
	var/eject_range = 3 //Did you know, in TGcode, it's a default of 2 tiles?

/obj/structure/disposaloutlet/Initialize(mapload)
	. = ..()

	update_target()

	var/obj/structure/disposalpipe/trunk/trunk = locate() in get_turf(src)
	AddComponent(/datum/component/disposal_system_connection)
	RegisterSignal(src, COMSIG_DISPOSAL_RECEIVE, PROC_REF(packet_expel))
	if(trunk)
		SEND_SIGNAL(src, COMSIG_DISPOSAL_LINK, trunk)

/obj/structure/disposaloutlet/Destroy()
	SEND_SIGNAL(src, COMSIG_DISPOSAL_UNLINK) //Just to be safe.
	target = null
	. = ..()

/obj/structure/disposaloutlet/attackby(obj/item/I, mob/user)
	if(!I || !user)
		return
	src.add_fingerprint(user)
	if(mode == OUTLET_SCREWED)
		return ..()

/obj/structure/disposaloutlet/screwdriver_act(mob/user, obj/item/I)
	mode = mode == OUTLET_SCREWED ? OUTLET_UNSCREWED : OUTLET_SCREWED
	to_chat(user, "You [mode == OUTLET_UNSCREWED ? "remove" : "attach"] the screws around the power connection.")
	playsound(src, I.usesound, 50, 1)
	return ITEM_INTERACT_SUCCESS

/obj/structure/disposaloutlet/welder_act(mob/user, obj/item/I)
	if(mode != OUTLET_UNSCREWED)
		return ITEM_INTERACT_BLOCKING
	if(use_tool(user, I, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 100, message_self = "You start slicing the floorweld off the disposal outlet."))
		if(!src)
			return ITEM_INTERACT_BLOCKING
		to_chat(user, "You sliced the floorweld off the disposal outlet.")
		SEND_SIGNAL(src, COMSIG_DISPOSAL_UNLINK)
		var/obj/structure/disposalconstruct/C = new(src.loc)
		transfer_fingerprints_to(C)
		C.set_dir(dir)
		C.ptype = 7
		C.update()
		C.anchored = TRUE
		C.density = TRUE
		qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/structure/disposaloutlet/multitool_act(mob/user, obj/item/I)
	if(mode == OUTLET_SCREWED)
		return ITEM_INTERACT_BLOCKING
	var/new_range = tgui_input_number(user, "Input a new ejection distance", "Set ejection strength", 3, 5, 1, round_value = TRUE)
	eject_range = new_range
	to_chat(user, span_notice("You set the range on the [src] to [new_range] tiles."))
	return ITEM_INTERACT_SUCCESS

/obj/structure/disposaloutlet/proc/packet_expel(datum/source, list/received_items, datum/gas_mixture/gas)
	SIGNAL_HANDLER

	flick("outlet-open", src)
	if((start_eject + 30) < world.time)
		start_eject = world.time
		playsound(src, 'sound/machines/warning-buzzer.ogg', 50, 0, 0)
		addtimer(CALLBACK(src, PROC_REF(expel_contents), received_items, gas, TRUE), 2 SECONDS)
	else
		addtimer(CALLBACK(src, PROC_REF(expel_contents), received_items, gas), 2 SECONDS)

/obj/structure/disposaloutlet/proc/expel_contents(list/ejected_items, datum/gas_mixture/gas, playsound = FALSE)
	if(playsound)
		playsound(src, 'sound/machines/hiss.ogg', 50, 0, 0)

	var/turf/T = get_turf(src)

	for(var/atom/movable/AM in ejected_items)
		AM.forceMove(T)
		AM.pipe_eject(dir)
		AM.throw_at(target, eject_range, 1)

	T.assume_air(gas)

/obj/structure/disposaloutlet/set_dir(newdir)
	. = ..()
	update_target()

/obj/structure/disposaloutlet/proc/update_target()
	target = get_ranged_target_turf(src, dir, 10)

#undef OUTLET_SCREWED
#undef OUTLET_UNSCREWED
