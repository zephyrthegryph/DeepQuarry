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
	var/process_timer
	var/pending_process
	var/pending_option
	var/pending_duration_seconds

/obj/machinery/material_processor/Destroy()
	if(process_timer)
		deltimer(process_timer)
		process_timer = null
	QDEL_NULL(batch)
	return ..()

/obj/machinery/material_processor/attack_hand(mob/user)
	if(..())
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/material_processor/attackby(obj/item/item, mob/user)
	if(processor_kind == "testing" && batch && !istype(item, /obj/item/stack/material))
		var/datum/material/item_material = item.get_material()
		if(istype(item_material, /datum/material/processed_alloy))
			var/datum/material/processed_alloy/processed_item_material = item_material
			if(processed_item_material.batch_template.fingerprint() == batch.fingerprint())
				batch.test_results[MATERIAL_TEST_FIELD] = 100 - batch.structure[MATERIAL_STRUCTURE_DEFECT]
				batch.process_history += "fabricated article [item.type] destructively field-tested"
				to_chat(user, span_notice("[src] destructively loads [item] through its service envelope and records the result."))
				qdel(item)
				return
	if(istype(item, /obj/item/stack/material))
		var/obj/item/stack/material/stack = item
		if(!stack.material || stack.amount < 1)
			return
		if(!batch)
			batch = new
		stack.ensure_feedstock_lot()
		if(batch.amount >= MATERIAL_SCIENCE_MAX_BATCH)
			to_chat(user, span_warning("The chamber is full."))
			return
		if(istype(stack.material, /datum/material/processed_alloy))
			var/datum/material/processed_alloy/processed = stack.material
			var/datum/material_batch/source = processed.batch_template
			var/feedstock_before = batch.cost_ledger[MATERIAL_COST_FEEDSTOCK] || 0
			for(var/component in source.composition)
				batch.add_material(component, source.composition[component] / max(source.amount, 1), null, source.purity, stack.feedstock_lot_id)
			var/recorded_feedstock = (batch.cost_ledger[MATERIAL_COST_FEEDSTOCK] || 0) - feedstock_before
			var/historical_unit_cost = source.unit_production_cost()
			if(historical_unit_cost > recorded_feedstock)
				var/carry_cost = historical_unit_cost - recorded_feedstock
				batch.cost_basis += carry_cost
				batch.record_cost(MATERIAL_COST_FEEDSTOCK, carry_cost)
			batch.purity = round((batch.purity + source.purity) * 0.5)
			batch.grain_size = round((batch.grain_size + source.grain_size) * 0.5)
			batch.internal_stress = round((batch.internal_stress + source.internal_stress) * 0.5)
			batch.porosity = round((batch.porosity + source.porosity) * 0.5)
			batch.homogeneity = round((batch.homogeneity + source.homogeneity) * 0.5)
		else
			batch.add_material(stack.material.name, 1, null, stack.feedstock_purity, stack.feedstock_lot_id)
			if(stack.feedstock_trace)
				batch.add_additive(stack.feedstock_trace, stack.feedstock_trace_units, 0)
		stack.use(1)
		batch.recalculate()
		to_chat(user, span_notice("You load one sheet into [src]."))
		return
	if(istype(item, /obj/item/slime_extract))
		if(!batch)
			to_chat(user, span_warning("Load material before adding a catalyst."))
			return
		var/obj/item/slime_extract/extract = item
		var/specialized_catalyst = FALSE
		if(istype(extract, /obj/item/slime_extract/metal))
			specialized_catalyst = TRUE
			batch.add_additive("metallic grain refiner", 4, 8, MATERIAL_COST_CATALYSTS)
			batch.structure[MATERIAL_STRUCTURE_REINFORCEMENT] += 14
		if(istype(extract, /obj/item/slime_extract/blue))
			specialized_catalyst = TRUE
			batch.add_additive("cryogenic stabilizer", 3, 8, MATERIAL_COST_CATALYSTS)
			batch.internal_stress = clamp(batch.internal_stress - 18, 0, 100)
		if(istype(extract, /obj/item/slime_extract/orange))
			specialized_catalyst = TRUE
			batch.add_additive("thermal phase catalyst", 4, 8, MATERIAL_COST_CATALYSTS)
			batch.heat_resistance = clamp(batch.heat_resistance + 10, 0, 100)
		if(istype(extract, /obj/item/slime_extract/yellow))
			specialized_catalyst = TRUE
			batch.add_additive("conductive dopant", 4, 8, MATERIAL_COST_CATALYSTS)
			batch.conductivity = clamp(batch.conductivity + 12, 0, 100)
		if(istype(extract, /obj/item/slime_extract/dark_purple))
			specialized_catalyst = TRUE
			batch.add_additive("corrosion inhibitor", 4, 8, MATERIAL_COST_CATALYSTS)
			batch.corrosion_resistance = clamp(batch.corrosion_resistance + 12, 0, 100)
		if(istype(extract, /obj/item/slime_extract/gold))
			specialized_catalyst = TRUE
			batch.add_additive("precipitation catalyst", 4, 8, MATERIAL_COST_CATALYSTS)
			batch.structure[MATERIAL_STRUCTURE_PRECIPITATE] += 16
		if(istype(extract, /obj/item/slime_extract/bluespace))
			specialized_catalyst = TRUE
			batch.add_additive("bluespace homogenizer", 3, 12, MATERIAL_COST_CATALYSTS)
			batch.homogeneity = clamp(batch.homogeneity + 24, 0, 100)
		if(!specialized_catalyst)
			batch.add_additive("[extract.name] organic matrix", 5, 6, MATERIAL_COST_CATALYSTS)
			batch.structure[MATERIAL_STRUCTURE_AMORPHOUS] += 12
		batch.purity = clamp(batch.purity + 4, 0, 100)
		batch.normalize_structure()
		batch.recalculate()
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
				batch.add_additive(reagent.name, taken, max(reagent.supply_conversion_value, 0.05), MATERIAL_COST_CHEMICALS)
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
	var/list/operation_availability = list()
	for(var/operation in available_operations())
		operation_availability[operation] = batch?.can_process(operation) || FALSE
	var/list/data = list("kind" = processor_kind, "batch" = null, "operations" = available_operations(), "operationAvailability" = operation_availability, "specifications" = list(), "processing" = !!process_timer)
	if(batch)
		var/list/composition_data = list()
		for(var/component in batch.composition)
			composition_data += list(list("id" = component, "name" = material_display_name(component) || component, "amount" = round(batch.composition[component], 0.01)))
		var/list/all_capabilities = batch.material_capability_preview(FALSE)
		var/list/qualified_capabilities = list()
		for(var/list/capability_data as anything in all_capabilities)
			if(material_capability_discovered(capability_data["id"], batch))
				qualified_capabilities += list(capability_data)
		data["batch"] = list(
			"name" = batch.display_name(), "amount" = round(batch.amount, 0.01), "phase" = batch.phase,
			"temperature" = round(batch.temperature), "purity" = batch.purity, "grain" = batch.grain_size,
			"stress" = batch.internal_stress, "porosity" = batch.porosity, "homogeneity" = batch.homogeneity,
			"hardness" = batch.test_results[MATERIAL_TEST_HARDNESS], "toughness" = batch.test_results[MATERIAL_TEST_TENSILE],
			"conductivity" = batch.test_results[MATERIAL_TEST_CONDUCTIVITY], "heat" = batch.test_results[MATERIAL_TEST_TENSILE] ? batch.heat_resistance : null,
			"corrosion" = batch.test_results[MATERIAL_TEST_CORROSION], "composition" = batch.test_results[MATERIAL_TEST_SPECTROMETRY] ? composition_data : list(),
			"structure" = batch.test_results[MATERIAL_TEST_MICROSCOPY] ? batch.structure.Copy() : null,
			"history" = batch.process_history.Copy(), "atmosphere" = batch.atmosphere, "yield" = round(batch.yield_fraction * 100),
			"energy" = batch.energy_spent, "cost" = round(batch.total_production_cost(), 0.01), "unitCost" = round(batch.unit_production_cost(), 0.01),
			"costBreakdown" = batch.cost_breakdown(),
			"hazard" = batch.hazard_score(),
			"roles" = batch.functional_roles(),
			"capabilities" = qualified_capabilities,
			"unqualifiedCapabilities" = length(all_capabilities) - length(qualified_capabilities),
			"melting" = batch.melting_temperature(),
		)
	for(var/spec_name in GLOB.material_specifications)
		var/datum/material_specification/specification = GLOB.material_specifications[spec_name]
		data["specifications"] += list(list("name" = specification.name, "fingerprint" = specification.fingerprint, "matches" = batch ? specification.matches(batch) : FALSE, "route" = specification.process_route, "form" = specification.form, "atmosphere" = specification.atmosphere, "requirements" = specification.requirements))
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
			if(!(process in available_operations()) || !batch || process_timer)
				return FALSE
			if(!batch.can_process(process))
				to_chat(user, span_warning("That operation is unavailable at the batch's current phase, temperature, form, or prior treatment state."))
				return FALSE
			pending_process = process
			pending_option = params["option"]
			pending_duration_seconds = clamp(round(batch.amount), 1, 8)
			var/cycle_power = process_power_units(pending_process, pending_option, pending_duration_seconds)
			use_power(cycle_power)
			batch.record_electricity(cycle_power)
			process_timer = addtimer(CALLBACK(src, PROC_REF(finish_process)), pending_duration_seconds SECONDS, TIMER_STOPPABLE)
			visible_message(span_notice("[src] begins a [process] cycle."))
			return TRUE
		if("atmosphere")
			if(!batch || processor_kind != "thermal")
				return FALSE
			var/selected = params["value"]
			if(!(selected in list(MATERIAL_ATMOSPHERE_AIR, MATERIAL_ATMOSPHERE_INERT, MATERIAL_ATMOSPHERE_VACUUM, MATERIAL_ATMOSPHERE_REDUCING)))
				return FALSE
			batch.atmosphere = selected
			return TRUE
		if("test")
			if(processor_kind != "testing")
				return FALSE
			return run_material_test(params["test"], user)
		if("eject")
			if(!batch || process_timer)
				return FALSE
			if(batch.phase != MATERIAL_PHASE_SOLID)
				to_chat(user, span_warning("Cast, crystallize, or solidify the batch before ejecting it."))
				return FALSE
			processed_spawn_stack(get_turf(src), batch, max(1, round(batch.amount * batch.yield_fraction)))
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
			if(!batch.test_results[MATERIAL_TEST_TENSILE] || !batch.test_results[MATERIAL_TEST_CORROSION])
				to_chat(user, span_warning("Run and certify a complete qualification portfolio before releasing a production specification."))
				return FALSE
			var/spec_name = stripped_input(user, "Name this material specification.", "Save specification", batch.display_name(), MAX_NAME_LEN)
			if(!spec_name || !batch)
				return FALSE
			GLOB.material_specifications[lowertext(spec_name)] = new /datum/material_specification(spec_name, batch, user.ckey)
			return TRUE
		if("print_spec")
			var/spec_name = lowertext(params["name"])
			var/datum/material_specification/specification = GLOB.material_specifications[spec_name]
			if(!istype(specification))
				return FALSE
			var/quantity = tgui_input_number(user, "How many usable sheets are requested?", "Material production order", 10, MATERIAL_SCIENCE_MAX_BATCH, 1)
			if(!quantity || !Adjacent(user))
				return FALSE
			specification.print_order(get_turf(src), user.real_name, round(quantity))
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
			var/datum/material/recovered_material = get_material_by_name(component)
			batch.record_recovery(max(recovered_material?.supply_conversion_value, 0.1) * component_amount)
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
	return list(MATERIAL_PROCESS_HEAT, MATERIAL_PROCESS_COOL, MATERIAL_PROCESS_MELT, MATERIAL_PROCESS_CAST, MATERIAL_PROCESS_HOMOGENIZE, MATERIAL_PROCESS_SOLUTION_TREAT, MATERIAL_PROCESS_ANNEAL, MATERIAL_PROCESS_QUENCH, MATERIAL_PROCESS_TEMPER, MATERIAL_PROCESS_SINTER)

