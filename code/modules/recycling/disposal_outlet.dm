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
	var/tmp/target_handle	// this will be where the output objects are 'thrown' to.
	var/mode = 0
	var/start_eject = 0
	var/eject_range = 3 //Did you know, in TGcode, it's a default of 2 tiles?

/obj/structure/disposaloutlet/Initialize(mapload)
	. = ..()

	update_target()

	var/obj/structure/disposalpipe/trunk/trunk = locate_on(get_turf(src), /obj/structure/disposalpipe/trunk)
	add_disposal_connection()
	om_hook(src, /datum/om/event/disposal_receive, src, PROC_REF(on_disposal_receive))
	if(trunk)
		OM_EMIT(src, /datum/om/event/disposal_link, trunk)

// ALLOW(lifecycle): it unlinks from its trunk.
/obj/structure/disposaloutlet/Destroy()
	OM_EMIT(src, /datum/om/event/disposal_unlink) //Just to be safe.
	target_handle = null
	. = ..()

DECLARE_INTERACTIONS(/obj/structure/disposaloutlet, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/disposaloutlet/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(!I || !user)
		return INTERACTION_HANDLED_PASS
	src.add_fingerprint(user)
	if(mode == OUTLET_SCREWED)
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/structure/disposaloutlet/screwdriver_act(mob/user, obj/item/I)
	mode = mode == OUTLET_SCREWED ? OUTLET_UNSCREWED : OUTLET_SCREWED
	to_chat(user, "You [mode == OUTLET_UNSCREWED ? "remove" : "attach"] the screws around the power connection.")
	playsound(src, I.usesound, 50, 1)
	return ITEM_INTERACT_SUCCESS

/obj/structure/disposaloutlet/welder_act(mob/user, obj/item/I)
	if(mode != OUTLET_UNSCREWED)
		return ITEM_INTERACT_BLOCKING
	use_tool(user, I, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 100, message_self = "You start slicing the floorweld off the disposal outlet.", receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/structure/disposaloutlet/proc/welder_act_tool_done(mob/user)
	if(!src)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, "You sliced the floorweld off the disposal outlet.")
	OM_EMIT(src, /datum/om/event/disposal_unlink)
	var/obj/structure/disposalconstruct/C = new(src.loc)
	transfer_fingerprints_to(C)
	C.set_dir(dir)
	C.ptype = 7
	C.update()
	C.anchored = TRUE
	C.density = TRUE
	replace_with(src, C)

/obj/structure/disposaloutlet/multitool_act(mob/user, obj/item/I)
	if(mode == OUTLET_SCREWED)
		return ITEM_INTERACT_BLOCKING
	var/new_range = rerun_ask(user, "k70", TYPE_PROC_REF(/atom, multitool_act), args, /datum/om/prompt/number, message = "Input a new ejection distance", title = "Set ejection strength", default = 3, max = 5, min = 1)
	if(isnull(new_range))
		return ITEM_INTERACT_BLOCKING
	eject_range = new_range
	to_chat(user, span_notice("You set the range on the [src] to [new_range] tiles."))
	return ITEM_INTERACT_SUCCESS


/// Hooked on our own disposal_receive event.
/obj/structure/disposaloutlet/proc/on_disposal_receive(datum/source, datum/om/event/disposal_receive/event)
	EVENT_HANDLER
	packet_expel(source, event.items, event.gas)

/obj/structure/disposaloutlet/proc/packet_expel(datum/source, list/received_items, datum/gas_mixture/gas)
	SHOULD_NOT_SLEEP(TRUE)

	flick("outlet-open", src)
	if((start_eject + 30) < world.time) // ALLOW(cooldown): eject progress
		start_eject = world.time
		playsound(src, 'sound/machines/warning-buzzer.ogg', 50, 0, 0)
		om_after(src, 2 SECONDS, PROC_REF(expel_contents), received_items, gas, TRUE)
	else
		om_after(src, 2 SECONDS, PROC_REF(expel_contents), received_items, gas)

/obj/structure/disposaloutlet/proc/expel_contents(list/ejected_items, datum/gas_mixture/gas, playsound = FALSE)
	if(playsound)
		playsound(src, 'sound/machines/hiss.ogg', 50, 0, 0)

	var/turf/T = get_turf(src)

	for(var/atom/movable/AM in ejected_items)
		AM.forceMove(T)
		AM.pipe_eject(dir)
		AM.throw_at(target(), eject_range, 1)

	T.assume_air(gas)

/obj/structure/disposaloutlet/set_dir(newdir)
	. = ..()
	update_target()

/obj/structure/disposaloutlet/proc/update_target()
	target_handle = om_handle(get_ranged_target_turf(src, dir, 10))

#undef OUTLET_SCREWED
#undef OUTLET_UNSCREWED

/// LC-refs: this will be where the output objects are 'thrown' to. -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/disposaloutlet/proc/target() as /turf
	return om_resolve(target_handle)
