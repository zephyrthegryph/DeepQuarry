/// Canonical state for a physical batch. Recipes do not select an alloy: player inputs and
/// processing history produce one, and all consumers derive their properties from this datum.
/datum/material_batch
	var/list/composition = list()
	var/list/impurities = list()
	var/list/process_history = list()
	var/list/contributors = list()
	var/list/feedstock_lots = list()
	var/list/test_results = list()
	var/list/process_counts = list()
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
	var/form = "stock"
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
	var/datum/substance/infused_substance

/datum/material_batch/Destroy()
	QDEL_NULL(infused_substance)
	composition = null
	impurities = null
	process_history = null
	contributors = null
	feedstock_lots = null
	test_results = null
	process_counts = null
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
	cost_basis += max(material.supply_conversion_value, 1) * sheets
	if(producer)
		contributors[producer.account_number] = (contributors[producer.account_number] || 0) + sheets
	if(istype(material, /datum/material/substance))
		var/datum/material/substance/substance_material = material
		if(!infused_substance && substance_material.infused_substance)
			infused_substance = substance_material.infused_substance.Clone()
	recalculate()
	return TRUE

/datum/material_batch/proc/add_additive(additive_name, units)
	if(!additive_name || units <= 0)
		return FALSE
	impurities[additive_name] = (impurities[additive_name] || 0) + units
	purity = clamp(purity - round(units * 0.4), 20, 100)
	homogeneity = clamp(homogeneity - round(units * 0.2), 0, 100)
	process_history += "alloyed with [units]u [additive_name]"
	cost_basis += units
	recalculate()
	return TRUE

