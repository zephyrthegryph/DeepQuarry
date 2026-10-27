// Body factors: the body's stats (doc/rewrite/final_api.html section 5; doc/rewrite/proposals/stat_layer.md).
// Every factor is a stat declared on /mob/living (code/contracts/ids/body_stats.dm) with a var of its own, the value the stat engine composes
// (code/engine/stats). The ids of the old stat ids space translate to them in code/modules/body/factor_compat.dm.
//
// Sources declare STATIC tables (stat id -> value), never per-tick code:
//   /datum/affliction   `factors`, value at severity 100, scaled by severity.
//                       A stage entry's "factors" replaces the table and is
//                       applied at full value (the stage is the severity band).
//   /datum/reagent      `factors`, value at the standard dose, scaled by the
//                       dose curve (dq_chem_dose_scale). get_factors(L) may
//                       return another static table per species.
//   /datum/body_effect  `factors` (per stack), or the application's own table
//                       (set_body_effect_factors() sets it on the application's record), applied at full value.
//   /datum/species      `factor_baseline`, applied at full value.
//   /datum/trait        `factors`, folded into the species' baseline.
//   /datum/form         `factors`, applied at full value while worn.
//   /obj/item           `worn_factors`, applied while equipped outside the hands.
//
// Every source holds its own table with a factors() entry in its type's CAPABILITIES block (code/engine/stats/contributes.dm): the engine holds it on the
// entity its relation names (hold_table()) at the exact current scale and releases it with the relation or the source, and the stat settles before the
// writer's next line. Stasis holds (code/modules/medical/stabilisation/stasis.dm), body effect applications (the /datum/body_effect_origin record,
// body_effects.dm), afflictions (affliction.dm) and reagent doses (/datum/reagent_dose, below) read what they contribute through their relations. The plan's
// own sources (species baseline and grants, the form, worn items) are /datum/factor_source records the body keeps in step with them (sync_species_factors(),
// sync_form_factors() and sync_worn_factors(), called where those change).
//
// Read a factor as the var of its stat: `L.slowdown`.

/datum/body_factor_def
	var/id
	var/name
	/// Book text: what the factor does.
	var/desc
	/// How the book prints a value: "percent" (multipliers), "points",
	/// "flag" (on/off), "flags" (bitfield).
	var/format = "points"

/datum/body_factor_def/New(id, name, format, desc)
	..()
	src.id = id
	src.name = name
	src.format = format
	src.desc = desc

