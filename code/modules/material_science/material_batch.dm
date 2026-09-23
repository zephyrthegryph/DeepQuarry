/// Canonical state for a physical batch. Recipes do not select an alloy: player inputs and
/// processing history produce one, and all consumers derive their properties from this datum.
/datum/material_batch
	var/list/composition = list()
	var/list/impurities = list()
	var/list/process_history
	var/list/contributors = list()
	var/list/feedstock_lots = list()
	var/list/test_results
	var/list/process_counts = list()
	/// Persistent physical surface treatments. These are layers, not bulk ingredients.
	var/list/surface_layers = list()
	/// Gases incorporated from the real processing atmosphere, in abstract retained units.
	var/list/dissolved_gases = list()
	/// High-energy or field treatments applied to the lattice.
	var/list/field_treatments = list()
	var/list/cost_ledger = list(
		MATERIAL_COST_FEEDSTOCK = 0,
		MATERIAL_COST_CHEMICALS = 0,
		MATERIAL_COST_CATALYSTS = 0,
		MATERIAL_COST_ELECTRICITY = 0,
		MATERIAL_COST_MEDIA = 0,
		MATERIAL_COST_LABOR = 0,
		MATERIAL_COST_EQUIPMENT = 0,
		MATERIAL_COST_WASTE_HANDLING = 0,
		MATERIAL_COST_RECOVERY = 0,
		MATERIAL_COST_WASTE = 0,
	)
	var/list/structure = list(
		MATERIAL_STRUCTURE_SOFT = 70,
		MATERIAL_STRUCTURE_HARDENED = 0,
		MATERIAL_STRUCTURE_PRECIPITATE = 0,
		MATERIAL_STRUCTURE_REINFORCEMENT = 0,
		MATERIAL_STRUCTURE_AMORPHOUS = 10,
		MATERIAL_STRUCTURE_DEFECT = 20,
	)
	var/amount = 0
	var/phase = MATERIAL_PHASE_SOLID
	var/temperature = T20C
	var/purity = 90
	var/grain_size = 50
	var/internal_stress = 15
	var/porosity = 10
	var/homogeneity = 75
	var/atmosphere = MATERIAL_ATMOSPHERE_AIR
	var/quench_medium = "water"
	var/solution_treated = FALSE
	var/yield_fraction = 1
	var/energy_spent = 0
	var/oxidation = 0
	var/cost_basis = 0
	var/surface_protection = 0
	var/hardness = 0
	var/toughness = 0
	var/conductivity = 0
	var/heat_resistance = 0
	var/corrosion_resistance = 0
	var/brittleness = 0

/datum/material_batch/Destroy()
	composition = null
	impurities = null
	process_history = null
	contributors = null
	feedstock_lots = null
	test_results = null
	process_counts = null
	surface_layers = null
	dissolved_gases = null
	field_treatments = null
	cost_ledger = null
	structure = null
	return ..()

/datum/material_batch/proc/add_material(material_name, sheets = 1, datum/money_account/producer, source_purity = 100, lot_id)
	var/datum/material/material = get_material_by_name(material_name)
	if(!material || sheets <= 0)
		return FALSE
	composition[material.name] = (composition[material.name] || 0) + sheets
	var/old_amount = amount
	amount += sheets
	purity = round((purity * old_amount + clamp(source_purity, 20, 100) * sheets) / max(amount, 1))
	if(lot_id)
		feedstock_lots[lot_id] = (feedstock_lots[lot_id] || 0) + sheets
	var/feedstock_cost = max(material.supply_conversion_value, 0.1) * sheets
	cost_basis += feedstock_cost
	record_cost(MATERIAL_COST_FEEDSTOCK, feedstock_cost)
	if(producer)
		contributors[producer.account_number] = (contributors[producer.account_number] || 0) + sheets
	recalculate()
	return TRUE

