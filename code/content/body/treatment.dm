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

// Each reagent declares its own `treatment_tags` next to its definition
// (code/modules/reagents/reagents/content/, packs/). The tag table is built
// from those prototypes below.

// --- Registry -----------------------------------------------------------

/// Display names for the book. Order here is the order the book lists them.
GLOBAL_LIST_INIT(dq_treatment_tag_names, list( \
	TREAT_HEMOSTATIC       = "Hemostatic", \
	TREAT_TISSUE_REPAIR    = "Tissue repair", \
	TREAT_BONE_REPAIR      = "Bone repair", \
	TREAT_BURN_CARE        = "Burn care", \
	TREAT_ANTIMICROBIAL    = "Antimicrobial", \
	TREAT_ANTITOXIN        = "Antitoxin", \
	TREAT_OXYGENATION      = "Oxygenation", \
	TREAT_NEURAL_REPAIR    = "Neural repair", \
	TREAT_CARDIAC          = "Cardiac support", \
	TREAT_RESPIRATORY      = "Respiratory repair", \
	TREAT_HEPATORENAL      = "Liver/kidney repair", \
	TREAT_OCULAR           = "Ocular repair", \
	TREAT_ANTIRADIATION    = "Anti-radiation", \
	TREAT_GENETIC_REPAIR   = "Genetic repair", \
	TREAT_THERMOREGULATION = "Thermoregulation", \
	TREAT_BLOOD_RESTORE    = "Blood restoration", \
	TREAT_CIRCULATORY      = "Circulatory support", \
	TREAT_ANALGESIC        = "Analgesic", \
	TREAT_STIMULANT        = "Stimulant", \
	TREAT_PLATING_REPAIR   = "Plating repair", \
	TREAT_WIRING_REPAIR    = "Wiring repair", \
	TREAT_SYSTEM_RESTORE   = "System restore", \
	TREAT_COOLANT          = "Coolant replenishment", \
	TREAT_CALIBRATION      = "Recalibration", \
	TREAT_SURGICAL_REPAIR  = "Surgical repair", \
	TREAT_RESECTION        = "Resection", \
	TREAT_AIRWAY           = "Airway clearance", \
	TREAT_DECOMPRESSION    = "Chest decompression", \
	TREAT_DEFIBRILLATION   = "Defibrillation", \
	TREAT_CHEST_COMPRESSION = "Chest compressions", \
	TREAT_VASOPRESSOR      = "Vasopressor", \
	TREAT_DIGESTIVE        = "Digestive repair", \
	TREAT_WOUND_PACKING    = "Wound packing", \
	TREAT_OCCLUSIVE_SEAL   = "Occlusive seal", \
	TREAT_REGENERATION     = "Natural regeneration", \
	TREAT_RESTORATION      = "Restoration", \
	TREAT_FEEDSTOCK        = "Refactory feedstock", \
	TREAT_SURGICAL_CLOSURE = "Surgical closure", \
	TREAT_PANEL_CLOSURE    = "Panel closure", \
	TREAT_BONE_SETTING     = "Bone setting", \
	TREAT_VESSEL_REPAIR    = "Vessel repair", \
	TREAT_TENDON_REPAIR    = "Tendon repair", \
	TREAT_FOREIGN_BODY_REMOVAL = "Foreign body removal", \
	TREAT_LITHOTRIPSY      = "Lithotripsy", \
))

/proc/dq_treatment_tag_name(tag)
	return GLOB.dq_treatment_tag_names[tag] || tag

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
	READS_FROM()
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
/proc/build_dq_reagent_tag_table()
	var/list/table = list()
	// Tags are NOT inherited: a subtype (dermalaze, inaprovalaze, slime
	// fixers…) only treats if it declares its own, different profile. DM
	// builds list defaults per instance, so compare contents, not refs.
	var/list/tags_by_type = list()
	for(var/id in SSchemistry.ready().chemical_reagents)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[id]
		if(R)
			tags_by_type[R.type] = R.treatment_tags
	for(var/id in SSchemistry.ready().chemical_reagents)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[id]
		if(!length(R?.treatment_tags))
			continue
		var/parent = R.parent_type
		if(ispath(parent, /datum/reagent) && parent != /datum/reagent)
			var/list/parent_tags = (parent in tags_by_type) ? tags_by_type[parent] : dq_proto_reagent_tags(parent)
			if(dq_same_tag_profile(parent_tags, R.treatment_tags))
				continue
		table[id] = R.treatment_tags
	return table

GLOBAL_TABLE(dq_reagent_tag_table, GLOBAL_PROC_REF(build_dq_reagent_tag_table))

/proc/dq_same_tag_profile(list/a, list/b)
	if(length(a) != length(b))
		return FALSE
	for(var/tag in a)
		if(a[tag] != b[tag])
			return FALSE
	return TRUE

/// treatment_tags of a reagent type that isn't registered in the chemistry service
/// (abstract intermediates). Instantiated once per type.
DECLARE_SHARED_CACHE(proto_reagent_tags, GLOBAL_PROC_REF(build_proto_reagent_tags), SC_NEVER)

/proc/dq_proto_reagent_tags(reagent_type)
	return CACHED(proto_reagent_tags, reagent_type)

/proc/build_proto_reagent_tags(reagent_type)
	var/datum/reagent/R = new reagent_type()
	. = R.treatment_tags
	spent(R)

/// reagent ID -> potency for every reagent that provides `tag`.
/proc/dq_reagents_providing(tag)
	var/list/out = list()
	var/list/table = GLOBAL_TABLE_GET(dq_reagent_tag_table)
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
	var/list/table = GLOBAL_TABLE_GET(dq_reagent_tag_table)
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
	var/list/table = GLOBAL_TABLE_GET(dq_reagent_tag_table)
	for(var/id in table)
		var/list/tags = table[id]
		var/rate = 0
		for(var/tag in worsened_by_tags)
			rate += worsened_by_tags[tag] * (tags[tag] || 0)
		if(rate > 0)
			out[id] = (out[id] || 0) + rate
	return out
