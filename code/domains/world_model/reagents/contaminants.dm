// Contaminants: impurities that are reagents (the types: code/content/reagents/reagents/content/contaminants.dm; the grades: code/defines/content/chem_purity.dm).
//
// A contaminant is a /datum/reagent/contaminant with a volume of its own: 2u of "Heavy metals" sits in the beaker beside the stock. It is added, moved,
// mixed, splashed, ingested and metabolised like any reagent, does its own harm when the body metabolises it, and is part of no transformation, so it
// never reacts. Nothing is attached to another reagent: dilution is physical, and a transfer carries a contaminant exactly as far as it carries any reagent.
//
//   * Purity is a property of the mixture: 1 minus the contaminant volume over the holder's total volume, computed, never stored. The grade (GRADE_*) is
//     the band it falls in. A recipe's `needs_grade` asks for a minimum of the holder (xform_matches()).
//   * Sources: a dispenser cartridge is rolled a profile per round (chem_source_profile()): units of each contaminant that come with each unit of stock,
//     deterministic for the round seed and the source key. add_sourced_reagent() puts the stock and its contaminants in the holder together; the cartridge
//     fills with it, recharges with it (so a recharge never raises purity) and dispenses stock plus the contaminants that sit with it.
//   * Scanners show every contaminant as a line of its own, with its volume, and the mixture's grade (purity_summary()).
//
// GLOB.chem_trace (code/content/reagents/drug_profile.dm) logs every path: a source roll, a stock added, a dispense, an effect on a patient.

/// The ids of the contaminant reagents, in the order the book lists them (the types' declaration order). Built once.
/proc/build_contaminant_ids()
	var/list/ids = list()
	var/list/defs = SSchemistry.ready().chemical_reagents
	for(var/id in defs)
		if(istype(defs[id], /datum/reagent/contaminant))
			ids += id
	return ids

GLOBAL_TABLE(contaminant_ids_table, GLOBAL_PROC_REF(build_contaminant_ids))

/// The contaminant reagents' ids, in book order. Shared, read-only.
/proc/contaminant_ids()
	return GLOBAL_TABLE_GET(contaminant_ids_table)

/// The prototype of a contaminant reagent (its name, role, description and numbers), or null.
/proc/contaminant_def(id)
	RETURN_TYPE(/datum/reagent/contaminant)
	var/datum/reagent/def = SSchemistry.ready().chemical_reagents[id]
	if(istype(def, /datum/reagent/contaminant))
		return def
	return null

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

// ---- the holder side ----

/// Units of contaminant reagents in the holder.
/datum/reagents/proc/contaminant_volume()
	. = 0
	for(var/datum/reagent/R as anything in reagent_list)
		if(istype(R, /datum/reagent/contaminant))
			. += R.volume

/// The share of the holder that is not contaminant (0..1): 1 for a holder with none or with nothing in it. Computed, never stored.
/datum/reagents/proc/purity()
	if(total_volume <= 0)
		return 1
	return clamp(1 - contaminant_volume() / total_volume, 0, 1)

/// The GRADE_* of the mixture.
/datum/reagents/proc/grade()
	return grade_of_purity(purity())

/// "Standard 74%", or null when the holder carries no contaminant: what a readout says about the mixture.
/datum/reagents/proc/purity_summary()
	if(contaminant_volume() <= 0)
		return null
	var/current_purity = purity()
	return "[grade_name(grade_of_purity(current_purity))] [round(current_purity * 100)]%"

/// Total volume per unit of stock: how much of the mixture holds one unit of what is not contaminant (1 when pure or when there is no stock).
/datum/reagents/proc/stock_scale()
	var/contaminants = contaminant_volume()
	var/stock = total_volume - contaminants
	if(contaminants <= 0 || stock <= 0)
		return 1
	return total_volume / stock

/// Adds `amount` units of the stock `id` together with the contaminants of `profile` (contaminant id -> units per unit of stock, chem_source_profile(); null
/// for none), as much as fits: the stock is `amount` or what leaves room for its contaminants. Returns the units of stock added.
/datum/reagents/proc/add_sourced_reagent(id, amount, list/profile, data = null, safety = 0)
	var/scale = 1
	for(var/contaminant_id in profile)
		scale += profile[contaminant_id]
	var/stock = min(amount, get_free_space() / scale)
	if(stock <= 0)
		return 0
	// The contaminants first, without reactions; the stock last, so the holder settles once with everything in.
	for(var/contaminant_id in profile)
		add_reagent(contaminant_id, stock * profile[contaminant_id], safety = 1)
	add_reagent(id, stock, data, safety = safety)
	if(GLOB.chem_trace)
		log_world("CHEM: [id] stock [round(stock, 0.001)]u added to [my_atom] with contaminants [contaminants_text(profile)] per unit; mixture now [purity_summary() || "pure"]")
	return stock

/// "contaminant_heavy_metal 0.12, contaminant_sulfur 0.05" for the trace log.
/proc/contaminants_text(list/amounts)
	var/list/parts = list()
	for(var/contaminant_id in amounts)
		parts += "[contaminant_id] [round(amounts[contaminant_id], 0.001)]"
	return length(parts) ? jointext(parts, ", ") : "none"

/// Can a dispenser or supply of this reagent carry impurities? Drinks, ethanol, nutriment, water and blood are not chemistry reagents: they override this.
/datum/reagent/proc/source_contaminable()
	return TRUE

// ---- sources ----

/// The per-round contaminant profile of a source of `reagent_id` (a cartridge, a supply: `source_key` names which), at `grade`: contaminant id -> units that
/// come with each unit of stock, or null for a reagent that cannot carry impurities or a Reagent-grade source. Deterministic for the round seed (round_seed(),
/// md5 streams, never rand_seed()) and the key: the same source always rolls the same profile, two sources differ. The units are what makes the mixture the
/// grade asked for: stock and its contaminants together fall in the grade's purity band.
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
	// The share of the finished mixture that is contaminant.
	var/total = min_total + (max_total - min_total) * roll.unit()
	var/count = roll.number(min_types, max_types)
	var/list/pool = list()
	for(var/contaminant_id in contaminant_ids())
		var/datum/reagent/contaminant/C = contaminant_def(contaminant_id)
		pool[contaminant_id] = C.source_weight
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
	// A share of the mixture becomes units per unit of stock: the stock is the rest of it.
	var/list/profile = list()
	for(var/contaminant_id in shares)
		profile[contaminant_id] = (total * shares[contaminant_id] / share_sum) / (1 - total)
	if(GLOB.chem_trace)
		log_world("CHEM: source [source_key] of [reagent_id] rolled [grade_name(grade)] profile [contaminants_text(profile)] per unit of stock")
	return profile
