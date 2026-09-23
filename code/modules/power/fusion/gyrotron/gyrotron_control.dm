/obj/machinery/computer/gyrotron_control
	name = "gyrotron control console"
	desc = "Used to control the R-UST stability beams."
	light_color = COLOR_BLUE
	circuit = /obj/item/circuitboard/gyrotron_control

	icon_keyboard = "generic_key"
	icon_screen = "mass_driver"

	var/id_tag
	var/scan_range = 25
	var/datum/tgui_module/gyrotron_control/monitor

/obj/machinery/computer/gyrotron_control/Initialize(mapload)
	. = ..()
	monitor = new(src)
	monitor.gyro_tag = id_tag
	monitor.scan_range = scan_range

/obj/machinery/computer/gyrotron_control/Destroy()
	QDEL_NULL(monitor)
	. = ..()

/obj/machinery/computer/gyrotron_control/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/gyrotron_control_use,
		/datum/interaction/machine_item/gyrotron_control_set_ident,
	)
	..()

/**
 * The old attack_hand: called ..() unconditionally (the machinery gate now runs
 * automatically before this effect) then opened the monitor UI.
 */
/datum/interaction/machine_hand/gyrotron_control_use
	id = "gyrotron_control_use"
	name = "Use"
	effect = /obj/machinery/computer/gyrotron_control/proc/interaction_use

/obj/machinery/computer/gyrotron_control/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(stat & (BROKEN|NOPOWER))
		return TRUE

	monitor.tgui_interact(user)
	return TRUE

/**
 * The old attackby: called ..() unconditionally (which always ran the base attack
 * chain) then, with a multitool, prompted for a new ident tag. This always
 * declines so the base chain still runs after it, approximating the old
 * unconditional ..() call without re-entering the item entry recursively.
 */
/datum/interaction/machine_item/gyrotron_control_set_ident
	id = "gyrotron_control_set_ident"
	name = "Set ident tag"
	tool = TOOL_MULTITOOL
	tool_volume = 0
	effect = /obj/machinery/computer/gyrotron_control/proc/interaction_set_ident

/obj/machinery/computer/gyrotron_control/proc/interaction_set_ident(mob/user, obj/item/W, datum/interaction/interaction)
	if(W.has_tool_quality(TOOL_MULTITOOL))
		var/new_ident = tgui_input_text(user, "Enter a new ident tag.", "Gyrotron Control", monitor.gyro_tag, MAX_NAME_LEN)
		if(new_ident && user.Adjacent(src))
			monitor.gyro_tag = new_ident
	return FALSE
