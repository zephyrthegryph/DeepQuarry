// Contaminants: what a reagent volume carries besides the reagent (defines: code/defines/content/chem_purity.dm).
//
// A /datum/reagent in a holder may carry a sparse `contaminants` list: contaminant id -> fraction of THAT reagent's volume (0..1). It is null unless
// something is nonzero. Purity is computed (1 - the sum), never stored; the grade (GRADE_*) is the band the purity falls in. A reagent without
// contaminants is pure: Reagent grade, potency 1, and every path below leaves it untouched.
//
//   * Mixing and moving: add_reagent(..., contaminants =) blends the incoming list into the volume already there by volume (the old volume weights
//     the old list, the added amount the new one); a new reagent copies it. Removal changes no fraction. Every holder-to-holder move passes
//     `current.contaminants`.
//   * Reactions: xform_step() averages the consumed reactants' fractions (weighted by the units used) into the product.
//   * Sources: a dispenser cartridge (or any supply of a reagent id) is stamped with a profile rolled per round, per source
//     (chem_source_profile()): deterministic for the round seed and the source key.
//   * Effects on a patient (apply_contaminants(), the blood route of on_mob_life): each contaminant's registry row says what it does, scaled by the
//     units of it metabolised. Every impurity dilutes the reagent's potency (its purity scales what affect_blood receives).
//   * Scanners show `purity_summary()` and the units of each contaminant.
//
// GLOB.chem_trace (code/content/reagents/drug_profile.dm) logs every propagation: mix, reaction carry, source roll, effect.

/// One contaminant type: what the book lists and what it does to a patient. Rows live in contaminant_defs(), built once.
/datum/contaminant
	var/id
	var/name
	var/role = CONTAMINANT_ROLE_INERT
	var/desc
	/// The effect on a patient in the book's words.
	var/effect_text
	/// How likely a source rolls it (weight among the registry rows).
	var/weight = 1
	/// Toxic: the organ (O_* tag) strained, with `rate` damage per unit of the contaminant metabolised in the blood. Null organ: general toxin damage.
	var/organ
	var/rate = 0
	/// Reactive: chance (percent) per metabolism cycle of a minor burn of `rate` per unit.
	var/burn_chance = 0
	/// Biological: kelvin of fever per REM-worth of the contaminant's fraction metabolised.
	var/fever = 0

/datum/contaminant/New(id, name, role, weight, desc, effect_text, organ = null, rate = 0, burn_chance = 0, fever = 0)
	..()
	src.id = id
	src.name = name
	src.role = role
	src.weight = weight
	src.desc = desc
	src.effect_text = effect_text
	src.organ = organ
	src.rate = rate
	src.burn_chance = burn_chance
	src.fever = fever

/proc/contaminant_def_add(list/defs, id, name, role, weight, desc, effect_text, organ = null, rate = 0, burn_chance = 0, fever = 0)
	defs[id] = new /datum/contaminant(id, name, role, weight, desc, effect_text, organ, rate, burn_chance, fever)