/datum/material_batch/proc/add_additive(additive_name, units, unit_cost = 1, cost_category = MATERIAL_COST_CHEMICALS)
	if(!additive_name || units <= 0)
		return FALSE
	impurities[additive_name] = (impurities[additive_name] || 0) + units
	var/concentration = units / max(amount, 1)
	purity = clamp(purity - round(concentration * 0.4), 20, 100)
	homogeneity = clamp(homogeneity - round(concentration * 0.2), 0, 100)
	LAZYADD(process_history, "alloyed with [units]u [additive_name]")
	var/additive_cost = max(unit_cost, 0) * units
	cost_basis += additive_cost
	record_cost(cost_category, additive_cost)
	recalculate()
	return TRUE

/datum/material_batch/proc/add_surface_layer(layer_name, strength, additive_name, additive_units = 0)
	if(!layer_name || strength <= 0)
		return FALSE
	surface_layers[layer_name] = clamp((surface_layers[layer_name] || 0) + strength, 0, 100)
	if(additive_name && additive_units > 0)
		impurities[additive_name] = (impurities[additive_name] || 0) + additive_units
	LAZYADD(process_history, "applied [layer_name]")
	recalculate()
	return TRUE

/datum/material_batch/proc/add_dissolved_gas(gas_name, units)
	if(!gas_name || units <= 0)
		return FALSE
	dissolved_gases[gas_name] = clamp((dissolved_gases[gas_name] || 0) + units, 0, 100)
	LAZYADD(process_history, "infused with [gas_name]")
	recalculate()
	return TRUE

/datum/material_batch/proc/add_field_treatment(treatment_name, strength)
	if(!treatment_name || strength <= 0)
		return FALSE
	field_treatments[treatment_name] = clamp((field_treatments[treatment_name] || 0) + strength, 0, 100)
	LAZYADD(process_history, treatment_name)
	recalculate()
	return TRUE

