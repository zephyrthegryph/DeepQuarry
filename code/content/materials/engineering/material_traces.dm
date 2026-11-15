/// Trace effects: what a little of a substance does to a material's card and traits. A batch's composition is real
/// substances with amounts; a substance listed here changes the numbers at low shares (up to its limit, past which it
/// is simply an ingredient). Small on purpose: each substance has one clear effect, and a stat's breakdown names it.

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

/datum/material_trace/sulfur
	id = "sulfur"
	label = "sulfur"
	effects = list(MATERIAL_STAT_TOUGHNESS = -4) // hot-short: brittle
	leaches = TRUE

/datum/material_trace/hydrogen
	id = "hydrogen"
	label = "dissolved hydrogen"
	effects = list(MATERIAL_STAT_TOUGHNESS = -6) // embrittlement
	degasses = TRUE

/datum/material_trace/lead
	id = "lead"
	label = "lead"
	effects = list(MATERIAL_STAT_STRENGTH = -3, MT_TOXIC = 10) // soft, and surgical tools made of it poison
	limit = 4

/datum/material_trace/carbon
	id = "carbon"
	label = "carbon"
	effects = list(MATERIAL_STAT_STRENGTH = 4, MATERIAL_STAT_CONDUCTIVITY = -2, MT_SUPERCONDUCTING = -10)

/datum/material_trace/silicon
	id = "silicon"
	label = "silicon"
	effects = list(MATERIAL_STAT_HEAT_RESISTANCE = 2)

/datum/material_trace/oxygen
	id = "oxygen"
	label = "oxide inclusions"
	effects = list(MATERIAL_STAT_CORROSION_RESISTANCE = -3)
	leaches = TRUE
	degasses = TRUE

/datum/material_trace/lithium
	id = "lithium"
	label = "lithium"
	effects = list(MATERIAL_STAT_CONDUCTIVITY = 3)

/datum/material_trace/phoron_gas
	id = "phoron gas"
	label = "interstitial phoron"
	effects = list(MATERIAL_STAT_HEAT_RESISTANCE = 1.5)

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