/// id -> /datum/contaminant. Built once. The order here is the order the book lists them.
/proc/build_contaminant_defs()
	var/list/defs = list()
	contaminant_def_add(defs, CONTAMINANT_HEAVY_METAL, "Heavy metals", CONTAMINANT_ROLE_TOXIC, 2, "Traces of lead, mercury and cadmium left from the source ore.", "Slowly poisons the liver.", O_LIVER, 0.2)
	contaminant_def_add(defs, CONTAMINANT_SULFUR, "Sulfur compounds", CONTAMINANT_ROLE_TOXIC, 2, "Sulfides and sulfates carried over from refining.", "Slowly damages the kidneys.", O_KIDNEYS, 0.15)
	contaminant_def_add(defs, CONTAMINANT_ORGANIC_RESIDUE, "Organic residue", CONTAMINANT_ROLE_TOXIC, 3, "Solvent and by-product left in the batch.", "A mild, general toxin.", null, 0.1)
	contaminant_def_add(defs, CONTAMINANT_SALTS, "Salts", CONTAMINANT_ROLE_TOXIC, 3, "Dissolved salts from neutralisation and washing.", "Strains the kidneys, lightly.", O_KIDNEYS, 0.06)
	contaminant_def_add(defs, CONTAMINANT_ACID_RESIDUE, "Acid residue", CONTAMINANT_ROLE_REACTIVE, 1.5, "Unneutralised acid left from the reaction.", "Occasionally burns on contact with tissue.", null, 0.5, 20)
	contaminant_def_add(defs, CONTAMINANT_BASE_RESIDUE, "Base residue", CONTAMINANT_ROLE_REACTIVE, 1.5, "Unneutralised base left from the reaction.", "Occasionally burns on contact with tissue.", null, 0.5, 20)
	contaminant_def_add(defs, CONTAMINANT_OILY_RESIDUE, "Oily residue", CONTAMINANT_ROLE_INERT, 3, "Lubricant and fat carried through the process.", "Harmless, but dilutes the dose.")
	contaminant_def_add(defs, CONTAMINANT_INERT_FILLER, "Inert filler", CONTAMINANT_ROLE_INERT, 4, "Binder and bulk that does nothing.", "Harmless, but dilutes the dose.")
	contaminant_def_add(defs, CONTAMINANT_BIOLOGICAL, "Endotoxin", CONTAMINANT_ROLE_BIOLOGICAL, 0.5, "Bacterial remnants from a poorly kept batch.", "A toxin that also raises the patient's temperature.", null, 0.15, 0, 8)
	contaminant_def_add(defs, CONTAMINANT_REACTIVE, "Reactive impurity", CONTAMINANT_ROLE_REACTIVE, 1, "An unstable by-product.", "Occasionally burns the patient.", null, 0.6, 15)
	return defs

GLOBAL_TABLE(contaminant_defs_table, GLOBAL_PROC_REF(build_contaminant_defs))

/// The registry: contaminant id -> /datum/contaminant, in book order. Shared, read-only.
/proc/contaminant_defs()
	return GLOBAL_TABLE_GET(contaminant_defs_table)

/// The row of a contaminant id, or null.
/proc/contaminant_def(id)
	RETURN_TYPE(/datum/contaminant)
	var/list/defs = contaminant_defs()
	return defs[id]

/// The name a grade goes by.
/proc/grade_name(grade)
	switch(grade)
		if(GRADE_CRUDE)
			return "Crude"
		if(GRADE_STANDARD)
			return "Standard"
		if(GRADE_PHARMA)
			return "Pharma"
		if(GRADE_REAGENT)
			return "Reagent"
	return "Unknown"

/// The purity band of a grade, as the book prints it.
/proc/purity_band_text(grade)
	switch(grade)
		if(GRADE_CRUDE)
			return "under [round(PURITY_STANDARD * 100)]%"
		if(GRADE_STANDARD)
			return "[round(PURITY_STANDARD * 100)]% to [round(PURITY_PHARMA * 100)]%"
		if(GRADE_PHARMA)
			return "[round(PURITY_PHARMA * 100)]% to [round(PURITY_REAGENT * 100)]%"
		if(GRADE_REAGENT)
			return "[round(PURITY_REAGENT * 100)]% and over"
	return "unknown"

/// The grade of a purity (0..1).
/proc/grade_of_purity(purity)
	if(purity + PURITY_EPSILON >= PURITY_REAGENT)
		return GRADE_REAGENT
	if(purity + PURITY_EPSILON >= PURITY_PHARMA)
		return GRADE_PHARMA
	if(purity + PURITY_EPSILON >= PURITY_STANDARD)
		return GRADE_STANDARD
	return GRADE_CRUDE

// ---- the reagent side ----

/// 1 minus the contaminant fractions: 1 for a pure reagent. Computed, never stored.
/datum/reagent/proc/purity()
	if(!contaminants)
		return 1
	var/sum = 0
	for(var/id in contaminants)
		sum += contaminants[id]
	return clamp(1 - sum, 0, 1)

/// The GRADE_* of this volume.
/datum/reagent/proc/grade()
	return grade_of_purity(purity())

/// How strong the reagent acts: its purity when it carries contaminants, exactly 1 otherwise.
/datum/reagent/proc/potency()
	return contaminants ? purity() : 1

/// Units of contaminant `contaminant_id` in this volume.
/datum/reagent/proc/contaminant_units(contaminant_id)
	return contaminants ? (contaminants[contaminant_id] || 0) * volume : 0

/// Can a dispenser or supply of this reagent carry impurities? Drinks, ethanol, nutriment, water and blood are not chemistry reagents: they override this.
/datum/reagent/proc/source_contaminable()
	return TRUE