/datum/material_batch/proc/apply_process(process, option)
	if(!length(composition))
		return FALSE
	if(!can_process(process))
		return FALSE
	var/old_yield = yield_fraction
	switch(process)
		if(MATERIAL_PROCESS_MELT)
			if(temperature < melting_temperature())
				return FALSE
			phase = MATERIAL_PHASE_MOLTEN
			homogeneity = clamp(homogeneity + 18, 0, 100)
			porosity = clamp(porosity + 4, 0, 100)
			structure[MATERIAL_STRUCTURE_AMORPHOUS] = 70
			structure[MATERIAL_STRUCTURE_SOFT] = 10
			structure[MATERIAL_STRUCTURE_DEFECT] = 20
		if(MATERIAL_PROCESS_CAST)
			if(phase != MATERIAL_PHASE_MOLTEN)
				return FALSE
			phase = MATERIAL_PHASE_SOLID
			temperature = T20C + 80
			grain_size = 72
			internal_stress = 28
			porosity = clamp(porosity + 8, 0, 100)
			structure[MATERIAL_STRUCTURE_SOFT] = 65
			structure[MATERIAL_STRUCTURE_AMORPHOUS] = 10
			structure[MATERIAL_STRUCTURE_DEFECT] = 25
			solution_treated = FALSE
		if(MATERIAL_PROCESS_QUENCH)
			if(phase != MATERIAL_PHASE_SOLID || !solution_treated || temperature < melting_temperature() * 0.62)
				return FALSE
			phase = MATERIAL_PHASE_SOLID
			grain_size = clamp(grain_size - 28, 1, 100)
			internal_stress = clamp(internal_stress + (option == "oil" ? 18 : 30), 0, 100)
			porosity = clamp(porosity - 4, 0, 100)
			temperature = T20C
			var/quench_strength = option == "oil" ? 45 : (option == "cryo" ? 75 : 60)
			structure[MATERIAL_STRUCTURE_HARDENED] = clamp(structure[MATERIAL_STRUCTURE_HARDENED] + quench_strength, 0, 90)
			structure[MATERIAL_STRUCTURE_SOFT] = clamp(structure[MATERIAL_STRUCTURE_SOFT] - quench_strength, 0, 100)
			structure[MATERIAL_STRUCTURE_DEFECT] = clamp(structure[MATERIAL_STRUCTURE_DEFECT] + round(quench_strength / 8), 0, 100)
			quench_medium = option || "water"
			solution_treated = FALSE
		if(MATERIAL_PROCESS_FORGE)
			if(phase != MATERIAL_PHASE_SOLID || temperature < melting_temperature() * 0.45 || temperature > melting_temperature() * 0.9)
				return FALSE
			porosity = clamp(porosity - 22, 0, 100)
			grain_size = clamp(grain_size - 8, 1, 100)
			homogeneity = clamp(homogeneity + 8, 0, 100)
			structure[MATERIAL_STRUCTURE_DEFECT] = clamp(structure[MATERIAL_STRUCTURE_DEFECT] - 14, 0, 100)
		if(MATERIAL_PROCESS_PURIFY)
			var/removed_contamination = 0
			for(var/impurity in impurities.Copy())
				var/lower_impurity = lowertext(impurity)
				if(findtext(lower_impurity, "oxide") || findtext(lower_impurity, "sulfur"))
					removed_contamination += impurities[impurity]
					impurities -= impurity
			purity = clamp(purity + min(10, 2 + round(removed_contamination)), 0, 100)
			oxidation = max(0, oxidation - 20)
			homogeneity = clamp(homogeneity + 12, 0, 100)
			structure[MATERIAL_STRUCTURE_DEFECT] = clamp(structure[MATERIAL_STRUCTURE_DEFECT] - 10, 0, 100)
		if(MATERIAL_PROCESS_HOMOGENIZE)
			if(phase != MATERIAL_PHASE_MOLTEN)
				return FALSE
			homogeneity = clamp(homogeneity + 28, 0, 100)
			structure[MATERIAL_STRUCTURE_DEFECT] = clamp(structure[MATERIAL_STRUCTURE_DEFECT] - 8, 0, 100)
		if(MATERIAL_PROCESS_SOLUTION_TREAT)
			if(phase != MATERIAL_PHASE_SOLID || temperature < melting_temperature() * 0.62 || temperature > melting_temperature() * 0.9)
				return FALSE
			solution_treated = TRUE
			structure[MATERIAL_STRUCTURE_PRECIPITATE] = clamp(structure[MATERIAL_STRUCTURE_PRECIPITATE] - 15, 0, 100)
			structure[MATERIAL_STRUCTURE_SOFT] = clamp(structure[MATERIAL_STRUCTURE_SOFT] + 10, 0, 100)
		else
			return FALSE
	LAZYADD(process_history, option ? "[process] ([option])" : process)
	process_counts[process] = (process_counts[process] || 0) + 1
	if(yield_fraction < old_yield)
		record_yield_loss(old_yield - yield_fraction)
	normalize_structure()
	recalculate()
	emit_contract_event(CONTRACT_EVENT_MATERIAL_PROCESSED, evidence_context(process))
	return TRUE

/datum/material_batch/proc/record_cost(category, value)
	if(!category || !isnum(value) || value == 0)
		return
	cost_ledger[category] = (cost_ledger[category] || 0) + value

/datum/material_batch/proc/record_electricity(power_units)
	if(power_units <= 0)
		return
	energy_spent += power_units
	record_cost(MATERIAL_COST_ELECTRICITY, power_units / MATERIAL_POWER_UNITS_PER_THALER)

/datum/material_batch/proc/record_yield_loss(fraction_lost)
	if(fraction_lost <= 0 || amount <= 0)
		return
	var/feedstock_per_sheet = (cost_ledger[MATERIAL_COST_FEEDSTOCK] || 0) / amount
	record_cost(MATERIAL_COST_WASTE, amount * fraction_lost * feedstock_per_sheet)
	record_cost(MATERIAL_COST_WASTE_HANDLING, amount * fraction_lost * 0.5)

