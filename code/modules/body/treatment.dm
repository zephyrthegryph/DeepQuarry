// Treatment tags — mechanism-based treatment matching.
// (Tags are defined in code/__defines/body.dm.)
//
// A condition never names the chems that treat it. It names the
// MECHANISMS that help it (`treated_by`, tag -> severity drop per tick at
// full effect) and the mechanisms that hurt it (`worsened_by_tags`).
// Treatment sources name the mechanisms they PROVIDE (`treatment_tags`,
// tag -> potency, where 1.0 is a specialist drug at its main job).
//
// Per tick, a patient's level in each tag is:
//   sum over sources of (potency * dose_scale * interference_modifier)
// capped at DQ_CHEM_DOSE_CAP. The body builds these levels ONCE per tick
// (body.treatment_levels(), rebuilt only when reagents change) along with
// natural regeneration (TREAT_REGENERATION). A condition then drops by
//   sum over its treated_by tags of (rate * level[tag])
// and climbs by the same sum over worsened_by_tags.
//
// This is what makes "generic vs. specialist" fall out of the numbers:
// a specialist drug carries one tag at high potency; a generic carries
// many tags at low potency (worse at everything, but works on anything
// when there is no doctor to diagnose). New sources (substances, slime
// products, devices) only need to declare tags to plug in.
//
// Reagents heal ONLY through their tags: no reagent calls heal procs on
// organs or limbs directly. `cured_by` / `worsened_by` (direct reagent-ID
// tables) remain as an escape hatch for one-off drug/condition pairings that
// aren't a mechanism. Both paths stack.

/datum/reagent
	/// Treatment mechanisms this reagent provides: TREAT_* -> potency.
	/// Null for the overwhelming majority of reagents.
	var/list/treatment_tags

// --- Reagent profiles ---------------------------------------------------
//
// Specialists: one strong tag, maybe a weak secondary.
// Generics: several weak tags.

/datum/reagent/bicaridine
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.0, TREAT_BONE_REPAIR = 0.3, TREAT_HEMOSTATIC = 0.2)

/datum/reagent/bicaridine/topical
	treatment_tags = list(TREAT_HEMOSTATIC = 1.0, TREAT_BONE_REPAIR = 1.0, TREAT_TISSUE_REPAIR = 0.6, TREAT_NEURAL_REPAIR = 0.3)

/datum/reagent/tricordrazine
	// The generic: weak at everything a field medic meets.
	treatment_tags = list(
		TREAT_HEMOSTATIC = 0.5,
		TREAT_TISSUE_REPAIR = 0.5,
		TREAT_BURN_CARE = 0.3,
		TREAT_ANTITOXIN = 0.3,
		TREAT_OXYGENATION = 0.3,
		TREAT_ANTIMICROBIAL = 0.2,
	)

/datum/reagent/kelotane
	treatment_tags = list(TREAT_BURN_CARE = 0.6)

/datum/reagent/dermaline
	treatment_tags = list(TREAT_BURN_CARE = 1.0, TREAT_THERMOREGULATION = 0.2)

/datum/reagent/dylovene
	treatment_tags = list(TREAT_ANTITOXIN = 0.6)

/datum/reagent/carthatoline
	treatment_tags = list(TREAT_ANTITOXIN = 1.0, TREAT_HEPATORENAL = 0.4)

/datum/reagent/necroxadone
	// Baseline (warm, living) action; the cryo/corpse boost mends directly.
	treatment_tags = list(TREAT_ANTITOXIN = 0.45, TREAT_GENETIC_REPAIR = 0.3, TREAT_OXYGENATION = 0.2)

/datum/reagent/dexalin
	treatment_tags = list(TREAT_OXYGENATION = 0.5)

/datum/reagent/dexalinp
	treatment_tags = list(TREAT_OXYGENATION = 1.0)

/datum/reagent/spaceacillin
	treatment_tags = list(TREAT_ANTIMICROBIAL = 1.0)

/datum/reagent/corophizine
	treatment_tags = list(TREAT_ANTIMICROBIAL = 1.3)

/datum/reagent/inaprovaline
	// The station's resuscitation stabiliser (and the AllergyPen's payload):
	// a weaker vasopressor on top of circulatory support.
	treatment_tags = list(TREAT_CIRCULATORY = 1.0, TREAT_VASOPRESSOR = 0.5)

/datum/reagent/adrenaline
	// The code-blue drug: restarts electrical activity in a flatlined heart
	// and shrinks swollen airway tissue.
	treatment_tags = list(TREAT_VASOPRESSOR = 1.2, TREAT_STIMULANT = 0.3)

