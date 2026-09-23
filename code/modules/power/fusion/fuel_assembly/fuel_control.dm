/obj/machinery/computer/fusion_fuel_control
	name = "fuel injection control computer"
	desc = "Displays information about the fuel rods."
	circuit = /obj/item/circuitboard/fusion_fuel_control

	icon_keyboard = "tech_key"
	icon_screen = "fuel_screen"

	var/id_tag
	var/scan_range = 25
	var/datum/tgui_module/rustfuel_control/monitor

/obj/machinery/computer/fusion_fuel_control/Initialize(mapload)
	. = ..()
	monitor = new(src)
	monitor.fuel_tag = id_tag

/obj/machinery/computer/fusion_fuel_control/Destroy()
	QDEL_NULL(monitor)
	. = ..()

/obj/machinery/computer/fusion_fuel_control/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/fusion_fuel_control_open_ui,
		/datum/interaction/machine_item/fusion_fuel_control_set_tag,
	)
	..()

/// Old attack_hand: opened the monitor UI (regardless of the gate result, which the old code ignored).
/datum/interaction/machine_hand/fusion_fuel_control_open_ui
	id = "fusion_fuel_control_open_ui"
	name = "Use"
	effect = /obj/machinery/computer/fusion_fuel_control/proc/interaction_open_ui

/obj/machinery/computer/fusion_fuel_control/interaction_open_ui(mob/user, obj/item/held, datum/interaction/interaction)
	if(stat & (BROKEN|NOPOWER))
		return TRUE

	monitor.tgui_interact(user)
	return TRUE

/// Old attackby: a multitool sets the fuel ident tag.
/datum/interaction/machine_item/fusion_fuel_control_set_tag
	id = "fusion_fuel_control_set_tag"
	name = "Set ident tag"
	category = INTERACTION_CAT_CONFIGURE
	tool = TOOL_MULTITOOL
	tool_volume = 0
	effect = /obj/machinery/computer/fusion_fuel_control/proc/interaction_set_tag

/obj/machinery/computer/fusion_fuel_control/proc/interaction_set_tag(mob/user, obj/item/W, datum/interaction/interaction)
	var/new_ident = tgui_input_text(user, "Enter a new ident tag.", "Fuel Control", monitor.fuel_tag, MAX_NAME_LEN)
	if(new_ident && user.Adjacent(src))
		monitor.fuel_tag = new_ident
	return TRUE
