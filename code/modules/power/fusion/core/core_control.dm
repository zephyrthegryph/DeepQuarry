/obj/machinery/computer/fusion_core_control
	name = "\improper R-UST Mk. 8 core control"
	light_color = COLOR_ORANGE
	circuit = /obj/item/circuitboard/fusion_core_control

	icon_keyboard = "tech_key"
	icon_screen = "core_control"

	var/id_tag = ""
	var/scan_range = 25
	var/list/connected_devices = list()
	var/obj/machinery/power/fusion_core/cur_viewed_device
	var/datum/tgui_module/rustcore_monitor/monitor

/obj/machinery/computer/fusion_core_control/Initialize(mapload)
	. = ..()
	monitor = new(src)
	monitor.core_tag = id_tag

/obj/machinery/computer/fusion_core_control/Destroy()
	QDEL_NULL(monitor)
	. = ..()

/obj/machinery/computer/fusion_core_control/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/fusion_core_control_multitool,
		/datum/interaction/machine_hand/fusion_core_control_open_ui,
	)
	..()

/**
 * Old attackby: called ..() unconditionally before its own check, so the base attack chain
 * always ran regardless of the item. The effect always declines so the base still runs.
 */
/datum/interaction/machine_item/fusion_core_control_multitool
	id = "fusion_core_control_multitool"
	name = "Set core tag"
	tool = TOOL_MULTITOOL
	tool_volume = 0
	effect = /obj/machinery/computer/fusion_core_control/proc/interaction_multitool

/obj/machinery/computer/fusion_core_control/proc/interaction_multitool(mob/user, obj/item/thing, datum/interaction/interaction)
	var/new_ident = sanitize_text(tgui_input_text(user, "Enter a new ident tag.", "Core Control", monitor.core_tag))
	if(new_ident && user.Adjacent(src))
		monitor.core_tag = new_ident
	return FALSE

/// Old attack_hand: called ..() unconditionally, then ignored its result and did its own stat check.
/datum/interaction/machine_hand/fusion_core_control_open_ui
	id = "fusion_core_control_open_ui"
	name = "Use"
	effect = /obj/machinery/computer/fusion_core_control/proc/interaction_open_ui_impl

/obj/machinery/computer/fusion_core_control/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	if(stat & (BROKEN|NOPOWER))
		return TRUE

	monitor.tgui_interact(user)
	return TRUE

//Returns 1 if the machine can be interacted with via this console.
/obj/machinery/computer/fusion_core_control/proc/check_core_status(obj/machinery/power/fusion_core/C)
	return istype(C) ? C.check_core_status() : FALSE