/datum/material_batch/proc/record_recovery(value)
	if(value > 0)
		record_cost(MATERIAL_COST_RECOVERY, value)

/datum/material_batch/proc/usable_output()
	return max(0.01, amount * yield_fraction)

/datum/material_batch/proc/total_production_cost()
	return max(0, (cost_ledger[MATERIAL_COST_FEEDSTOCK] || 0) + (cost_ledger[MATERIAL_COST_CHEMICALS] || 0) + (cost_ledger[MATERIAL_COST_CATALYSTS] || 0) + (cost_ledger[MATERIAL_COST_ELECTRICITY] || 0) + (cost_ledger[MATERIAL_COST_MEDIA] || 0) + (cost_ledger[MATERIAL_COST_LABOR] || 0) + (cost_ledger[MATERIAL_COST_EQUIPMENT] || 0) + (cost_ledger[MATERIAL_COST_WASTE_HANDLING] || 0) - (cost_ledger[MATERIAL_COST_RECOVERY] || 0))

/datum/material_batch/proc/unit_production_cost()
	return total_production_cost() / usable_output()

/datum/material_batch/proc/cost_breakdown()
	var/list/result = cost_ledger.Copy()
	result["total"] = total_production_cost()
	result["usable_output"] = usable_output()
	result["per_sheet"] = unit_production_cost()
	return result

/datum/material_batch/proc/can_process(process)
	if(!length(composition))
		return FALSE
	switch(process)
		if(MATERIAL_PROCESS_MELT)
			return phase != MATERIAL_PHASE_MOLTEN && temperature >= melting_temperature()
		if(MATERIAL_PROCESS_CAST)
			return phase == MATERIAL_PHASE_MOLTEN
		if(MATERIAL_PROCESS_QUENCH)
			return phase == MATERIAL_PHASE_SOLID && solution_treated && temperature >= melting_temperature() * 0.62
		if(MATERIAL_PROCESS_FORGE)
			return phase == MATERIAL_PHASE_SOLID && temperature >= melting_temperature() * 0.45 && temperature <= melting_temperature() * 0.9 && (process_counts[MATERIAL_PROCESS_FORGE] || 0) < 2
		if(MATERIAL_PROCESS_HOMOGENIZE)
			return phase == MATERIAL_PHASE_MOLTEN
		if(MATERIAL_PROCESS_SOLUTION_TREAT)
			return phase == MATERIAL_PHASE_SOLID && temperature >= melting_temperature() * 0.62 && temperature <= melting_temperature() * 0.9
		if(MATERIAL_PROCESS_PURIFY)
			return TRUE
	return FALSE