/obj/machinery/material_processor/proc/finish_process()
	process_timer = null
	if(!batch || !pending_process)
		pending_process = null
		pending_option = null
		return
	var/completed_process = pending_process
	var/completed_option = pending_option
	var/completed_duration_seconds = pending_duration_seconds
	pending_process = null
	pending_option = null
	pending_duration_seconds = 0
	if(!batch.apply_process(completed_process, completed_option))
		visible_message(span_warning("[src] rejects the cycle because the batch is outside its valid phase or temperature window."))
		return
	batch.record_cost(MATERIAL_COST_MEDIA, process_media_cost(completed_process, completed_option))
	batch.record_cost(MATERIAL_COST_LABOR, completed_duration_seconds * MATERIAL_LABOR_COST_PER_SECOND)
	batch.record_cost(MATERIAL_COST_EQUIPMENT, completed_duration_seconds * MATERIAL_EQUIPMENT_COST_PER_SECOND)
	if(batch.hazard_score() >= 75)
		var/datum/effect/effect/system/spark_spread/sparks = new
		sparks.set_up(3, FALSE, src)
		sparks.start()
		qdel(sparks)
		batch.structure[MATERIAL_STRUCTURE_DEFECT] = clamp(batch.structure[MATERIAL_STRUCTURE_DEFECT] + 8, 0, 100)
		batch.yield_fraction = clamp(batch.yield_fraction - 0.05, 0.5, 1)
		batch.record_yield_loss(0.05)
		batch.normalize_structure()
		batch.recalculate()
		visible_message(span_warning("[src] vents a reactive process upset; usable yield falls."))
	else
		visible_message(span_notice("[src] completes a [completed_process] cycle."))

