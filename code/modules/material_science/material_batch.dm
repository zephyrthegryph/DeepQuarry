/// Canonical state for a physical batch. Recipes do not select an alloy: player inputs and
/// processing history produce one, and all consumers derive their properties from this datum.
/datum/material_batch
	var/list/composition = list()
	var/list/impurities = list()
	var/list/process_history = list()
	var/list/contributors = list()
	var/amount = 0
	var/phase = MATERIAL_PHASE_SOLID
	var/temperature = T20C
	var/purity = 90
	var/grain_size = 50
	var/internal_stress = 15
	var/porosity = 10
	var/homogeneity = 75
	var/form = "stock"
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
	return ..()

/datum/material_batch/proc/add_material(material_name, sheets = 1, datum/money_account/producer)
	var/datum/material/material = get_material_by_name(material_name)
	if(!material || sheets <= 0)
		return FALSE
	composition[material.name] = (composition[material.name] || 0) + sheets
	amount += sheets
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
	recalculate()
	return TRUE

/datum/material_batch/proc/apply_process(process, option)
	if(!length(composition))
		return FALSE
	switch(process)
		if(MATERIAL_PROCESS_MELT)
			phase = MATERIAL_PHASE_MOLTEN
			temperature = max(temperature, melting_temperature() + 100)
			homogeneity = clamp(homogeneity + 18, 0, 100)
			porosity = clamp(porosity + 4, 0, 100)
		if(MATERIAL_PROCESS_CAST)
			if(phase != MATERIAL_PHASE_MOLTEN)
				return FALSE
			phase = MATERIAL_PHASE_SOLID
			temperature = T20C + 80
			grain_size = 72
			internal_stress = 28
			porosity = clamp(porosity + 8, 0, 100)
			form = option || "billet"
		if(MATERIAL_PROCESS_ANNEAL)
			phase = MATERIAL_PHASE_SOLID
			grain_size = clamp(grain_size + 16, 5, 100)
			internal_stress = clamp(internal_stress - 35, 0, 100)
			brittleness = clamp(brittleness - 10, 0, 100)
		if(MATERIAL_PROCESS_QUENCH)
			phase = MATERIAL_PHASE_SOLID
			grain_size = clamp(grain_size - 28, 1, 100)
			internal_stress = clamp(internal_stress + (option == "oil" ? 18 : 30), 0, 100)
			porosity = clamp(porosity - 4, 0, 100)
			temperature = T20C
		if(MATERIAL_PROCESS_TEMPER)
			internal_stress = clamp(internal_stress - 24, 0, 100)
			grain_size = clamp(grain_size + 5, 1, 100)
		if(MATERIAL_PROCESS_SINTER)
			phase = MATERIAL_PHASE_SOLID
			porosity = clamp(porosity - 28, 0, 100)
			homogeneity = clamp(homogeneity + 10, 0, 100)
			form = "sintered stock"
		if(MATERIAL_PROCESS_ROLL)
			porosity = clamp(porosity - 16, 0, 100)
			internal_stress = clamp(internal_stress + 12, 0, 100)
			form = "sheet"
		if(MATERIAL_PROCESS_FORGE)
			porosity = clamp(porosity - 22, 0, 100)
			grain_size = clamp(grain_size - 8, 1, 100)
			homogeneity = clamp(homogeneity + 8, 0, 100)
			form = "forged billet"
		if(MATERIAL_PROCESS_DRAW)
			internal_stress = clamp(internal_stress + 20, 0, 100)
			form = "wire stock"
		if(MATERIAL_PROCESS_PURIFY, MATERIAL_PROCESS_ELECTROLYZE)
			purity = clamp(purity + (process == MATERIAL_PROCESS_ELECTROLYZE ? 18 : 10), 0, 100)
			impurities.Cut()
			homogeneity = clamp(homogeneity + 12, 0, 100)
			phase = process == MATERIAL_PROCESS_ELECTROLYZE ? MATERIAL_PHASE_SOLUTION : phase
		if(MATERIAL_PROCESS_CRYSTALLIZE)
			phase = MATERIAL_PHASE_SOLID
			grain_size = 35
			porosity = clamp(porosity - 12, 0, 100)
			form = "crystalline stock"
		else
			return FALSE
	process_history += option ? "[process] ([option])" : process
	recalculate()
	emit_contract_event(CONTRACT_EVENT_MATERIAL_PROCESSED, evidence_context(process))
	return TRUE

/datum/material_batch/proc/recalculate()
	if(!length(composition) || amount <= 0)
		return
	var/base_hardness = 0
	var/base_toughness = 0
	var/base_conductivity = 0
	var/base_heat = 0
	var/base_corrosion = 0
	for(var/material_name in composition)
		var/datum/material/material = get_material_by_name(material_name)
		if(!material)
			continue
		var/share = composition[material_name] / amount
		base_hardness += max(material.hardness, 20) * share
		base_toughness += max(material.integrity + material.elasticity * 0.35, 20) * share
		base_conductivity += max(material.conductivity, 5) * share
		base_heat += max(material.heat_resistance, 10) * share
		base_corrosion += max(material.corrosion_resistance, 10) * share
	var/quality = purity * 0.55 + homogeneity * 0.45
	hardness = clamp(round(base_hardness * (0.72 + quality / 250) + (50 - grain_size) * 0.22), 1, 100)
	brittleness = clamp(round((100 - base_toughness) * 0.35 + internal_stress * 0.45 + porosity * 0.3), 0, 100)
	toughness = clamp(round(base_toughness * (0.65 + quality / 300) - brittleness * 0.25), 1, 100)
	conductivity = clamp(round(base_conductivity * (0.55 + purity / 180) - porosity * 0.12), 0, 100)
	heat_resistance = clamp(round(base_heat * (0.65 + purity / 260)), 1, 100)
	corrosion_resistance = clamp(round(base_corrosion * (0.6 + purity / 240)), 1, 100)

/datum/material_batch/proc/melting_temperature()
	var/weighted = 0
	for(var/material_name in composition)
		var/datum/material/material = get_material_by_name(material_name)
		if(material)
			weighted += material.melting_point * (composition[material_name] / max(amount, 1))
	return max(round(weighted), 500)

/datum/material_batch/proc/fingerprint()
	var/list/parts = list()
	for(var/material_name in sortList(composition.Copy()))
		parts += "[material_name]=[round(composition[material_name], 0.01)]"
	for(var/impurity in sortList(impurities.Copy()))
		parts += "+[impurity]=[round(impurities[impurity], 0.01)]"
	parts += "p[purity]g[grain_size]s[internal_stress]o[porosity]h[homogeneity]f[form]"
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
		"conductivity" = conductivity,
		"heat_resistance" = heat_resistance,
		"corrosion_resistance" = corrosion_resistance,
		"composition_count" = length(composition),
		"amount" = amount,
	)

/datum/material_batch/proc/copy_batch()
	var/datum/material_batch/copy = new
	copy.composition = composition.Copy()
	copy.impurities = impurities.Copy()
	copy.process_history = process_history.Copy()
	copy.contributors = contributors.Copy()
	copy.amount = amount
	copy.phase = phase
	copy.temperature = temperature
	copy.purity = purity
	copy.grain_size = grain_size
	copy.internal_stress = internal_stress
	copy.porosity = porosity
	copy.homogeneity = homogeneity
	copy.form = form
	if(infused_substance)
		copy.infused_substance = infused_substance.Clone()
	copy.recalculate()
	return copy