/// stat ids -> /datum/body_factor_def (the book's names and texts). Built once; a factor that was deleted has no entry.
/proc/build_body_factor_defs()
	var/alist/defs = alist()
	var/list/rows = list( // ALLOW(sys_const_list_alloc): input rows of a one-shot table builder, runs once
		// id, name, format, desc
		list(STAT_AIRWAY, "Airway", "percent", "How open the airway is."),
		list(STAT_RESP_DRIVE, "Breathing drive", "percent", "The drive to breathe unaided."),
		list(STAT_LUNG_MECHANICS, "Lung expansion", "percent", "How well the chest and lungs expand."),
		list(STAT_GAS_EXCHANGE, "Gas exchange", "percent", "How well the lungs exchange gas."),
		list(STAT_PUMP, "Cardiac output", "percent", "How much blood (or power) the heart moves."),
		list(STAT_CIRCULATION, "Circulation", "percent", "Vascular tone and circulation."),
		list(STAT_DEMAND, "Metabolic demand", "percent", "How much oxygen and fuel the tissues need."),
		list(STAT_PROGRESSION, "Affliction progression", "percent", "How fast conditions worsen."),
		list(STAT_METABOLISM_MULT, "Metabolism", "percent", "How fast reagents are processed and hunger grows."),
		list(STAT_BLEEDING, "Bleeding", "percent", "How fast wounds bleed."),
		list(STAT_HEALING, "Natural healing", "percent", "Natural regeneration."),
		list(STAT_ANALGESIA, "Analgesia", "points", "Pain relief."),
		list(STAT_PAIN, "Pain", "points", "Extra pain."),
		list(STAT_SEDATION, "Sedation", "points", "Lowered consciousness."),
		list(STAT_HEART_RATE, "Heart rate", "bpm", "Change in heart rate."),
		list(STAT_TEMPERATURE, "Temperature", "°C", "Change in core temperature."),
		list(STAT_BP_SYSTOLIC, "Systolic pressure", "mmHg", "Change in systolic blood pressure."),
		list(STAT_BP_DIASTOLIC, "Diastolic pressure", "mmHg", "Change in diastolic blood pressure."),
		list(STAT_O2_SAT, "Oxygen saturation", "%", "Change in blood oxygen saturation."),
		list(STAT_RESP_RATE, "Breathing rate", "/min", "Change in breaths per minute."),
		list(STAT_SLOWDOWN, "Slowdown", "points", "Movement delay; negative is faster."),
		list(STAT_ITEM_ENCUMBRANCE, "Item encumbrance", "points", "Movement delay from the weight of worn and held equipment."),
		list(STAT_PENALTY_SCALE, "Movement penalties", "percent", "Scale on every movement penalty."),
		list(STAT_HASTE, "Haste", "flag", "Ignores every slowdown."),
		list(STAT_ACCURACY, "Accuracy", "%", "Ranged accuracy."),
		list(STAT_DISPERSION, "Dispersion", "points", "How widely shots stray."),
		list(STAT_EVASION, "Evasion", "%", "Chance for attacks to miss."),
		list(STAT_ATTACK_SPEED, "Attack delay", "percent", "Delay between attacks."),
		list(STAT_MELEE_DAMAGE, "Melee damage", "percent", "Damage dealt in melee and unarmed."),
		list(STAT_MOTOR_CONTROL, "Motor control", "percent", "Fine motor control; poor control drops held items."),
		list(STAT_DARKSIGHT, "Darksight", "flag", "Sees in the dark."),
		list(STAT_SIGHT_FLAGS, "Special sight", "flags", "Sees through walls."),
		list(STAT_ACTION_BLOCKS, "Blocked actions", "flags", "Actions that can't be performed."),
		list(STAT_INCOMING_ALL, "Injury taken", "percent", "Every injury taken."),
		list(STAT_INCOMING_PHYSICAL, "Physical injury taken", "percent", "Blunt, cutting and piercing injury taken."),
		list(STAT_INCOMING_THERMAL, "Thermal injury taken", "percent", "Burn, frostbite, corrosive and electrical injury taken."),
		list(STAT_INCOMING_TOXIC, "Toxic injury taken", "percent", "Poisoning taken."),
		list(STAT_INCOMING_GENETIC, "Genetic injury taken", "percent", "Radiation and cellular injury taken."),
		list(STAT_INCOMING_NEURAL, "Neural injury taken", "percent", "Neural injury taken."),
		list(STAT_INCOMING_PAIN, "Pain taken", "percent", "Pain inflicted by weapons."),
		list(STAT_DISABLE_DURATION, "Disable duration", "percent", "How long stuns and knockdowns last."),
		list(STAT_HEALING_RECEIVED, "Healing received", "percent", "Strength of every treatment received."),
		list(STAT_ENDURANCE_FLAT, "Endurance", "points", "Toughness."),
		list(STAT_ENDURANCE_MULT, "Endurance scale", "percent", "Toughness."),
		list(STAT_SCALE_MULT_X, "Width", "percent", "Sprite width."),
		list(STAT_SCALE_MULT_Y, "Height", "percent", "Sprite height."),
		list(STAT_PAIN_IMMUNITY, "Pain immunity", "flag", "Feels no pain."),
		list(STAT_PULSE_SHIFT, "Pulse shift", "points", "Shifts the pulse up or down."),
		list(STAT_PULSE_SET, "Forced pulse", "points", "Forces the pulse to a level."),
		list(STAT_EMP_SHIFT, "EMP resistance", "points", "Weakens EMPs (higher is weaker)."),
		list(STAT_EXPLOSION_SHIFT, "Blast resistance", "points", "Weakens explosions (higher is weaker)."),
		list(STAT_HEAT_EXPOSURE, "Heat exposure", "percent", "Share of environmental heat that reaches the body."),
		list(STAT_COLD_EXPOSURE, "Cold exposure", "percent", "Share of environmental cold that reaches the body."),
		list(STAT_SIEMENS, "Conductivity", "percent", "Electrical conductivity."),
		list(STAT_STABILIZATION, "Stabilisation", "points", "Keeps the heart and breathing stable in crisis."),
		list(STAT_ANTIMICROBIAL, "Antimicrobial", "points", "Fights infection."),
		list(STAT_BLOOD_REGEN, "Blood regeneration", "points", "Blood rebuilt per tick."),
		list(STAT_INTOXICATION, "Intoxication", "points", "Alcohol intoxication."),
		list(STAT_HEPATOTOXICITY, "Liver toxicity", "points", "Alcohol poisoning of the liver."),
		list(STAT_ANTIEMETIC, "Antiemetic", "points", "Suppresses vomiting."),
		list(STAT_ALLERGY, "Allergic reaction", "points", "Strength of an allergic reaction."),
		list(STAT_WITHDRAWAL, "Withdrawal", "points", "Withdrawal strain on the organs."),
		list(STAT_NEURAL_REPAIR, "Neural repair", "points", "Extra brain repair per tick."),
		list(STAT_IMMUNE_SUPPRESSION, "Immune suppression", "points", "Suppresses the immune response."),
		list(STAT_O2_CARRIAGE, "Oxygen carriage", "percent", "How much oxygen the blood carries."),
		list(STAT_TISSUE_UPTAKE, "Tissue oxygen uptake", "percent", "How well the tissues use the oxygen that reaches them."),
		list(STAT_STASIS, "Stasis", "points", "Share of life processes suspended: conditions, metabolism and breathing slow by this much."),
		list(STAT_CARDIAC_IRRITABILITY, "Cardiac irritability", "percent", "How fast a disordered heart rhythm deteriorates: an unstable rhythm tips into fibrillation and fibrillation fades to a flatline this much sooner."),
	)
	for(var/list/row as anything in rows)
		defs[row[1]] = new /datum/body_factor_def(row[1], row[2], row[3], row[4])
	var/static/list/armor_stats = list(STAT_ARMOR_BLUNT, STAT_ARMOR_CUT, STAT_ARMOR_PIERCE, STAT_ARMOR_BURN, STAT_ARMOR_FROSTBITE, STAT_ARMOR_CORROSIVE, STAT_ARMOR_ELECTRIC, STAT_ARMOR_TOXIN, STAT_ARMOR_RADIATION, STAT_ARMOR_CELLULAR, STAT_ARMOR_NEURAL, STAT_ARMOR_PAIN, STAT_ARMOR_DIGESTION, STAT_ARMOR_BLAST)
	for(var/kind in 1 to ARMOR_KIND_COUNT)
		var/kind_name = armor_kind_name(kind)
		defs[armor_stats[kind]] = new /datum/body_factor_def(armor_stats[kind], "[capitalize(kind_name)] armour", "points", "Extra armour against [kind_name] harm.")
	return defs