/obj/machinery/material_processor/proc/process_media_cost(process, option)
	if(!batch)
		return 0

	var/per_sheet = 0
	if(process == MATERIAL_PROCESS_QUENCH)
		per_sheet += option == "cryo" ? 6 : (option == "oil" ? 2 : 0.5)
	if(process in list(MATERIAL_PROCESS_HEAT, MATERIAL_PROCESS_MELT, MATERIAL_PROCESS_HOMOGENIZE, MATERIAL_PROCESS_SOLUTION_TREAT, MATERIAL_PROCESS_ANNEAL, MATERIAL_PROCESS_TEMPER))
		per_sheet += batch.atmosphere == MATERIAL_ATMOSPHERE_REDUCING ? 3 : (batch.atmosphere == MATERIAL_ATMOSPHERE_VACUUM ? 2 : (batch.atmosphere == MATERIAL_ATMOSPHERE_INERT ? 1 : 0))
	if(process in list(MATERIAL_PROCESS_DISSOLVE, MATERIAL_PROCESS_ELECTROLYZE, MATERIAL_PROCESS_PLATE, MATERIAL_PROCESS_CRYSTALLIZE))
		per_sheet += 1.5
	if(process == MATERIAL_PROCESS_SINTER)
		per_sheet += 1
	return per_sheet * batch.amount

