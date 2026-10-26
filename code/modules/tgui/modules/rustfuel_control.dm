/datum/tgui_module/rustfuel_control
	name = "Fuel Injector Control"

	var/fuel_tag = ""

CAPABILITIES(/datum/tgui_module/rustfuel_control)
	interface("RustFuelControl")
	op("toggle_active", ui_act("toggle_active", arg("fuel", schema_text(32))), then(PROC_REF(ui_act_toggle_active)))
	op("set_tag", ui_act("set_tag"), asks(/datum/prompt/text, fields = list("title" = "Gyrotron Control", "question" = "Enter a new ident tag.", "default" = nameof(fuel_tag), "timeout" = 0)), then(PROC_REF(ui_act_set_tag)))

/// The injectors the window lists: those on this console's tag.
/datum/tgui_module/rustfuel_control/proc/listed_fuels()
	var/list/listed = list()
	for(var/obj/machinery/fusion_fuel_injector/FI in registry_all(REGISTRY_FUEL_INJECTORS, fuel_tag))
		if(FI.id_tag == fuel_tag)
			listed += FI
	return listed

/datum/tgui_module/rustfuel_control/proc/ui_act_toggle_active(datum/act/op/A, fuel)
	var/obj/machinery/fusion_fuel_injector/FI = ui_member(fuel, listed_fuels(), /obj/machinery/fusion_fuel_injector)
	if(!FI)
		return FALSE

	if(FI.injecting)
		FI.StopInjecting()
	else
		FI.BeginInjecting()

	return TRUE

/datum/tgui_module/rustfuel_control/proc/ui_act_set_tag(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/new_ident = sanitize_text(A.answer.value)
	if(new_ident)
		set_fuel_tag(new_ident)
	SStgui.update_uis(src)
	return OP_OK

/datum/tgui_module/rustfuel_control/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/list/fuels = list()

	for(var/obj/machinery/fusion_fuel_injector/FI in registry_all(REGISTRY_FUEL_INJECTORS, fuel_tag))
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
				"ref" = ref_token(FI)
			)))

	data["fuels"] = fuels
	return data

/datum/tgui_module/rustfuel_control/ntos
	ntos = TRUE
