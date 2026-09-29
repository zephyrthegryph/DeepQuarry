/datum/tgui_module/rustfuel_control
	name = "Fuel Injector Control"
	tgui_id = "RustFuelControl"

	var/fuel_tag = ""

UI_ACT(/datum/tgui_module/rustfuel_control, "toggle_active", ui_act_toggle_active, UI_ARG_REF("fuel", "proc:ui_source_registry_members_registry_fuel_injectors", /obj/machinery/fusion_fuel_injector))
UI_ACT_PROC(/datum/tgui_module/rustfuel_control, ui_act_toggle_active)
	var/obj/machinery/fusion_fuel_injector/FI = params["fuel"]
	if(!istype(FI))
		return FALSE

	if(FI.injecting)
		FI.StopInjecting()
	else
		FI.BeginInjecting()

	return TRUE

UI_ACT(/datum/tgui_module/rustfuel_control, "set_tag", ui_act_set_tag)
UI_ACT_PROC(/datum/tgui_module/rustfuel_control, ui_act_set_tag)
	var/_answer_a1 = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/text, message = "Enter a new ident tag.", title = "Gyrotron Control", default = fuel_tag)
	if(isnull(_answer_a1))
		return
	var/new_ident = sanitize_text(_answer_a1)
	if(new_ident)
		fuel_tag = new_ident

/// The list the UI_ARG_REF rows resolve refs in.
/datum/tgui_module/rustfuel_control/proc/ui_source_registry_members_registry_fuel_injectors()
	return REGISTRY_MEMBERS(REGISTRY_FUEL_INJECTORS)

UI_DATA_REPLACE(/datum/tgui_module/rustfuel_control, "merge:ui_data_datum_tgui_module_rustfuel_control{fuels:list}")

/// The computed part of /datum/tgui_module/rustfuel_control's window data (declared on its UI_DATA row).
/datum/tgui_module/rustfuel_control/proc/ui_data_datum_tgui_module_rustfuel_control(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	var/list/fuels = list()

	for(var/obj/machinery/fusion_fuel_injector/FI in REGISTRY_MEMBERS(REGISTRY_FUEL_INJECTORS))
		if(FI.id_tag == fuel_tag)
			fuels.Add(list(list(
				"name" = FI.name,
				"active" = FI.injecting,
				"fuel_type" = (FI.cur_assembly ? FI.cur_assembly.fuel_type : "NONE"),
				"fuel_amt" = (FI.cur_assembly ? "[FI.cur_assembly.percent_depleted * 100]%" : "NONE"),
				"deployed" = FI.anchored,
				"x" = FI.x,
				"y" = FI.y,
				"z" = FI.z,
				"ref" = "\ref[FI]"
			)))

	data["fuels"] = fuels
	return data

/datum/tgui_module/rustfuel_control/ntos
	ntos = TRUE
