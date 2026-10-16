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
//                       (set_body_effect_factors()), applied at full value.
//   /datum/species      `factor_baseline`, applied at full value.
//   /datum/trait        `factors`, folded into the species' baseline.
//   /datum/form         `factors`, applied at full value while worn.
//   /obj/item           `worn_factors`, applied while equipped outside the hands.
//
// The body holds each source's table as rows of that source on the mob (hold_table(), code/engine/stats/tables.dm); the stat engine composes the
// rows by each stat's rule and settles the stat var before the next line. The body re-reads every source in refresh_factors() whenever one of
// them changed (BODY_DIRTY_FACTORS is that trigger, never a stored bit): an affliction is added or removed or crosses a FACTOR_SEVERITY_BAND, a body
// effect changes, a factor reagent crosses a dose band, equipment with worn_factors moves, the form or species changes.
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

/// A body factor's source changed: the body re-reads its sources (a mob with no body has none).
/mob/living/proc/invalidate_factors()
	body?.invalidate(BODY_DIRTY_FACTORS)

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

/// The most times one refresh_factors() runs again because a source changed while it ran (a hook that adds an affliction, a snapshot that finds a
/// dose band crossed): a loop past it is reported and stops.
#define FACTOR_REFRESH_PASSES 8

/datum/body
	/// C12: reagent id -> dose band of every factor-contributing reagent at the
	/// last treatment snapshot, or null. A change here is what refreshes the factors.
	var/tmp/list/reagent_factor_bands
	/// A reagent holder changed since the bands were last compared (on_reagent_change() sets it and settles it at once).
	var/tmp/reagent_bands_pending = FALSE
	/// Above 0 while refresh_factors() runs: a trigger meanwhile asks for one more pass instead of starting a nested one.
	var/tmp/factor_refresh_depth = 0
	var/tmp/factor_refresh_again = FALSE
	/// TRUE once the first refresh_factors() pass has run.
	var/tmp/factors_primed = FALSE

PROC_SUMMARY(/datum/body/proc/refresh_factors) // writes the factor stats from the body's sources: a caller reads the stats it publishes, never the afflictions, effects and reagents this reads
/// The body's factor sources changed: re-read every one of them into the stat store. Each source holds its table as rows of its own
/// (hold_table()); a source that is gone, or whose table no longer names a stat, loses its rows; every stat that moved settles once, at the end.
/// A trigger that arrives while this runs (a hook on a stat that adds an affliction) is folded into one more pass, never a nested one.
/datum/body/proc/refresh_factors()
	if(!owner || QDELETED(owner))
		return
	if(factor_refresh_depth)
		factor_refresh_again = TRUE
		return
	factor_refresh_depth++
	var/passes = 0
	do
		factor_refresh_again = FALSE
		passes++
		if(hold_tables_begin(owner))
			for(var/datum/affliction/A as anything in afflictions)
				A.hold_factors(owner)
			owner.hold_effect_factors()
			owner.hold_stasis_factors()
			hold_reagent_factors()
			hold_plan_factors()
			// Only a factor the cached vitals or the physiology read dirties them; the first pass, which fills the factors in for the first time,
			// dirties them whichever factor moved (they were cached against the baselines).
			var/list/moved = list()
			hold_tables_end(owner, moved)
			var/everything = !factors_primed
			factors_primed = TRUE
			for(var/stat_id in moved)
				if(everything || (stat_id in GLOB.factor_vitals_stats))
					invalidate(BODY_DIRTY_VITALS | BODY_DIRTY_PHYSIOLOGY)
					break
		if(passes >= FACTOR_REFRESH_PASSES && factor_refresh_again)
			stack_trace("refresh_factors() of [owner.type] is still being asked to run again after [passes] passes")
			break
	while(factor_refresh_again)
	factor_refresh_depth--

/// The factor stats the cached vitals and the physiology read: pain and consciousness read analgesia, pain, sedation and pain immunity; the physiology reads
/// the oxygen-transport chain (airway, drive, lungs, exchange, pump, circulation, demand, carriage, uptake, stabilisation) and the readouts it writes
/// (heart rate, pressures, saturation, breathing rate). A change of any other factor leaves them as they are.
GLOBAL_LIST_INIT(factor_vitals_stats, list(STAT_AIRWAY, STAT_RESP_DRIVE, STAT_LUNG_MECHANICS, STAT_GAS_EXCHANGE, STAT_PUMP, STAT_CIRCULATION, STAT_DEMAND, STAT_O2_CARRIAGE, STAT_TISSUE_UPTAKE, STAT_STABILIZATION, STAT_HEART_RATE, STAT_BP_SYSTOLIC, STAT_BP_DIASTOLIC, STAT_O2_SAT, STAT_RESP_RATE, STAT_ANALGESIA, STAT_PAIN, STAT_SEDATION, STAT_PAIN_IMMUNITY))

/// Resolves a pending reagent change now (C12): the volumes are read again and the dose bands compared, so the factors follow a reagent the moment
/// its holder changes. The treatment snapshot stays stale; it rebuilds when something asks for it.
/datum/body/proc/settle_reagent_factors()
	if(!reagent_bands_pending)
		return
	set_reagent_volumes(collect_reagent_volumes(reagent_volumes))
	update_reagent_factor_bands()