/datum/reagent/iron
	treatment_tags = list(TREAT_BLOOD_RESTORE = 1.0)

/datum/reagent/nutriment
	treatment_tags = list(TREAT_BLOOD_RESTORE = 0.25, TREAT_TISSUE_REPAIR = 0.1)

/datum/reagent/synaptizine
	treatment_tags = list(TREAT_NEURAL_REPAIR = 1.0)

/datum/reagent/alkysine
	treatment_tags = list(TREAT_NEURAL_REPAIR = 0.5)

/datum/reagent/paracetamol
	treatment_tags = list(TREAT_ANALGESIC = 1.0)

/datum/reagent/osteodaxon
	treatment_tags = list(TREAT_BONE_REPAIR = 1.0, TREAT_TISSUE_REPAIR = 0.3)

/datum/reagent/respirodaxon
	treatment_tags = list(TREAT_RESPIRATORY = 1.0)

/datum/reagent/hepanephrodaxon
	treatment_tags = list(TREAT_HEPATORENAL = 1.0, TREAT_ANTITOXIN = 0.7)

/datum/reagent/cordradaxon
	treatment_tags = list(TREAT_CARDIAC = 1.0, TREAT_OXYGENATION = 0.6)

/datum/reagent/imidazoline
	treatment_tags = list(TREAT_OCULAR = 1.0)

/datum/reagent/peridaxon
	// Generic organ support: weak on every organ-repair mechanism.
	treatment_tags = list(
		TREAT_OCULAR = 0.3,
		TREAT_RESPIRATORY = 0.3,
		TREAT_HEPATORENAL = 0.3,
		TREAT_CARDIAC = 0.3,
		TREAT_DIGESTIVE = 0.3,
	)

/datum/reagent/arithrazine
	treatment_tags = list(TREAT_ANTIRADIATION = 1.0, TREAT_ANTITOXIN = 0.6)

/datum/reagent/hyronalin
	treatment_tags = list(TREAT_ANTIRADIATION = 0.5)

/datum/reagent/rezadone
	// "Almost magical": a strong generic on top of its genetic specialty.
	treatment_tags = list(
		TREAT_GENETIC_REPAIR = 1.0,
		TREAT_TISSUE_REPAIR = 0.8,
		TREAT_BURN_CARE = 0.8,
		TREAT_ANTITOXIN = 0.8,
		TREAT_ANTIRADIATION = 0.25,
		TREAT_OXYGENATION = 0.1,
	)

/datum/reagent/ryetalyn
	treatment_tags = list(TREAT_GENETIC_REPAIR = 0.5)

/datum/reagent/leporazine
	treatment_tags = list(TREAT_THERMOREGULATION = 1.0)

/datum/reagent/hyperzine
	treatment_tags = list(TREAT_STIMULANT = 1.0)

/datum/reagent/adminordrazine
	// Admin magic: restores every biology, surgical lesions included.
	treatment_tags = list(TREAT_RESTORATION = DQ_CHEM_DOSE_CAP)

/datum/reagent/coolant
	// Only synthetic parts respond (TREAT_COOLANT is a synthetic mechanism).
	treatment_tags = list(TREAT_COOLANT = 1.0)

// --- Specialists (medicine.dm) ---

/datum/reagent/dermaline/topical
	// Dermalaze: stronger topical burn care (a distinct profile, so it treats).
	treatment_tags = list(TREAT_BURN_CARE = 1.3, TREAT_THERMOREGULATION = 0.2)

/datum/reagent/alizene
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.5)

/datum/reagent/vermicetol
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.3)

/datum/reagent/burncard
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.5)

/datum/reagent/neotane
	treatment_tags = list(TREAT_BURN_CARE = 1.5)

/datum/reagent/gastirodaxon
	treatment_tags = list(TREAT_DIGESTIVE = 1.0, TREAT_ANTITOXIN = 0.6)

/datum/reagent/cleansingagent
	treatment_tags = list(TREAT_ANTITOXIN = 0.8)

/datum/reagent/purifyingagent
	treatment_tags = list(TREAT_ANTITOXIN = 0.8)

/datum/reagent/serazine
	treatment_tags = list(TREAT_ANTITOXIN = 0.3)

/datum/reagent/eden
	// Eden/snake inherits this identical list and is therefore skipped by the tag table.
	treatment_tags = list(TREAT_ANTITOXIN = 0.3)

/datum/reagent/prussian_blue
	treatment_tags = list(TREAT_ANTITOXIN = 0.1)