/datum/material_batch/proc/apply_process(process, option)
	if(!length(composition))
		return FALSE
	if(!can_process(process))
		return FALSE
	switch(process)
		if(MATERIAL_PROCESS_HEAT)
			var/heat_step = text2num(option) || 400
			temperature = clamp(temperature + heat_step, T20C, melting_temperature() + 800)
			energy_spent += round(heat_step * max(amount, 1) / 25)
			if(atmosphere == MATERIAL_ATMOSPHERE_AIR && temperature > melting_temperature() * 0.55)
				oxidation = clamp(oxidation + 3, 0, 100)
				yield_fraction = clamp(yield_fraction - 0.01, 0.5, 1)
			else if(atmosphere == MATERIAL_ATMOSPHERE_REDUCING)
				oxidation = clamp(oxidation - 2, 0, 100)
		if(MATERIAL_PROCESS_COOL)
			if(phase == MATERIAL_PHASE_MOLTEN)
				return FALSE
			temperature = max(T20C, temperature - (text2num(option) || 300))
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
			form = option || "billet"
			structure[MATERIAL_STRUCTURE_SOFT] = 65
			structure[MATERIAL_STRUCTURE_AMORPHOUS] = 10
			structure[MATERIAL_STRUCTURE_DEFECT] = 25
			solution_treated = FALSE
		if(MATERIAL_PROCESS_ANNEAL)
			if(phase != MATERIAL_PHASE_SOLID || temperature < melting_temperature() * 0.4 || temperature > melting_temperature() * 0.75)
				return FALSE
			phase = MATERIAL_PHASE_SOLID
			grain_size = clamp(grain_size + 16, 5, 100)
			internal_stress = clamp(internal_stress - 35, 0, 100)
			brittleness = clamp(brittleness - 10, 0, 100)
			structure[MATERIAL_STRUCTURE_SOFT] = clamp(structure[MATERIAL_STRUCTURE_SOFT] + 24, 0, 100)
			structure[MATERIAL_STRUCTURE_HARDENED] = clamp(structure[MATERIAL_STRUCTURE_HARDENED] - 18, 0, 100)
			structure[MATERIAL_STRUCTURE_DEFECT] = clamp(structure[MATERIAL_STRUCTURE_DEFECT] - 8, 0, 100)
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
		if(MATERIAL_PROCESS_TEMPER)
			if(phase != MATERIAL_PHASE_SOLID || structure[MATERIAL_STRUCTURE_HARDENED] < 15 || temperature < melting_temperature() * 0.18 || temperature > melting_temperature() * 0.48)
				return FALSE
			internal_stress = clamp(internal_stress - 24, 0, 100)
			grain_size = clamp(grain_size + 5, 1, 100)
			structure[MATERIAL_STRUCTURE_HARDENED] = clamp(structure[MATERIAL_STRUCTURE_HARDENED] - 10, 0, 100)
			structure[MATERIAL_STRUCTURE_PRECIPITATE] = clamp(structure[MATERIAL_STRUCTURE_PRECIPITATE] + 12, 0, 100)
			structure[MATERIAL_STRUCTURE_DEFECT] = clamp(structure[MATERIAL_STRUCTURE_DEFECT] - 12, 0, 100)
		if(MATERIAL_PROCESS_SINTER)
			if(phase != MATERIAL_PHASE_POWDER && form != "powder")
				return FALSE
			phase = MATERIAL_PHASE_SOLID
			porosity = clamp(porosity - 28, 0, 100)
			homogeneity = clamp(homogeneity + 10, 0, 100)
			form = "sintered stock"
			structure[MATERIAL_STRUCTURE_REINFORCEMENT] = clamp(structure[MATERIAL_STRUCTURE_REINFORCEMENT] + 18, 0, 100)
		if(MATERIAL_PROCESS_ROLL)
			if(phase != MATERIAL_PHASE_SOLID || temperature > melting_temperature() * 0.8)
				return FALSE
			porosity = clamp(porosity - 16, 0, 100)
			internal_stress = clamp(internal_stress + 12, 0, 100)
			form = "sheet"
		if(MATERIAL_PROCESS_FORGE)
			if(phase != MATERIAL_PHASE_SOLID || temperature < melting_temperature() * 0.45 || temperature > melting_temperature() * 0.9)
				return FALSE
			porosity = clamp(porosity - 22, 0, 100)
			grain_size = clamp(grain_size - 8, 1, 100)
			homogeneity = clamp(homogeneity + 8, 0, 100)
			form = "forged billet"
			structure[MATERIAL_STRUCTURE_DEFECT] = clamp(structure[MATERIAL_STRUCTURE_DEFECT] - 14, 0, 100)
		if(MATERIAL_PROCESS_DRAW)
			if(phase != MATERIAL_PHASE_SOLID || form != "sheet")
				return FALSE
			internal_stress = clamp(internal_stress + 20, 0, 100)
			form = "wire stock"
		if(MATERIAL_PROCESS_PURIFY, MATERIAL_PROCESS_ELECTROLYZE)
			if(process == MATERIAL_PROCESS_ELECTROLYZE && phase != MATERIAL_PHASE_SOLUTION)
				return FALSE
			purity = clamp(purity + (process == MATERIAL_PROCESS_ELECTROLYZE ? 18 : 10), 0, 100)
			impurities.Cut()
			homogeneity = clamp(homogeneity + 12, 0, 100)
			structure[MATERIAL_STRUCTURE_DEFECT] = clamp(structure[MATERIAL_STRUCTURE_DEFECT] - 10, 0, 100)
		if(MATERIAL_PROCESS_DISSOLVE)
			if(phase != MATERIAL_PHASE_SOLID)
				return FALSE
			phase = MATERIAL_PHASE_SOLUTION
			temperature = max(temperature, T20C + 80)
			homogeneity = clamp(homogeneity + 8, 0, 100)
		if(MATERIAL_PROCESS_PULVERIZE)
			if(phase != MATERIAL_PHASE_SOLID)
				return FALSE
			phase = MATERIAL_PHASE_POWDER
			form = "powder"
			porosity = clamp(porosity + 18, 0, 100)
		if(MATERIAL_PROCESS_PLATE)
			if(phase != MATERIAL_PHASE_SOLUTION)
				return FALSE
			phase = MATERIAL_PHASE_SOLID
			form = "electroplated laminate"
			surface_protection = clamp(surface_protection + 15, 0, 30)
			yield_fraction = clamp(yield_fraction - 0.06, 0.5, 1)
		if(MATERIAL_PROCESS_CRYSTALLIZE)
			if(phase != MATERIAL_PHASE_SOLUTION && phase != MATERIAL_PHASE_MOLTEN)
				return FALSE
			phase = MATERIAL_PHASE_SOLID
			grain_size = 35
			porosity = clamp(porosity - 12, 0, 100)
			form = "crystalline stock"
			structure[MATERIAL_STRUCTURE_AMORPHOUS] = 5
			structure[MATERIAL_STRUCTURE_PRECIPITATE] = clamp(structure[MATERIAL_STRUCTURE_PRECIPITATE] + 25, 0, 100)
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
	process_history += option ? "[process] ([option])" : process
	process_counts[process] = (process_counts[process] || 0) + 1
	normalize_structure()
	recalculate()
	emit_contract_event(CONTRACT_EVENT_MATERIAL_PROCESSED, evidence_context(process))
	return TRUE

