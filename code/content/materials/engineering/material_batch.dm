/// Canonical state for a physical batch. Recipes do not select an alloy: player inputs and
/// processing history produce one, and all consumers derive their properties from this datum.
///
/// A batch is three things (doc/material_engineering_implementation.md):
///   composition  real substances with amounts, bulk materials and traces alike (wanted carbon in steel is just composition);
///   temper       how hard it has been worked or quenched, 0 soft to 100 hard (annealing brings it back down);
///   flaws        one number, 0 flawless to 100 ruined (porosity, stress, defects, poor mixing, all folded into it).
/// Its card (strength, toughness, heat resistance, conductivity, corrosion resistance, weight) and traits are computed from
/// those three plus its surface layers and field treatments, and recalculate() keeps the steps behind every number.
/datum/material_batch
	/// Substance id -> amount, in sheets. A bulk material (a registered /datum/material) counts toward `amount`; a trace substance
	/// (sulfur, dissolved hydrogen, a reagent residue) does not, and its share is its amount over `amount`.
	var/list/composition
	var/list/process_history
	var/list/contributors = list() // ALLOW(instance_list): d: batch provenance, filled when the batch is made
	var/list/process_counts
	/// Persistent physical surface treatments. These are layers, not bulk ingredients.
	var/list/surface_layers
	/// High-energy or field treatments applied to the lattice.
	var/list/field_treatments
	var/list/cost_ledger = list( // ALLOW(instance_list): d: edited in place per instance (6 writers)
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
	/// Sheets of bulk material.
	var/amount = 0
	var/phase = MATERIAL_PHASE_SOLID
	/// The batch's temperature while it holds no heat store (at rest, at its surroundings), K.
	var/rest_temperature = T20C
	/// The Rust heat store (code/domains/heat/heat_store.dm) holding the batch's heat while it differs from its surroundings, or null.
	var/heat_store
	/// The heat links its store makes to where it cools (edge ids), and the "x,y,z" of the turf they were made for.
	var/list/heat_links
	var/heat_linked_at
	/// 0 soft to 100 hard. Hard stock is stronger and less tough; annealing softens it again.
	var/temper = MATERIAL_TEMPER_DEFAULT
	/// 0 flawless to 100 ruined: the one number for porosity, locked-in stress, defects and poor mixing.
	var/flaws = MATERIAL_FLAWS_DEFAULT
	/// Held at solution-treatment heat and not yet quenched; left to cool, it anneals instead.
	var/solution_treated = FALSE
	var/energy_spent = 0
	var/cost_basis = 0
	// The card, computed by recalculate().
	var/strength = 0
	var/toughness = 0
	var/conductivity = 0
	var/heat_resistance = 0
	var/corrosion_resistance = 0
	var/weight = 0
	/// Trait id -> strength, computed by recalculate().
	var/list/traits
	/// Card stat or trait id -> list of list(label, delta) behind the number, starting with "base" (computed by recalculate()).
	var/list/stat_notes

/// Sheets of a reagent's worth of substance: one unit of a reagent poured into a melt is this many sheets of it.
#define MATERIAL_SHEETS_PER_REAGENT_UNIT 0.05
/// A batch's merge identity buckets its temper to this many points.
#define MATERIAL_TEMPER_MERGE_BUCKET 5

/datum/material_batch/proc/add_material(material_name, sheets = 1, datum/money_account/producer)
	var/datum/material/material = get_material_by_name(material_name)
	if(!material || sheets <= 0)
		return FALSE
	LAZYSET(composition, material.name, (LAZYACCESS(composition, material.name) || 0) + sheets)
	amount += sheets
	var/feedstock_cost = max(material.supply_conversion_value, 0.1) * sheets
	cost_basis += feedstock_cost
	record_cost(MATERIAL_COST_FEEDSTOCK, feedstock_cost)
	if(producer)
		contributors[producer.account_number] = (contributors[producer.account_number] || 0) + sheets
	recalculate()
	return TRUE

/// Adds `sheets` of a substance that is not counted as bulk: a trace (sulfur, dissolved hydrogen, a reagent residue). A substance that is
/// a registered material goes through add_material() instead.
/datum/material_batch/proc/add_substance(substance_id, sheets, unit_cost = 1, cost_category = MATERIAL_COST_CHEMICALS)
	if(!substance_id || sheets <= 0)
		return FALSE
	LAZYSET(composition, substance_id, (LAZYACCESS(composition, substance_id) || 0) + sheets)
	LAZYADD(process_history, "alloyed with [round(sheets, 0.01)] sheets of [substance_id]")
	var/substance_cost = max(unit_cost, 0) * sheets / MATERIAL_SHEETS_PER_REAGENT_UNIT
	cost_basis += substance_cost
	record_cost(cost_category, substance_cost)
	material_log("[REF(src)] +[round(sheets, 0.001)] [substance_id] (composition now [json_encode(composition)])")
	recalculate()
	return TRUE

/// Removes a substance entirely (an acid wash, a degassing); returns how much it removed, in sheets.
/datum/material_batch/proc/remove_substance(substance_id)
	var/removed = LAZYACCESS(composition, substance_id) || 0
	if(removed <= 0)
		return 0
	LAZYREMOVE(composition, substance_id)
	material_log("[REF(src)] -[round(removed, 0.001)] [substance_id]")
	return removed

/// An acid wash (`leaching`) dissolves every substance that `leaches` out of the batch, to nothing; a hard vacuum (not leaching) degasses what `degasses` down to its floor.
/datum/material_batch/proc/strip_traces(leaching)
	if(!leaching)
		return refine_traces(MATERIAL_REFINE_DEGAS)
	var/removed_total = 0
	for(var/id in LAZYCOPY(composition))
		var/datum/material_trace/trace = GLOB.material_traces[id]
		if(!trace || get_material_by_name(id))
			continue
		if(trace.leaches)
			removed_total += remove_substance(id)
	return removed_total

/// Takes every trace the method acts on down to its floor (a percent of the batch, per trace type: a method never takes a trace to nothing, and a trace already below
/// the floor is left). Returns the sheets taken out. The shared processes of the chemistry are the methods: reduce smelts, oxidise roasts, displace fluxes, electrolyse
/// electrorefines, and a vacuum degasses (MATERIAL_REFINE_*, GLOB.material_refine_methods).
/datum/material_batch/proc/refine_traces(method)
	var/removed_total = 0
	if(amount <= 0)
		return removed_total
	for(var/id in LAZYCOPY(composition))
		var/datum/material_trace/trace = GLOB.material_traces[id]
		if(!trace || get_material_by_name(id))
			continue
		var/floor_percent = trace.floors?[method]
		if(isnull(floor_percent))
			continue
		var/have = LAZYACCESS(composition, id)
		var/keep = floor_percent * amount / 100
		if(have <= keep)
			continue
		LAZYSET(composition, id, keep)
		removed_total += have - keep
		material_log("[REF(src)] [method] takes [id] from [round(have * 100 / amount, 0.001)]% to [round(floor_percent, 0.001)]% of the batch")
	if(removed_total > 0)
		recalculate()
	return removed_total

/// Refines the melt with a shared chemistry process (CHEM_PROCESS_REDUCE, _OXIDISE, _DISPLACE or _ELECTROLYSE): returns the sheets of traces it took out, or FALSE when
/// the process is not a refining one. A cleaner melt is also a less flawed one.
/datum/material_batch/proc/refine_by_process(process_id)
	var/method = GLOB.material_refine_methods[process_id]
	if(!method)
		return FALSE
	var/removed = refine_traces(method)
	refine(min(8, round(removed * 40)))
	LAZYADD(process_history, "[method] ([process_id])")
	LAZYSET(process_counts, method, (LAZYACCESS(process_counts, method) || 0) + 1)
	material_log("[REF(src)] refined by [process_id] ([method]): [round(removed, 0.001)] sheets of traces out, flaws [flaws]")
	return removed

/datum/material_batch/proc/add_surface_layer(layer_name, strength, additive_name, additive_units = 0)
	if(!layer_name || strength <= 0)
		return FALSE
	LAZYSET(surface_layers, layer_name, clamp((LAZYACCESS(surface_layers, layer_name) || 0) + strength, 0, 100))
	LAZYADD(process_history, "applied [layer_name]")
	recalculate()
	return TRUE

/datum/material_batch/proc/add_field_treatment(treatment_name, strength)
	if(!treatment_name || strength <= 0)
		return FALSE
	LAZYSET(field_treatments, treatment_name, clamp((LAZYACCESS(field_treatments, treatment_name) || 0) + strength, 0, 100))
	LAZYADD(process_history, treatment_name)
	recalculate()
	return TRUE

/// Fewer flaws (a cleaner melt, a forging, a beam): `amount` points, never below 0.
/datum/material_batch/proc/refine(points)
	flaws = clamp(flaws - points, 0, 100)

/datum/material_batch/proc/apply_process(process, option)
	if(!length(composition))
		return FALSE
	if(!can_process(process))
		return FALSE
	switch(process)
		if(MATERIAL_PROCESS_MELT)
			if(temperature() < melting_temperature())
				return FALSE
			phase = MATERIAL_PHASE_MOLTEN
			flaws = clamp(flaws + 4, 0, 100)
		if(MATERIAL_PROCESS_CAST)
			if(phase != MATERIAL_PHASE_MOLTEN)
				return FALSE
			phase = MATERIAL_PHASE_SOLID
			bring_to_temperature(T20C + 80, HEAT_SOURCE_MATERIAL) // the mould takes the casting's heat
			flaws = clamp(flaws + 12, 0, 100)
			temper = MATERIAL_TEMPER_DEFAULT
			solution_treated = FALSE
		if(MATERIAL_PROCESS_QUENCH)
			if(phase != MATERIAL_PHASE_SOLID || !solution_treated || temperature() < melting_temperature() * 0.62)
				return FALSE
			bring_to_temperature(T20C, HEAT_SOURCE_MATERIAL) // the quench bath takes the heat
			var/quench_strength = option == "oil" ? 45 : (option == "cryo" ? 75 : 60)
			temper = clamp(temper + quench_strength, 0, 100)
			flaws = clamp(flaws + (option == "oil" ? 5 : (option == "cryo" ? 10 : 8)), 0, 100)
			solution_treated = FALSE
		if(MATERIAL_PROCESS_FORGE)
			if(phase != MATERIAL_PHASE_SOLID || temperature() < melting_temperature() * 0.45 || temperature() > melting_temperature() * 0.9)
				return FALSE
			refine(15)
			temper = clamp(temper + 8, 0, 100)
		if(MATERIAL_PROCESS_PURIFY)
			var/removed_contamination = strip_traces(TRUE)
			refine(6 + min(10, round(removed_contamination * 20)))
		if(MATERIAL_PROCESS_HOMOGENIZE)
			if(phase != MATERIAL_PHASE_MOLTEN)
				return FALSE
			refine(10)
		if(MATERIAL_PROCESS_SOLUTION_TREAT)
			if(phase != MATERIAL_PHASE_SOLID || temperature() < melting_temperature() * 0.62 || temperature() > melting_temperature() * 0.9)
				return FALSE
			solution_treated = TRUE
			temper = clamp(temper - 15, 0, 100)
		if(MATERIAL_PROCESS_ANNEAL)
			if(phase != MATERIAL_PHASE_SOLID || !solution_treated)
				return FALSE
			temper = round(temper * 0.2)
			refine(12)
			solution_treated = FALSE
		else
			return FALSE
	LAZYADD(process_history, option ? "[process] ([option])" : process)
	LAZYSET(process_counts, process, (LAZYACCESS(process_counts, process) || 0) + 1)
	material_log("[REF(src)] [process][option ? " ([option])" : ""]: temper [temper], flaws [flaws]")
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

/datum/material_batch/proc/record_recovery(value)
	if(value > 0)
		record_cost(MATERIAL_COST_RECOVERY, value)

/datum/material_batch/proc/usable_output()
	return max(0.01, amount)

/datum/material_batch/proc/total_production_cost()
	return max(0, (cost_ledger[MATERIAL_COST_FEEDSTOCK] || 0) + (cost_ledger[MATERIAL_COST_CHEMICALS] || 0) + (cost_ledger[MATERIAL_COST_CATALYSTS] || 0) + (cost_ledger[MATERIAL_COST_ELECTRICITY] || 0) + (cost_ledger[MATERIAL_COST_MEDIA] || 0) + (cost_ledger[MATERIAL_COST_LABOR] || 0) + (cost_ledger[MATERIAL_COST_EQUIPMENT] || 0) + (cost_ledger[MATERIAL_COST_WASTE_HANDLING] || 0) - (cost_ledger[MATERIAL_COST_RECOVERY] || 0))

/datum/material_batch/proc/unit_production_cost()
	return total_production_cost() / usable_output()

/datum/material_batch/proc/can_process(process)
	if(!length(composition))
		return FALSE
	switch(process)
		if(MATERIAL_PROCESS_MELT)
			return phase != MATERIAL_PHASE_MOLTEN && temperature() >= melting_temperature()
		if(MATERIAL_PROCESS_CAST)
			return phase == MATERIAL_PHASE_MOLTEN
		if(MATERIAL_PROCESS_QUENCH)
			return phase == MATERIAL_PHASE_SOLID && solution_treated && temperature() >= melting_temperature() * 0.62
		if(MATERIAL_PROCESS_FORGE)
			return phase == MATERIAL_PHASE_SOLID && temperature() >= melting_temperature() * 0.45 && temperature() <= melting_temperature() * 0.9 && (LAZYACCESS(process_counts, MATERIAL_PROCESS_FORGE) || 0) < 2
		if(MATERIAL_PROCESS_HOMOGENIZE)
			return phase == MATERIAL_PHASE_MOLTEN
		if(MATERIAL_PROCESS_SOLUTION_TREAT)
			return phase == MATERIAL_PHASE_SOLID && temperature() >= melting_temperature() * 0.62 && temperature() <= melting_temperature() * 0.9
		if(MATERIAL_PROCESS_ANNEAL)
			return phase == MATERIAL_PHASE_SOLID && solution_treated
		if(MATERIAL_PROCESS_PURIFY)
			return TRUE
	return FALSE

/// Share (0-1) of the batch's bulk that is substance `id`.
/datum/material_batch/proc/share_of(id)
	return amount > 0 ? (LAZYACCESS(composition, id) || 0) / amount : 0

/// The recalculation. Each card stat is the composition's weighted base, then flaws, temper, treatments and traces, each a
/// delta kept in stat_notes so the number can be explained ("Toughness 62: base 70, sulfur -12, tempered +4").
/datum/material_batch/proc/recalculate()
	if(!length(composition) || amount <= 0)
		return
	var/base_strength = 0
	var/base_toughness = 0
	var/base_conductivity = 0
	var/base_heat = 0
	var/base_corrosion = 0
	var/base_weight = 0
	for(var/material_name in composition)
		var/datum/material/material = get_material_by_name(material_name)
		if(!material)
			continue
		var/share = LAZYACCESS(composition, material_name) / amount
		base_strength += material.strength * share
		base_toughness += material.toughness * share
		base_conductivity += material.conductivity * share
		base_heat += material.heat_resistance * share
		base_corrosion += material.corrosion_resistance * share
		base_weight += material.weight * share
	var/quality = 100 - flaws
	var/flaw_factor = 0.6 + quality * 0.004
	var/temper_shift = temper - MATERIAL_TEMPER_DEFAULT
	var/carbon_case = LAZYACCESS(surface_layers, MATERIAL_SURFACE_CARBON) || 0
	var/metal_skin = LAZYACCESS(surface_layers, MATERIAL_SURFACE_SLIME_METAL) || 0
	var/corrosion_skin = LAZYACCESS(surface_layers, MATERIAL_SURFACE_SLIME_CORROSION) || 0
	var/radiation_hardened = LAZYACCESS(field_treatments, MATERIAL_FIELD_RADIATION_HARDENED) || 0
	var/list/trace_deltas = trace_stat_deltas()
	stat_notes = list()
	strength = compose_stat(MATERIAL_STAT_STRENGTH, base_strength, flaw_factor, list("tempered" = temper_shift * 0.25, "carbon case" = carbon_case * 0.16, "metal skin" = metal_skin * 0.2, "radiation hardening" = radiation_hardened * 0.1), trace_deltas, 1, 100)
	toughness = compose_stat(MATERIAL_STAT_TOUGHNESS, base_toughness, flaw_factor, list("tempered" = -temper_shift * 0.15, "metal skin" = metal_skin * 0.4, "radiation hardening" = -max(0, radiation_hardened - 60) * 0.25), trace_deltas, 1, 100)
	conductivity = compose_stat(MATERIAL_STAT_CONDUCTIVITY, base_conductivity, flaw_factor, null, trace_deltas, 0, 100)
	var/nichrome = share_of(MAT_NICKEL) >= 0.15 && share_of(MAT_CHROMIUM) >= 0.15 ? max(0, 70 + share_of(MAT_TUNGSTEN) * 30 - base_heat) : 0
	heat_resistance = compose_stat(MATERIAL_STAT_HEAT_RESISTANCE, base_heat, flaw_factor, list("nickel-chromium" = nichrome, "radiation hardening" = radiation_hardened * 0.2), trace_deltas, 1, 120)
	corrosion_resistance = compose_stat(MATERIAL_STAT_CORROSION_RESISTANCE, base_corrosion, flaw_factor, list("corrosion skin" = corrosion_skin * 0.6), trace_deltas, 1, 100)
	weight = clamp(round(max(base_weight, strength * 0.35 + toughness * 0.25)), 1, 120)
	LAZYSET(stat_notes, MATERIAL_STAT_WEIGHT, list(list("base", weight)))
	compute_traits(quality, trace_deltas)
	heat_capacity_changed()

/// Stat or trait id -> list of list(substance label, delta) the traces in the composition make, per the trace table.
/datum/material_batch/proc/trace_stat_deltas()
	var/list/result
	if(amount <= 0)
		return result
	for(var/id in composition)
		var/datum/material_trace/trace = GLOB.material_traces[id]
		if(!trace)
			continue
		var/percent = LAZYACCESS(composition, id) * 100 / amount
		var/list/effects = trace.effect_at(percent)
		for(var/target in effects)
			var/list/rows = LAZYACCESS(result, target)
			if(!rows)
				rows = list()
				LAZYSET(result, target, rows)
			rows += list(list(trace.label, effects[target]))
	return result

/// One card stat's value and its breakdown: `base`, flaws, `extra` (label -> delta), then the traces' rows. The stat is the rounded sum, clamped.
/datum/material_batch/proc/compose_stat(stat, base, flaw_factor, list/extra, list/trace_rows, low, high)
	var/list/notes = list(list("base", round(base)))
	var/total = round(base)
	var/flaw_delta = round(base * (flaw_factor - 1))
	if(flaw_delta)
		notes += list(list("flaws", flaw_delta))
		total += flaw_delta
	for(var/label in extra)
		var/delta = round(extra[label])
		if(delta)
			notes += list(list(label, delta))
			total += delta
	for(var/list/row as anything in LAZYACCESS(trace_rows, stat))
		var/delta = round(row[2])
		if(delta)
			notes += list(list(row[1], delta))
			total += delta
	var/clamped = clamp(total, low, high)
	if(clamped != total)
		notes += list(list("limit", clamped - total))
	LAZYSET(stat_notes, stat, notes)
	return clamped

/// Sets trait `id` from its gated base strength, then the traces' effects on it; a trait with no strength is absent.
/datum/material_batch/proc/set_trait_strength(id, base, list/trace_rows)
	var/list/notes = list(list("base", round(base)))
	var/total = round(base)
	for(var/list/row as anything in LAZYACCESS(trace_rows, id))
		var/delta = round(row[2])
		if(delta)
			notes += list(list(row[1], delta))
			total += delta
	total = clamp(total, 0, 100)
	if(total <= 0)
		LAZYREMOVE(traits, id)
		LAZYREMOVE(stat_notes, id)
		return
	LAZYSET(traits, id, total)
	LAZYSET(stat_notes, id, notes)

/// The batch's traits: each needs its ingredients and treatments (as the old coefficients did), and its strength is one number.
/datum/material_batch/proc/compute_traits(quality, list/trace_rows)
	traits = null
	var/cryo_skin = LAZYACCESS(surface_layers, MATERIAL_SURFACE_SLIME_CRYO) || 0
	var/thermal_skin = LAZYACCESS(surface_layers, MATERIAL_SURFACE_SLIME_THERMAL) || 0
	var/bluespace_skin = LAZYACCESS(surface_layers, MATERIAL_SURFACE_SLIME_BLUESPACE) || 0
	var/particle_conditioned = LAZYACCESS(field_treatments, MATERIAL_FIELD_PARTICLE) || 0
	var/emitter_charged = LAZYACCESS(field_treatments, MATERIAL_FIELD_EMITTER) || 0
	var/fusion_stabilized = LAZYACCESS(field_treatments, MATERIAL_FIELD_FUSION) || 0
	var/energy_storage = LAZYACCESS(field_treatments, MATERIAL_FIELD_ENERGY_STORAGE) || 0
	var/metal_hydrogen_share = share_of(MAT_METALHYDROGEN)
	var/nickel_share = share_of(MAT_NICKEL)
	var/copper_share = share_of(MAT_COPPER)
	var/titanium_share = share_of(MAT_TITANIUM)
	var/tungsten_share = share_of(MAT_TUNGSTEN)
	var/ceramic_share = share_of(MAT_TECH_CERAMIC)
	var/phoron_share = share_of(MAT_PHORON) + share_of("phoron gas")
	var/crystal_share = share_of(MAT_QUARTZ) + share_of(MAT_DIAMOND) + share_of(MAT_GLASS) + share_of(MAT_VOLTAIC_CRYSTAL) + share_of(MAT_KINETIC_CRYSTAL) + share_of(MAT_LUMEN_CRYSTAL) + share_of(MAT_RIFT_GLASS)
	var/biological_share = share_of(MAT_BIOMASS) + share_of(MAT_FLESH) + share_of(MAT_CHITIN) + share_of(MAT_ALIENCHITIN) + share_of(MAT_SPORE_BIOMASS)
	var/has_crystal = crystal_share >= 0.1
	var/has_biological = biological_share >= 0.15
	var/radioactive_share = share_of(MAT_URANIUM) + share_of(MAT_TRITIUM)
	var/hardened = temper >= 50
	// Emissions follow the components in proportion, as before.
	var/luminescent = 0
	var/radioactive = 0
	var/toxic = 0
	for(var/component in composition)
		var/datum/material/component_material = get_material_by_name(component)
		if(!component_material)
			continue
		var/share = LAZYACCESS(composition, component) / amount
		luminescent += component_material.trait(MT_LUMINESCENT) * share
		radioactive += component_material.trait(MT_RADIOACTIVE) * share
		toxic += component_material.trait(MT_TOXIC) * share
	set_trait_strength(MT_LUMINESCENT, luminescent, trace_rows)
	set_trait_strength(MT_RADIOACTIVE, radioactive, trace_rows)
	set_trait_strength(MT_TOXIC, toxic * (1 - corrosion_resistance / 200), trace_rows)
	// Superconducting: metal hydrogen (or a cryogenic stabiliser under a cryogenic skin) in a clean, very conductive batch.
	if((metal_hydrogen_share >= 0.15 || (share_of(REAGENT_ID_FROSTOIL) > 0 && cryo_skin)) && conductivity >= 75 && quality >= 60)
		set_trait_strength(MT_SUPERCONDUCTING, (conductivity + quality) / 2 - 15 + cryo_skin * 0.2 + (metal_hydrogen_share >= 0.15 ? fusion_stabilized * 0.17 : 0), trace_rows)
	else
		set_trait_strength(MT_SUPERCONDUCTING, 0, trace_rows)
	set_trait_strength(MT_THERMAL_BUFFER, max(thermal_skin * 1.8, share_of(MAT_THERMIC_CERAMIC) * 65 * quality / 100), trace_rows)
	set_trait_strength(MT_CRYO_BUFFER, cryo_skin * 1.8, trace_rows)
	var/catalytic = 0
	if(LAZYACCESS(surface_layers, MATERIAL_SURFACE_SLIME_CATALYTIC) || share_of(MAT_PLATINUM) >= 0.1)
		catalytic = quality * 0.7 + corrosion_resistance * 0.3
	if(share_of(MAT_ETCHING_CERAMIC) > 0)
		catalytic = max(catalytic, quality * corrosion_resistance / 100)
	set_trait_strength(MT_CATALYTIC, catalytic, trace_rows)
	// Thermoelectric covers the generator and the heat pump: one coupling of heat and charge.
	var/thermoelectric = 0
	if((nickel_share >= 0.15 && copper_share >= 0.15) || (share_of(REAGENT_ID_COOLANT) > 0 && thermal_skin && conductivity >= 45))
		thermoelectric = (conductivity + heat_resistance) / 2
	if((ceramic_share >= 0.2 && conductivity >= 25 && particle_conditioned >= 25) || (copper_share >= 0.2 && nickel_share >= 0.15 && fusion_stabilized >= 25))
		thermoelectric = max(thermoelectric, clamp((particle_conditioned + fusion_stabilized + quality) / 2.5, 10, 100))
	set_trait_strength(MT_THERMOELECTRIC, thermoelectric, trace_rows)
	var/piezo = 0
	if(has_crystal && conductivity >= 30 && quality >= 70)
		piezo = (conductivity + quality - flaws * 0.5) / 2
	if(share_of(MAT_KINETIC_CRYSTAL) > 0)
		piezo = max(piezo, 68 * share_of(MAT_KINETIC_CRYSTAL) * quality / 100)
	set_trait_strength(MT_PIEZOELECTRIC, piezo, trace_rows)
	// Field storage covers the stored deposit and the slow trickle: charge a lattice holds and gives back.
	var/field_storage = 0
	if(has_crystal && conductivity >= 35 && (particle_conditioned >= 20 || emitter_charged >= 20))
		field_storage = clamp((energy_storage + particle_conditioned + emitter_charged) * quality * 8 / 1000, 1, 100)
	if(share_of(REAGENT_ID_LITHIUM) > 0 && LAZYACCESS(surface_layers, MATERIAL_SURFACE_SLIME_CONDUCTIVE) && conductivity >= 40 && quality >= 60)
		field_storage = max(field_storage, (conductivity + quality) / 2)
	set_trait_strength(MT_FIELD_STORAGE, field_storage, trace_rows)
	var/radiovoltaic = 0
	var/radioactive_strength = LAZYACCESS(traits, MT_RADIOACTIVE) || 0
	if(radioactive_share >= 0.1 && conductivity >= 35 && particle_conditioned >= 20)
		radiovoltaic = (conductivity + radioactive_strength) / 2
	if(radioactive_share >= 0.1 && has_crystal && quality >= 65 && particle_conditioned >= 20)
		radiovoltaic = max(radiovoltaic, quality / 2 + 20)
	if(share_of(MAT_LUMEN_CRYSTAL) >= 0.15 && quality >= 60)
		radiovoltaic = max(radiovoltaic, quality * 0.9)
	set_trait_strength(MT_RADIOVOLTAIC, radiovoltaic, trace_rows)
	var/exothermic = 0
	if(phoron_share >= 0.08 && tungsten_share >= 0.15 && fusion_stabilized >= 20)
		exothermic = clamp(phoron_share * fusion_stabilized * 18, 25, 500) / 5
	set_trait_strength(MT_EXOTHERMIC, exothermic, trace_rows)
	var/thermal_switch = 0
	if(copper_share >= 0.2 && nickel_share >= 0.15 && fusion_stabilized >= 35)
		thermal_switch = clamp(fusion_stabilized, 40, 100)
	set_trait_strength(MT_THERMAL_SWITCH, thermal_switch, trace_rows)
	var/shape_memory = 0
	if((share_of(MAT_MORPHIUM) >= 0.15 || (nickel_share >= 0.2 && titanium_share >= 0.2) || (titanium_share >= 0.25 && hardened)) && toughness >= 28)
		shape_memory = (toughness + quality - 30) / 2
	set_trait_strength(MT_SHAPE_MEMORY, shape_memory, trace_rows)
	var/reactive = 0
	if(share_of(MAT_WARD_METAL) >= 0.15 || (share_of(MAT_PLASTEEL) >= 0.25 && hardened))
		reactive = (toughness + strength) / 2
	set_trait_strength(MT_REACTIVE, reactive, trace_rows)
	var/antimicrobial = 0
	if((share_of(MAT_SILVER) >= 0.1) && corrosion_resistance >= 50)
		antimicrobial = (corrosion_resistance + quality) / 2
	set_trait_strength(MT_ANTIMICROBIAL, antimicrobial, trace_rows)
	var/hemostatic = 0
	if(has_biological && share_of(MAT_IRON) > 0)
		hemostatic = quality
	if(has_biological && share_of(MAT_MORPHIUM) > 0)
		hemostatic = max(hemostatic, (toughness + quality) / 2)
	set_trait_strength(MT_HEMOSTATIC, hemostatic, trace_rows)
	var/sorbent = 0
	if(flaws >= 25 && (share_of(MAT_TITANIUM) > 0 || share_of(MAT_ALUMINIUM) > 0 || share_of(MAT_GRAPHITE) > 0))
		sorbent = flaws * 0.8 + corrosion_resistance / 5
	sorbent = max(sorbent, bluespace_skin * 2)
	if(share_of(MAT_RIFT_GLASS) >= 0.15)
		sorbent = max(sorbent, flaws + quality / 2)
	set_trait_strength(MT_SORBENT, sorbent, trace_rows)

/// The kinds of batch that merge: the same bulk materials in the same proportions, the same temper bucket and the same treatments.
/// Traces and flaws are not part of it; they average when the two merge.
/datum/material_batch/proc/identity()
	var/list/parts = list()
	var/quantity = max(amount, 0.01)
	for(var/material_name in sortList(LAZYCOPY(composition)))
		if(get_material_by_name(material_name))
			parts += "[material_name]=[round(LAZYACCESS(composition, material_name) / quantity, 0.01)]"
	for(var/layer_name in sortList(LAZYCOPY(surface_layers)))
		parts += "l[layer_name]=[LAZYACCESS(surface_layers, layer_name)]"
	for(var/treatment_name in sortList(LAZYCOPY(field_treatments)))
		parts += "t[treatment_name]=[LAZYACCESS(field_treatments, treatment_name)]"
	parts += "T[round(temper / MATERIAL_TEMPER_MERGE_BUCKET)]s[solution_treated]p[phase]"
	return md5(jointext(parts, ";"))

/// The bulk materials in the composition, material name -> sheets (traces left out).
/datum/material_batch/proc/bulk_composition()
	var/list/result = list()
	for(var/id in composition)
		if(get_material_by_name(id))
			result[id] = round(composition[id], 0.01)
	return result

/// What a spectrometer would read: the trace substances and their amounts, so two batches with the same traces compare equal.
/datum/material_batch/proc/trace_signature()
	var/list/parts = list()
	var/quantity = max(amount, 0.01)
	for(var/id in sortList(LAZYCOPY(composition)))
		if(!get_material_by_name(id))
			parts += "[id]=[round(LAZYACCESS(composition, id) / quantity, 0.001)]"
	return jointext(parts, ";")

/// Takes a portion of stock into this batch, like pouring one beaker of solid into another: amounts add (so traces average by amount),
/// flaws and temper average by amount, the heat mixes. The portion's costs and provenance come with it.
/datum/material_batch/proc/absorb(datum/material_batch/portion)
	var/total = amount + portion.amount
	if(total > 0)
		flaws = round((flaws * amount + portion.flaws * portion.amount) / total)
		temper = round((temper * amount + portion.temper * portion.amount) / total)
	amount = total
	for(var/substance in portion.composition)
		LAZYSET(composition, substance, (LAZYACCESS(composition, substance) || 0) + LAZYACCESS(portion.composition, substance))
	for(var/account_number in portion.contributors)
		contributors[account_number] = (contributors[account_number] || 0) + portion.contributors[account_number]
	for(var/category in portion.cost_ledger)
		cost_ledger[category] = (cost_ledger[category] || 0) + portion.cost_ledger[category]
	cost_basis += portion.cost_basis
	energy_spent += portion.energy_spent
	if(abs(temperature() - portion.temperature()) > 0.01)
		heat_equalize(HEAT_STORE(ensure_heat_store()), HEAT_STORE(portion.ensure_heat_store()))
	recalculate()

/datum/material_batch/proc/melting_temperature()
	var/weighted = 0
	for(var/material_name in composition)
		var/datum/material/material = get_material_by_name(material_name)
		if(material)
			weighted += material.melting_point() * (LAZYACCESS(composition, material_name) / max(amount, 1))
	return max(round(weighted), 500)

/datum/material_batch/proc/fingerprint()
	var/list/parts = list()
	var/quantity = max(amount, 0.01)
	for(var/substance in sortList(LAZYCOPY(composition)))
		parts += "[substance]=[round(LAZYACCESS(composition, substance) / quantity, 0.001)]"
	for(var/layer_name in sortList(LAZYCOPY(surface_layers)))
		parts += "l[layer_name]=[LAZYACCESS(surface_layers, layer_name)]"
	for(var/treatment_name in sortList(LAZYCOPY(field_treatments)))
		parts += "t[treatment_name]=[LAZYACCESS(field_treatments, treatment_name)]"
	parts += "T[temper]f[flaws]s[solution_treated]"
	return md5(jointext(parts, ";"))

/datum/material_batch/proc/display_name()
	var/list/names = list()
	for(var/material_name in composition)
		var/datum/material/material = get_material_by_name(material_name)
		if(!material)
			continue
		names += material.display_name || material_name
		if(length(names) >= 3)
			break
	return "[jointext(names, "-")] processed alloy"

/datum/material_batch/proc/evidence_context(process)
	return list(
		"department" = DEPARTMENT_RESEARCH,
		"process" = process,
		"fingerprint" = fingerprint(),
		"quality" = 100 - flaws,
		"strength" = strength,
		"toughness" = toughness,
		"brittleness" = clamp(strength - toughness, 0, 100),
		"conductivity" = conductivity,
		"heat_resistance" = heat_resistance,
		"corrosion_resistance" = corrosion_resistance,
		"composition_count" = length(composition),
		"amount" = max(1, round(amount)),
		"energy_cost" = round(cost_ledger[MATERIAL_COST_ELECTRICITY], 0.01),
		"production_cost" = round(total_production_cost(), 0.01),
		"unit_cost" = round(unit_production_cost(), 0.01),
		"waste_value" = round(cost_ledger[MATERIAL_COST_WASTE], 0.01),
		"recovery_value" = round(cost_ledger[MATERIAL_COST_RECOVERY], 0.01),
		"flaws" = flaws,
	)

/datum/material_batch/proc/copy_batch()
	var/datum/material_batch/copy = new
	copy.composition = LAZYCOPY(composition)
	copy.process_history = LAZYCOPY(process_history)
	copy.contributors = contributors.Copy()
	copy.process_counts = LAZYCOPY(process_counts)
	copy.surface_layers = LAZYCOPY(surface_layers)
	copy.field_treatments = LAZYCOPY(field_treatments)
	copy.cost_ledger = cost_ledger.Copy()
	copy.amount = amount
	copy.phase = phase
	copy.rest_temperature = temperature()
	if(heat_store)
		copy.heat_store = heat_store_create(copy.thermal_capacity(), copy.rest_temperature) // its share of the heat: the original is replaced by its copies
	copy.temper = temper
	copy.flaws = flaws
	copy.solution_treated = solution_treated
	copy.energy_spent = energy_spent
	copy.cost_basis = cost_basis
	copy.recalculate()
	return copy

/// Preserve intensive properties while dividing quantity, provenance, energy,
/// reagents, and expense with a physical piece of stock.
/datum/material_batch/proc/copy_for_amount(new_amount)
	var/datum/material_batch/copy = copy_batch()
	var/ratio = max(0, new_amount / max(amount, 0.01))
	copy.amount = new_amount
	for(var/substance in copy.composition)
		copy.composition[substance] *= ratio
	for(var/account_number in copy.contributors)
		copy.contributors[account_number] *= ratio
	for(var/category in copy.cost_ledger)
		copy.cost_ledger[category] *= ratio
	copy.cost_basis *= ratio
	copy.energy_spent *= ratio
	copy.heat_capacity_changed()
	return copy

/datum/material_batch/proc/thermal_capacity()
	var/weighted_specific_heat = 0
	for(var/material_name in composition)
		var/datum/material/material = get_material_by_name(material_name)
		if(material)
			weighted_specific_heat += max(material.specific_heat(), 100) * LAZYACCESS(composition, material_name) / max(amount, 1)
	return max(1, amount * weighted_specific_heat / 160)

/datum/material_batch/proc/add_batch_heat(joules, source = HEAT_SOURCE_MATERIAL)
	if(!isnum(joules) || !joules)
		return 0
	var/old_temperature = temperature()
	heat_store_add(ensure_heat_store(), joules, source)
	return temperature() - old_temperature

/// A batch's temperature, K.
/proc/material_batch_temperature(datum/material_batch/batch)
	return batch.temperature()

/// Sets a batch's temperature (a spawn, a test), booked as an authority write.
/proc/material_batch_set_temperature(datum/material_batch/batch, kelvin)
	batch.bring_to_temperature(kelvin)

// ---- heat (doc/rewrite/temperature.md §7) ----
// A batch away from its surroundings holds its heat in a Rust heat store (code/domains/heat/heat_store.dm); at rest it holds none and reads its
// rest temperature. Processed stock lying in a room cools through a heat link to the room's air (processed_material.dm).

/datum/material_batch/proc/temperature()
	return heat_store ? heat_store_temperature(heat_store, rest_temperature) : rest_temperature

/// Brings the batch to `kelvin`, booked under `source` (a process step's bath or mould takes the difference).
/datum/material_batch/proc/bring_to_temperature(kelvin, source = HEAT_SOURCE_AUTHORITY)
	if(!isnum(kelvin) || !heat_store && kelvin == rest_temperature)
		return
	heat_store_set_temperature(ensure_heat_store(), kelvin, source)

/// The batch's heat store, made at its rest temperature on first use.
/datum/material_batch/proc/ensure_heat_store()
	if(!heat_store)
		heat_store = heat_store_create(thermal_capacity(), rest_temperature)
	return heat_store

/// Keeps the store's capacity with the batch's quantity and composition (the temperature is kept, as it always was).
/datum/material_batch/proc/heat_capacity_changed()
	if(heat_store)
		heat_store_set_capacity(heat_store, thermal_capacity())

/// Cools into `air` (a turf's) through a heat link at `conductance` W/K, re-made when the turf changes.
/datum/material_batch/proc/cool_into(turf/T, conductance)
	var/key = T ? "[T.x],[T.y],[T.z]" : null
	if(key == heat_linked_at && length(heat_links))
		return
	drop_heat_links()
	if(!T || !ensure_heat_store())
		return
	heat_linked_at = key
	var/id = heat_store_link(heat_store, T, conductance)
	if(id)
		LAZYADD(heat_links, id)

/datum/material_batch/proc/drop_heat_links()
	for(var/id in heat_links)
		heat_edge_drop(id)
	heat_links = null
	heat_linked_at = null

/// At its surroundings' temperature: the batch gives what it still holds over `into`'s temperature to it and lets its store go.
/datum/material_batch/proc/settle_heat(into)
	if(!heat_store)
		return
	if(into)
		heat_equalize(HEAT_STORE(heat_store), into)
	rest_temperature = temperature()
	drop_heat_links()
	heat_store_drop(heat_store)
	heat_store = null

/datum/material_batch/on_destroy(force)
	drop_heat_links()
	if(heat_store)
		heat_store_drop(heat_store)
		heat_store = null
	return ..()
SCHEMA(/datum/material_batch, rest_temperature, num())
