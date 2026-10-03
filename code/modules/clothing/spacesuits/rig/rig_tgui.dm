// Just used to force the icon into the rsc, Byond.iconRefMap does the rest
GLOBAL_DATUM_INIT(rigsuit_ui_icon, /icon, 'icons/hud/rig/rig_ui_slots.dmi')

/*
 * This defines the global UI for RIGSuits.
 * It has all of the relevant TGUI procs, but it's entry point is in rig_verbs.dm
 * as part of rig/proc/hardsuit_interface().
 */

/*
 * tgui_interact() is the proc that opens the UI. It doesn't really do anything else, unlike NanoV1.
 * We add an extra argument, custom_state, for the things that want a custom state for their UI.
 */
DECLARE_UI(/obj/item/rig, UI_FROM_VAR("interface_path"))

/// The AI (worn-suit control from outside) gets its own interface.
/obj/item/rig/ui_interface(mob/user)
	return loc != user ? ai_interface_path : interface_path

/obj/item/rig/ui_title(mob/user)
	return interface_title

/*
 * tgui_state() gives the UI the state to use by default.
 */
DECLARE_UI_STATE(/obj/item/rig, GLOB.tgui_inventory_state)

/*
 * tgui_status() is middlewere for objects to add little exceptions or special cases to the state they use.
 * In this case, we're using it in order to make the UI refuse to let the user press any buttons if they're
 * not authorized to do so.
 * This saves us two lines of code in tgui_act().
 */
/obj/item/rig/tgui_status(mob/user, datum/tgui_state/state)
	. = ..()
	if(!check_suit_access(user, FALSE)) // don't send a message to the user, this is a UI thing
		// Forces the UI to never go interactive,
		// but doesn't interfere with state saying to close.
		. = min(., STATUS_UPDATE)

/*
 * tgui_data() is the heavy lifter, it gives the UI it's relevant datastructure every SStgui tick.
 */
UI_DATA_REPLACE(/obj/item/rig, "cooling=cooling_on:num", "sealing", "emagged=subverted:num", "coverlock=locked:num", "interfacelock=interface_locked:num", "aicontrol=control_overridden:num", "aioverride=ai_override_enabled:num", "securitycheck=security_check_enabled:num", "malf=malfunction_delay:num", "merge:ui_data_obj_item_rig{primarysystem:text,ai:bool,sealed:bool,helmet:text,gauntlets:text,boots:text,chest:text,helmetDeployed:bool,gauntletsDeployed:bool,bootsDeployed:bool,chestDeployed:bool,charge:num,maxcharge:num,chargestatus:num,modules:list}")

/// The computed part of /obj/item/rig's window data (declared on its UI_DATA row).
/obj/item/rig/proc/ui_data_obj_item_rig(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/*
 * Sends data once each time the UI is opened.
 */
/obj/item/rig/tgui_static_data(mob/user)
	var/list/data = ..()

	data["interface_intro"] = interface_intro

	return data


/datum/asset/simple/rig
	assets = list(
		"tentacles.mp4" = 'icons/hud/rig/tentacles.mp4',
	)

/obj/item/rig/ui_assets(mob/user)
	. = ..()
	. += get_asset_datum(/datum/asset/simple/rig)

/*
 * tgui_act() is the TGUI equivelent of Topic(). It's responsible for all of the "actions" you can take in the UI.
 */
/obj/item/rig/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/item/rig, "toggle_seals", ui_act_toggle_seals)
UI_ACT_PROC(/obj/item/rig, ui_act_toggle_seals)
	toggle_seals(ui.user)
	. = TRUE

UI_ACT(/obj/item/rig, "toggle_cooling", ui_act_toggle_cooling)
UI_ACT_PROC(/obj/item/rig, ui_act_toggle_cooling)
	toggle_cooling(ui.user) // cooling toggles have its own to_chats, tbf
	. = TRUE

UI_ACT(/obj/item/rig, "toggle_ai_control", ui_act_toggle_ai_control)
UI_ACT_PROC(/obj/item/rig, ui_act_toggle_ai_control)
	ai_override_enabled = !ai_override_enabled
	notify_ai("Synthetic suit control has been [ai_override_enabled ? "enabled" : "disabled"].")
	. = TRUE

UI_ACT(/obj/item/rig, "toggle_suit_lock", ui_act_toggle_suit_lock)
UI_ACT_PROC(/obj/item/rig, ui_act_toggle_suit_lock)
	locked = !locked
	. = TRUE

UI_ACT(/obj/item/rig, "toggle_piece", ui_act_toggle_piece, UI_ARG_TEXT("piece"))
UI_ACT_PROC(/obj/item/rig, ui_act_toggle_piece)
	if(ishuman(ui.user) && (ui.user.stat || ui.user.has_status(EFFECT_STUNNED) || ui.user.lying))
		return FALSE
	toggle_piece(params["piece"], ui.user)
	. = TRUE

UI_ACT(/obj/item/rig, "interact_module", ui_act_interact_module, UI_ARG_TEXT("charge_type"), UI_ARG_NUM("module"), UI_ARG_TEXT("module_mode"))
UI_ACT_PROC(/obj/item/rig, ui_act_interact_module)
	var/module_index = params["module"]

	if(module_index > 0 && module_index <= length(installed_modules))
		var/obj/item/rig_module/module = LAZYACCESS(installed_modules, module_index)
		switch(params["module_mode"])
			if("select")
				rel_set(src, nameof(/datum/tgui_module/robot_ui_module::selected_module), module)
				. = TRUE
			if("engage")
				module.engage(null, FALSE, ui.user)
				. = TRUE
			if("toggle")
				if(module.active)
					module.deactivate()
				else
					module.activate(FALSE, ui.user)
				. = TRUE
			if("select_charge_type")
				module.charge_selected = params["charge_type"]
				. = TRUE

UI_ACT(/obj/item/rig, "tank_settings", ui_act_tank_settings)
UI_ACT_PROC(/obj/item/rig, ui_act_tank_settings)
	air_supply?.attack_self(ui.user)
	. = TRUE