/datum/material_batch/proc/can_process(process)
	if(!length(composition))
		return FALSE
	if(!(process in list(MATERIAL_PROCESS_HEAT, MATERIAL_PROCESS_COOL)) && (process_counts[process] || 0) >= 2)
		return FALSE
	switch(process)
		if(MATERIAL_PROCESS_HEAT)
			return temperature < melting_temperature() + 800
		if(MATERIAL_PROCESS_COOL)
			return phase != MATERIAL_PHASE_MOLTEN && temperature > T20C
		if(MATERIAL_PROCESS_MELT)
			return phase != MATERIAL_PHASE_MOLTEN && temperature >= melting_temperature()
		if(MATERIAL_PROCESS_CAST)
			return phase == MATERIAL_PHASE_MOLTEN
		if(MATERIAL_PROCESS_ANNEAL)
			return phase == MATERIAL_PHASE_SOLID && temperature >= melting_temperature() * 0.4 && temperature <= melting_temperature() * 0.75
		if(MATERIAL_PROCESS_QUENCH)
			return phase == MATERIAL_PHASE_SOLID && solution_treated && temperature >= melting_temperature() * 0.62
		if(MATERIAL_PROCESS_TEMPER)
			return phase == MATERIAL_PHASE_SOLID && structure[MATERIAL_STRUCTURE_HARDENED] >= 15 && temperature >= melting_temperature() * 0.18 && temperature <= melting_temperature() * 0.48
		if(MATERIAL_PROCESS_SINTER)
			return phase == MATERIAL_PHASE_POWDER || form == "powder"
		if(MATERIAL_PROCESS_ROLL)
			return phase == MATERIAL_PHASE_SOLID && temperature <= melting_temperature() * 0.8
		if(MATERIAL_PROCESS_FORGE)
			return phase == MATERIAL_PHASE_SOLID && temperature >= melting_temperature() * 0.45 && temperature <= melting_temperature() * 0.9
		if(MATERIAL_PROCESS_DRAW)
			return phase == MATERIAL_PHASE_SOLID && form == "sheet"
		if(MATERIAL_PROCESS_ELECTROLYZE, MATERIAL_PROCESS_PLATE)
			return phase == MATERIAL_PHASE_SOLUTION
		if(MATERIAL_PROCESS_CRYSTALLIZE)
			return phase == MATERIAL_PHASE_SOLUTION || phase == MATERIAL_PHASE_MOLTEN
		if(MATERIAL_PROCESS_HOMOGENIZE)
			return phase == MATERIAL_PHASE_MOLTEN
		if(MATERIAL_PROCESS_SOLUTION_TREAT)
			return phase == MATERIAL_PHASE_SOLID && temperature >= melting_temperature() * 0.62 && temperature <= melting_temperature() * 0.9
		if(MATERIAL_PROCESS_DISSOLVE, MATERIAL_PROCESS_PULVERIZE)
			return phase == MATERIAL_PHASE_SOLID
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
		if(material.material_class == MATCLASS_CERAMIC || material.material_class == MATCLASS_CRYSTAL)
			reinforcement += share * 100
	var/carbon_units = additive_units_matching("carbon")
	var/silicon_units = additive_units_matching("silicon")
	var/flux_units = additive_units_matching("flux")
	var/conductive_dopant = additive_units_matching("conductive dopant")
	var/thermal_catalyst = additive_units_matching("thermal phase")
	var/corrosion_inhibitor = additive_units_matching("corrosion inhibitor")
	var/grain_refiner = additive_units_matching("grain refiner")
	var/effective_porosity = max(0, porosity - min(flux_units, 8))
	var/carbon_window = max(0, 18 - abs(carbon_units - 6) * 3)
	var/silicon_window = max(0, 14 - abs(silicon_units - 4) * 2)
	structure[MATERIAL_STRUCTURE_REINFORCEMENT] = clamp(max(structure[MATERIAL_STRUCTURE_REINFORCEMENT], reinforcement * 0.45), 0, 100)
	var/quality = purity * 0.55 + homogeneity * 0.45
	var/hardened_fraction = structure[MATERIAL_STRUCTURE_HARDENED] / 100
	var/effective_precipitate = clamp(structure[MATERIAL_STRUCTURE_PRECIPITATE] + round((carbon_window + silicon_window) / 4), 0, 100)
	var/precipitate_fraction = effective_precipitate / 100
	var/defect_fraction = structure[MATERIAL_STRUCTURE_DEFECT] / 100
	hardness = clamp(round(base_hardness * (0.62 + quality / 280) + hardened_fraction * (30 + hardener * 0.25) + precipitate_fraction * 18 + carbon_window + grain_refiner - grain_size * 0.08), 1, 100)
	brittleness = clamp(round((100 - base_toughness) * 0.28 + internal_stress * 0.38 + effective_porosity * 0.28 + defect_fraction * 35 + max(carbon_units - 10, 0) * 3), 0, 100)
	toughness = clamp(round(base_toughness * (0.62 + quality / 300) + structure[MATERIAL_STRUCTURE_SOFT] * 0.14 + precipitate_fraction * 12 + grain_refiner * 0.5 - brittleness * 0.3), 1, 100)
	conductivity = clamp(round(base_conductivity * (0.55 + purity / 180) - effective_porosity * 0.12 + conductive_dopant * 3), 0, 100)
	heat_resistance = clamp(round(base_heat * (0.65 + purity / 260) + stabilizer * 0.15 + silicon_window * 0.4 + thermal_catalyst * 2), 1, 100)
	corrosion_resistance = clamp(round(base_corrosion * (0.6 + purity / 240) + stabilizer * 0.12 - oxidation * 0.25 + surface_protection + corrosion_inhibitor * 3), 1, 100)