/datum/material_batch/proc/recalculate()
	if(!length(composition) || amount <= 0)
		return
	var/base_hardness = 0
	var/base_toughness = 0
	var/base_conductivity = 0
	var/base_heat = 0
	var/base_corrosion = 0
	var/hardener = 0
	var/stabilizer = 0
	var/reinforcement = 0
	for(var/material_name in composition)
		var/datum/material/material = get_material_by_name(material_name)
		if(!material)
			continue
		var/share = composition[material_name] / amount
		var/material_heat = max(material.heat_resistance, clamp((material.melting_point - 500) / 60, 10, 100))
		var/material_corrosion = max(material.corrosion_resistance, clamp(58 - material.reactivity * 0.4, 10, 85))
		base_hardness += max(material.hardness, 20) * share
		base_toughness += max(material.integrity + material.elasticity * 0.35, 20) * share
		base_conductivity += max(material.conductivity, 5) * share
		base_heat += material_heat * share
		base_corrosion += material_corrosion * share
		hardener += max(material.hardness - 45, 0) * share
		stabilizer += max(material_heat + material_corrosion - 90, 0) * share
		if(material.fracture_toughness >= 60 || (material.hardness >= 55 && material.brittleness >= 25))
			reinforcement += share * 100
	var/carbon_units = additive_units_matching("carbon")
	var/silicon_units = additive_units_matching("silicon")
	var/flux_units = additive_units_matching("flux")
	var/conductive_dopant = additive_units_matching("conductive dopant")
	var/thermal_catalyst = additive_units_matching("thermal phase")
	var/corrosion_inhibitor = additive_units_matching("corrosion inhibitor")
	var/grain_refiner = additive_units_matching("grain refiner")
	var/nitrogen_infusion = (dissolved_gases["nitrogen"] || 0) / max(amount, 1)
	var/hydrogen_infusion = (dissolved_gases["hydrogen"] || 0) / max(amount, 1)
	var/oxygen_infusion = (dissolved_gases["oxygen"] || 0) / max(amount, 1)
	var/phoron_infusion = (dissolved_gases["phoron"] || 0) / max(amount, 1)
	var/carbon_case = surface_layers[MATERIAL_SURFACE_CARBON] || 0
	var/effective_porosity = max(0, porosity - min(flux_units, 8))
	var/carbon_window = max(0, 18 - abs(carbon_units - 6) * 3)
	var/silicon_window = max(0, 14 - abs(silicon_units - 4) * 2)
	structure[MATERIAL_STRUCTURE_REINFORCEMENT] = clamp(max(structure[MATERIAL_STRUCTURE_REINFORCEMENT], reinforcement * 0.45), 0, 100)
	var/quality = purity * 0.55 + homogeneity * 0.45
	var/hardened_fraction = structure[MATERIAL_STRUCTURE_HARDENED] / 100
	var/effective_precipitate = clamp(structure[MATERIAL_STRUCTURE_PRECIPITATE] + round((carbon_window + silicon_window) / 4), 0, 100)
	var/precipitate_fraction = effective_precipitate / 100
	var/defect_fraction = structure[MATERIAL_STRUCTURE_DEFECT] / 100
	hardness = clamp(round(base_hardness * (0.62 + quality / 280) + hardened_fraction * (30 + hardener * 0.25) + precipitate_fraction * 18 + carbon_window + grain_refiner + nitrogen_infusion * 0.3 + carbon_case * 0.16 - grain_size * 0.08), 1, 100)
	brittleness = clamp(round((100 - base_toughness) * 0.28 + internal_stress * 0.38 + effective_porosity * 0.28 + defect_fraction * 35 + max(carbon_units - 10, 0) * 3 + hydrogen_infusion * 0.18 + oxygen_infusion * 0.2), 0, 100)
	toughness = clamp(round(base_toughness * (0.62 + quality / 300) + structure[MATERIAL_STRUCTURE_SOFT] * 0.14 + precipitate_fraction * 12 + grain_refiner * 0.5 - brittleness * 0.3), 1, 100)
	conductivity = clamp(round(base_conductivity * (0.55 + purity / 180) - effective_porosity * 0.12 + conductive_dopant * 3), 0, 100)
	heat_resistance = clamp(round(base_heat * (0.65 + purity / 260) + stabilizer * 0.15 + silicon_window * 0.4 + thermal_catalyst * 2 + phoron_infusion * 0.25), 1, 100)
	corrosion_resistance = clamp(round(base_corrosion * (0.6 + purity / 240) + stabilizer * 0.12 - oxidation * 0.25 + surface_protection + corrosion_inhibitor * 3 - oxygen_infusion * 0.12), 1, 100)

/datum/material_batch/proc/additive_units_matching(fragment)
	var/total = 0
	for(var/additive in impurities)
		if(findtext(lowertext(additive), lowertext(fragment)))
			total += impurities[additive]
	return total / max(amount, 1)

