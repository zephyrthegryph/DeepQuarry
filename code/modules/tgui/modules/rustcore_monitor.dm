/datum/tgui_module/rustcore_monitor
	name = "R-UST Core Monitoring"
	tgui_id = "RustCoreMonitor"

	var/core_tag = ""

/// The devices this console controls, for the UI's refs.
/datum/tgui_module/rustcore_monitor/proc/fusion_cores()
	return REGISTRY_MEMBERS(REGISTRY_FUSION_CORES)

UI_ACT(/datum/tgui_module/rustcore_monitor, "toggle_active", ui_act_toggle_active, UI_ARG_REF("core", "proc:fusion_cores", /obj/machinery/power/fusion_core))
UI_ACT_PROC(/datum/tgui_module/rustcore_monitor, ui_act_toggle_active)
	var/obj/machinery/power/fusion_core/C = params["core"]
	if(!C)
		return TRUE
	if(!C.Startup()) //Startup() whilst the device is active will return null.
		C.Shutdown()
	return TRUE

UI_ACT(/datum/tgui_module/rustcore_monitor, "toggle_reactantdump", ui_act_toggle_reactantdump, UI_ARG_REF("core", "proc:fusion_cores", /obj/machinery/power/fusion_core))
UI_ACT_PROC(/datum/tgui_module/rustcore_monitor, ui_act_toggle_reactantdump)
	var/obj/machinery/power/fusion_core/C = params["core"]
	if(C)
		C.reactant_dump = !C.reactant_dump
	return TRUE

UI_ACT(/datum/tgui_module/rustcore_monitor, "set_tag", ui_act_set_tag)
UI_ACT_PROC(/datum/tgui_module/rustcore_monitor, ui_act_set_tag)
	var/_answer_a1 = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/text, message = "Enter a new ident tag.", title = "Core Control", default = core_tag)
	if(isnull(_answer_a1))
		return
	var/new_ident = sanitize_text(_answer_a1)
	if(new_ident)
		core_tag = new_ident
	return TRUE

UI_ACT(/datum/tgui_module/rustcore_monitor, "set_fieldstr", ui_act_set_fieldstr, UI_ARG_REF("core", "proc:fusion_cores", /obj/machinery/power/fusion_core), UI_ARG_NUM("fieldstr"))
UI_ACT_PROC(/datum/tgui_module/rustcore_monitor, ui_act_set_fieldstr)
	var/obj/machinery/power/fusion_core/C = params["core"]
	var/new_strength = params["fieldstr"]
	if(C)
		C.target_field_strength = new_strength
	return TRUE

/datum/tgui_module/rustcore_monitor/tgui_data(mob/user)
	var/list/data = list()
	var/list/cores = list()

	for(var/obj/machinery/power/fusion_core/C in REGISTRY_MEMBERS(REGISTRY_FUSION_CORES))
		if(C.id_tag == core_tag)

			var/list/reactants = list()

			if(C.owned_field)
				for(var/reagent in C.owned_field.dormant_reactant_quantities)
					reactants.Add(list(list(
						"name" = reagent,
						"amount" = C.owned_field.dormant_reactant_quantities[reagent]
						)))

			cores.Add(list(list(
				"name" = C.name,
				"has_field" = C.owned_field ? TRUE : FALSE,
				"reactant_dump" = C.reactant_dump,
				"core_operational" = C.check_core_status(),
				"field_instability" = (C.owned_field ? "[C.owned_field.percent_unstable * 100]%" : "ERROR"),
				"field_temperature" = (C.owned_field ? "[C.owned_field.plasma_temperature + 295]K" : "ERROR"),
				"field_strength" = C.field_strength,
				"target_field_strength" = C.target_field_strength,
				"x" = C.x,
				"y" = C.y,
				"z" = C.z,
				"ref" = "\ref[C]"
			)))

	data["cores"] = cores
	return data

/datum/tgui_module/rustcore_monitor/ntos
	ntos = TRUE
