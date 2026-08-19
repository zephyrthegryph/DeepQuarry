/obj/machinery/material_processor
	name = "integrated materials workstation"
	desc = "A modular workstation for physically processing, forming, and certifying material batches."
	icon = 'icons/obj/machines/research.dmi'
	icon_state = "protolathe"
	anchored = TRUE
	density = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 75
	active_power_usage = 1500
	circuit = /obj/item/circuitboard/machine/material_processor
	var/datum/material_batch/batch
	var/processor_kind = "thermal"

/obj/machinery/material_processor/Destroy()
	QDEL_NULL(batch)
	return ..()

/obj/machinery/material_processor/attack_hand(mob/user)
	if(..())
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/material_processor/attackby(obj/item/item, mob/user)
	if(istype(item, /obj/item/stack/material))
		var/obj/item/stack/material/stack = item
		if(!stack.material || stack.amount < 1)
			return
		if(!batch)
			batch = new
		if(batch.amount >= MATERIAL_SCIENCE_MAX_BATCH)
			to_chat(user, span_warning("The chamber is full."))
			return
		if(istype(stack.material, /datum/material/processed_alloy))
			var/datum/material/processed_alloy/processed = stack.material
			var/datum/material_batch/source = processed.batch_template
			for(var/component in source.composition)
				batch.add_material(component, source.composition[component] / max(source.amount, 1))
			batch.purity = round((batch.purity + source.purity) * 0.5)
			batch.grain_size = round((batch.grain_size + source.grain_size) * 0.5)
			batch.internal_stress = round((batch.internal_stress + source.internal_stress) * 0.5)
			batch.porosity = round((batch.porosity + source.porosity) * 0.5)
			batch.homogeneity = round((batch.homogeneity + source.homogeneity) * 0.5)
		else
			batch.add_material(stack.material.name, 1)
		stack.use(1)
		batch.recalculate()
		to_chat(user, span_notice("You load one sheet into [src]."))
		return
	if(istype(item, /obj/item/slime_extract))
		if(!batch)
			to_chat(user, span_warning("Load material before adding a catalyst."))
			return
		var/obj/item/slime_extract/extract = item
		batch.add_additive("[extract.name] catalyst", 5)
		batch.homogeneity = clamp(batch.homogeneity + 12, 0, 100)
		batch.purity = clamp(batch.purity + 4, 0, 100)
		qdel(extract)
		to_chat(user, span_notice("The extractor matrix dissolves into the batch as a catalytic dopant."))
		return
	if(item.reagents?.total_volume)
		if(!batch)
			to_chat(user, span_warning("Load material before adding chemical dopants."))
			return
		var/remaining = MATERIAL_SCIENCE_REAGENT_SAMPLE
		for(var/datum/reagent/reagent in item.reagents.reagent_list)
			if(remaining <= 0)
				break
			var/taken = min(reagent.volume, remaining)
			if(taken > 0)
				batch.add_additive(reagent.name, taken)
				item.reagents.remove_reagent(reagent.id, taken)
				remaining -= taken
		to_chat(user, span_notice("You meter chemical additives into the batch."))
		return
	return ..()

/obj/machinery/material_processor/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "MaterialScience", name)
		ui.open()

/obj/machinery/material_processor/tgui_data(mob/user)
	var/list/data = list("kind" = processor_kind, "batch" = null, "operations" = available_operations(), "specifications" = list())
	if(batch)
		var/list/composition_data = list()
		for(var/component in batch.composition)
			composition_data += list(list("id" = component, "name" = material_display_name(component) || component, "amount" = round(batch.composition[component], 0.01)))
		data["batch"] = list(
			"name" = batch.display_name(), "amount" = round(batch.amount, 0.01), "phase" = batch.phase,
			"temperature" = round(batch.temperature), "purity" = batch.purity, "grain" = batch.grain_size,
			"stress" = batch.internal_stress, "porosity" = batch.porosity, "homogeneity" = batch.homogeneity,
			"hardness" = batch.hardness, "toughness" = batch.toughness, "conductivity" = batch.conductivity,
			"heat" = batch.heat_resistance, "corrosion" = batch.corrosion_resistance,
			"composition" = composition_data, "history" = batch.process_history.Copy(),
		)
	for(var/spec_name in GLOB.material_specifications)
		var/datum/material_specification/specification = GLOB.material_specifications[spec_name]
		data["specifications"] += list(list("name" = specification.name, "fingerprint" = specification.fingerprint))
	return data

