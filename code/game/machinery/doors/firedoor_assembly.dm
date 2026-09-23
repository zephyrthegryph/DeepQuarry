/obj/structure/firedoor_assembly
	name = "\improper emergency shutter assembly"
	desc = "It can save lives."
	icon = 'icons/obj/doors/DoorHazard.dmi'
	icon_state = "door_construction"
	anchored = FALSE
	opacity = 0
	density = TRUE
	var/wired = 0
	var/glass = FALSE

/obj/structure/firedoor_assembly/update_icon()
	if(glass)
		icon = 'icons/obj/doors/DoorHazardGlass.dmi'
	else
		icon = 'icons/obj/doors/DoorHazard.dmi'
	if(anchored)
		icon_state = "door_anchored"
	else
		icon_state = "door_construction"

/obj/structure/firedoor_assembly/attackby(obj/item/C, mob/user as mob)
	if(istype(C, /obj/item/stack/cable_coil) && !wired && anchored)
		var/obj/item/stack/cable_coil/cable = C
		if (cable.get_amount() < 1)
			to_chat(user, span_warning("You need one length of coil to wire \the [src]."))
			return
		user.visible_message("[user] wires \the [src].", "You start to wire \the [src].")
		if(do_after(user, 4 SECONDS, target = src) && !wired && anchored)
			if (cable.use(1))
				wired = 1
				to_chat(user, span_notice("You wire \the [src]."))

	else if(istype(C, /obj/item/circuitboard/airalarm) && wired)
		if(anchored)
			playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
			user.visible_message(span_warning("[user] has inserted a circuit into \the [src]!"),
								  "You have inserted the circuit into \the [src]!")
			if(glass)
				new /obj/machinery/door/firedoor/glass(loc)
			else
				new /obj/machinery/door/firedoor(loc)
			qdel(C)
			qdel(src)
		else
			to_chat(user, span_warning("You must secure \the [src] first!"))
	else if(istype(C, /obj/item/stack/material) && C.get_material_name() == MAT_RGLASS && !glass)
		var/obj/item/stack/S = C
		if (S.get_amount() >= 1)
			playsound(src, 'sound/items/Crowbar.ogg', 100, 1)
			user.visible_message(span_info("[user] adds [S.name] to \the [src]."),
								span_notice("You start to install [S.name] into \the [src]."))
			if(do_after(user, 4 SECONDS, target = src) && !glass && S.use(1))
				to_chat(user, span_notice("You installed reinforced glass windows into \the [src]."))
				glass = TRUE
				update_icon()

	else
		..(C, user)

/obj/structure/firedoor_assembly/wirecutter_act(mob/user, obj/item/tool)
	if(!wired)
		return FALSE
	playsound(src, tool.usesound, 100, TRUE)
	user.visible_message("[user] cuts the wires from \the [src].", "You start to cut the wires from \the [src].")
	if(do_after(user, 4 SECONDS, target = src) && !QDELETED(src) && wired)
		to_chat(user, span_notice("You cut the wires!"))
		new /obj/item/stack/cable_coil(loc, 1)
		wired = FALSE
	return TRUE

/obj/structure/firedoor_assembly/wrench_act(mob/user, obj/item/tool)
	anchored = !anchored
	playsound(src, tool.usesound, 50, TRUE)
	user.visible_message(span_warning("[user] has [anchored ? "" : "un"]secured \the [src]!"), "You have [anchored ? "" : "un"]secured \the [src]!")
	update_icon()
	return TRUE

/obj/structure/firedoor_assembly/welder_act(mob/user, obj/item/tool)
	if(!glass && anchored)
		return FALSE
	if(glass)
		if(use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WELDER, volume = 50, amount = 0,
				message_self = "You start to weld the glass panel out of \the [src].",
				message_others = "[user] welds the glass panel out of \the [src]."))
			to_chat(user, span_notice("You welded the glass panel out!"))
			new /obj/item/stack/material/glass/reinforced(drop_location())
			glass = FALSE
			update_icon()
		return TRUE
	if(use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WELDER, volume = 50, amount = 0,
			message_self = "You start to disassemble \the [src].",
			message_others = "[user] disassembles \the [src]."))
		user.visible_message(span_warning("[user] has disassembled \the [src]."), "You have disassembled \the [src].")
		new /obj/item/stack/material/steel(drop_location(), 2)
		qdel(src)
	return TRUE
