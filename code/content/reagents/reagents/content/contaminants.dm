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
	/// How likely a source rolls it (weight among the contaminant reagents); 0: a process makes it, no source carries it.
	var/source_weight = 1
	/// The share of a mixture below which a filter cannot take it out any further (code/content/reagents/purification/filters.dm): a trace stays.
	var/filter_floor = 0

/// A contaminant does its harm silently (INJURE_SILENT), so the patient gets a mild unwell cue now and then. The scanner names the
/// substance at the improved tier (scannable = SCANNABLE_ADVANCED); the cue never does.
/datum/reagent/contaminant/proc/feel_unwell(mob/living/carbon/M)
	if(M.stat != CONSCIOUS || !prob(10))
		return
	to_chat(M, span_warning(pick("You feel queasy.", "Your stomach turns for a moment.", "You feel a little off, as if something you took disagreed with you.")))

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
	feel_unwell(M)
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
	feel_unwell(M)
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
		feel_unwell(M)
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
	effect_text = "Poisons the liver, strongly even at a trace."
	source_weight = 2
	organ = O_LIVER
	rate = 0.8
	filter_floor = 0.005

/datum/reagent/contaminant/toxic/sulfur
	name = REAGENT_CONTAMINANT_SULFUR
	id = REAGENT_ID_CONTAMINANT_SULFUR
	description = "Sulfides and sulfates carried over from refining."
	boiling_point = T0C + 445
	effect_text = "Slowly damages the kidneys."
	source_weight = 2
	organ = O_KIDNEYS
	rate = 0.15
	filter_floor = 0.01

/datum/reagent/contaminant/toxic/organic_residue
	name = REAGENT_CONTAMINANT_ORGANIC_RESIDUE
	id = REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE
	description = "Solvent and by-product left in the batch."
	boiling_point = T0C + 250
	effect_text = "A mild, general toxin."
	source_weight = 3
	rate = 0.1
	filter_floor = 0.01

/datum/reagent/contaminant/toxic/salts
	name = REAGENT_CONTAMINANT_SALTS
	id = REAGENT_ID_CONTAMINANT_SALTS
	description = "Dissolved salts from neutralisation and washing."
	boiling_point = BOILING_POINT_NEVER
	effect_text = "Strains the kidneys, lightly."
	source_weight = 3
	organ = O_KIDNEYS
	rate = 0.06
	filter_floor = 0.02

/datum/reagent/contaminant/reactive/acid_residue
	name = REAGENT_CONTAMINANT_ACID_RESIDUE
	id = REAGENT_ID_CONTAMINANT_ACID_RESIDUE
	description = "Unneutralised acid left from the reaction."
	boiling_point = T0C + 160
	effect_text = "Occasionally burns on contact with tissue."
	source_weight = 1.5
	rate = 0.5
	burn_chance = 20
	filter_floor = 0.01

/datum/reagent/contaminant/reactive/base_residue
	name = REAGENT_CONTAMINANT_BASE_RESIDUE
	id = REAGENT_ID_CONTAMINANT_BASE_RESIDUE
	description = "Unneutralised base left from the reaction."
	boiling_point = T0C + 300
	effect_text = "Occasionally burns on contact with tissue."
	source_weight = 1.5
	rate = 0.5
	burn_chance = 20
	filter_floor = 0.01

/datum/reagent/contaminant/inert/oily_residue
	name = REAGENT_CONTAMINANT_OILY_RESIDUE
	id = REAGENT_ID_CONTAMINANT_OILY_RESIDUE
	description = "Lubricant and fat carried through the process."
	boiling_point = T0C + 350
	effect_text = "Harmless, but takes up room in the dose."
	source_weight = 3
	filter_floor = 0.008

/datum/reagent/contaminant/inert/inert_filler
	name = REAGENT_CONTAMINANT_INERT_FILLER
	id = REAGENT_ID_CONTAMINANT_INERT_FILLER
	description = "Binder and bulk that does nothing."
	boiling_point = BOILING_POINT_NEVER
	effect_text = "Harmless, but takes up room in the dose."
	source_weight = 4
	reagent_state = SOLID

/datum/reagent/contaminant/biological/endotoxin
	name = REAGENT_CONTAMINANT_BIOLOGICAL
	id = REAGENT_ID_CONTAMINANT_BIOLOGICAL
	description = "Bacterial remnants from a poorly kept batch."
	boiling_point = BOILING_POINT_NEVER
	effect_text = "A toxin that also raises the patient's temperature, strongly even at a trace."
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD
	source_weight = 0.5
	rate = 0.6
	fever = 12
	filter_floor = 0.01

