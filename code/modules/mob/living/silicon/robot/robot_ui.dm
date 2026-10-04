// Major Control UI for all things robots can do.
/datum/tgui_module/robot_ui
	name = "Robotact"
	tgui_id = "Robotact"

DECLARE_UI_STATE(/datum/tgui_module/robot_ui, GLOB.tgui_self_state)

/datum/tgui_module/robot_ui/tgui_static_data()
	var/list/data = ..()

	var/mob/living/silicon/robot/R = host()

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

UI_DATA(/datum/tgui_module/robot_ui, "merge:ui_data_datum_tgui_module_robot_ui{module_name:text,theme:unknown,name:text,ai:text,charge:num,max_charge:num,health:num,max_health:num,light_color:text,weapon_lock:bool,modules:list,emag_modules:list,diag_functional:unknown,components:list,faults:list}")

/// The computed part of /datum/tgui_module/robot_ui's window data (declared on its UI_DATA row).
/datum/tgui_module/robot_ui/proc/ui_data_datum_tgui_module_robot_ui(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/mob/living/silicon/robot/R = host()

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

	data["weapon_lock"] = !!after_pending(R, "weapon_lock")

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

UI_ACT(/datum/tgui_module/robot_ui, "set_light_col", ui_act_set_light_col, UI_ARG_TEXT("value"))
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_set_light_col)
	var/mob/living/silicon/robot/R = host()
	var/new_color = params["value"]
	if(findtext(new_color, GLOB.is_color))
		R.robot_light_col = new_color
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "select_module", ui_act_select_module)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_select_module)
	var/mob/living/silicon/robot/R = host()
	R.pick_module()
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "toggle_component", ui_act_toggle_component, UI_ARG_NUM("component"))
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_toggle_component)
	var/mob/living/silicon/robot/R = host()
	var/slot = params["component"]
	var/datum/robot_component/C = R.get_component(slot)
	if(istype(C) && !C.internal && R.toggle_component(slot))
		if(C.toggled)
			to_chat(ui.user, span_notice("You enable [C]."))
		else
			to_chat(ui.user, span_warning("You disable [C]."))
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "toggle_module", ui_act_toggle_module, UI_ARG_REF("ref", null, /obj/item))
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_toggle_module)
	var/mob/living/silicon/robot/R = host()
	if(after_pending(R, "weapon_lock"))
		to_chat(ui.user, span_danger("Error: Modules locked."))
		return
	var/obj/item/module = params["ref"]
	if(istype(module))
		if(R.activated(module))
			R.uneq_specific(module)
		else
			R.activate_module(module)
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "activate_module", ui_act_activate_module, UI_ARG_REF("ref", null, /obj/item))
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_activate_module)
	var/mob/living/silicon/robot/R = host()
	var/obj/item/module = params["ref"]
	if(istype(module) && module.loc == R)
		module.attack_self(R)
	. = TRUE

// Quick actions

UI_ACT(/datum/tgui_module/robot_ui, "quick_action_comm", ui_act_quick_action_comm)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_quick_action_comm)
	var/mob/living/silicon/robot/R = host()
	R.communicator?.attack_self(R)
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "quick_action_pda", ui_act_quick_action_pda)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_quick_action_pda)
	var/mob/living/silicon/robot/R = host()
	R.rbPDA?.tgui_interact(R)
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "quick_action_crew_manifest", ui_act_quick_action_crew_manifest)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_quick_action_crew_manifest)
	var/mob/living/silicon/robot/R = host()
	R.subsystem_crew_manifest()
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "quick_action_law_manager", ui_act_quick_action_law_manager)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_quick_action_law_manager)
	var/mob/living/silicon/robot/R = host()
	R.subsystem_law_manager()
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "quick_action_alarm_monitoring", ui_act_quick_action_alarm_monitoring)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_quick_action_alarm_monitoring)
	var/mob/living/silicon/robot/R = host()
	R.subsystem_alarm_monitor()
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "quick_action_power_monitoring", ui_act_quick_action_power_monitoring)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_quick_action_power_monitoring)
	var/mob/living/silicon/robot/R = host()
	R.subsystem_power_monitor()
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "quick_action_take_image", ui_act_quick_action_take_image)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_quick_action_take_image)
	var/mob/living/silicon/robot/R = host()
	R.take_image()
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "quick_action_view_images", ui_act_quick_action_view_images)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_quick_action_view_images)
	var/mob/living/silicon/robot/R = host()
	R.view_images()
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "quick_action_delete_images", ui_act_quick_action_delete_images)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_quick_action_delete_images)
	var/mob/living/silicon/robot/R = host()
	R.delete_images()
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "quick_action_flashlight", ui_act_quick_action_flashlight)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_quick_action_flashlight)
	var/mob/living/silicon/robot/R = host()
	dq_use_ability(R, ABILITY_ID_ROBOT_TOGGLE_LIGHTS)
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "quick_action_sensors", ui_act_quick_action_sensors)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_quick_action_sensors)
	var/mob/living/silicon/robot/R = host()
	dq_use_ability(R, ABILITY_ID_ROBOT_SENSOR_MODE)
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui, "quick_action_sparks", ui_act_quick_action_sparks)
UI_ACT_PROC(/datum/tgui_module/robot_ui, ui_act_quick_action_sparks)
	var/mob/living/silicon/robot/R = host()
	dq_use_ability(R, ABILITY_ID_ROBOT_SPARK_PLUG)
	. = TRUE
