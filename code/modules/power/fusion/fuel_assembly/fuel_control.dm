/obj/machinery/computer/fusion_fuel_control
	name = "fuel injection control computer"
	desc = "Displays information about the fuel rods."
	circuit = /obj/item/circuitboard/fusion_fuel_control

	icon_keyboard = "tech_key"
	icon_screen = "fuel_screen"

	var/id_tag
	var/scan_range = 25
	var/datum/tgui_module/rustfuel_control/monitor

DECLARE_DEFAULT_CHILD(/obj/machinery/computer/fusion_fuel_control, "monitor", /datum/tgui_module/rustfuel_control)

/obj/machinery/computer/fusion_fuel_control/Initialize(mapload)
	. = ..()
	monitor.fuel_tag = id_tag

DECLARE_REF(/obj/machinery/computer/fusion_fuel_control, "monitor", OWNED, null)

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
	effect = /obj/machinery/computer/fusion_fuel_control/proc/interaction_open_ui_impl

/obj/machinery/computer/fusion_fuel_control/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
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
	var/new_ident = rerun_ask(user, "k52", PROC_REF(interaction_set_tag), args, /datum/om/prompt/text, message = "Enter a new ident tag.", title = "Fuel Control", default = monitor.fuel_tag, max_length = MAX_NAME_LEN)
	if(isnull(new_ident))
		return
	if(new_ident && user.Adjacent(src))
		monitor.fuel_tag = new_ident
	return TRUE