/datum/material_batch/proc/additive_units_matching(fragment)
	var/total = 0
	for(var/additive in impurities)
		if(findtext(lowertext(additive), lowertext(fragment)))
			total += impurities[additive]
	return total

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
		if(material.material_class == MATCLASS_CERAMIC || material.material_class == MATCLASS_CRYSTAL)
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
	for(var/material_name in sortList(composition.Copy()))
		parts += "[material_name]=[round(composition[material_name], 0.01)]"
	for(var/impurity in sortList(impurities.Copy()))
		parts += "+[impurity]=[round(impurities[impurity], 0.01)]"
	for(var/structure_name in sortList(structure.Copy()))
		parts += "#[structure_name]=[structure[structure_name]]"
	parts += "p[purity]g[grain_size]s[internal_stress]o[porosity]h[homogeneity]f[form]a[atmosphere]x[oxidation]"
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
		"energy_cost" = energy_spent,
		"production_cost" = round(cost_basis + energy_spent / 20),
		"defect_fraction" = structure[MATERIAL_STRUCTURE_DEFECT],
		"oxidation" = oxidation,
	)

/datum/material_batch/proc/copy_batch()
	var/datum/material_batch/copy = new
	copy.composition = composition.Copy()
	copy.impurities = impurities.Copy()
	copy.process_history = process_history.Copy()
	copy.contributors = contributors.Copy()
	copy.feedstock_lots = feedstock_lots.Copy()
	copy.test_results = test_results.Copy()
	copy.process_counts = process_counts.Copy()
	copy.structure = structure.Copy()
	copy.amount = amount
	copy.phase = phase
	copy.temperature = temperature
	copy.purity = purity
	copy.grain_size = grain_size
	copy.internal_stress = internal_stress
	copy.porosity = porosity
	copy.homogeneity = homogeneity
	copy.form = form
	copy.atmosphere = atmosphere
	copy.quench_medium = quench_medium
	copy.solution_treated = solution_treated
	copy.yield_fraction = yield_fraction
	copy.energy_spent = energy_spent
	copy.oxidation = oxidation
	copy.cost_basis = cost_basis
	copy.surface_protection = surface_protection
	if(infused_substance)
		copy.infused_substance = infused_substance.Clone()
	copy.recalculate()
	return copy
