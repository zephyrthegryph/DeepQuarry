/datum/tgui_module/rustfuel_control
	name = "Fuel Injector Control"

	var/fuel_tag = ""

CAPABILITIES(/datum/tgui_module/rustfuel_control)
	interface("RustFuelControl")
	op("toggle_active", ui_act("toggle_active", arg("fuel", schema_ref(/obj/machinery/fusion_fuel_injector))), then(PROC_REF(ui_act_toggle_active)))
	op("set_tag", ui_act("set_tag"), then(PROC_REF(ui_act_set_tag)))

/datum/tgui_module/rustfuel_control/proc/ui_act_toggle_active(datum/act/op/A, fuel)
	var/obj/machinery/fusion_fuel_injector/FI = fuel
	if(!istype(FI))
		return FALSE

	if(FI.injecting)
		FI.StopInjecting()
	else
		FI.BeginInjecting()

	return TRUE

/datum/tgui_module/rustfuel_control/proc/ui_act_set_tag(datum/act/op/A)
	open_request(src, /datum/prompt/text, PROC_REF(tag_entered), valid = PROC_REF(request_usable), answerer = A.actor, title = "Gyrotron Control", question = "Enter a new ident tag.", default = fuel_tag, timeout = 0)

/datum/tgui_module/rustfuel_control/proc/tag_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/new_ident = sanitize_text(A.answer.value)
	if(new_ident)
		fuel_tag = new_ident
	SStgui.update_uis(src)

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
				"ref" = "\ref[FI]"
			)))

	data["fuels"] = fuels
	return data

/datum/tgui_module/rustfuel_control/ntos
	ntos = TRUE