/// C12: compare each factor reagent's dose band with the last snapshot's and
/// refresh the factors only on a band crossing, or when a factor reagent appears
/// or leaves. Called by build_treatment_snapshot() with fresh volumes.
/datum/body/proc/update_reagent_factor_bands()
	set_reagent_bands_pending(FALSE)
	var/list/bands = null
	for(var/reagent_id in reagent_volumes)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[reagent_id]
		if(!R || !R.contributes_factors(owner))
			continue
		LAZYSET(bands, reagent_id, reagent_factor_band(reagent_volumes[reagent_id]))
	var/list/old = reagent_factor_bands
	set_reagent_factor_bands(bands)
	if(!reagent_bands_equal(old, bands))
		invalidate(BODY_DIRTY_FACTORS)

/datum/body/proc/reagent_bands_equal(list/a, list/b)
	if(length(a) != length(b))
		return FALSE
	for(var/reagent_id in a)
		if(!(reagent_id in b) || a[reagent_id] != b[reagent_id])
			return FALSE
	return TRUE

/// Dose band of `volume` for factor refreshing (DQ_CHEM_FACTOR_BAND of the dose scale).
/proc/reagent_factor_band(volume)
	return round(dq_chem_dose_scale(volume) / DQ_CHEM_FACTOR_BAND)

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

/// Reagent contributions: each reagent's table at its dose scale (from the
/// treatment snapshot's volumes).
/datum/body/proc/hold_reagent_factors()
	if(!reagent_volumes)
		return
	for(var/reagent_id in reagent_volumes)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[reagent_id]
		if(!R)
			continue
		var/alist/table = R.get_factors(owner)
		var/scale = dq_chem_dose_scale(reagent_volumes[reagent_id])
		// B2: the reagent's own table obeys the same gates as on_mob_life; the
		// patient-side contributions (allergy, blood rebuild) still apply.
		if(length(table) && scale > 0 && R.acts_on_body(owner))
			hold_reagent_table(R, table, scale)
		R.hold_special_factors(owner, reagent_volumes[reagent_id])

/// One reagent table. Plans scale individual factors (a species' analgesic
/// sensitivity) by overriding this.
/datum/body/proc/hold_reagent_table(datum/reagent/R, alist/table, scale)
	hold_table(owner, R, table, scale)

/// Plan-specific sources: species, traits, form, worn equipment. Base: none.
/datum/body/proc/hold_plan_factors()
	return


// --- Source tables -------------------------------------------------------------------

/datum/affliction
	/// Body factors at severity 100, scaled by severity (stat id -> value).
	var/alist/factors
	/// Severity band the factors were last read at.
	var/tmp/factor_band = -1

/// Holds the table this affliction contributes now. A staged affliction uses its
/// active stage's "factors" (applied at full value; a stage without one
/// contributes nothing); otherwise `factors`, scaled by severity.
/datum/affliction/proc/hold_factors(mob/living/L)
	factor_band = round(severity / FACTOR_SEVERITY_BAND)
	if(stage)
		var/list/stages = TYPE_TABLE_GET(src, affliction_stages)
		var/list/entry = stages?[stage]
		if(entry)
			hold_table(L, src, entry["factors"], 1)
			return
	hold_table(L, src, factors, severity / AFFLICTION_SEVERITY_TERMINAL)

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
/// the reaction itself is `hold_special_factors`).
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
			if(!C.synth_reag_processing)
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
/// patient-side contribution in hold_special_factors().) Reagents that
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

/// Contributions that depend on the patient rather than the reagent: the
/// mob's allergies, and blood rebuilt from its own blood reagent. Held at
/// every factor refresh with the reagent's volume across the mob's holders,
/// each as a part of the reagent's own rows.
/datum/reagent/proc/hold_special_factors(mob/living/L, volume)
	if(!ishuman(L) || volume <= 0)
		return
	var/mob/living/carbon/human/H = L
	var/scale = dq_chem_dose_scale(volume)
	if((H.species.allergens & allergen_type) || (H.species.medallergens & medallergen_type))
		// REM: the old per-tick reaction came from the ~REM units metabolised.
		var/static/alist/allergy = alist(STAT_ALLERGY = REM)
		hold_table(L, src, allergy, allergen_factor * scale, 1, "allergy")
	if(id == H.species.blood_reagents)
		var/static/alist/blood_rebuild = alist(STAT_BLOOD_REGEN = 1.6)
		hold_table(L, src, blood_rebuild, scale, 1, "blood")

/// Reagent tag (IS_*) the mob metabolises as, or null.
/mob/living/proc/reagent_tag()
	return null

/mob/living/carbon/human/reagent_tag()
	return species?.reagent_tag

/datum/form
	/// Body factors applied at full value while this form is worn.
	var/alist/factors

/obj/item
	/// Body factors applied while this item is equipped outside the hands.
	var/alist/worn_factors

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