GLOBAL_TABLE(body_factor_defs, GLOBAL_PROC_REF(build_body_factor_defs))


// --- Mob-side queries ----------------------------------------------------------

/// Is `block` (ACTION_BLOCK_*) set on this mob?
/mob/living/proc/action_blocked(block)
	return (action_blocks & block) ? TRUE : FALSE

/// Incoming multiplier for an INJURY_CATEGORY_*: the overall and the
/// per-category factor.
/mob/living/proc/incoming_injury_factor(category)
	. = incoming_all
	switch(category)
		if(INJURY_CATEGORY_PHYSICAL)
			. *= incoming_physical
		if(INJURY_CATEGORY_THERMAL)
			. *= incoming_thermal
		if(INJURY_CATEGORY_TOXIC)
			. *= incoming_toxic
		if(INJURY_CATEGORY_GENETIC)
			. *= incoming_genetic
		if(INJURY_CATEGORY_NEURAL)
			. *= incoming_neural
		if(INJURY_CATEGORY_PAIN)
			. *= incoming_pain

// --- Body side ---------------------------------------------------------------------

/datum/body
	/// Reagent id -> its /datum/reagent_dose, one for every reagent in the body that can change a factor (the body owns them). Lazy.
	var/list/reagent_doses
	/// A reagent holder changed since the volumes were last read (on_reagent_change() sets it and settles it at once).
	var/tmp/reagent_change_pending = FALSE
	/// Key (FACTOR_SOURCE_*) -> the plan's /datum/factor_source of it (the body owns them). Lazy.
	var/list/factor_sources