/obj/machinery/material_processor/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return
	if(stat & (BROKEN | NOPOWER))
		return FALSE
	var/mob/user = ui.user
	switch(action)
		if("process")
			var/process = params["process"]
			if(!(process in available_operations()) || !batch)
				return FALSE
			use_power(active_power_usage)
			if(!batch.apply_process(process, params["option"]))
				to_chat(user, span_warning("That operation is incompatible with the batch's present phase."))
				return FALSE
			visible_message(span_notice("[src] completes a [process] cycle."))
			return TRUE
		if("eject")
			if(!batch)
				return FALSE
			if(batch.phase != MATERIAL_PHASE_SOLID)
				to_chat(user, span_warning("Cast, crystallize, or solidify the batch before ejecting it."))
				return FALSE
			processed_spawn_stack(get_turf(src), batch, batch.amount)
			QDEL_NULL(batch)
			return TRUE
		if("discard")
			QDEL_NULL(batch)
			return TRUE
		if("certify")
			return certify_batch(user)
		if("save_spec")
			if(!batch)
				return FALSE
			var/spec_name = stripped_input(user, "Name this material specification.", "Save specification", batch.display_name(), MAX_NAME_LEN)
			if(!spec_name || !batch)
				return FALSE
			GLOB.material_specifications[lowertext(spec_name)] = new /datum/material_specification(spec_name, batch, user.ckey)
			return TRUE
		if("separate")
			if(processor_kind != "electrochemical" || !batch || length(batch.composition) < 2)
				return FALSE
			var/component = params["component"]
			var/component_amount = batch.composition[component]
			if(!component_amount)
				return FALSE
			var/datum/material_batch/separated = new
			separated.add_material(component, component_amount)
			separated.purity = clamp(batch.purity + 8, 0, 100)
			separated.form = "electrolytic deposit"
			separated.process_history += "electrolytically separated from [batch.display_name()]"
			separated.recalculate()
			processed_spawn_stack(get_turf(src), separated, separated.amount)
			qdel(separated)
			batch.composition -= component
			batch.amount -= component_amount
			batch.purity = clamp(batch.purity + 6, 0, 100)
			batch.process_history += "electrolytic separation of [component]"
			batch.recalculate()
			emit_contract_event(CONTRACT_EVENT_MATERIAL_PROCESSED, batch.evidence_context(MATERIAL_PROCESS_ELECTROLYZE))
			return TRUE
	return FALSE

/obj/machinery/material_processor/proc/available_operations()
	return list(MATERIAL_PROCESS_MELT, MATERIAL_PROCESS_CAST, MATERIAL_PROCESS_ANNEAL, MATERIAL_PROCESS_QUENCH, MATERIAL_PROCESS_TEMPER, MATERIAL_PROCESS_SINTER)

/obj/machinery/material_processor/proc/certify_batch(mob/user)
	if(!batch)
		return FALSE
	var/obj/item/paper/report = new(get_turf(src))
	report.set_content("MATERIAL QUALIFICATION REPORT\nBatch: [batch.display_name()]\nFingerprint: [batch.fingerprint()]\nComposition: [json_encode(batch.composition)]\nPurity: [batch.purity]%\nHardness: [batch.hardness]\nToughness: [batch.toughness]\nConductivity: [batch.conductivity]\nHeat resistance: [batch.heat_resistance]\nCorrosion resistance: [batch.corrosion_resistance]\nCertified by: [user.real_name]", "material qualification - [copytext(batch.fingerprint(), 1, 9)]")
	report.set_economic_provenance(DEPARTMENT_RESEARCH, 50)
	emit_contract_event(CONTRACT_EVENT_MATERIAL_CERTIFIED, batch.evidence_context("certification"), batch.fingerprint(), src, user)
	return TRUE

