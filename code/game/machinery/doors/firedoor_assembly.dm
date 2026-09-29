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

DECLARE_APPEARANCE(/obj/structure/firedoor_assembly, "glass", list("1" = list(APPEARANCE_ICON = 'icons/obj/doors/DoorHazardGlass.dmi'), APPEARANCE_ANY = list(APPEARANCE_ICON = 'icons/obj/doors/DoorHazard.dmi')))
DECLARE_APPEARANCE(/obj/structure/firedoor_assembly, "anchored", list("1" = list(APPEARANCE_ICON_STATE = "door_anchored"), APPEARANCE_ANY = list(APPEARANCE_ICON_STATE = "door_construction")))

DECLARE_INTERACTIONS(/obj/structure/firedoor_assembly, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/firedoor_assembly/proc/interaction_item(mob/user, obj/item/C, datum/interaction/interaction)
	if(istype(C, /obj/item/stack/cable_coil) && !wired && anchored)
		var/obj/item/stack/cable_coil/cable = C
		if (cable.get_amount() < 1)
			to_chat(user, span_warning("You need one length of coil to wire \the [src]."))
			return INTERACTION_HANDLED_PASS
		act_message(user, src, MSG_SELF("You start to wire %T%."), MSG_OTHERS("%U% wires %T%."))
		om_task_timed(user, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user, cable))

	else if(istype(C, /obj/item/circuitboard/airalarm) && wired)
		if(anchored)
			play_sfx(src, SFX_ITEMS_DECONSTRUCT)
			act_message(user, src, MSG_SELF("You have inserted the circuit into %T%!"), MSG_OTHERS(span_warning("%U% has inserted a circuit into %T%!")))
			if(glass)
				new /obj/machinery/door/firedoor/glass(loc)
			else
				new /obj/machinery/door/firedoor(loc)
			consume(C, user)
			qdel(src)
		else
			to_chat(user, span_warning("You must secure \the [src] first!"))
	else if(istype(C, /obj/item/stack/material) && C.get_material_name() == MAT_RGLASS && !glass)
		var/obj/item/stack/S = C
		if (S.get_amount() >= 1)
			play_sfx(src, SFX_ITEMS_CROWBAR, 2)
			act_message(user, src, MSG_SELF(span_notice("You start to install [S.name] into %T%.")), MSG_OTHERS(span_info("%U% adds [S.name] to %T%.")))
			om_task_timed(user, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done2), done_args = list(user, S))

	else
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/structure/firedoor_assembly/proc/attackby_timed_done(mob/user, obj/item/stack/cable_coil/cable)
	if(!(!wired && anchored))
		return
	if (cable.use(1))
		wired = 1
		to_chat(user, span_notice("You wire \the [src]."))
/obj/structure/firedoor_assembly/proc/attackby_timed_done2(mob/user, obj/item/stack/S)
	if(!(!glass && S.use(1)))
		return
	to_chat(user, span_notice("You installed reinforced glass windows into \the [src]."))
	glass = TRUE
	update_icon()

/obj/structure/firedoor_assembly/wirecutter_act(mob/user, obj/item/tool)
	if(!wired)
		return FALSE
	playsound(src, tool.usesound, 100, TRUE)
	act_message(user, src, MSG_SELF("You start to cut the wires from %T%."), MSG_OTHERS("%U% cuts the wires from %T%."))
	om_task_timed(user, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(wirecutter_act_timed_done), done_args = list(user))
	return TRUE

/obj/structure/firedoor_assembly/proc/wirecutter_act_timed_done(mob/user)
	if(!(!QDELETED(src) && wired))
		return
	to_chat(user, span_notice("You cut the wires!"))
	new /obj/item/stack/cable_coil(loc, 1)
	wired = FALSE

/obj/structure/firedoor_assembly/wrench_act(mob/user, obj/item/tool)
	set_anchored(!anchored)
	playsound(src, tool.usesound, 50, TRUE)
	act_message(user, src, MSG_SELF("You have [anchored ? "" : "un"]secured %T%!"), MSG_OTHERS(span_warning("%U% has [anchored ? "" : "un"]secured %T%!")))
	update_icon()
	return TRUE

/obj/structure/firedoor_assembly/welder_act(mob/user, obj/item/tool)
	if(!glass && anchored)
		return FALSE
	if(glass)
		use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WELDER, volume = 50, amount = 0, start_self = "You start to weld the glass panel out of \the [src].", start_others = "[user] welds the glass panel out of \the [src].", receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
		return TRUE
	use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WELDER, volume = 50, amount = 0, start_self = "You start to disassemble \the [src].", start_others = "[user] disassembles \the [src].", receiver = src, on_done = PROC_REF(welder_act_tool_done2), done_args = list(user))
	return TRUE

/obj/structure/firedoor_assembly/proc/welder_act_tool_done(mob/user)
	to_chat(user, span_notice("You welded the glass panel out!"))
	new /obj/item/stack/material/glass/reinforced(drop_location())
	glass = FALSE
	update_icon()
/obj/structure/firedoor_assembly/proc/welder_act_tool_done2(mob/user)
	act_message(user, src, MSG_SELF("You have disassembled %T%."), MSG_OTHERS(span_warning("%U% has disassembled %T%.")))
	replace_with(src, /obj/item/stack/material/steel, 2)