/// A source's own factors() entry held or released a table on this mob (code/engine/stats/contributes.dm): the vitals and the physiology are dirty when a stat they
/// read moved.
/mob/living/factors_held(list/moved)
	if(!body)
		return
	for(var/stat_id in moved)
		if(stat_id in GLOB.factor_vitals_stats)
			body.invalidate(BODY_DIRTY_VITALS | BODY_DIRTY_PHYSIOLOGY)
			return

/// The factor stats the cached vitals and the physiology read: pain and consciousness read analgesia, pain, sedation and pain immunity; the physiology reads
/// the oxygen-transport chain (airway, drive, lungs, exchange, pump, circulation, demand, carriage, uptake, stabilisation) and the readouts it writes
/// (heart rate, pressures, saturation, breathing rate). A change of any other factor leaves them as they are.
GLOBAL_LIST_INIT(factor_vitals_stats, list(STAT_AIRWAY, STAT_RESP_DRIVE, STAT_LUNG_MECHANICS, STAT_GAS_EXCHANGE, STAT_PUMP, STAT_CIRCULATION, STAT_DEMAND, STAT_O2_CARRIAGE, STAT_TISSUE_UPTAKE, STAT_STABILIZATION, STAT_HEART_RATE, STAT_BP_SYSTOLIC, STAT_BP_DIASTOLIC, STAT_O2_SAT, STAT_RESP_RATE, STAT_ANALGESIA, STAT_PAIN, STAT_SEDATION, STAT_PAIN_IMMUNITY))

/// Resolves a pending reagent change now: the volumes are read again and the doses follow, so the factors follow a reagent the moment its holder changes.
/// The treatment snapshot stays stale; it rebuilds when something asks for it.
/datum/body/proc/settle_reagent_factors()
	if(!reagent_change_pending)
		return
	refresh_reagent_volumes()
	sync_reagent_doses()

/// Reads the volumes of every reagent in the mob's holders into reagent_volumes and tells what reads them (each dose record follows its volume).
/datum/body/proc/refresh_reagent_volumes()
	var/list/volumes = collect_reagent_volumes(reagent_volumes)
	if(volumes && volumes == reagent_volumes)
		// Refilled in place (collect_reagent_volumes() reuses the list): the setter would see the same list, so the write is announced by hand.
		tracked_changed(src, nameof(reagent_volumes))
	else
		set_reagent_volumes(volumes)

/// One dose record for each reagent in the body that can change a factor (contributes_factors()), and none for the rest: a reagent that appears gets
/// its record, one that leaves loses it, and a record's rows go with it. Called with fresh volumes.
/datum/body/proc/sync_reagent_doses()
	reagent_change_pending = FALSE
	for(var/reagent_id in reagent_volumes)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[reagent_id]
		var/wanted = R && R.contributes_factors(owner)
		var/datum/reagent_dose/existing = reagent_doses?[reagent_id]
		if(wanted && !existing)
			var/datum/reagent_dose/D = new
			D.set_reagent_id(reagent_id)
			rel_set(D, nameof(D.body), src)
			rel_set(D, nameof(D.holder), owner)
			rel_add(src, nameof(reagent_doses), D, reagent_id)
		else if(!wanted && existing)
			rel_add(src, nameof(reagent_doses), null, reagent_id)
	for(var/reagent_id in reagent_doses?.Copy())
		if(!(reagent_id in reagent_volumes))
			rel_add(src, nameof(reagent_doses), null, reagent_id)

