GLOBAL_LIST_EMPTY(processed_material_dedup)
GLOBAL_LIST_EMPTY(material_specifications)

/obj/item/stack/material
	/// Source variability lives on the physical feedstock lot; material laws remain deterministic.
	var/feedstock_purity
	var/feedstock_lot_id
	var/feedstock_trace
	var/feedstock_trace_units = 0

/obj/item/stack/material/proc/ensure_feedstock_lot()
	if(feedstock_purity)
		return
	if(istype(material, /datum/material/processed_alloy))
		var/datum/material/processed_alloy/processed = material
		feedstock_purity = processed.batch_template.purity
		feedstock_lot_id = copytext(processed.batch_template.fingerprint(), 1, 9)
		return
	feedstock_purity = rand(78, 99)
	feedstock_lot_id = uppertext(copytext(md5("[world.realtime]-[REF(src)]-[rand()]"), 1, 9))
	if(feedstock_purity < 96)
		feedstock_trace = pick("carbon trace", "silicon trace", "sulfur contamination", "copper trace", "oxide inclusion")
		feedstock_trace_units = rand(2, max(2, 100 - feedstock_purity)) / 10

/obj/item/stack/material/examine(mob/user)
	. = ..()
	ensure_feedstock_lot()
	. += span_notice("Feedstock lot [feedstock_lot_id], assay purity [feedstock_purity]%.")
	if(feedstock_trace)
		. += span_notice("Trace assay: [feedstock_trace_units]u [feedstock_trace] per sheet.")

/datum/material/processed_alloy
	stack_type = /obj/item/stack/material/processed_alloy
	var/datum/material_batch/batch_template
	var/effect_charges = SUBSTANCE_INFUSION_CHARGES

/datum/material/processed_alloy/Destroy()
	QDEL_NULL(batch_template)
	return ..()

/datum/material/processed_alloy/dq_apply_material_behaviors(obj/item/item)
	. = ..()
	if(batch_template?.infused_substance)
		item.AddComponent(/datum/component/substance_infusion, batch_template.infused_substance, effect_charges)

/proc/register_processed_material(datum/material_batch/batch)
	if(!istype(batch) || !length(batch.composition))
		return null
	batch.recalculate()
	var/fingerprint = batch.fingerprint()
	var/existing = GLOB.processed_material_dedup[fingerprint]
	if(existing && GLOB.name_to_material[existing])
		return existing
	var/key = "processed_alloy_[copytext(fingerprint, 1, 13)]"
	var/datum/material/processed_alloy/material = new
	material.name = key
	material.display_name = batch.display_name()
	material.use_name = material.display_name
	material.batch_template = batch.copy_batch()
	material.effect_charges = clamp(round(1 + batch.purity / 25 - batch.structure[MATERIAL_STRUCTURE_DEFECT] / 20), 1, 6)
	material.hardness = batch.hardness
	material.integrity = clamp(round(batch.toughness * 2), 5, 250)
	material.elasticity = clamp(batch.toughness - batch.brittleness * 0.25, 1, 100)
	material.brittleness = batch.brittleness
	material.heat_resistance = batch.heat_resistance
	material.conductivity = batch.conductivity
	material.corrosion_resistance = batch.corrosion_resistance
	material.reactivity = clamp(100 - batch.purity + length(batch.impurities) * 5, 0, 100)
	material.melting_point = batch.melting_temperature()
	var/weighted_density = 0
	var/weighted_magnetism = 0
	var/weighted_reflectivity = 0
	var/weighted_opacity = 0
	var/weighted_luminescence = 0
	var/weighted_radioactivity = 0
	var/weighted_toxicity = 0
	var/weighted_radiation_resistance = 0
	material.composite_material = list()
	for(var/component in batch.composition)
		var/share = batch.composition[component] / max(batch.amount, 1)
		material.composite_material[component] = round(SHEET_MATERIAL_AMOUNT * share)
		var/datum/material/component_material = get_material_by_name(component)
		if(!component_material)
			continue
		weighted_density += component_material.density * share
		weighted_magnetism += component_material.magnetism * share
		weighted_reflectivity += component_material.reflectivity * share
		weighted_opacity += component_material.opacity * share
		weighted_luminescence += dq_material_luminescence(component_material) * share
		weighted_radioactivity += dq_material_radioactivity(component_material) * share
		weighted_toxicity += dq_material_toxicity(component_material) * share
		weighted_radiation_resistance += component_material.radiation_resistance * share
	material.density = clamp(round(max(weighted_density, batch.hardness * 0.35 + batch.toughness * 0.25)), 1, 120)
	material.protectiveness = clamp(round(batch.toughness * 0.48 + batch.hardness * 0.28 - batch.brittleness * 0.2), 1, 75)
	material.explosion_resistance = clamp(round(batch.toughness / 8 + batch.hardness / 14 - batch.brittleness / 20), 1, 25)
	material.thermal_insulation = clamp(round(batch.heat_resistance * 0.65 + (100 - batch.conductivity) * 0.35), 0, 100)
	material.magnetism = clamp(round(weighted_magnetism), 0, 100)
	material.reflectivity = clamp(weighted_reflectivity + batch.purity / 500, 0, 1)
	material.opacity = clamp(weighted_opacity > 0 ? weighted_opacity : 1, 0, 1)
	material.luminescence = max(0, round(weighted_luminescence))
	material.radioactivity = max(0, round(weighted_radioactivity))
	material.toxicity = max(0, round(weighted_toxicity * (1 - batch.corrosion_resistance / 200)))
	material.radiation_resistance = max(0, round(weighted_radiation_resistance + material.density / 12))
	material.conductive = batch.conductivity >= 15
	if(batch.brittleness >= 70)
		material.flags |= MATERIAL_BRITTLE
	var/performance_value = (batch.hardness + batch.toughness + batch.conductivity + batch.heat_resistance + batch.corrosion_resistance + batch.purity) / 24
	material.supply_conversion_value = clamp(round(max(performance_value, batch.unit_production_cost() * 1.15)), 5, 80)
	var/datum/material/dominant
	var/dominant_amount = 0
	for(var/component in batch.composition)
		if(batch.composition[component] > dominant_amount)
			dominant = get_material_by_name(component)
			dominant_amount = batch.composition[component]
	if(dominant)
		material.icon_colour = dominant.icon_colour
		material.material_class = dominant.material_class
	GLOB.name_to_material[key] = material
	GLOB.processed_material_dedup[fingerprint] = key
	return key

