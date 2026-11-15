/// Trace effects: what a little of a substance does to a material's card and traits. A batch's composition is real
/// substances with amounts; a substance listed here changes the numbers at low shares (up to its limit, past which it
/// is simply an ingredient). Small on purpose: each substance has one clear effect, and a stat's breakdown names it.
///
/// The vocabulary is one with the chemistry's contaminants: a trace is the same thing as the contaminant reagent it names (`contaminant`), so a ground ore gives the
/// contaminant its vein carries, a contaminant poured into a melt becomes the trace, and a source rolls one list of contaminants for both (trace_sources.dm).

/datum/material_trace
	/// The substance's id: a material name or a reagent id (the composition key).
	var/id
	var/label
	/// What each percent of the batch's mass does: card stat or trait id -> change (negative lowers it).
	var/list/effects
	/// The share, percent, past which more of the substance changes nothing more (it is an alloying ingredient by then).
	var/limit = 5
	/// An acid wash (the purify step) strips it from a batch.
	var/leaches = FALSE
	/// A hot vacuum degasses it.
	var/degasses = FALSE
	/// The contaminant reagent this trace is (the chemistry's name for it), or null for a trace with no contaminant of its own (slag, a gas).
	var/contaminant
	/// Other contaminants that become this trace when they are poured into a melt: contaminant id -> the share of the amount that stays (the rest burns off).
	var/list/absorbs
	/// How far each refining step takes it down: MATERIAL_REFINE_* -> the lowest percent of the batch the step leaves (a step never takes it to nothing).
	var/list/floors

/datum/material_trace/sulfur
	id = "sulfur"
	label = "sulfur"
	effects = list(MATERIAL_STAT_TOUGHNESS = -4) // hot-short: brittle
	leaches = TRUE
	contaminant = REAGENT_ID_CONTAMINANT_SULFUR
	floors = list(MATERIAL_REFINE_ROAST = 0.15)

/datum/material_trace/hydrogen
	id = "hydrogen"
	label = "dissolved hydrogen"
	effects = list(MATERIAL_STAT_TOUGHNESS = -6) // embrittlement
	degasses = TRUE
	contaminant = REAGENT_ID_CONTAMINANT_ACID_RESIDUE
	absorbs = list(REAGENT_ID_CONTAMINANT_HYDROCHLORIC = 0.5)
	floors = list(MATERIAL_REFINE_DEGAS = 0.04)

/datum/material_trace/lead
	id = "lead"
	label = "lead"
	effects = list(MATERIAL_STAT_STRENGTH = -3, MT_TOXIC = 10) // soft, and surgical tools made of it poison
	limit = 4
	contaminant = REAGENT_ID_CONTAMINANT_HEAVY_METAL
	floors = list(MATERIAL_REFINE_ELECTRO = 0.03)

/datum/material_trace/carbon
	id = "carbon"
	label = "carbon"
	effects = list(MATERIAL_STAT_STRENGTH = 4, MATERIAL_STAT_CONDUCTIVITY = -2, MT_SUPERCONDUCTING = -10)
	contaminant = REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE
	// Organic leftovers char to carbon in a melt; a roast burns most of it off again.
	absorbs = list(REAGENT_ID_CONTAMINANT_TAR = 0.6, REAGENT_ID_CONTAMINANT_OILY_RESIDUE = 0.5, REAGENT_ID_CONTAMINANT_PLASTICISER = 0.5, \
		REAGENT_ID_CONTAMINANT_METHANOL = 0.3, REAGENT_ID_CONTAMINANT_BIOLOGICAL = 0.3, REAGENT_ID_CONTAMINANT_NITROSAMINE = 0.3, REAGENT_ID_CONTAMINANT_DIOXIN = 0.3)
	floors = list(MATERIAL_REFINE_ROAST = 0.4)

/datum/material_trace/silicon
	id = "silicon"
	label = "silicon"
	effects = list(MATERIAL_STAT_HEAT_RESISTANCE = 2)
	contaminant = REAGENT_ID_CONTAMINANT_INERT_FILLER
	floors = list(MATERIAL_REFINE_FLUX = 0.25)

/datum/material_trace/oxygen
	id = "oxygen"
	label = "oxide inclusions"
	effects = list(MATERIAL_STAT_CORROSION_RESISTANCE = -3)
	leaches = TRUE
	degasses = TRUE
	contaminant = REAGENT_ID_CONTAMINANT_REACTIVE
	absorbs = list(REAGENT_ID_CONTAMINANT_PEROXIDE = 1)
	floors = list(MATERIAL_REFINE_SMELT = 0.12, MATERIAL_REFINE_DEGAS = 0.3)

/datum/material_trace/lithium
	id = "lithium"
	label = "lithium"
	effects = list(MATERIAL_STAT_CONDUCTIVITY = 3)
	contaminant = REAGENT_ID_CONTAMINANT_BASE_RESIDUE
	floors = list(MATERIAL_REFINE_ELECTRO = 0.08)

/datum/material_trace/phoron_gas
	id = "phoron gas"
	label = "interstitial phoron"
	effects = list(MATERIAL_STAT_HEAT_RESISTANCE = 1.5)


/// Chloride and other salts left in the metal (a flux takes most of it).
/datum/material_trace/salts
	id = "salts"
	label = "chloride inclusions"
	effects = list(MATERIAL_STAT_CORROSION_RESISTANCE = -4)
	contaminant = REAGENT_ID_CONTAMINANT_SALTS
	floors = list(MATERIAL_REFINE_FLUX = 0.2, MATERIAL_REFINE_ELECTRO = 0.1)

