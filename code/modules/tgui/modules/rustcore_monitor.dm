/datum/tgui_module/rustcore_monitor
	name = "R-UST Core Monitoring"

	var/core_tag = ""

CAPABILITIES(/datum/tgui_module/rustcore_monitor)
	interface("RustCoreMonitor")
	op("toggle_active", ui_act("toggle_active", arg("core", schema_text(32))), then(PROC_REF(ui_act_toggle_active)))
	op("toggle_reactantdump", ui_act("toggle_reactantdump", arg("core", schema_text(32))), then(PROC_REF(ui_act_toggle_reactantdump)))
	op("set_tag", ui_act("set_tag"), asks(/datum/prompt/text, fields = list("title" = "Core Control", "question" = "Enter a new ident tag.", "default" = nameof(core_tag), "timeout" = 0)), then(PROC_REF(ui_act_set_tag)))
	op("set_fieldstr", ui_act("set_fieldstr", arg("core", schema_text(32)), arg("fieldstr", num())), then(PROC_REF(ui_act_set_fieldstr)))

/// The cores the window lists: those on this console's tag.
/datum/tgui_module/rustcore_monitor/proc/listed_cores()
	var/list/listed = list()
	for(var/obj/machinery/power/fusion_core/C in registry_all(REGISTRY_FUSION_CORES, core_tag))
		if(C.id_tag == core_tag)
			listed += C
	return listed

/datum/tgui_module/rustcore_monitor/proc/ui_act_toggle_active(datum/act/op/A, core)
	var/obj/machinery/power/fusion_core/C = ui_member(core, listed_cores(), /obj/machinery/power/fusion_core)
	if(!C)
		return TRUE
	if(!C.Startup()) //Startup() whilst the device is active will return null.
		C.Shutdown()
	return TRUE

/datum/tgui_module/rustcore_monitor/proc/ui_act_toggle_reactantdump(datum/act/op/A, core)
	var/obj/machinery/power/fusion_core/C = ui_member(core, listed_cores(), /obj/machinery/power/fusion_core)
	if(C)
		C.reactant_dump = !C.reactant_dump
	return TRUE

/datum/tgui_module/rustcore_monitor/proc/ui_act_set_tag(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/new_ident = sanitize_text(A.answer.value)
	if(new_ident)
		set_core_tag(new_ident)
	SStgui.update_uis(src)
	return OP_OK

/datum/tgui_module/rustcore_monitor/proc/ui_act_set_fieldstr(datum/act/op/A, core, fieldstr)
	var/obj/machinery/power/fusion_core/C = core
	var/new_strength = fieldstr
	if(C)
		C.target_field_strength = new_strength
	return TRUE

/datum/tgui_module/rustcore_monitor/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/list/cores = list()

	for(var/obj/machinery/power/fusion_core/C in registry_all(REGISTRY_FUSION_CORES, core_tag))
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
				"ref" = ref_token(C)
			)))

	data["cores"] = cores
	return data

/datum/tgui_module/rustcore_monitor/ntos
	ntos = TRUE