/obj/machinery/material_processor/proc/process_power_units(process, option, duration_seconds)
	var/power_units = active_power_usage * duration_seconds
	if(process == MATERIAL_PROCESS_HEAT)
		var/heat_step = text2num(option)
		if(!heat_step)
			heat_step = 400
		power_units += round(heat_step * max(batch?.amount, 1) * 4)
	else if(process in list(MATERIAL_PROCESS_MELT, MATERIAL_PROCESS_HOMOGENIZE, MATERIAL_PROCESS_ELECTROLYZE, MATERIAL_PROCESS_SINTER))
		power_units += active_power_usage * duration_seconds
	return max(power_units, 0)

/obj/machinery/material_processor/proc/run_material_test(test, mob/user)
	if(!batch || !(test in list(MATERIAL_TEST_SPECTROMETRY, MATERIAL_TEST_MICROSCOPY, MATERIAL_TEST_HARDNESS, MATERIAL_TEST_CONDUCTIVITY, MATERIAL_TEST_TENSILE, MATERIAL_TEST_CORROSION)))
		return FALSE
	if(test in list(MATERIAL_TEST_TENSILE, MATERIAL_TEST_CORROSION))
		if(batch.amount <= 1)
			to_chat(user, span_warning("A destructive test needs a spare sheet beyond the retained reference sample."))
			return FALSE
		var/old_amount = batch.amount
		batch.amount--
		for(var/component in batch.composition)
			batch.composition[component] *= batch.amount / old_amount
		batch.yield_fraction = clamp(batch.yield_fraction - 0.03, 0.5, 1)
		batch.record_yield_loss(0.03)
	switch(test)
		if(MATERIAL_TEST_SPECTROMETRY)
			batch.test_results[test] = batch.purity
		if(MATERIAL_TEST_MICROSCOPY)
			batch.test_results[test] = 100 - batch.structure[MATERIAL_STRUCTURE_DEFECT]
		if(MATERIAL_TEST_HARDNESS)
			batch.test_results[test] = batch.hardness
		if(MATERIAL_TEST_CONDUCTIVITY)
			batch.test_results[test] = batch.conductivity
		if(MATERIAL_TEST_TENSILE)
			batch.test_results[test] = batch.toughness
		if(MATERIAL_TEST_CORROSION)
			batch.test_results[test] = batch.corrosion_resistance
	batch.process_history += "[test] performed"
	var/test_seconds = (test in list(MATERIAL_TEST_TENSILE, MATERIAL_TEST_CORROSION)) ? 4 : 2
	var/test_power = active_power_usage * test_seconds
	use_power(test_power)
	batch.record_electricity(test_power)
	batch.record_cost(MATERIAL_COST_LABOR, test_seconds * MATERIAL_LABOR_COST_PER_SECOND)
	batch.record_cost(MATERIAL_COST_EQUIPMENT, test_seconds * MATERIAL_EQUIPMENT_COST_PER_SECOND)
	return TRUE