/// Replaces the contaminants with a copy of `fractions` (fractions below CONTAMINANT_EPSILON dropped; null when nothing is left).
/datum/reagent/proc/set_contaminants(list/fractions)
	if(!length(fractions) && !contaminants) // a pure reagent made pure: nothing changes, nothing is marked (every reagent made into a container comes through here)
		return
	var/list/kept
	for(var/contaminant_id in fractions)
		var/fraction = fractions[contaminant_id]
		if(isnum(fraction) && fraction >= CONTAMINANT_EPSILON)
			LAZYSET(kept, contaminant_id, min(fraction, 1))
	contaminants = kept
	tracked_changed(src, nameof(contaminants))

/// `amount` units of this reagent carrying `incoming` are about to be added (the volume is still the old one): the new fractions are the volume-weighted
/// average. Called by /datum/reagents/proc/add_reagent() before it raises the volume.
/datum/reagent/proc/blend_contaminants(list/incoming, amount)
	if(!contaminants && !incoming)
		return
	var/old = max(volume, 0)
	var/total = old + amount
	if(total <= 0)
		return
	var/list/merged
	for(var/contaminant_id in contaminants)
		var/fraction = ((contaminants[contaminant_id] * old) + ((incoming?[contaminant_id] || 0) * amount)) / total
		if(fraction >= CONTAMINANT_EPSILON)
			LAZYSET(merged, contaminant_id, fraction)
	for(var/contaminant_id in incoming)
		if(contaminants && (contaminant_id in contaminants))
			continue
		var/fraction = (incoming[contaminant_id] * amount) / total
		if(fraction >= CONTAMINANT_EPSILON)
			LAZYSET(merged, contaminant_id, fraction)
	contaminants = merged
	if(GLOB.chem_trace)
		log_world("CHEM: [id] mixed [amount]u into [old]u; contaminants now [contaminants_text(contaminants)]")

/// "Standard 74%", or null for a pure reagent: what a readout appends to the name.
/datum/reagent/proc/purity_summary()
	if(!contaminants)
		return null
	var/current_purity = purity()
	return "[grade_name(grade_of_purity(current_purity))] [round(current_purity * 100)]%"

/// One line per contaminant: "<name> <units>u" (units = fraction * volume), in registry order. Empty list when pure.
/datum/reagent/proc/contaminant_lines()
	. = list()
	if(!contaminants)
		return
	var/list/defs = contaminant_defs()
	for(var/contaminant_id in defs)
		if(!contaminants[contaminant_id])
			continue
		var/datum/contaminant/C = defs[contaminant_id]
		. += "[C.name] [round(contaminants[contaminant_id] * volume, 0.01)]u"

/// "<name> <volume>u, <grade> <purity>%" with each contaminant's units after it: what a scanner prints for one reagent (just the name and volume when pure).
/datum/reagent/proc/scan_text()
	var/text = "[name] [round(volume, 0.1)]u"
	var/summary = purity_summary()
	if(!summary)
		return text
	text += ", [summary]"
	var/list/lines = contaminant_lines()
	if(length(lines))
		text += " ([english_list(lines)])"
	return text

/// "heavy_metal 0.12, sulfur 0.05" for the trace log.
/proc/contaminants_text(list/fractions)
	var/list/parts = list()
	for(var/contaminant_id in fractions)
		parts += "[contaminant_id] [round(fractions[contaminant_id], 0.001)]"
	return length(parts) ? jointext(parts, ", ") : "none"

// ---- sources ----