/proc/processed_spawn_stack(turf/location, datum/material_batch/batch, amount)
	if(!location || !istype(batch))
		return null
	var/material_key = register_processed_material(batch)
	if(!material_key)
		return null
	var/stack_amount = clamp(round(amount || batch.amount), 1, MATERIAL_SCIENCE_MAX_BATCH)
	return new /obj/item/stack/material/processed_alloy(location, stack_amount, material_key)

/proc/material_batch_from_stack(obj/item/stack/material/stack)
	if(!istype(stack) || !stack.material)
		return null
	if(istype(stack.material, /datum/material/processed_alloy))
		var/datum/material/processed_alloy/processed = stack.material
		return processed.batch_template.copy_batch()
	var/datum/material_batch/batch = new
	batch.add_material(stack.material.name, stack.amount)
	return batch

/obj/item/stack/material/processed_alloy
	name = "processed material stock"
	desc = "Traceable material stock whose composition and processing history determine its performance."
	icon = 'icons/obj/mining.dmi'
	icon_state = "sheet-plastic"
	default_type = MAT_STEEL
	no_variants = TRUE
	pass_color = TRUE
	strict_color_stacking = TRUE
	exotic_no_autolathe_reprint = TRUE

/obj/item/stack/material/processed_alloy/Initialize(mapload, _amount, _material_name)
	if(_material_name)
		default_type = _material_name
	. = ..(mapload, _amount)
	if(material)
		color = material.icon_colour
		set_economic_provenance(DEPARTMENT_RESEARCH, max(material.supply_conversion_value, 1) * amount)

/obj/item/stack/material/processed_alloy/examine(mob/user)
	. = ..()
	if(!istype(material, /datum/material/processed_alloy))
		return
	var/datum/material/processed_alloy/processed = material
	var/datum/material_batch/batch = processed.batch_template
	. += span_notice("Form: <b>[batch.form]</b>; [batch.phase] at [round(batch.temperature)] K.")
	if(batch.test_results[MATERIAL_TEST_SPECTROMETRY])
		. += span_notice("Certified assay purity: [batch.purity]%.")
	if(length(batch.test_results))
		var/list/disclosed = list()
		for(var/test in batch.test_results)
			disclosed += "[test]: [batch.test_results[test]]"
		. += span_notice("Recorded tests: [jointext(disclosed, "; ")].")
	else
		. += span_notice("No qualified properties are marked on this stock; use a materials test stand.")
	. += span_notice("Batch fingerprint: [batch.fingerprint()].")

/datum/material_specification
	var/name
	var/fingerprint
	var/list/requirements
	var/list/composition
	var/created_by
	var/created_at
	var/list/process_route
	var/atmosphere
	var/form
	var/tolerance = 5

/datum/material_specification/New(spec_name, datum/material_batch/batch, author)
	..()
	name = spec_name
	fingerprint = batch.fingerprint()
	requirements = batch.evidence_context(MATERIAL_PROCESS_CAST)
	composition = batch.composition.Copy()
	created_by = author
	created_at = world.time
	process_route = batch.process_history.Copy()
	atmosphere = batch.atmosphere
	form = batch.form

/datum/material_specification/proc/matches(datum/material_batch/batch)
	if(!istype(batch))
		return FALSE
	for(var/property in list("purity", "hardness", "toughness", "conductivity", "heat_resistance", "corrosion_resistance"))
		if(abs(requirements[property] - batch.evidence_context("comparison")[property]) > tolerance)
			return FALSE
	return TRUE

/datum/material_specification/proc/print_order(turf/location, requester, quantity)
	var/obj/item/paper/order = new(location)
	var/req_purity = requirements["purity"]
	var/req_hardness = requirements["hardness"]
	var/req_toughness = requirements["toughness"]
	var/req_conductivity = requirements["conductivity"]
	var/req_heat = requirements["heat_resistance"]
	var/req_corrosion = requirements["corrosion_resistance"]
	var/route_text = jointext(process_route, " -> ")
	var/list/lines = list(
		"MATERIAL PRODUCTION ORDER",
		"Specification: [name]",
		"Requested by: [requester]",
		"Quantity: [quantity] usable sheets",
		"Required form: [form]",
		"Controlled atmosphere: [atmosphere]",
		"Composition: [json_encode(composition)]",
		"Acceptance tolerance: +/-[tolerance] points",
		"Purity: [req_purity]",
		"Hardness: [req_hardness]",
		"Toughness: [req_toughness]",
		"Conductivity: [req_conductivity]",
		"Heat resistance: [req_heat]",
		"Corrosion resistance: [req_corrosion]",
		"Qualified route: [route_text]",
		"Acceptance requires a matching batch fingerprint comparison and ordinary certification paperwork.",
	)
	order.set_content(jointext(lines, "\n"), "material production order - [name]")
	return order