/obj/machinery/material_processor/proc/certify_batch(mob/user)
	if(!batch)
		return FALSE
	for(var/required_test in list(MATERIAL_TEST_SPECTROMETRY, MATERIAL_TEST_MICROSCOPY, MATERIAL_TEST_HARDNESS, MATERIAL_TEST_CONDUCTIVITY, MATERIAL_TEST_TENSILE, MATERIAL_TEST_CORROSION))
		if(isnull(batch.test_results[required_test]))
			to_chat(user, span_warning("Certification requires a complete spectroscopy, microscopy, mechanical, conductivity, and corrosion test portfolio."))
			return FALSE
	var/obj/item/paper/report = new(get_turf(src))
	var/license_value = clamp(round((batch.hardness + batch.toughness + batch.conductivity + batch.heat_resistance + batch.corrosion_resistance) * 0.8 + length(batch.composition) * 45 + (batch.test_results[MATERIAL_TEST_FIELD] ? 100 : 0) - batch.unit_production_cost() * 2), 100, 900)
	var/list/costs = batch.cost_breakdown()
	var/list/capability_names = list()
	for(var/list/capability_data as anything in batch.material_capability_preview())
		var/capability_name = capability_data["name"]
		var/capability_potency = capability_data["potency"]
		capability_names += "[capability_name] ([capability_potency]%)"
	report.set_content("MATERIAL QUALIFICATION AND LICENSE REPORT\nBatch: [batch.display_name()]\nFingerprint: [batch.fingerprint()]\nComposition: [json_encode(batch.composition)]\nSource lots: [json_encode(batch.feedstock_lots)]\nPurity: [batch.purity]%\nHardness: [batch.hardness]\nToughness: [batch.toughness]\nConductivity: [batch.conductivity]\nHeat resistance: [batch.heat_resistance]\nCorrosion resistance: [batch.corrosion_resistance]\nEmergent capabilities: [length(capability_names) ? jointext(capability_names, ", ") : "none"]\nUsable output: [round(batch.usable_output(), 0.01)] sheets ([round(batch.yield_fraction * 100)]% yield)\nFeedstock: [round(costs[MATERIAL_COST_FEEDSTOCK], 0.01)] Th\nChemical additives: [round(costs[MATERIAL_COST_CHEMICALS], 0.01)] Th\nCatalysts: [round(costs[MATERIAL_COST_CATALYSTS], 0.01)] Th\nElectricity: [round(costs[MATERIAL_COST_ELECTRICITY], 0.01)] Th\nProcess media: [round(costs[MATERIAL_COST_MEDIA], 0.01)] Th\nProcess-time allocation: [round(costs[MATERIAL_COST_LABOR], 0.01)] Th\nEquipment wear: [round(costs[MATERIAL_COST_EQUIPMENT], 0.01)] Th\nWaste handling: [round(costs[MATERIAL_COST_WASTE_HANDLING], 0.01)] Th\nByproduct recovery credit: -[round(costs[MATERIAL_COST_RECOVERY], 0.01)] Th\nWaste value: [round(costs[MATERIAL_COST_WASTE], 0.01)] Th (already included in purchased inputs)\nTotal batch expense: [round(costs["total"], 0.01)] Th\nCost per usable sheet: [round(costs["per_sheet"], 0.01)] Th\nProcess route: [jointext(batch.process_history, " -> ")]\nCertified by: [user.real_name]\n\nThis ordinary signed report may be shipped as a licensable process specification. Its external value is based on measured performance, novelty, field validation, and cost per usable output.", "material qualification and license - [copytext(batch.fingerprint(), 1, 9)]")
	report.set_economic_provenance(DEPARTMENT_RESEARCH, license_value)
	report.AddElement(/datum/element/sellable/manufactured)
	emit_contract_event(CONTRACT_EVENT_MATERIAL_CERTIFIED, batch.evidence_context("certification"), batch.fingerprint(), src, user)
	return TRUE

/obj/machinery/material_processor/forming
	name = "materials forming press"
	desc = "A programmable rolling, forging, and wire-drawing press."
	icon_state = "circuit_imprinter"
	processor_kind = "forming"
	circuit = /obj/item/circuitboard/machine/material_processor/forming

/obj/machinery/material_processor/forming/available_operations()
	return list(MATERIAL_PROCESS_PULVERIZE, MATERIAL_PROCESS_ROLL, MATERIAL_PROCESS_FORGE, MATERIAL_PROCESS_DRAW)

/obj/machinery/material_processor/electrochemical
	name = "electrochemical materials cell"
	desc = "A sealed cell for purification, electrolysis, deposition, and crystallization."
	icon_state = "protolathe"
	processor_kind = "electrochemical"
	circuit = /obj/item/circuitboard/machine/material_processor/electrochemical

/obj/machinery/material_processor/electrochemical/available_operations()
	return list(MATERIAL_PROCESS_DISSOLVE, MATERIAL_PROCESS_PURIFY, MATERIAL_PROCESS_ELECTROLYZE, MATERIAL_PROCESS_PLATE, MATERIAL_PROCESS_CRYSTALLIZE)

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