/obj/machinery/material_processor/forming
	name = "materials forming press"
	desc = "A programmable rolling, forging, and wire-drawing press."
	icon_state = "circuit_imprinter"
	processor_kind = "forming"
	circuit = /obj/item/circuitboard/machine/material_processor/forming

/obj/machinery/material_processor/forming/available_operations()
	return list(MATERIAL_PROCESS_ROLL, MATERIAL_PROCESS_FORGE, MATERIAL_PROCESS_DRAW)

/obj/machinery/material_processor/electrochemical
	name = "electrochemical materials cell"
	desc = "A sealed cell for purification, electrolysis, deposition, and crystallization."
	icon_state = "protolathe"
	processor_kind = "electrochemical"
	circuit = /obj/item/circuitboard/machine/material_processor/electrochemical

/obj/machinery/material_processor/electrochemical/available_operations()
	return list(MATERIAL_PROCESS_PURIFY, MATERIAL_PROCESS_ELECTROLYZE, MATERIAL_PROCESS_CRYSTALLIZE)

/obj/machinery/material_processor/tester
	name = "materials test stand"
	desc = "A metrology stand for material qualification and repeatable specifications."
	icon_state = "circuit_imprinter"
	processor_kind = "testing"
	circuit = /obj/item/circuitboard/machine/material_processor/tester

/obj/machinery/material_processor/tester/available_operations()
	return list()

/obj/item/circuitboard/machine/material_processor
	name = T_BOARD("materials thermal processor")
	build_path = /obj/machinery/material_processor
	board_type = new /datum/frame/frame_types/machine
	req_components = list(/obj/item/stock_parts/matter_bin = 2, /obj/item/stock_parts/manipulator = 2, /obj/item/stock_parts/micro_laser = 2)

/obj/item/circuitboard/machine/material_processor/forming
	name = T_BOARD("materials forming press")
	build_path = /obj/machinery/material_processor/forming

/obj/item/circuitboard/machine/material_processor/electrochemical
	name = T_BOARD("electrochemical materials cell")
	build_path = /obj/machinery/material_processor/electrochemical
	req_components = list(/obj/item/stock_parts/matter_bin = 2, /obj/item/stock_parts/manipulator = 2, /obj/item/reagent_containers/glass/beaker = 2)

/obj/item/circuitboard/machine/material_processor/tester
	name = T_BOARD("materials test stand")
	build_path = /obj/machinery/material_processor/tester
	req_components = list(/obj/item/stock_parts/scanning_module = 2, /obj/item/stock_parts/manipulator = 1, /obj/item/stock_parts/console_screen = 1)

/datum/design_techweb/board/material_processor
	SET_CIRCUIT_DESIGN_NAMEDESC("materials thermal processor")
	id = "board_material_processor"
	build_path = /obj/item/circuitboard/machine/material_processor
	category = list(RND_CATEGORY_COMPUTER + RND_SUBCATEGORY_MACHINE_RESEARCH)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/material_forming
	SET_CIRCUIT_DESIGN_NAMEDESC("materials forming press")
	id = "board_material_forming"
	build_path = /obj/item/circuitboard/machine/material_processor/forming
	category = list(RND_CATEGORY_COMPUTER + RND_SUBCATEGORY_MACHINE_RESEARCH)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/material_electrochemical
	SET_CIRCUIT_DESIGN_NAMEDESC("electrochemical materials cell")
	id = "board_material_electrochemical"
	build_path = /obj/item/circuitboard/machine/material_processor/electrochemical
	category = list(RND_CATEGORY_COMPUTER + RND_SUBCATEGORY_MACHINE_RESEARCH)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/board/material_tester
	SET_CIRCUIT_DESIGN_NAMEDESC("materials test stand")
	id = "board_material_tester"
	build_path = /obj/item/circuitboard/machine/material_processor/tester
	category = list(RND_CATEGORY_COMPUTER + RND_SUBCATEGORY_MACHINE_RESEARCH)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE

/datum/techweb_node/material_science
	id = "material_science"
	display_name = "Applied Material Science"
	description = "Physical alloy production, heat treatment, electrochemistry, forming, and qualification."
	starting_node = TRUE
	design_ids = list("board_material_processor", "board_material_forming", "board_material_electrochemical", "board_material_tester")