/datum/reagent/contaminant/reactive/reactive_impurity
	name = REAGENT_CONTAMINANT_REACTIVE
	id = REAGENT_ID_CONTAMINANT_REACTIVE
	description = "An unstable by-product."
	boiling_point = T0C + 60
	effect_text = "Occasionally burns the patient."
	source_weight = 1
	rate = 0.6
	burn_chance = 15
	filter_floor = 0.01

// ---- the trace-potent contaminants: made by processes (code/content/reagents/blocks/processes.dm), carried by no source, one clear symptom each, strong at a trace ----

/// Peroxide: left by a hot, uncatalysed oxidation. Detonates when the container is heated (detonate_peroxide()).
/datum/reagent/contaminant/reactive/peroxide
	name = REAGENT_CONTAMINANT_PEROXIDE
	id = REAGENT_ID_CONTAMINANT_PEROXIDE
	description = "An organic peroxide, left by an oxidation that ran hot with nothing to steer it."
	boiling_point = T0C + 150
	effect_text = "Detonates when the container it is in is heated; burns tissue a little."
	source_weight = 0
	filter_floor = 0.004
	rate = 1.5
	burn_chance = 30

/// Methanol: left by a fermentation. Blinds.
/datum/reagent/contaminant/toxic/methanol
	name = REAGENT_CONTAMINANT_METHANOL
	id = REAGENT_ID_CONTAMINANT_METHANOL
	description = "Wood alcohol, a trace of which every fermentation makes."
	boiling_point = T0C + 65
	effect_text = "Destroys the eyes: blindness."
	source_weight = 0
	filter_floor = 0.01
	organ = O_EYES
	rate = 3

/// Plasticiser: left by a hot condensation of a ring. Slows the metabolism.
/datum/reagent/contaminant/plasticiser
	name = REAGENT_CONTAMINANT_PLASTICISER
	id = REAGENT_ID_CONTAMINANT_PLASTICISER
	description = "A diester that makes plastics supple and leaches out of them."
	contaminant_role = CONTAMINANT_ROLE_TOXIC
	boiling_point = T0C + 370
	effect_text = "Slows the metabolism: every drug in the blood clears more slowly."
	source_weight = 0
	filter_floor = 0.003
	factors = alist(STAT_METABOLISM_MULT = 0.6)

/// Tar: left by cracking and by decarboxylation. Coats the lungs.
/datum/reagent/contaminant/toxic/tar
	name = REAGENT_CONTAMINANT_TAR
	id = REAGENT_ID_CONTAMINANT_TAR
	description = "Heavy black residue of a chain broken apart by heat."
	boiling_point = T0C + 380
	effect_text = "Coats and strains the lungs."
	source_weight = 0
	filter_floor = 0.008
	organ = O_LUNGS
	rate = 1

/// Dioxin: left by a hot halogenation of a ring that carries a hydroxyl. Eats lesions into the skin.
/datum/reagent/contaminant/toxic/dioxin
	name = REAGENT_CONTAMINANT_DIOXIN
	id = REAGENT_ID_CONTAMINANT_DIOXIN
	description = "A chlorinated ring compound, made when a hot chlorination meets a phenol."
	boiling_point = T0C + 450
	effect_text = "Eats lesions into the skin."
	source_weight = 0
	filter_floor = 0.002
	rate = 3

/datum/reagent/contaminant/toxic/dioxin/affect_blood(mob/living/carbon/M, alien, removed)
	if(inert_for(M))
		return
	var/amount = removed * rate
	if(amount <= 0)
		return
	var/zone = null
	var/mob/living/carbon/human/H = M
	if(istype(H) && length(H.organs))
		zone = pick(H.organs)
	M.injure(INJURY_CORROSIVE, amount, zone, src, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	feel_unwell(M)
	if(GLOB.chem_trace)
		log_world("CHEM: [id] ([round(removed, 0.0001)]u metabolised) leaves a lesion on [M] for [round(amount, 0.0001)]")

/// Nitrosamine: left by a nitration of an amine. Slow genetic damage.
/datum/reagent/contaminant/toxic/nitrosamine
	name = REAGENT_CONTAMINANT_NITROSAMINE
	id = REAGENT_ID_CONTAMINANT_NITROSAMINE
	description = "A nitrosated amine, made when a nitrating acid meets one."
	boiling_point = T0C + 175
	effect_text = "Slowly damages the genes: cellular damage."
	source_weight = 0
	filter_floor = 0.002
	rate = 0.8

/datum/reagent/contaminant/toxic/nitrosamine/affect_blood(mob/living/carbon/M, alien, removed)
	if(inert_for(M))
		return
	var/amount = removed * rate
	if(amount <= 0)
		return
	M.injure(INJURY_CELLULAR, amount, source = src, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	feel_unwell(M)
	if(GLOB.chem_trace)
		log_world("CHEM: [id] ([round(removed, 0.0001)]u metabolised) damages the cells of [M] for [round(amount, 0.0001)]")