/// The per-round contaminant profile of a source of `reagent_id` (a cartridge, a supply: `source_key` names which), at `grade`: id -> fraction, or null
/// for a reagent that cannot carry impurities or a Reagent-grade source. Deterministic for the round seed (round_seed(), md5 streams, never rand_seed())
/// and the key: the same source always rolls the same profile, two sources differ.
/proc/chem_source_profile(reagent_id, source_key = "", grade = GRADE_STANDARD)
	var/datum/reagent/def = SSchemistry.ready().chemical_reagents[reagent_id]
	if(!def || !def.source_contaminable() || grade >= GRADE_REAGENT)
		return null
	var/datum/roller/roll = new /datum/roller("[round_seed()]|chem_source|[reagent_id]|[source_key]")
	// The purity band the grade names, rolled CONTAMINANT_ROLL_MARGIN inside its edges (so a profile never sits on a boundary).
	var/low_purity
	var/high_purity
	var/min_types
	var/max_types
	switch(grade)
		if(GRADE_CRUDE)
			low_purity = 0.3
			high_purity = PURITY_STANDARD
			min_types = 3
			max_types = 4
		if(GRADE_PHARMA)
			low_purity = PURITY_PHARMA
			high_purity = PURITY_REAGENT
			min_types = 1
			max_types = 2
		else
			low_purity = PURITY_STANDARD
			high_purity = PURITY_PHARMA
			min_types = 2
			max_types = 3
	var/min_total = 1 - high_purity + CONTAMINANT_ROLL_MARGIN
	var/max_total = 1 - low_purity - CONTAMINANT_ROLL_MARGIN
	var/total = min_total + (max_total - min_total) * roll.unit()
	var/count = roll.number(min_types, max_types)
	var/list/pool = list()
	var/list/defs = contaminant_defs()
	for(var/contaminant_id in defs)
		var/datum/contaminant/C = defs[contaminant_id]
		pool[contaminant_id] = C.weight
	var/list/shares = list()
	var/share_sum = 0
	for(var/i in 1 to count)
		var/picked = roll.weighted(pool)
		if(isnull(picked))
			break
		pool -= picked
		var/share = 0.5 + roll.unit()
		shares[picked] = share
		share_sum += share
	if(share_sum <= 0)
		return null
	var/list/profile = list()
	for(var/contaminant_id in shares)
		profile[contaminant_id] = total * shares[contaminant_id] / share_sum
	if(GLOB.chem_trace)
		log_world("CHEM: source [source_key] of [reagent_id] rolled [grade_name(grade)] profile [contaminants_text(profile)]")
	return profile

/// Stamps a source profile onto the reagent `reagent_id` of `holder` (its starting stock): the volume there takes the rolled fractions.
/proc/chem_stamp_source(datum/reagents/holder, reagent_id, source_key, grade = GRADE_STANDARD)
	var/datum/reagent/R = holder?.get_reagent(reagent_id)
	if(!R)
		return FALSE
	var/list/profile = chem_source_profile(reagent_id, source_key, grade)
	if(!profile)
		return FALSE
	R.set_contaminants(profile)
	return TRUE

// ---- on the patient ----

/// The effects of the contaminants of `removed` units metabolised in the blood: each registry row's role and numbers, scaled by the units of the
/// contaminant (fraction * removed). Toxic rows strain an organ or poison; reactive rows may burn; biological rows poison and warm the patient.
/// Natural regeneration outpaces Standard-grade doses; the damage is small per unit by design.
/datum/reagent/proc/apply_contaminants(mob/living/carbon/M, removed)
	if(!contaminants || removed <= 0 || inert_for(M))
		return
	var/list/defs = contaminant_defs()
	for(var/contaminant_id in contaminants)
		var/datum/contaminant/C = defs[contaminant_id]
		if(!C)
			continue
		var/units = contaminants[contaminant_id] * removed
		if(units <= 0)
			continue
		var/amount = units * C.rate
		switch(C.role)
			if(CONTAMINANT_ROLE_TOXIC)
				if(amount <= 0)
					continue
				var/obj/item/organ/O = C.organ ? M.organ_in(C.organ) : null
				if(O)
					M.injure(INJURY_BLUNT, amount, O, src, affliction = /datum/affliction/lesion/toxic_injury, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
				else
					M.injure(INJURY_TOXIN, amount, source = src, flags = INJURE_SILENT)
			if(CONTAMINANT_ROLE_REACTIVE)
				if(amount <= 0 || !prob(C.burn_chance))
					continue
				M.injure(INJURY_BURN, amount, source = src, flags = INJURE_SILENT)
			if(CONTAMINANT_ROLE_BIOLOGICAL)
				if(amount > 0)
					M.injure(INJURY_TOXIN, amount, source = src, flags = INJURE_SILENT)
				if(C.fever > 0)
					warm_body(M, C.fever * contaminants[contaminant_id], removed, max_temp = T0C + 39)
			else
				continue
		if(GLOB.chem_trace)
			log_world("CHEM: [id] contaminant [contaminant_id] ([round(units, 0.0001)]u) acts on [M] ([C.role], [round(amount, 0.0001)])")
