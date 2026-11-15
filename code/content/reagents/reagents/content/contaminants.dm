// The contaminant reagents (code/domains/world_model/reagents/contaminants.dm). Each is a reagent with a volume of its own: it is added, moved, mixed,
// splashed, ingested and metabolised like any other, and does its own harm when the body metabolises it. None is part of any ordinary recipe, so a
// contaminant rides along in the beaker and counts against the mixture's purity (only neutralisation spends an acid or base residue).
//
// A role is a type under /datum/reagent/contaminant (toxic, reactive, biological, inert); the row of a contaminant is the type that carries its numbers.

/datum/reagent/contaminant
	reagent_state = LIQUID
	taste_description = "something foul"
	color = "#7a6f5a"
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_RAW
	/// What the book files it under (CONTAMINANT_ROLE_*).
	var/contaminant_role = CONTAMINANT_ROLE_INERT
	/// What it does to a patient, in the book's words.
	var/effect_text = ""
	/// How likely a source rolls it (weight among the contaminant reagents).
	var/source_weight = 1

/// A contaminant's catalogue line in a machine's listing also says what the mixture it sits in is graded.
/datum/reagent/contaminant/listing_description()
	var/summary = holder?.purity_summary()
	return summary ? "[description] The mixture is [summary]." : description

/// Toxic: `rate` damage per unit metabolised in the blood, to `organ` (an O_* tag), or general toxin damage when there is none.
/datum/reagent/contaminant/toxic
	contaminant_role = CONTAMINANT_ROLE_TOXIC
	var/organ
	var/rate = 0

