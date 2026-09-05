GLOBAL_LIST_EMPTY(processed_material_dedup)

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

/datum/material/processed_alloy/Destroy()
	QDEL_NULL(batch_template)
	return ..()

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
	material.hardness = batch.hardness
	material.integrity = clamp(round(batch.toughness * 2), 5, 250)
	material.elasticity = clamp(batch.toughness - batch.brittleness * 0.25, 1, 100)
	material.brittleness = batch.brittleness
	material.heat_resistance = batch.heat_resistance
	material.conductivity = batch.conductivity
	material.corrosion_resistance = batch.corrosion_resistance
	material.reactivity = clamp(100 - batch.purity + length(batch.impurities) * 5, 0, 100)
	material.melting_point = batch.melting_temperature()
	material.electrical_resistivity = max(0.02, (105 - batch.conductivity) / max(batch.conductivity, 1))
	material.specific_heat = clamp(round(250 + batch.heat_resistance * 5 + batch.porosity * 2), 200, 1200)
	material.yield_strength = clamp(round(batch.hardness * 8 + batch.toughness * 3 - batch.porosity * 2), 25, 1200)
	material.fracture_toughness = clamp(round(batch.toughness - batch.brittleness * 0.5), 5, 150)
	material.dielectric_strength = clamp(round((100 - batch.conductivity) * 1.2 + batch.corrosion_resistance * 0.25), 1, 150)
	var/cryo_skin = batch.surface_layers[MATERIAL_SURFACE_SLIME_CRYO] || 0
	var/thermal_skin = batch.surface_layers[MATERIAL_SURFACE_SLIME_THERMAL] || 0
	var/metal_hydrogen_share = (batch.composition[MAT_METALHYDROGEN] || 0) / max(batch.amount, 1)
	if((metal_hydrogen_share >= 0.15 || (batch.additive_units_matching("cryogenic stabilizer") && cryo_skin)) && batch.conductivity >= 75 && batch.purity >= 90)
		material.critical_temperature = clamp(T0C - 120 + cryo_skin * 0.8, 40, T0C - 5)
		material.critical_current_density = clamp(batch.conductivity * batch.purity / 8, 100, 1500)
	if(cryo_skin || thermal_skin)
		material.phase_change_temperature = cryo_skin ? max(60, T0C - cryo_skin) : T0C + thermal_skin * 2
		material.phase_change_capacity = clamp(round((cryo_skin + thermal_skin) * material.specific_heat * 4), 1000, 500000)
	if(batch.surface_layers[MATERIAL_SURFACE_SLIME_CATALYTIC] || batch.additive_units_matching("platinum plating") || batch.additive_units_matching("gold plating"))
		material.catalytic_activity = clamp(round(batch.purity * 0.7 + batch.corrosion_resistance * 0.3), 1, 100)
	var/crystal_amount = (batch.composition[MAT_QUARTZ] || 0) + (batch.composition[MAT_DIAMOND] || 0) + (batch.composition[MAT_GLASS] || 0) + (batch.composition[MAT_VOLTAIC_CRYSTAL] || 0) + (batch.composition[MAT_KINETIC_CRYSTAL] || 0) + (batch.composition[MAT_LUMEN_CRYSTAL] || 0) + (batch.composition[MAT_RIFT_GLASS] || 0)
	var/biological_amount = (batch.composition[MAT_BIOMASS] || 0) + (batch.composition[MAT_FLESH] || 0) + (batch.composition[MAT_CHITIN] || 0) + (batch.composition[MAT_ALIENCHITIN] || 0) + (batch.composition[MAT_SPORE_BIOMASS] || 0)
	var/has_crystal = crystal_amount / max(batch.amount, 1) >= 0.1
	var/has_biological = biological_amount / max(batch.amount, 1) >= 0.15
	var/particle_conditioned = batch.field_treatments[MATERIAL_FIELD_PARTICLE] || 0
	if(batch.additive_units_matching("thermal phase catalyst") && thermal_skin && batch.conductivity >= 45)
		material.thermoelectric_coefficient = clamp((batch.conductivity + batch.heat_resistance) / 200, 0, 1)
	if(has_crystal && batch.conductivity >= 30 && batch.homogeneity >= 70)
		material.piezoelectric_coefficient = clamp((batch.conductivity + batch.homogeneity - batch.porosity) / 200, 0, 1)
	if(batch.composition[MAT_KINETIC_CRYSTAL])
		var/kinetic_share = batch.composition[MAT_KINETIC_CRYSTAL] / max(batch.amount, 1)
		material.piezoelectric_coefficient = max(material.piezoelectric_coefficient, clamp(0.68 * kinetic_share * batch.homogeneity / 100, 0, 1))
	if(batch.composition[MAT_THERMIC_CERAMIC])
		var/thermic_share = batch.composition[MAT_THERMIC_CERAMIC] / max(batch.amount, 1)
		material.phase_change_temperature = T0C + 40
		material.phase_change_capacity = max(material.phase_change_capacity, round(65000 * thermic_share * batch.purity / 100))
	if(batch.composition[MAT_ETCHING_CERAMIC])
		material.catalytic_activity = max(material.catalytic_activity, clamp(batch.purity * batch.corrosion_resistance / 100, 0, 100))
	if(batch.additive_units_matching("conductive dopant") && batch.surface_layers[MATERIAL_SURFACE_SLIME_CONDUCTIVE] && batch.conductivity >= 40 && batch.homogeneity >= 60)
		material.electrogenic_rate = clamp((batch.conductivity + batch.homogeneity) / 4, 0, 50)
	if(((batch.composition[MAT_MORPHIUM] || 0) / max(batch.amount, 1) >= 0.15 || ((batch.composition[MAT_TITANIUM] || 0) / max(batch.amount, 1) >= 0.25 && batch.structure[MATERIAL_STRUCTURE_HARDENED] >= 20)) && batch.toughness >= 55)
		material.shape_recovery_rate = clamp((batch.toughness + batch.homogeneity - batch.internal_stress) / 40, 0, 5)
		material.shape_recovery_temperature = T0C + 80
	if((batch.composition[MAT_WARD_METAL] || 0) / max(batch.amount, 1) >= 0.15 || ((batch.composition[MAT_PLASTEEL] || 0) / max(batch.amount, 1) >= 0.25 && batch.structure[MATERIAL_STRUCTURE_PRECIPITATE] >= 20))
		material.reactive_energy_capacity = clamp((batch.toughness + batch.hardness) * 25, 0, 5000)
	if(((batch.composition[MAT_SILVER] || 0) / max(batch.amount, 1) >= 0.1 || batch.additive_units_matching("silver plating")) && batch.corrosion_resistance >= 50)
		material.antimicrobial_activity = clamp((batch.corrosion_resistance + batch.purity) / 2, 0, 100)
	if(has_biological && (batch.composition[MAT_IRON] || batch.additive_units_matching("precipitation catalyst")))
		material.hemostatic_activity = clamp((batch.homogeneity + batch.purity) / 2, 0, 100)
	if(has_biological && (batch.composition[MAT_MORPHIUM] || batch.structure[MATERIAL_STRUCTURE_AMORPHOUS] >= 20))
		material.biocompatibility = clamp((batch.toughness + batch.homogeneity) / 2, 0, 100)
	if(batch.porosity >= 18 && (batch.composition[MAT_TITANIUM] || batch.composition[MAT_ALUMINIUM] || batch.composition[MAT_GRAPHITE]))
		material.gas_sorption_capacity = clamp(batch.porosity / 5 + batch.corrosion_resistance / 20, 0, 25)
	if((batch.composition[MAT_RIFT_GLASS] || 0) / max(batch.amount, 1) >= 0.15)
		material.gas_sorption_capacity = max(material.gas_sorption_capacity, clamp(batch.porosity / 4 + batch.purity / 8, 0, 25))
	if(batch.porosity >= 22 && batch.corrosion_resistance >= 45)
		material.reagent_porosity = clamp(batch.porosity / 4, 0, 25)
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
		material.composite_material[component] = SHEET_MATERIAL_AMOUNT * share
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
	var/radioactive_share = ((batch.composition[MAT_URANIUM] || 0) + (batch.composition[MAT_TRITIUM] || 0)) / max(batch.amount, 1)
	if(radioactive_share >= 0.1 && batch.conductivity >= 35 && particle_conditioned >= 20)
		material.radiovoltaic_efficiency = clamp((batch.conductivity + material.radioactivity) / 200, 0, 1)
	if(radioactive_share >= 0.1 && has_crystal && batch.homogeneity >= 65 && particle_conditioned >= 20)
		material.scintillation_efficiency = clamp((batch.homogeneity + material.reflectivity * 100) / 200, 0, 1)
	if((batch.composition[MAT_LUMEN_CRYSTAL] || 0) / max(batch.amount, 1) >= 0.15 && batch.homogeneity >= 60)
		material.scintillation_efficiency = max(material.scintillation_efficiency, clamp((batch.homogeneity + batch.purity) / 220, 0, 1))
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
	// Material stacks require a physical location during atom initialization.
	// Stack merging is an explicit later interaction, so constructing directly
	// on the output turf preserves both initialization and the returned ref.
	var/obj/item/stack/material/processed_alloy/stock = new /obj/item/stack/material/processed_alloy(location, stack_amount, material_key)
	QDEL_NULL(stock.batch_state)
	stock.batch_state = batch.copy_for_amount(stack_amount)
	stock.update_thermal_processing()
	return stock