/// Per-tick consequences of the current factors: poor motor control drops
/// held items, blocked hands can't hold anything.
/datum/body/proc/tick_factor_effects()
	if(!ishuman(owner) || owner.is_dead())
		return
	var/mob/living/carbon/human/H = owner
	var/blocks = H.action_blocks
	if((blocks & ACTION_BLOCK_HOLD_LEFT) && H.get_equipped_item(SLOT_ID_HAND_L))
		to_chat(H, span_warning("Your left hand won't close around \the [H.get_equipped_item(SLOT_ID_HAND_L)]."))
		H.drop_l_hand()
	if((blocks & ACTION_BLOCK_HOLD_RIGHT) && H.get_equipped_item(SLOT_ID_HAND_R))
		to_chat(H, span_warning("Your right hand won't close around \the [H.get_equipped_item(SLOT_ID_HAND_R)]."))
		H.drop_r_hand()
	var/motor = H.motor_control
	if(motor < 1 && prob(min(FACTOR_MAX_DROP_CHANCE, (1 - motor) * 100)))
		dq_drop_random_held(H)

/// Does the body's tick have a factor effect to apply (a hand that can't hold, poor motor control)?
/datum/body/proc/factor_effects_due()
	return (owner.action_blocks || owner.motor_control < 1) ? TRUE : FALSE

/// One of the plan's sources (the species baseline, a table a trait granted it, the form, a worn item): the table it had when the body last read it, held on the mob
/// as rows of this record. The body owns it under its key (factor_sources, set_factor_source()) and it goes when the source has no table.
/datum/factor_source
	/// The mob it is on: a relation view.
	var/mob/living/holder
	/// The source's table (stat id -> value), held at full value.
	var/alist/table

CAPABILITIES(/datum/factor_source)
	ref_one(nameof(holder), /mob/living)
	factors(nameof(table), rel = nameof(holder))

/// Sets the table of the plan source `key`: its record is made if it has none, and ends when the table is empty.
/datum/body/proc/set_factor_source(key, alist/table)
	var/datum/factor_source/S = factor_sources?[key]
	if(!length(table))
		if(S)
			rel_add(src, nameof(factor_sources), null, key)
		return
	if(!S)
		S = new
		rel_set(S, nameof(S.holder), owner)
		rel_add(src, nameof(factor_sources), S, key)
	S.set_table(table)

/// Ends every plan source whose key starts with `prefix` and is not in `keep` (a list of keys).
/datum/body/proc/drop_factor_sources(prefix, list/keep)
	for(var/key in factor_sources?.Copy())
		if(findtext(key, prefix) == 1 && !(key in keep))
			rel_add(src, nameof(factor_sources), null, key)

/// Plan-specific sources, read when they change. Base: none.
/datum/body/proc/sync_species_factors()
	return

/datum/body/proc/sync_form_factors()
	return

/datum/body/proc/sync_worn_factors()
	return


// --- Source tables -------------------------------------------------------------------

/datum/affliction
	/// Body factors at severity 100, scaled by severity (stat id -> value).
	var/alist/factors

/// The table this affliction contributes now (the factors() entry in its CAPABILITIES block, code/modules/body/affliction.dm). A staged affliction uses its
/// active stage's "factors" (a stage without one contributes nothing); otherwise `factors`.
/datum/affliction/proc/factor_table(datum/act/eval/A)
	if(stage)
		var/list/stages = TYPE_TABLE_GET(src, affliction_stages)
		var/list/entry = stages?[stage]
		if(entry)
			return entry["factors"]
	return factors

