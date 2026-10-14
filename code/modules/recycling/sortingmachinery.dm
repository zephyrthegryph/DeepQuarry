/obj/machinery/disposal/deliveryChute
	name = "Delivery chute"
	desc = "A chute for big and small packages alike!"
	density = TRUE
	icon_state = "intake"
	stat_tracking = FALSE
	var/c_mode = FALSE

/obj/machinery/disposal/deliveryChute/interact()
	return

/// A delivery chute draws none of a bin's handle and lights.
/obj/machinery/disposal/deliveryChute/look_parts(datum/look/look)
	return

CAPABILITIES(/obj/machinery/disposal/deliveryChute)
	op("swallow", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT), label("Alt-click"), then(TYPE_PROC_REF(/atom, op_swallow)))

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

/obj/machinery/disposal/deliveryChute/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	c_mode = !c_mode
	playsound(src, sounds_of(I).use, 50, 1)
	to_chat(user, "You [c_mode ? "remove" : "attach"] the screws around the power connection.")
	return OP_OK

/// A chute is unwelded when its panel is open (c_mode), whatever its mode.
/obj/machinery/disposal/deliveryChute/unweldable_mode(datum/act/op/A)
	return !!read_once(c_mode)

/obj/machinery/disposal/deliveryChute/empty_refusal(datum/act/op/A)
	return null

/obj/machinery/disposal/deliveryChute/slice_begins(datum/act/op/A)
	return msg_text("You start slicing the floorweld off the delivery chute.")

/obj/machinery/disposal/deliveryChute/welder_act_tool_done(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, "You sliced the floorweld off the delivery chute.")
	var/obj/structure/disposalconstruct/C = new(src.loc)
	C.ptype = 8
	C.update()
	C.set_anchored(TRUE)
	C.set_density(TRUE)
	replace_with(src, C)
