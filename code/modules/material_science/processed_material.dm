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
	material.integrity = batch.toughness
	material.elasticity = clamp(batch.toughness - batch.brittleness * 0.25, 1, 100)
	material.brittleness = batch.brittleness
	material.heat_resistance = batch.heat_resistance
	material.conductivity = batch.conductivity
	material.corrosion_resistance = batch.corrosion_resistance
	material.reactivity = clamp(100 - batch.purity + length(batch.impurities) * 5, 0, 100)
	material.melting_point = batch.melting_temperature()
	material.supply_conversion_value = clamp(round((batch.hardness + batch.toughness + batch.conductivity + batch.purity) / 20), 5, 30)
	material.composite_material = list()
	for(var/component in batch.composition)
		material.composite_material[component] = round(SHEET_MATERIAL_AMOUNT * batch.composition[component] / max(batch.amount, 1))
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

/datum/material_specification/proc/matches(datum/material_batch/batch)
	if(!istype(batch))
		return FALSE
	for(var/property in list("purity", "hardness", "toughness", "conductivity", "heat_resistance", "corrosion_resistance"))
		if(abs(requirements[property] - batch.evidence_context("comparison")[property]) > tolerance)
			return FALSE
	return TRUE