/// The scale of factor_table(): a stage's table is applied at full value (the stage is the severity band), `factors` scales with severity.
/datum/affliction/proc/factor_scale(datum/act/eval/A)
	if(stage)
		var/list/stages = TYPE_TABLE_GET(src, affliction_stages)
		if(stages?[stage])
			return 1
	return severity / AFFLICTION_SEVERITY_TERMINAL

/datum/reagent
	/// Body factors at the standard dose (DQ_CHEM_STANDARD_DOSE), scaled by
	/// the dose curve. stat id -> value.
	var/alist/factors
	/// Per-species replacements for `factors`: reagent tag (IS_*) -> table.
	/// A tag mapped to null gets nothing (diona ignore most drugs).
	var/alist/species_factors

/// The table this reagent contributes to `L`: `factors`, with its species' entry in
/// `species_factors` merged over it (B19: an entry overrides the factors it names and keeps the
/// rest; it used to replace the whole table). A species mapped to null gets nothing.
/datum/reagent/proc/get_factors(mob/living/L)
	if(species_factors)
		var/tag = L.reagent_tag()
		if(!isnull(tag) && (tag in species_factors))
			return merged_species_factors(tag)
	return factors

/// `factors` with species `tag`'s overrides on top; built once per reagent type and tag.
/datum/reagent/proc/merged_species_factors(tag)
	var/alist/over = species_factors[tag]
	if(isnull(over))
		return null
	if(!length(factors))
		return over
	return CACHED_KEY(reagent_merged_species_factors, "[type]|[tag]", factors, over)

DECLARE_SHARED_CACHE(reagent_merged_species_factors, GLOBAL_PROC_REF(build_reagent_merged_species_factors), SC_NEVER)

/// A reagent type's factors overlaid with one species tag's overrides.
/proc/build_reagent_merged_species_factors(alist/factors, alist/over)
	var/alist/merged = alist()
	for(var/id in factors)
		merged[id] = factors[id]
	for(var/id in over)
		merged[id] = over[id]
	return merged

/// B2: the one gate for whether a reagent's own effects (treatment tags,
/// body factors) reach this mob — the same rules `on_mob_life` applies: dead
/// bodies, synthetic processing, and medical allergy (which gives no benefit;
/// the reaction itself is special_table()).
/datum/reagent/proc/acts_on_body(mob/living/L)
	if(!L)
		return FALSE
	// P2-S13: a species that ignores the reagent by every route gets none of its tags or factors.
	if(species_immune(L))
		return FALSE
	if(!affects_dead && L.stat == DEAD && !L.has_body_effect(/datum/body_effect/bloodpump_corpse))
		return FALSE
	if(HAS_SYNTHETIC_BIOLOGY(L))
		if(!affects_robots)
			return FALSE
		if(iscarbon(L))
			var/mob/living/carbon/C = L
			if(!sparse_get_or(C, synth_reag_processing, TRUE))
				return FALSE
	if(ishuman(L))
		var/mob/living/carbon/human/H = L
		if(H.species?.medallergens & medallergen_type)
			return FALSE
	return TRUE

/proc/dq_reagent_acts_on(reagent_id, mob/living/L)
	var/datum/reagent/R = SSchemistry.ready().chemical_reagents[reagent_id]
	return R ? R.acts_on_body(L) : FALSE

/// C12: can this reagent change `L`'s body factors at all? (Its own table, or a
/// patient-side contribution in special_table().) Reagents that
/// can't never refresh the factors when their dose moves.
/datum/reagent/proc/contributes_factors(mob/living/L)
	if(length(get_factors(L)))
		return TRUE
	if(ishuman(L))
		var/mob/living/carbon/human/H = L
		if((H.species.allergens & allergen_type) || (H.species.medallergens & medallergen_type))
			return TRUE
		if(id == H.species.blood_reagents)
			return TRUE
	return FALSE