/proc/material_batch_from_stack(obj/item/stack/material/stack)
	if(!istype(stack) || !stack.material)
		return null
	if(istype(stack.material, /datum/material/processed_alloy))
		var/obj/item/stack/material/processed_alloy/processed_stack = stack
		return processed_stack.physical_batch()?.copy_batch()
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
	var/datum/material_batch/batch_state

/obj/item/stack/material/processed_alloy/Initialize(mapload, _amount, _material_name)
	if(_material_name)
		default_type = _material_name
	. = ..(mapload, _amount)
	if(istype(material, /datum/material/processed_alloy))
		color = material.icon_colour
		set_economic_provenance(DEPARTMENT_RESEARCH, max(material.supply_conversion_value, 1) * amount)
		var/datum/material/processed_alloy/processed = material
		batch_state = processed.batch_template.copy_for_amount(amount)

/obj/item/stack/material/processed_alloy/Destroy()
	STOP_PROCESSING(SSobj, src)
	QDEL_NULL(batch_state)
	return ..()

/obj/item/stack/material/processed_alloy/proc/physical_batch() as /datum/material_batch
	if(batch_state)
		return batch_state
	var/datum/material/processed_alloy/processed = material
	batch_state = processed?.batch_template?.copy_for_amount(amount)
	return batch_state

