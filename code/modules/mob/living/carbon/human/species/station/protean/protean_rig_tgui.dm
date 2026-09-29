/*
It's a bit snowflake, but some rigsuit rewriting was necessary to achieved what I wanted
for protean rigsuits, and rolling these changes into the base RIGsuit code would definitely create
merge conflicts down the line.
So here it sits, snowflake code for a single item.
*/

DECLARE_UI_STATE(/obj/item/rig/protean, GLOB.tgui_always_state)

UI_DATA_REPLACE(/obj/item/rig/protean, "cooling=cooling_on:num", "sealing", "emagged=subverted:num", "coverlock=locked:num", "interfacelock=interface_locked:num", "aicontrol=control_overridden:num", "aioverride=ai_override_enabled:num", "securitycheck=security_check_enabled:num", "malf=malfunction_delay:num", "merge:ui_data_obj_item_rig_protean{primarysystem:text,ai:bool,sealed:bool,helmet:text,gauntlets:text,boots:text,chest:text,helmetDeployed:bool,gauntletsDeployed:bool,bootsDeployed:bool,chestDeployed:bool,charge:num,maxcharge:num,chargestatus:num,modules:list}")

/// The computed part of /obj/item/rig/protean's window data (declared on its UI_DATA row).
/obj/item/rig/protean/proc/ui_data_obj_item_rig_protean(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	if(selected_module)
		data["primarysystem"] = "[selected_module.interface_name]"
	else
		data["primarysystem"] = null

	if(loc != user)
		data["ai"] = TRUE
	else
		data["ai"] = FALSE

	data["sealed"] = !canremove
	data["helmet"] = (helmet ? "[helmet.name]" : "None.")
	data["gauntlets"] = (gloves ? "[gloves.name]" : "None.")
	data["boots"] = (boots ?  "[boots.name]" :  "None.")
	data["chest"] = (chest ?  "[chest.name]" :  "None.")

	data["helmetDeployed"] = (helmet && helmet.loc == loc)
	data["gauntletsDeployed"] = (gloves && gloves.loc == loc)
	data["bootsDeployed"] = (boots && boots.loc == loc)
	data["chestDeployed"] = (chest && chest.loc == loc)

	data["charge"] = cell ? round(cell.charge,1) : 0
	data["maxcharge"] = cell ? cell.maxcharge : 0
	data["chargestatus"] = cell ? FLOOR((cell.charge/cell.maxcharge)*50, 1) : 0


	var/list/module_list = list()
	if(!canremove && !sealing)
		var/i = 1
		for(var/obj/item/rig_module/module in installed_modules)
			var/list/module_data = list(
				"index" = i,
				"name" = "[module.interface_name]",
				"desc" = "[module.interface_desc]",
				"can_use" = module.usable,
				"can_select" = module.selectable,
				"can_toggle" = module.toggleable,
				"is_active" = module.active,
				"engagecost" = module.use_power_cost*10,
				"activecost" = module.active_power_cost*10,
				"passivecost" = module.passive_power_cost*10,
				"engagestring" = module.engage_string,
				"activatestring" = module.activate_string,
				"deactivatestring" = module.deactivate_string,
				"damage" = module.damage
				)

			if(module.charges && module.charges.len)
				module_data["charges"] = list()
				var/datum/rig_charge/selected = module.charges["[module.charge_selected]"]
				module_data["realchargetype"] = module.charge_selected
				module_data["chargetype"] = selected ? "[selected.display_name]" : "none"

				for(var/chargetype in module.charges)
					var/datum/rig_charge/charge = module.charges[chargetype]
					module_data["charges"] += list(list("caption" = "[charge.display_name] ([charge.charges])", "index" = "[chargetype]"))

			module_list += list(module_data)
			i++

	if(module_list.len)
		data["modules"] = module_list
	else
		data["modules"] = list()

	return data