/// Contributions that depend on the patient rather than the reagent: the mob's allergies, blood rebuilt from its own blood reagent (the base reagent), and
/// intoxication and liver toxicity (ethanol). Each is one part of the reagent's dose record (REAGENT_PART_*, /datum/reagent_dose): this is the part's table
/// for `L` at `volume` of the reagent in its system, or null for none.
/datum/reagent/proc/special_table(part, mob/living/L, volume)
	if(!ishuman(L) || volume <= 0)
		return null
	var/mob/living/carbon/human/H = L
	switch(part)
		if(REAGENT_PART_ALLERGY)
			// REM: the old per-tick reaction came from the ~REM units metabolised.
			var/static/alist/allergy = alist(STAT_ALLERGY = REM)
			if((H.species.allergens & allergen_type) || (H.species.medallergens & medallergen_type))
				return allergy
		if(REAGENT_PART_BLOOD)
			var/static/alist/blood_rebuild = alist(STAT_BLOOD_REGEN = 1.6)
			if(id == H.species.blood_reagents)
				return blood_rebuild
	return null

/// The scale of special_table(part) at `volume`.
/datum/reagent/proc/special_scale(part, volume)
	if(part == REAGENT_PART_ALLERGY)
		return allergen_factor * dq_chem_dose_scale(volume)
	return dq_chem_dose_scale(volume)

/// Reagent tag (IS_*) the mob metabolises as, or null.
/mob/living/proc/reagent_tag()
	return null

/mob/living/carbon/human/reagent_tag()
	return species?.reagent_tag

/// One reagent in a body that can change a factor: the dose the stat layer composes. The body owns it under the reagent id (reagent_doses, sync_reagent_doses()),
/// for as long as the reagent is in the mob's holders and contributes_factors(); its volume is read through `body` from the body's reagent_volumes, so the tables
/// follow the dose exactly. Its parts: the reagent's own table (gated like on_mob_life: acts_on_body()), the species' analgesic sensitivity (humanoids), and the
/// patient-side parts of special_table().
/datum/reagent_dose
	/// The reagent this is the dose of.
	var/reagent_id
	/// The mob it is in, and its body: relation views.
	var/mob/living/holder
	var/datum/body/body

CAPABILITIES(/datum/reagent_dose)
	ref_one(nameof(holder), /mob/living)
	ref_one(nameof(body), /datum/body)
	factors(PROC_REF(dose_table), scale = PROC_REF(dose_scale), rel = nameof(holder), reads = list("body.reagent_volumes"))
	factors(PROC_REF(strength_table), scale = PROC_REF(dose_scale), rel = nameof(holder), part = REAGENT_PART_STRENGTH, reads = list("body.reagent_volumes"))
	factors(PROC_REF(allergy_table), scale = PROC_REF(allergy_scale), rel = nameof(holder), part = REAGENT_PART_ALLERGY, reads = list("body.reagent_volumes"))
	factors(PROC_REF(blood_table), scale = PROC_REF(dose_scale), rel = nameof(holder), part = REAGENT_PART_BLOOD, reads = list("body.reagent_volumes"))
	factors(PROC_REF(intoxication_table), scale = PROC_REF(dose_scale), rel = nameof(holder), part = REAGENT_PART_INTOXICATION, reads = list("body.reagent_volumes"))
	factors(PROC_REF(hepatotoxicity_table), scale = PROC_REF(hepatotoxicity_scale), rel = nameof(holder), part = REAGENT_PART_HEPATOTOXICITY, reads = list("body.reagent_volumes"))

/datum/reagent_dose/proc/reagent_def()
	RETURN_TYPE(/datum/reagent)
	return SSchemistry.ready().chemical_reagents[reagent_id]

/// The reagent's volume across the mob's holders (the body's snapshot).
/datum/reagent_dose/proc/volume()
	return body?.reagent_volumes?[reagent_id] || 0

/datum/reagent_dose/proc/dose_scale(datum/act/eval/A)
	return dq_chem_dose_scale(volume())

