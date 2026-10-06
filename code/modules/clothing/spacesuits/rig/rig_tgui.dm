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

/// The AI (worn-suit control from outside) gets its own interface.
/obj/item/rig/ui_interface(mob/user)
	return loc != user ? ai_interface_path : interface_path

/obj/item/rig/ui_title(mob/user)
	return interface_title

/*
 * tgui_state() gives the UI the state to use by default.
 */

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
/obj/item/rig/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["cooling"] = cooling_on
	data["sealing"] = sealing
	data["emagged"] = subverted
	data["coverlock"] = locked
	data["interfacelock"] = interface_locked
	data["aicontrol"] = control_overridden
	data["aioverride"] = ai_override_enabled
	data["securitycheck"] = security_check_enabled
	data["malf"] = malfunction_delay
	var/list/merged_1 = ui_data_obj_item_rig(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/rig's window data.
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
/obj/item/rig/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	return TRUE

/obj/item/rig/proc/ui_act_toggle_seals(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	toggle_seals(user)
	. = TRUE

/obj/item/rig/proc/ui_act_toggle_cooling(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	toggle_cooling(user) // cooling toggles have its own to_chats, tbf
	. = TRUE

/obj/item/rig/proc/ui_act_toggle_ai_control(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	ai_override_enabled = !ai_override_enabled
	notify_ai("Synthetic suit control has been [ai_override_enabled ? "enabled" : "disabled"].")
	. = TRUE

/obj/item/rig/proc/ui_act_toggle_suit_lock(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	locked = !locked
	. = TRUE

/obj/item/rig/proc/ui_act_toggle_piece(datum/act/op/A, piece)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(ishuman(user) && (user.stat || user.has_status(EFFECT_STUNNED) || user.lying))
		return FALSE
	toggle_piece(piece, user)
	. = TRUE

/obj/item/rig/proc/ui_act_interact_module(datum/act/op/A, charge_type, module_arg, module_mode)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/module_index = module_arg

	if(module_index > 0 && module_index <= length(installed_modules))
		var/obj/item/rig_module/module = LAZYACCESS(installed_modules, module_index)
		switch(module_mode)
			if("select")
				rel_set(src, nameof(selected_module), module)
				. = TRUE
			if("engage")
				module.engage(null, FALSE, user)
				. = TRUE
			if("toggle")
				if(module.active)
					module.deactivate(FALSE, user)
				else
					module.activate(FALSE, user)
				. = TRUE
			if("select_charge_type")
				module.charge_selected = charge_type
				. = TRUE

/obj/item/rig/proc/ui_act_tank_settings(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	air_supply?.attack_self(user)
	. = TRUE