/datum/reagent/spacomycaze
	treatment_tags = list(TREAT_ANTIMICROBIAL = 0.8)

/datum/reagent/claridyl
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.25)

// --- Generics (medicine.dm / other.dm / drugs.dm) ---

/datum/reagent/tricorlidaze
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.3,
		TREAT_BURN_CARE = 0.3,
		TREAT_OXYGENATION = 0.3,
		TREAT_ANTITOXIN = 0.4,
		TREAT_ANTIMICROBIAL = 0.3,
	)

/datum/reagent/livingagent
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.5,
		TREAT_BURN_CARE = 0.5,
		TREAT_OXYGENATION = 0.4,
		TREAT_ANTITOXIN = 0.4,
	)

/datum/reagent/quadcord
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.2,
		TREAT_BURN_CARE = 0.2,
		TREAT_OXYGENATION = 0.1,
		TREAT_ANTITOXIN = 0.1,
		TREAT_NEURAL_REPAIR = 0.3,
	)

/datum/reagent/bullvalene
	// Converts injury into toxin: the toxin side is injured in medicine.dm.
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.3,
		TREAT_BURN_CARE = 0.3,
		TREAT_OXYGENATION = 0.2,
	)

/datum/reagent/earthsblood
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.6,
		TREAT_BURN_CARE = 0.6,
		TREAT_OXYGENATION = 0.5,
		TREAT_ANTITOXIN = 0.5,
		TREAT_GENETIC_REPAIR = 0.3,
	)

/datum/reagent/healing_nanites
	// Nanites repair organic and synthetic parts alike.
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.4,
		TREAT_BURN_CARE = 0.4,
		TREAT_OXYGENATION = 0.3,
		TREAT_ANTITOXIN = 0.3,
		TREAT_GENETIC_REPAIR = 0.3,
		TREAT_PLATING_REPAIR = 0.4,
		TREAT_WIRING_REPAIR = 0.4,
	)

/datum/reagent/liquid_protean
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.1,
		TREAT_BURN_CARE = 0.1,
		TREAT_OXYGENATION = 0.1,
		TREAT_ANTITOXIN = 0.1,
		TREAT_PLATING_REPAIR = 0.1,
		TREAT_WIRING_REPAIR = 0.1,
	)

/datum/reagent/drugs/ambrosia_extract
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.8, TREAT_ANTITOXIN = 0.3, TREAT_OXYGENATION = 0.2)

// --- Food & drink (food_drinks.dm) ---
// Food-grade: a tenth of a specialist. Subtypes that inherit an identical
// list (tea variants, chocolate milk, …) are skipped by the tag table.

/datum/reagent/drink/juice/lime
	treatment_tags = list(TREAT_ANTITOXIN = 0.1)

/datum/reagent/drink/juice/orange
	treatment_tags = list(TREAT_OXYGENATION = 0.1)

/datum/reagent/drink/juice/tomato
	treatment_tags = list(TREAT_BURN_CARE = 0.1)

/datum/reagent/drink/milk
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.1)

/datum/reagent/drink/tea
	treatment_tags = list(TREAT_ANTITOXIN = 0.1)

/datum/reagent/drink/tea/dyloteane
	treatment_tags = list(TREAT_ANTITOXIN = 0.15)

/datum/reagent/drink/lowpower
	treatment_tags = list(TREAT_ANTITOXIN = 0.1)

/datum/reagent/drink/freshtea
	treatment_tags = list(TREAT_ANTITOXIN = 0.3)

/datum/reagent/drink/matcha
	treatment_tags = list(TREAT_ANTITOXIN = 0.45)

/datum/reagent/drink/coffee/soy_latte
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.1)

/datum/reagent/drink/coffee/cafe_latte
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.1)

/datum/reagent/drink/doctor_delight
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.4,
		TREAT_BURN_CARE = 0.4,
		TREAT_OXYGENATION = 0.2,
		TREAT_ANTITOXIN = 0.3,
	)

/datum/reagent/drink/coffee/nukie/mega/heart
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.0, TREAT_BURN_CARE = 1.0)

/datum/reagent/drink/coffee/nukie/mega/one
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.3, TREAT_BURN_CARE = 0.3)

/datum/reagent/infusedarachnidslammer/enragedarachnidslammer
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.3,
		TREAT_BURN_CARE = 0.3,
		TREAT_OXYGENATION = 0.3,
		TREAT_ANTITOXIN = 0.3,
	)


// --- Registry -----------------------------------------------------------