/// The reagent's own table, when it acts on this mob (B2: the same gates as on_mob_life).
/datum/reagent_dose/proc/dose_table(datum/act/eval/A)
	var/datum/reagent/R = reagent_def()
	if(!R || !holder || !R.acts_on_body(holder))
		return null
	return R.get_factors(holder)

/// The humanoid plan's extra share of a reagent's analgesia (the species' analgesic sensitivity).
/datum/reagent_dose/proc/strength_table(datum/act/eval/A)
	var/alist/table = dose_table(A)
	return length(table) ? body.strength_table(table) : null

/datum/reagent_dose/proc/allergy_table(datum/act/eval/A)
	return reagent_def()?.special_table(REAGENT_PART_ALLERGY, holder, volume())

/datum/reagent_dose/proc/allergy_scale(datum/act/eval/A)
	return reagent_def()?.special_scale(REAGENT_PART_ALLERGY, volume()) || 0

/datum/reagent_dose/proc/blood_table(datum/act/eval/A)
	return reagent_def()?.special_table(REAGENT_PART_BLOOD, holder, volume())

/datum/reagent_dose/proc/intoxication_table(datum/act/eval/A)
	return reagent_def()?.special_table(REAGENT_PART_INTOXICATION, holder, volume())

/datum/reagent_dose/proc/hepatotoxicity_table(datum/act/eval/A)
	return reagent_def()?.special_table(REAGENT_PART_HEPATOTOXICITY, holder, volume())

/datum/reagent_dose/proc/hepatotoxicity_scale(datum/act/eval/A)
	return reagent_def()?.special_scale(REAGENT_PART_HEPATOTOXICITY, volume()) || 0

/// What a plan adds to a reagent table (its analgesia scaled by the species' sensitivity), or null. Base: nothing.
/datum/body/proc/strength_table(alist/table)
	return null

/datum/form
	/// Body factors applied at full value while this form is worn.
	var/alist/factors

/obj/item
	/// Body factors applied while this item is equipped outside the hands. STAT_ITEM_ENCUMBRANCE is how much the item slows its carrier (positive) or
	/// speeds them up (negative); it also counts while the item is held, when it slows (humanoid sync_worn_factors()).
	var/alist/worn_factors

/// The value of one of the item's worn factors, 0 when it has none.
/obj/item/proc/worn_factor(stat)
	return worn_factors?[stat] || 0

/// Sets one of the item's worn factors (0 removes it) and re-reads the body that carries the item. The table is replaced, never written, because a
/// type's table is shared.
/obj/item/proc/set_worn_factor(stat, value)
	var/alist/table = alist()
	for(var/key in worn_factors)
		table[key] = worn_factors[key]
	if(value)
		table[stat] = value
	else
		table -= stat
	worn_factors = length(table) ? table : null
	var/mob/living/carrier = loc
	if(istype(carrier))
		carrier.body?.sync_worn_factors()

// --- Book text -------------------------------------------------------------------------

/// Human-readable lines for a factor table, e.g. "Airway: -80%". `suffix`
/// is appended to each line (" at full severity", " at a standard dose").
/proc/body_factor_describe(alist/table, suffix = "")
	. = list()
	if(!length(table))
		return
	var/list/defs = GLOBAL_TABLE_GET(body_factor_defs)
	for(var/id in table)
		var/datum/body_factor_def/D = isnum(id) ? defs[id] : null
		if(!D)
			continue
		. += "[D.name]: [body_factor_format_value(D, table[id])][suffix]"

/proc/body_factor_format_value(datum/body_factor_def/D, value)
	switch(D.format)
		if("percent")
			var/delta = round((value - 1) * 100)
			return "[delta >= 0 ? "+" : ""][delta]%"
		if("flag")
			return value ? "yes" : "no"
		if("flags")
			return "set"
	var/rounded = round(value, 0.01)
	var/unit = D.format == "points" ? "" : " [D.format]"
	return "[rounded >= 0 ? "+" : ""][rounded][unit]"
