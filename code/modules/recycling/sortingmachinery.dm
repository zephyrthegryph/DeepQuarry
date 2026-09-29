/obj/machinery/disposal/deliveryChute
	name = "Delivery chute"
	desc = "A chute for big and small packages alike!"
	density = TRUE
	icon_state = "intake"
	stat_tracking = FALSE
	var/c_mode = FALSE

/obj/machinery/disposal/deliveryChute/interact()
	return

// ALLOW(sys_update_icon): opts out of /obj/machinery/disposal's procedural overlays
/obj/machinery/disposal/deliveryChute/update_icon()
	return

/obj/machinery/disposal/deliveryChute/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_alt/delivery_chute_no_flush,
	)
	..()

/// Old click_alt: never called ..(), so alt-clicking never flushes the chute.
/datum/interaction/machine_alt/delivery_chute_no_flush
	id = "delivery_chute_no_flush"
	name = "Alt-click"
	effect = /atom/proc/interaction_swallow

/obj/machinery/disposal/deliveryChute/Bumped(atom/movable/AM) //Go straight into the chute
	if(QDELETED(AM) || istype(AM, /obj/item/projectile) || istype(AM, /obj/effect) || istype(AM, /obj/mecha))	return
	switch(dir)
		if(NORTH)
			if(AM.loc.y != src.loc.y+1) return
		if(EAST)
			if(AM.loc.x != src.loc.x+1) return
		if(SOUTH)
			if(AM.loc.y != src.loc.y-1) return
		if(WEST)
			if(AM.loc.x != src.loc.x-1) return

	if(isobj(AM) || ismob(AM))
		AM.forceMove(src)
	flush()

/obj/machinery/disposal/deliveryChute/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	if(!QDELETED(source) && (isitem(source) || isliving(source)) && !istype(source, /obj/item/projectile))
		switch(dir)
			if(NORTH)
				if(source.loc.y != src.loc.y+1) return ..()
			if(EAST)
				if(source.loc.x != src.loc.x+1) return ..()
			if(SOUTH)
				if(source.loc.y != src.loc.y-1) return ..()
			if(WEST)
				if(source.loc.x != src.loc.x-1) return ..()
		source.forceMove(src)
		flush()

/obj/machinery/disposal/deliveryChute/screwdriver_act(mob/user, obj/item/I)
	c_mode = !c_mode
	playsound(src, I.usesound, 50, 1)
	to_chat(user, "You [c_mode ? "remove" : "attach"] the screws around the power connection.")
	return ITEM_INTERACT_SUCCESS

/obj/machinery/disposal/deliveryChute/welder_act(mob/user, obj/item/I)
	if(!c_mode)
		return ITEM_INTERACT_BLOCKING
	use_tool(user, I, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, start_self = "You start slicing the floorweld off the delivery chute.", receiver = src, on_done = PROC_REF(welder_act_tool_done_sorter), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/disposal/deliveryChute/proc/welder_act_tool_done_sorter(mob/user)
	if(!src)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, "You sliced the floorweld off the delivery chute.")
	var/obj/structure/disposalconstruct/C = new(src.loc)
	C.ptype = 8
	C.update()
	C.set_anchored(TRUE)
	C.set_density(TRUE)
	replace_with(src, C)
