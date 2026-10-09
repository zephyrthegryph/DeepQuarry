// Major Control UI for all things robots can do.
/datum/tgui_module/robot_ui
	name = "Robotact"

CAPABILITIES(/datum/tgui_module/robot_ui)
	interface("Robotact", state = nameof(GLOB.tgui_self_state))
	op("set_light_col", ui_act("set_light_col", arg("value", schema_text(4096))), then(PROC_REF(ui_act_set_light_col)))
	op("select_module", ui_act("select_module"), then(PROC_REF(ui_act_select_module)))
	op("toggle_component", ui_act("toggle_component", arg("component", num())), then(PROC_REF(ui_act_toggle_component)))
	op("toggle_module", ui_act("toggle_module", arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_toggle_module)))
	op("activate_module", ui_act("activate_module", arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_activate_module)))
	op("quick_action_comm", ui_act("quick_action_comm"), then(PROC_REF(ui_act_quick_action_comm)))
	op("quick_action_pda", ui_act("quick_action_pda"), then(PROC_REF(ui_act_quick_action_pda)))
	op("quick_action_crew_manifest", ui_act("quick_action_crew_manifest"), then(PROC_REF(ui_act_quick_action_crew_manifest)))
	op("quick_action_law_manager", ui_act("quick_action_law_manager"), then(PROC_REF(ui_act_quick_action_law_manager)))
	op("quick_action_alarm_monitoring", ui_act("quick_action_alarm_monitoring"), then(PROC_REF(ui_act_quick_action_alarm_monitoring)))
	op("quick_action_power_monitoring", ui_act("quick_action_power_monitoring"), then(PROC_REF(ui_act_quick_action_power_monitoring)))
	op("quick_action_take_image", ui_act("quick_action_take_image"), then(PROC_REF(ui_act_quick_action_take_image)))
	op("quick_action_view_images", ui_act("quick_action_view_images"), then(PROC_REF(ui_act_quick_action_view_images)))
	op("quick_action_delete_images", ui_act("quick_action_delete_images"), then(PROC_REF(ui_act_quick_action_delete_images)))
	op("quick_action_flashlight", ui_act("quick_action_flashlight"), then(PROC_REF(ui_act_quick_action_flashlight)))
	op("quick_action_sensors", ui_act("quick_action_sensors"), then(PROC_REF(ui_act_quick_action_sensors)))
	op("quick_action_sparks", ui_act("quick_action_sparks"), then(PROC_REF(ui_act_quick_action_sparks)))

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

/datum/tgui_module/robot_ui/ui_data(datum/act/eval/A)
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
		spent(D)
	data["faults"] = faults

	return data

/datum/tgui_module/robot_ui/proc/ui_act_set_light_col(datum/act/op/A, value)
	var/mob/living/silicon/robot/R = host()
	var/new_color = value
	if(findtext(new_color, GLOB.is_color))
		R.robot_light_col = new_color
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_select_module(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	R.pick_module()
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_toggle_component(datum/act/op/A, component)
	var/mob/user = A.actor
	var/mob/living/silicon/robot/R = host()
	var/slot = component
	var/datum/robot_component/C = R.get_component(slot)
	if(istype(C) && !C.internal && R.toggle_component(slot))
		if(C.toggled)
			to_chat(user, span_notice("You enable [C]."))
		else
			to_chat(user, span_warning("You disable [C]."))
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_toggle_module(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/mob/living/silicon/robot/R = host()
	if(after_pending(R, "weapon_lock"))
		to_chat(user, span_danger("Error: Modules locked."))
		return
	var/obj/item/module = ref
	if(istype(module))
		if(R.activated(module))
			R.uneq_specific(module)
		else
			R.activate_module(module)
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_activate_module(datum/act/op/A, ref)
	var/mob/living/silicon/robot/R = host()
	var/obj/item/module = ref
	if(istype(module) && module.loc == R)
		module.attack_self(R)
	. = TRUE

// Quick actions

/datum/tgui_module/robot_ui/proc/ui_act_quick_action_comm(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	R.communicator?.attack_self(R)
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_quick_action_pda(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	R.rbPDA?.tgui_interact(R)
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_quick_action_crew_manifest(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	R.subsystem_crew_manifest()
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_quick_action_law_manager(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	R.subsystem_law_manager()
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_quick_action_alarm_monitoring(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	R.subsystem_alarm_monitor()
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_quick_action_power_monitoring(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	R.subsystem_power_monitor()
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_quick_action_take_image(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	R.take_image()
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_quick_action_view_images(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	R.view_images()
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_quick_action_delete_images(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	R.delete_images()
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_quick_action_flashlight(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	perform_op(R, R, ABILITY_ID_ROBOT_TOGGLE_LIGHTS, null, ORIGIN_MENU)
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_quick_action_sensors(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	perform_op(R, R, ABILITY_ID_ROBOT_SENSOR_MODE, null, ORIGIN_MENU)
	. = TRUE

/datum/tgui_module/robot_ui/proc/ui_act_quick_action_sparks(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	perform_op(R, R, ABILITY_ID_ROBOT_SPARK_PLUG, null, ORIGIN_MENU)
	. = TRUE