/// Display names for the book. Order here is the order the book lists them.
/proc/dq_treatment_tag_names()
	var/static/list/names = list(
		TREAT_HEMOSTATIC       = "Hemostatic",
		TREAT_TISSUE_REPAIR    = "Tissue repair",
		TREAT_BONE_REPAIR      = "Bone repair",
		TREAT_BURN_CARE        = "Burn care",
		TREAT_ANTIMICROBIAL    = "Antimicrobial",
		TREAT_ANTITOXIN        = "Antitoxin",
		TREAT_OXYGENATION      = "Oxygenation",
		TREAT_NEURAL_REPAIR    = "Neural repair",
		TREAT_CARDIAC          = "Cardiac support",
		TREAT_RESPIRATORY      = "Respiratory repair",
		TREAT_HEPATORENAL      = "Liver/kidney repair",
		TREAT_OCULAR           = "Ocular repair",
		TREAT_ANTIRADIATION    = "Anti-radiation",
		TREAT_GENETIC_REPAIR   = "Genetic repair",
		TREAT_THERMOREGULATION = "Thermoregulation",
		TREAT_BLOOD_RESTORE    = "Blood restoration",
		TREAT_CIRCULATORY      = "Circulatory support",
		TREAT_ANALGESIC        = "Analgesic",
		TREAT_STIMULANT        = "Stimulant",
		TREAT_PLATING_REPAIR   = "Plating repair",
		TREAT_WIRING_REPAIR    = "Wiring repair",
		TREAT_SYSTEM_RESTORE   = "System restore",
		TREAT_COOLANT          = "Coolant replenishment",
		TREAT_CALIBRATION      = "Recalibration",
		TREAT_SURGICAL_REPAIR  = "Surgical repair",
		TREAT_RESECTION        = "Resection",
		TREAT_AIRWAY           = "Airway clearance",
		TREAT_DECOMPRESSION    = "Chest decompression",
		TREAT_DEFIBRILLATION   = "Defibrillation",
		TREAT_CHEST_COMPRESSION = "Chest compressions",
		TREAT_VASOPRESSOR      = "Vasopressor",
		TREAT_DIGESTIVE        = "Digestive repair",
		TREAT_WOUND_PACKING    = "Wound packing",
		TREAT_OCCLUSIVE_SEAL   = "Occlusive seal",
		TREAT_REGENERATION     = "Natural regeneration",
		TREAT_RESTORATION      = "Restoration",
		TREAT_FEEDSTOCK        = "Refactory feedstock",
		TREAT_SURGICAL_CLOSURE = "Surgical closure",
		TREAT_PANEL_CLOSURE    = "Panel closure",
		TREAT_BONE_SETTING     = "Bone setting",
		TREAT_VESSEL_REPAIR    = "Vessel repair",
		TREAT_TENDON_REPAIR    = "Tendon repair",
		TREAT_FOREIGN_BODY_REMOVAL = "Foreign body removal",
		TREAT_LITHOTRIPSY      = "Lithotripsy",
	)
	return names

/proc/dq_treatment_tag_name(tag)
	return dq_treatment_tag_names()[tag] || tag

/// Mechanisms delivered by tools, kits, machines or procedures rather than
/// (only) by reagents — a cure path the reagent tables can't see.
/proc/treatment_tag_has_tool_source(tag)
	switch(tag)
		if(TREAT_PLATING_REPAIR, TREAT_WIRING_REPAIR, TREAT_SYSTEM_RESTORE, TREAT_CALIBRATION, TREAT_TISSUE_REPAIR, TREAT_BURN_CARE, TREAT_HEMOSTATIC, TREAT_BONE_REPAIR, TREAT_SURGICAL_REPAIR, TREAT_RESECTION)
			return TRUE
		if(TREAT_AIRWAY, TREAT_DECOMPRESSION, TREAT_DEFIBRILLATION, TREAT_CHEST_COMPRESSION)
			return TRUE
		if(TREAT_WOUND_PACKING, TREAT_OCCLUSIVE_SEAL)
			return TRUE
		if(TREAT_REGENERATION, TREAT_RESTORATION, TREAT_FEEDSTOCK)
			return TRUE // the body itself, powers, magic, admin, steel fed to a refactory
		if(TREAT_SURGICAL_CLOSURE, TREAT_PANEL_CLOSURE, TREAT_BONE_SETTING, TREAT_VESSEL_REPAIR, TREAT_TENDON_REPAIR, TREAT_FOREIGN_BODY_REMOVAL, TREAT_LITHOTRIPSY)
			return TRUE // surgical procedure steps
	return FALSE

