/datum/tgui_module/computer_configurator
	name = "NTOS Computer Configuration Tool"
	ntos = TRUE
	tgui_id = "Configuration"
	var/tmp/movable_handle

UI_DATA(/datum/tgui_module/computer_configurator, "merge:ui_data_datum_tgui_module_computer_configurator{disk_size:num,disk_used:num,power_usage:num,battery_exists:num,battery_rating:num,battery_percent:num,battery:listmap,hardware:unknown}")

/// The computed part of /datum/tgui_module/computer_configurator's window data (declared on its UI_DATA row).
/datum/tgui_module/computer_configurator/proc/ui_data_datum_tgui_module_computer_configurator(mob/user, datum/tgui/ui, datum/tgui_state/state)
	movable_handle = om_handle(tgui_host())
	// No computer connection, we can't get data from that.
	if(!istype(movable(), /obj/item/modular_computer))
		return 0

	var/list/data = list()

	data["disk_size"] = movable().hard_drive.max_capacity
	data["disk_used"] = movable().hard_drive.used_capacity
	data["power_usage"] = movable().last_power_usage
	data["battery_exists"] = movable().battery_module ? 1 : 0
	if(movable().battery_module)
		data["battery_rating"] = movable().battery_module.battery.maxcharge
		data["battery_percent"] = round(movable().battery_module.battery.percent())

	if(movable().battery_module && movable().battery_module.battery)
		data["battery"] = list("max" = movable().battery_module.battery.maxcharge, "charge" = round(movable().battery_module.battery.charge))

	var/list/hardware = movable().get_all_components()
	var/list/all_entries[0]
	for(var/obj/item/computer_hardware/H in hardware)
		all_entries.Add(list(list(
		"name" = H.name,
		"desc" = H.desc,
		"enabled" = H.enabled,
		"critical" = H.critical,
		"powerusage" = H.power_usage
		)))

	data["hardware"] = all_entries
	return data

UI_ACT(/datum/tgui_module/computer_configurator, "PC_toggle_component", ui_act_pc_toggle_component, UI_ARG_TEXT("name"))
UI_ACT_PROC(/datum/tgui_module/computer_configurator, ui_act_pc_toggle_component)
	var/obj/item/computer_hardware/H = movable().find_hardware_by_name(params["name"])
	if(H && istype(H))
		H.enabled = !H.enabled
	. = TRUE

/// LC-refs: the movable this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/tgui_module/computer_configurator/proc/movable() as /obj/item/modular_computer
	return om_resolve(movable_handle)