/datum/material_batch/proc/functional_roles()
	var/list/roles = list("matrix" = TRUE)
	for(var/material_name in composition)
		var/datum/material/material = get_material_by_name(material_name)
		if(!material)
			continue
		if(material.hardness >= 60)
			roles["hardener"] = TRUE
		if(material.conductivity >= 40)
			roles["conductive phase"] = TRUE
		if(max(material.heat_resistance, (material.melting_point - 500) / 60) >= 55)
			roles["thermal stabilizer"] = TRUE
		if(max(material.corrosion_resistance, 58 - material.reactivity * 0.4) >= 55)
			roles["corrosion inhibitor"] = TRUE
		if(material.fracture_toughness >= 60 || (material.hardness >= 55 && material.brittleness >= 25))
			roles["reinforcement"] = TRUE
	for(var/additive in impurities)
		var/lower_additive = lowertext(additive)
		if(findtext(lower_additive, "carbon"))
			roles["interstitial hardener"] = TRUE
		if(findtext(lower_additive, "silicon"))
			roles["deoxidizer"] = TRUE
		if(findtext(lower_additive, "flux"))
			roles["flux"] = TRUE
		if(findtext(lower_additive, "catalyst") || findtext(lower_additive, "stabilizer"))
			roles["phase catalyst"] = TRUE
	return roles

/datum/material_batch/proc/normalize_structure()
	var/total = 0
	for(var/structure_name in structure)
		structure[structure_name] = max(0, structure[structure_name])
		total += structure[structure_name]
	if(total <= 0)
		structure[MATERIAL_STRUCTURE_SOFT] = 100
		return
	for(var/structure_name in structure)
		structure[structure_name] = round(structure[structure_name] * 100 / total)

/datum/material_batch/proc/melting_temperature()
	var/weighted = 0
	for(var/material_name in composition)
		var/datum/material/material = get_material_by_name(material_name)
		if(material)
			weighted += material.melting_point * (composition[material_name] / max(amount, 1))
	return max(round(weighted), 500)

/datum/material_batch/proc/hazard_score()
	var/reactivity = 0
	for(var/material_name in composition)
		var/datum/material/material = get_material_by_name(material_name)
		if(material)
			reactivity += material.reactivity * composition[material_name] / max(amount, 1)
	var/thermal_fraction = temperature / max(melting_temperature(), 1)
	var/atmosphere_risk = atmosphere == MATERIAL_ATMOSPHERE_AIR ? 22 : (atmosphere == MATERIAL_ATMOSPHERE_REDUCING ? 10 : -10)
	return clamp(round(reactivity * 0.45 + thermal_fraction * 35 + atmosphere_risk + oxidation * 0.3), 0, 100)

/datum/material_batch/proc/fingerprint()
	var/list/parts = list()
	var/quantity = max(amount, 0.01)
	for(var/material_name in sortList(composition.Copy()))
		parts += "[material_name]=[round(composition[material_name] / quantity, 0.001)]"
	for(var/impurity in sortList(impurities.Copy()))
		parts += "+[impurity]=[round(impurities[impurity] / quantity, 0.001)]"
	for(var/layer_name in sortList(surface_layers.Copy()))
		parts += "l[layer_name]=[surface_layers[layer_name]]"
	for(var/gas_name in sortList(dissolved_gases.Copy()))
		parts += "g[gas_name]=[round(dissolved_gases[gas_name] / quantity, 0.001)]"
	for(var/treatment_name in sortList(field_treatments.Copy()))
		parts += "t[treatment_name]=[field_treatments[treatment_name]]"
	for(var/structure_name in sortList(structure.Copy()))
		parts += "#[structure_name]=[structure[structure_name]]"
	parts += "p[purity]g[grain_size]s[internal_stress]o[porosity]h[homogeneity]a[atmosphere]x[oxidation]"
	return md5(jointext(parts, ";"))

/datum/material_batch/proc/display_name()
	var/list/names = list()
	for(var/material_name in composition)
		names += material_display_name(material_name) || material_name
		if(length(names) >= 3)
			break
	return "[jointext(names, "-")] processed alloy"