/datum/reagent/contaminant/toxic/affect_blood(mob/living/carbon/M, alien, removed)
	if(inert_for(M))
		return
	var/amount = removed * rate
	if(amount <= 0)
		return
	var/obj/item/organ/O = organ ? M.organ_in(organ) : null
	if(O)
		M.injure(INJURY_BLUNT, amount, O, src, affliction = /datum/affliction/lesion/toxic_injury, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	else
		M.injure(INJURY_TOXIN, amount, source = src, flags = INJURE_SILENT)
	if(GLOB.chem_trace)
		log_world("CHEM: [id] ([round(removed, 0.0001)]u metabolised) strains [organ || "the body"] of [M] for [round(amount, 0.0001)]")

/// Reactive: each metabolism cycle, `burn_chance` percent of a minor burn of `rate` per unit metabolised.
/datum/reagent/contaminant/reactive
	contaminant_role = CONTAMINANT_ROLE_REACTIVE
	var/rate = 0
	var/burn_chance = 0

/datum/reagent/contaminant/reactive/affect_blood(mob/living/carbon/M, alien, removed)
	if(inert_for(M))
		return
	var/amount = removed * rate
	if(amount <= 0 || !prob(burn_chance))
		return
	M.injure(INJURY_BURN, amount, source = src, flags = INJURE_SILENT)
	if(GLOB.chem_trace)
		log_world("CHEM: [id] ([round(removed, 0.0001)]u metabolised) burns [M] for [round(amount, 0.0001)]")

/// Biological: `rate` toxin damage per unit metabolised, and `fever` kelvin of fever per REM of it.
/datum/reagent/contaminant/biological
	contaminant_role = CONTAMINANT_ROLE_BIOLOGICAL
	var/rate = 0
	var/fever = 0

/datum/reagent/contaminant/biological/affect_blood(mob/living/carbon/M, alien, removed)
	if(inert_for(M))
		return
	var/amount = removed * rate
	if(amount > 0)
		M.injure(INJURY_TOXIN, amount, source = src, flags = INJURE_SILENT)
	if(fever > 0)
		warm_body(M, fever, removed, max_temp = T0C + 39)
	if(GLOB.chem_trace)
		log_world("CHEM: [id] ([round(removed, 0.0001)]u metabolised) poisons [M] for [round(amount, 0.0001)] and raises the fever by [fever] K per REM")

/// Inert: only takes up volume.
/datum/reagent/contaminant/inert
	contaminant_role = CONTAMINANT_ROLE_INERT

/datum/reagent/contaminant/toxic/heavy_metal
	name = REAGENT_CONTAMINANT_HEAVY_METAL
	id = REAGENT_ID_CONTAMINANT_HEAVY_METAL
	description = "Traces of lead, mercury and cadmium left from the source ore."
	boiling_point = BOILING_POINT_NEVER
	effect_text = "Slowly poisons the liver."
	source_weight = 2
	organ = O_LIVER
	rate = 0.2

/datum/reagent/contaminant/toxic/sulfur
	name = REAGENT_CONTAMINANT_SULFUR
	id = REAGENT_ID_CONTAMINANT_SULFUR
	description = "Sulfides and sulfates carried over from refining."
	boiling_point = T0C + 445
	effect_text = "Slowly damages the kidneys."
	source_weight = 2
	organ = O_KIDNEYS
	rate = 0.15

/datum/reagent/contaminant/toxic/organic_residue
	name = REAGENT_CONTAMINANT_ORGANIC_RESIDUE
	id = REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE
	description = "Solvent and by-product left in the batch."
	boiling_point = T0C + 250
	effect_text = "A mild, general toxin."
	source_weight = 3
	rate = 0.1

/datum/reagent/contaminant/toxic/salts
	name = REAGENT_CONTAMINANT_SALTS
	id = REAGENT_ID_CONTAMINANT_SALTS
	description = "Dissolved salts from neutralisation and washing."
	boiling_point = BOILING_POINT_NEVER
	effect_text = "Strains the kidneys, lightly."
	source_weight = 3
	organ = O_KIDNEYS
	rate = 0.06

/datum/reagent/contaminant/reactive/acid_residue
	name = REAGENT_CONTAMINANT_ACID_RESIDUE
	id = REAGENT_ID_CONTAMINANT_ACID_RESIDUE
	description = "Unneutralised acid left from the reaction."
	boiling_point = T0C + 160
	effect_text = "Occasionally burns on contact with tissue."
	source_weight = 1.5
	rate = 0.5
	burn_chance = 20

/datum/reagent/contaminant/reactive/base_residue
	name = REAGENT_CONTAMINANT_BASE_RESIDUE
	id = REAGENT_ID_CONTAMINANT_BASE_RESIDUE
	description = "Unneutralised base left from the reaction."
	boiling_point = T0C + 300
	effect_text = "Occasionally burns on contact with tissue."
	source_weight = 1.5
	rate = 0.5
	burn_chance = 20

/datum/reagent/contaminant/inert/oily_residue
	name = REAGENT_CONTAMINANT_OILY_RESIDUE
	id = REAGENT_ID_CONTAMINANT_OILY_RESIDUE
	description = "Lubricant and fat carried through the process."
	boiling_point = T0C + 350
	effect_text = "Harmless, but takes up room in the dose."
	source_weight = 3

/datum/reagent/contaminant/inert/inert_filler
	name = REAGENT_CONTAMINANT_INERT_FILLER
	id = REAGENT_ID_CONTAMINANT_INERT_FILLER
	description = "Binder and bulk that does nothing."
	boiling_point = BOILING_POINT_NEVER
	effect_text = "Harmless, but takes up room in the dose."
	source_weight = 4

/datum/reagent/contaminant/biological/endotoxin
	name = REAGENT_CONTAMINANT_BIOLOGICAL
	id = REAGENT_ID_CONTAMINANT_BIOLOGICAL
	description = "Bacterial remnants from a poorly kept batch."
	boiling_point = BOILING_POINT_NEVER
	effect_text = "A toxin that also raises the patient's temperature."
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD
	source_weight = 0.5
	rate = 0.15
	fever = 8

/datum/reagent/contaminant/reactive/reactive_impurity
	name = REAGENT_CONTAMINANT_REACTIVE
	id = REAGENT_ID_CONTAMINANT_REACTIVE
	description = "An unstable by-product."
	boiling_point = T0C + 60
	effect_text = "Occasionally burns the patient."
	source_weight = 1
	rate = 0.6
	burn_chance = 15