/obj/item/stack/material/processed_alloy/proc/update_thermal_processing()
	var/datum/material_batch/batch = physical_batch()
	if(batch?.temperature > T20C + 40)
		set_light(2, 1, "#ff7b22")
		START_PROCESSING(SSobj, src)
	else
		set_light(0)
		STOP_PROCESSING(SSobj, src)

/obj/item/stack/material/processed_alloy/process()
	var/datum/material_batch/batch = physical_batch()
	if(!batch)
		return PROCESS_KILL
	var/ambient_temperature = T20C
	var/turf/open/turf = get_turf(src)
	if(istype(turf) && turf.air)
		ambient_temperature = turf.air.return_temperature()
	batch.temperature += (ambient_temperature - batch.temperature) * 0.08
	if(abs(batch.temperature - ambient_temperature) < 5)
		batch.temperature = ambient_temperature
		set_light(0)
		return PROCESS_KILL
	return

/obj/item/stack/material/processed_alloy/split(tamount)
	var/old_amount = get_amount()
	var/datum/material_batch/original = physical_batch()?.copy_batch()
	var/obj/item/stack/material/processed_alloy/new_stack = ..()
	if(!new_stack || !original)
		qdel(original)
		return new_stack
	new_stack.set_processed_material(material.name)
	QDEL_NULL(new_stack.batch_state)
	new_stack.batch_state = original.copy_for_amount(new_stack.get_amount())
	QDEL_NULL(batch_state)
	batch_state = original.copy_for_amount(max(old_amount - new_stack.get_amount(), 0))
	qdel(original)
	return new_stack

