// Major Control UI for all things robots can do.
/datum/tgui_module/robot_ui
	name = "Robotact"
	tgui_id = "Robotact"

/datum/tgui_module/robot_ui/tgui_state(mob/user)
	return GLOB.tgui_self_state

/datum/tgui_module/robot_ui/tgui_static_data()
	var/list/data = ..()

	var/mob/living/silicon/robot/R = host

	if(!R.module)
		return data

	var/list/modules = list()
	for(var/obj/item/I as anything in R.module.modules)
		if(!I)
			continue

		UNTYPED_LIST_ADD(modules, list(
			"ref" = REF(I),
			"name" = "[I]",
			"icon" = "[I.icon]",
			"icon_state" = "[I.icon_state]",
		))
	data["modules_static"] = modules

	var/list/emag_modules = list()
	if(R.emagged || R.emag_items)
		for(var/obj/item/I as anything in R.module.emag)
			if(!I)
				continue

			UNTYPED_LIST_ADD(emag_modules, list(
				"ref" = REF(I),
				"name" = "[I.name]",
				"icon" = "[I.icon]",
				"icon_state" = "[I.icon_state]",
			))
	data["emag_modules_static"] = emag_modules

	return data

/datum/tgui_module/robot_ui/tgui_data()
	var/list/data = ..()

	var/mob/living/silicon/robot/R = host

	data["module_name"] = R.module ? "[R.module]" : null

	data["theme"] = R.get_ui_theme()

	if(!R.module)
		return data

	data["name"] = R.name
	data["ai"] = "[R.connected_ai]"
	data["charge"] = R.cell?.charge
	data["max_charge"] = R.cell?.maxcharge
	data["health"] = round(R.vitality() * 100)
	data["max_health"] = 100
	data["light_color"] = R.robot_light_col

	data["weapon_lock"] = !!R.weapon_lock

	var/list/modules = list()
	for(var/obj/item/I as anything in R.module.modules)
		if(!I)
			continue

		LAZYSET(modules, REF(I), R.get_slot_from_module(I))
	data["modules"] = modules

	var/list/emag_modules = list()
	if(R.emagged || R.emag_items)
		for(var/obj/item/I as anything in R.module.emag)
			if(!I)
				continue

			LAZYSET(emag_modules, REF(I), R.get_slot_from_module(I))
	data["emag_modules"] = emag_modules

	var/diagnosis_functional = R.is_component_functioning(ROBOT_SLOT_DIAGNOSIS)
	data["diag_functional"] = diagnosis_functional

	var/list/components = list()
	for(var/datum/robot_component/comp as anything in R.components)
		if(comp.internal && !diagnosis_functional)
			continue // internal parts are only reported by a working diagnosis unit
		UNTYPED_LIST_ADD(components, list(
			"key" = comp.slot,
			"name" = "[comp]",
			"band" = diagnosis_functional ? dq_qualitative_damage_band(comp.get_structural_damage() + comp.get_wiring_damage(), comp.max_damage) : null,
			"idle_usage" = diagnosis_functional ? comp.idle_usage : -1,
			"is_powered" = diagnosis_functional ? comp.is_powered() : 0,
			"toggled" = comp.toggled,
		))
	data["components"] = components

	// Self-diagnosis: the synthetic bus reports faults while the diagnosis
	// unit works.
	var/list/faults = list()
	if(diagnosis_functional)
		var/datum/diagnosis/D = R.diagnose(/datum/diagnostic_profile/robot_analyzer)
		for(var/datum/diagnosis_finding/F as anything in D?.findings)
			UNTYPED_LIST_ADD(faults, list("name" = F.name, "band" = F.band, "location" = F.location))
		qdel(D)
	data["faults"] = faults

	return data

/datum/tgui_module/robot_ui/tgui_act(action, params, datum/tgui/ui)
	. = ..()
	if(.)
		return

	var/mob/living/silicon/robot/R = host

	switch(action)
		if("set_light_col")
			var/new_color = params["value"]
			if(findtext(new_color, GLOB.is_color))
				R.robot_light_col = new_color
			. = TRUE
		if("select_module")
			R.pick_module()
			. = TRUE
		if("toggle_component")
			var/slot = text2num(params["component"])
			var/datum/robot_component/C = R.get_component(slot)
			if(istype(C) && !C.internal && R.toggle_component(slot))
				if(C.toggled)
					to_chat(ui.user, span_notice("You enable [C]."))
				else
					to_chat(ui.user, span_warning("You disable [C]."))
			. = TRUE
		if("toggle_module")
			if(R.weapon_lock)
				to_chat(ui.user, span_danger("Error: Modules locked."))
				return
			var/obj/item/module = locate(params["ref"])
			if(istype(module))
				if(R.activated(module))
					R.uneq_specific(module)
				else
					R.activate_module(module)
			. = TRUE
		if("activate_module")
			var/obj/item/module = locate(params["ref"])
			if(istype(module) && module.loc == R)
				module.attack_self(R)
			. = TRUE

		// Quick actions
		if("quick_action_comm")
			R.communicator?.attack_self(R)
			. = TRUE
		if("quick_action_pda")
			R.rbPDA?.tgui_interact(R)
			. = TRUE
		if("quick_action_crew_manifest")
			R.subsystem_crew_manifest()
			. = TRUE
		if("quick_action_law_manager")
			R.subsystem_law_manager()
			. = TRUE
		if("quick_action_alarm_monitoring")
			R.subsystem_alarm_monitor()
			. = TRUE
		if("quick_action_power_monitoring")
			R.subsystem_power_monitor()
			. = TRUE
		if("quick_action_take_image")
			R.take_image()
			. = TRUE
		if("quick_action_view_images")
			R.view_images()
			. = TRUE
		if("quick_action_delete_images")
			R.delete_images()
			. = TRUE
		if("quick_action_flashlight")
			dq_use_ability(R, ABILITY_ID_ROBOT_TOGGLE_LIGHTS)
			. = TRUE
		if("quick_action_sensors")
			R.sensor_mode()
			. = TRUE
		if("quick_action_sparks")
			R.spark_plug()
			. = TRUE