/datum/material_batch/proc/evidence_context(process)
	return list(
		"department" = DEPARTMENT_RESEARCH,
		"process" = process,
		"fingerprint" = fingerprint(),
		"purity" = purity,
		"hardness" = hardness,
		"toughness" = toughness,
		"brittleness" = brittleness,
		"conductivity" = conductivity,
		"heat_resistance" = heat_resistance,
		"corrosion_resistance" = corrosion_resistance,
		"composition_count" = length(composition),
		"amount" = max(1, round(amount * yield_fraction)),
		"yield" = round(yield_fraction * 100),
		"energy_cost" = round(cost_ledger[MATERIAL_COST_ELECTRICITY], 0.01),
		"production_cost" = round(total_production_cost(), 0.01),
		"unit_cost" = round(unit_production_cost(), 0.01),
		"waste_value" = round(cost_ledger[MATERIAL_COST_WASTE], 0.01),
		"recovery_value" = round(cost_ledger[MATERIAL_COST_RECOVERY], 0.01),
		"defect_fraction" = structure[MATERIAL_STRUCTURE_DEFECT],
		"oxidation" = oxidation,
	)

/datum/material_batch/proc/copy_batch()
	var/datum/material_batch/copy = new
	copy.composition = composition.Copy()
	copy.impurities = impurities.Copy()
	copy.process_history = LAZYCOPY(process_history)
	copy.contributors = contributors.Copy()
	copy.feedstock_lots = feedstock_lots.Copy()
	copy.test_results = LAZYCOPY(test_results)
	copy.process_counts = process_counts.Copy()
	copy.surface_layers = surface_layers.Copy()
	copy.dissolved_gases = dissolved_gases.Copy()
	copy.field_treatments = field_treatments.Copy()
	copy.cost_ledger = cost_ledger.Copy()
	copy.structure = structure.Copy()
	copy.amount = amount
	copy.phase = phase
	copy.temperature = temperature
	copy.purity = purity
	copy.grain_size = grain_size
	copy.internal_stress = internal_stress
	copy.porosity = porosity
	copy.homogeneity = homogeneity
	copy.atmosphere = atmosphere
	copy.quench_medium = quench_medium
	copy.solution_treated = solution_treated
	copy.yield_fraction = yield_fraction
	copy.energy_spent = energy_spent
	copy.oxidation = oxidation
	copy.cost_basis = cost_basis
	copy.surface_protection = surface_protection
	copy.recalculate()
	return copy

/// Preserve intensive properties while dividing quantity, provenance, energy,
/// reagents, and expense with a physical piece of stock.
/datum/material_batch/proc/copy_for_amount(new_amount)
	var/datum/material_batch/copy = copy_batch()
	var/ratio = max(0, new_amount / max(amount, 0.01))
	copy.amount = new_amount
	for(var/material_name in copy.composition)
		copy.composition[material_name] *= ratio
	for(var/impurity in copy.impurities)
		copy.impurities[impurity] *= ratio
	for(var/lot_id in copy.feedstock_lots)
		copy.feedstock_lots[lot_id] *= ratio
	for(var/account_number in copy.contributors)
		copy.contributors[account_number] *= ratio
	for(var/gas_name in copy.dissolved_gases)
		copy.dissolved_gases[gas_name] *= ratio
	for(var/category in copy.cost_ledger)
		copy.cost_ledger[category] *= ratio
	copy.cost_basis *= ratio
	copy.energy_spent *= ratio
	return copy

/datum/material_batch/proc/thermal_capacity()
	var/weighted_specific_heat = 0
	for(var/material_name in composition)
		var/datum/material/material = get_material_by_name(material_name)
		if(material)
			weighted_specific_heat += max(material.specific_heat, 100) * composition[material_name] / max(amount, 1)
	return max(1, amount * weighted_specific_heat / 160)

/datum/material_batch/proc/add_thermal_energy(joules)
	if(!isnum(joules) || !joules)
		return 0
	var/old_temperature = temperature
	temperature = max(2.7, temperature + joules / thermal_capacity())
	return temperature - old_temperature