/// Biologies a treatment mechanism works on. Biological mechanisms (every
/// reagent tag) only treat organic tissue; repair mechanisms treat synthetic
/// parts. A nanite swarm answers only to structural repair (plating, wiring,
/// calibration), its own regeneration and refactory feedstock, plus the
/// electrical jump-start that reboots a dormant core.
/proc/treatment_tag_biology(tag)
	switch(tag)
		if(TREAT_PLATING_REPAIR, TREAT_WIRING_REPAIR, TREAT_CALIBRATION, TREAT_PANEL_CLOSURE)
			return BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM
		if(TREAT_SYSTEM_RESTORE, TREAT_COOLANT)
			return BIOLOGY_SYNTHETIC
		if(TREAT_REGENERATION, TREAT_DEFIBRILLATION)
			return BIOLOGY_ORGANIC | BIOLOGY_NANOFORM
		if(TREAT_FEEDSTOCK)
			return BIOLOGY_NANOFORM
		if(TREAT_RESTORATION, TREAT_FOREIGN_BODY_REMOVAL)
			return BIOLOGY_ALL
	return BIOLOGY_ORGANIC

/// reagent ID -> treatment_tags, built once from the chemistry prototypes.
/// Only reagents that carry tags appear.
/proc/dq_reagent_tag_table()
	var/static/list/table
	if(table)
		return table
	table = list()
	// Tags are NOT inherited: a subtype (dermalaze, inaprovalaze, slime
	// fixers…) only treats if it declares its own, different profile. DM
	// builds list defaults per instance, so compare contents, not refs.
	var/list/tags_by_type = list()
	for(var/id in SSchemistry.chemical_reagents)
		var/datum/reagent/R = SSchemistry.chemical_reagents[id]
		if(R)
			tags_by_type[R.type] = R.treatment_tags
	for(var/id in SSchemistry.chemical_reagents)
		var/datum/reagent/R = SSchemistry.chemical_reagents[id]
		if(!length(R?.treatment_tags))
			continue
		var/parent = R.parent_type
		if(ispath(parent, /datum/reagent) && parent != /datum/reagent)
			var/list/parent_tags = (parent in tags_by_type) ? tags_by_type[parent] : dq_proto_reagent_tags(parent)
			if(dq_same_tag_profile(parent_tags, R.treatment_tags))
				continue
		table[id] = R.treatment_tags
	return table

/proc/dq_same_tag_profile(list/a, list/b)
	if(length(a) != length(b))
		return FALSE
	for(var/tag in a)
		if(a[tag] != b[tag])
			return FALSE
	return TRUE

/// treatment_tags of a reagent type that isn't registered in SSchemistry
/// (abstract intermediates). Instantiated once per type.
/proc/dq_proto_reagent_tags(reagent_type)
	var/static/list/cache = list()
	if(!(reagent_type in cache))
		var/datum/reagent/R = new reagent_type()
		cache[reagent_type] = R.treatment_tags
		qdel(R)
	return cache[reagent_type]

/// reagent ID -> potency for every reagent that provides `tag`.
/proc/dq_reagents_providing(tag)
	var/list/out = list()
	var/list/table = dq_reagent_tag_table()
	for(var/id in table)
		var/potency = table[id][tag]
		if(potency)
			out[id] = potency
	return out



// --- Affliction-side helpers ---------------------------------------------------

/// reagent ID -> effective cure rate at standard dose, merging the direct
/// `cured_by` table with every tagged reagent's contribution. What the
/// book shows; the runtime computes the same thing per tick.
/datum/affliction/proc/effective_cures()
	var/list/out = cured_by ? cured_by.Copy() : list()
	if(!treated_by)
		return out
	var/list/table = dq_reagent_tag_table()
	for(var/id in table)
		var/list/tags = table[id]
		var/rate = 0
		for(var/tag in treated_by)
			rate += treated_by[tag] * (tags[tag] || 0)
		if(rate > 0)
			out[id] = (out[id] || 0) + rate
	return out

/// reagent ID -> effective worsen rate at standard dose.
/datum/affliction/proc/effective_worsens()
	var/list/out = worsened_by ? worsened_by.Copy() : list()
	if(!worsened_by_tags)
		return out
	var/list/table = dq_reagent_tag_table()
	for(var/id in table)
		var/list/tags = table[id]
		var/rate = 0
		for(var/tag in worsened_by_tags)
			rate += worsened_by_tags[tag] * (tags[tag] || 0)
		if(rate > 0)
			out[id] = (out[id] || 0) + rate
	return out