/obj/item/stack/material/processed_alloy/transfer_to(obj/item/stack/target, tamount = null, type_verified)
	var/obj/item/stack/material/processed_alloy/processed_target = target
	if(!istype(processed_target) || processed_target.material?.name != material?.name)
		return 0
	var/source_before = get_amount()
	var/target_before = processed_target.get_amount()
	var/datum/material_batch/source_batch = physical_batch()?.copy_batch()
	var/datum/material_batch/target_batch = processed_target.physical_batch()?.copy_batch()
	var/transferred = ..(target, tamount, type_verified)
	if(!transferred)
		qdel(source_batch)
		qdel(target_batch)
		return 0
	var/datum/material_batch/new_target = target_batch.copy_for_amount(target_before)
	var/datum/material_batch/source_portion = source_batch.copy_for_amount(transferred)
	new_target.amount += source_portion.amount
	for(var/material_name in source_portion.composition)
		new_target.composition[material_name] = (new_target.composition[material_name] || 0) + source_portion.composition[material_name]
	for(var/impurity in source_portion.impurities)
		new_target.impurities[impurity] = (new_target.impurities[impurity] || 0) + source_portion.impurities[impurity]
	for(var/lot_id in source_portion.feedstock_lots)
		new_target.feedstock_lots[lot_id] = (new_target.feedstock_lots[lot_id] || 0) + source_portion.feedstock_lots[lot_id]
	for(var/account_number in source_portion.contributors)
		new_target.contributors[account_number] = (new_target.contributors[account_number] || 0) + source_portion.contributors[account_number]
	for(var/category in source_portion.cost_ledger)
		new_target.cost_ledger[category] = (new_target.cost_ledger[category] || 0) + source_portion.cost_ledger[category]
	new_target.cost_basis += source_portion.cost_basis
	new_target.energy_spent += source_portion.energy_spent
	new_target.temperature = (target_batch.temperature * target_before + source_batch.temperature * transferred) / max(target_before + transferred, 1)
	new_target.recalculate()
	QDEL_NULL(processed_target.batch_state)
	processed_target.batch_state = new_target
	processed_target.update_thermal_processing()
	if(!QDELETED(src))
		var/datum/material_batch/new_source = source_batch.copy_for_amount(source_before - transferred)
		QDEL_NULL(batch_state)
		batch_state = new_source
		update_thermal_processing()
	qdel(source_portion)
	qdel(source_batch)
	qdel(target_batch)
	return transferred

/obj/item/stack/material/processed_alloy/proc/set_processed_material(material_name)
	var/datum/material/new_material = get_material_by_name(material_name)
	if(!istype(new_material, /datum/material/processed_alloy))
		return FALSE
	default_type = material_name
	material = new_material
	recipes = material.get_recipes()
	stacktype = material.stack_type
	color = material.icon_colour
	if(material.conductive)
		flags &= ~NOCONDUCT
	else
		flags |= NOCONDUCT
	matter = material.get_matter()
	update_strings()
	set_economic_provenance(DEPARTMENT_RESEARCH, max(material.supply_conversion_value, 1) * amount)
	return TRUE

/obj/item/stack/material/processed_alloy/examine(mob/user)
	. = ..()
	if(!istype(material, /datum/material/processed_alloy))
		return
	var/datum/material_batch/batch = physical_batch()
	. += span_notice("Finished solid stock at [round(batch.temperature)] K, produced at [round(batch.yield_fraction * 100)]% retained yield.")
	if(length(batch.surface_layers))
		. += span_notice("Persistent surface treatments: [jointext(batch.surface_layers, ", ")].")
	if(length(batch.dissolved_gases))
		. += span_notice("Entrained gas signatures: [jointext(batch.dissolved_gases, ", ")].")
	if(length(batch.field_treatments))
		. += span_notice("Field-conditioned lattice: [jointext(batch.field_treatments, ", ")].")
	if(length(batch.test_results))
		var/list/disclosed = list()
		for(var/test in batch.test_results)
			disclosed += "[test]: [batch.test_results[test]]"
		. += span_notice("Recorded tests: [jointext(disclosed, "; ")].")
	else
		. += span_notice("No physical observations have been recorded; its behavior remains experimental.")
	. += span_notice("Batch fingerprint: [batch.fingerprint()].")
