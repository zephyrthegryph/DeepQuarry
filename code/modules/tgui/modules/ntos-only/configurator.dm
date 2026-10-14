/datum/tgui_module/computer_configurator
	name = "NTOS Computer Configuration Tool"
	ntos = TRUE
	var/tmp/obj/item/modular_computer/movable

CAPABILITIES(/datum/tgui_module/computer_configurator)
	interface("Configuration")
	op("PC_toggle_component", ui_act("PC_toggle_component", arg("name", schema_text(4096))), then(PROC_REF(ui_act_pc_toggle_component)))

/datum/tgui_module/computer_configurator/ui_data(datum/act/eval/A)
	rel_set(src, nameof(movable), tgui_host())
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

/datum/tgui_module/computer_configurator/proc/ui_act_pc_toggle_component(datum/act/op/A, name)
	var/obj/item/computer_hardware/H = movable().find_hardware_by_name(name)
	if(H && istype(H))
		H.enabled = !H.enabled
	. = TRUE

/// The movable this refers to (a relation view: null once that is deleted).
/datum/tgui_module/computer_configurator/proc/movable() as /obj/item/modular_computer
	return movable