/// What a reagent with no trace of its own becomes in a melt: slag. It weakens, and a flux skims it.
/datum/material_trace/slag
	id = "slag"
	label = "slag"
	effects = list(MATERIAL_STAT_STRENGTH = -2, MATERIAL_STAT_TOUGHNESS = -2)
	floors = list(MATERIAL_REFINE_FLUX = 0.1)

/// Substance id -> its /datum/material_trace.
GLOBAL_LIST_INIT(material_traces, build_material_traces())

/proc/build_material_traces()
	var/list/table = list()
	for(var/type in subtypesof(/datum/material_trace))
		var/datum/material_trace/trace = new type
		table[trace.id] = trace
	return table

/// What a substance's share (percent of the batch) changes, as `stat or trait id -> delta`, or null for a substance with no effect.
/datum/material_trace/proc/effect_at(percent)
	var/list/result
	for(var/target in effects)
		LAZYSET(result, target, effects[target] * min(percent, limit))
	return result

/// The substances a spectrometer reads off a composition: those that are not the batch's bulk materials, plus any bulk
/// material present in a trace-effect row below its limit. Returns id -> percent of the batch.
/proc/material_trace_shares(list/composition, bulk_amount)
	var/list/result
	if(bulk_amount <= 0)
		return result
	for(var/id in composition)
		var/percent = composition[id] * 100 / bulk_amount
		if(percent <= 0.005)
			continue
		if(GLOB.material_traces[id])
			LAZYSET(result, id, percent)
		else if(!get_material_by_name(id))
			LAZYSET(result, id, percent)
	return result

/// "sulfur 0.8% (toughness -3)" lines for a share list.
/proc/material_trace_lines(list/shares)
	var/list/lines = list()
	for(var/id in shares)
		var/datum/material_trace/trace = GLOB.material_traces[id]
		var/percent = shares[id]
		var/list/effects = trace?.effect_at(percent)
		var/list/effect_text = list()
		for(var/target in effects)
			var/delta = effects[target]
			if(abs(delta) >= 0.5)
				effect_text += "[target] [delta > 0 ? "+" : ""][round(delta)]"
		lines += "[trace ? trace.label : id] [round(percent, 0.1)]%[length(effect_text) ? " ([jointext(effect_text, ", ")])" : ""]"
	return lines

/// One audit line for a batch's composition or process change (game log).
/proc/material_log(text)
	log_game("material: [text]")

// ---- the vocabulary: contaminant reagent <-> material trace ----

/// A reagent that boils below this (K) is a vapour in a melt: it leaves instead of staying as a residue.
#define MELT_VAPOUR_POINT 1300

/// Contaminant reagent id -> the trace id that is it.
/proc/build_material_trace_of_contaminant()
	var/list/table = list()
	for(var/trace_id in GLOB.material_traces)
		var/datum/material_trace/trace = GLOB.material_traces[trace_id]
		if(trace.contaminant)
			table[trace.contaminant] = trace.id
	return table

GLOBAL_TABLE(material_trace_of_contaminant_table, GLOBAL_PROC_REF(build_material_trace_of_contaminant))

/// The material trace a contaminant reagent is, or null when no trace is it.
/proc/material_trace_of_contaminant(contaminant_id)
	var/list/table = GLOBAL_TABLE_GET(material_trace_of_contaminant_table)
	return table[contaminant_id]

/// The contaminant reagent a material trace is, or null for one with none (slag, a gas).
/proc/contaminant_of_material_trace(trace_id)
	var/datum/material_trace/trace = GLOB.material_traces[trace_id]
	return trace?.contaminant

/// What a reagent poured into a melt becomes, as list(trace id, the share of the amount that stays), or null when it leaves as a vapour. Nothing is an inert residue
/// any more: a reagent is a trace of its own (sulfur, hydrogen), the trace a contaminant is, a part of one (organics char to carbon, a halide acid takes up as dissolved
/// hydrogen), a vapour, or slag.
/proc/melt_trace_of(reagent_id)
	if(GLOB.material_traces[reagent_id])
		return list(reagent_id, 1)
	var/direct = material_trace_of_contaminant(reagent_id)
	if(direct)
		return list(direct, 1)
	for(var/trace_id in GLOB.material_traces)
		var/datum/material_trace/trace = GLOB.material_traces[trace_id]
		var/kept = trace.absorbs?[reagent_id]
		if(kept)
			return list(trace_id, kept)
	var/datum/reagent/def = SSchemistry.ready().chemical_reagents[reagent_id]
	if(!def)
		return list("slag", 1)
	var/datum/chem_structure/structure = chem_structure_of(reagent_id)
	if(structure?.is_organic())
		return list("carbon", 0.4)
	if(def.boiling_point_k() < MELT_VAPOUR_POINT)
		return null
	return list("slag", 1)

/// The refining method each shared chemistry process is, applied to a melt (reduce is smelting, ...).
GLOBAL_LIST_INIT(material_refine_methods, list(
	CHEM_PROCESS_REDUCE = MATERIAL_REFINE_SMELT,
	CHEM_PROCESS_OXIDISE = MATERIAL_REFINE_ROAST,
	CHEM_PROCESS_DISPLACE = MATERIAL_REFINE_FLUX,
	CHEM_PROCESS_ELECTROLYSE = MATERIAL_REFINE_ELECTRO,
))
