// Body factors: the unified stat layer (doc/health_system_review.md §5.3).
// Defines live in code/__defines/body_factors.dm.
//
// Sources declare STATIC tables, never per-tick code:
//   /datum/affliction   `factors`, value at severity 100, scaled by severity.
//                       A stage entry's "factors" replaces the table and is
//                       applied at full value (the stage is the severity band).
//   /datum/reagent      `factors`, value at the standard dose, scaled by the
//                       dose curve (dq_chem_dose_scale). get_factors(L) may
//                       return another static table per species.
//   /datum/modifier     `factors`, applied at full value.
//   /datum/species      `factor_baseline`, applied at full value.
//   /datum/trait        `factors`, folded into the species' baseline.
//   /datum/form         `factors`, applied at full value while worn.
//   /obj/item           `worn_factors`, applied while equipped outside the hands.
//
// The body keeps one flat cached list, `body.factors`, indexed by BF_*. It
// stays null while every factor is at baseline (most bodies). It is rebuilt
// only when marked dirty (BODY_DIRTY_FACTORS): an affliction is added or
// removed or crosses a BF_SEVERITY_BAND, a modifier changes, reagents change,
// equipment with worn_factors moves, the form or species changes.
//
// Read with `L.factor(BF_X)`.

/datum/body_factor_def
	var/id
	var/name
	var/rule = BF_RULE_ADD
	var/baseline = 0
	var/min_value = -INFINITY
	var/max_value = INFINITY
	/// Book text: what the factor does.
	var/desc
	/// How the book prints a value: "percent" (multipliers), "points",
	/// "flag" (on/off), "flags" (bitfield).
	var/format = "points"

/datum/body_factor_def/New(id, name, rule, baseline, min_value, max_value, format, desc)
	..()
	src.id = id
	src.name = name
	src.rule = rule
	src.baseline = baseline
	src.min_value = min_value
	src.max_value = max_value
	src.format = format
	src.desc = desc

/// BF_* -> /datum/body_factor_def. Built once.
/proc/body_factor_defs()
	var/static/list/defs
	if(defs)
		return defs
	defs = new /list(BF_COUNT)
	var/list/rows = list(
		// id, name, rule, baseline, min, max, format, desc
		list(BF_AIRWAY, "Airway", BF_RULE_MULT, 1, 0, 1, "percent", "How open the airway is."),
		list(BF_RESP_DRIVE, "Breathing drive", BF_RULE_MULT, 1, 0, 2, "percent", "The drive to breathe unaided."),
		list(BF_LUNG_MECHANICS, "Lung expansion", BF_RULE_MULT, 1, 0, 1, "percent", "How well the chest and lungs expand."),
		list(BF_GAS_EXCHANGE, "Gas exchange", BF_RULE_MULT, 1, 0, 1, "percent", "How well the lungs exchange gas."),
		list(BF_PUMP, "Cardiac output", BF_RULE_MULT, 1, 0, 2, "percent", "How much blood (or power) the heart moves."),
		list(BF_CIRCULATION, "Circulation", BF_RULE_MULT, 1, 0, 2, "percent", "Vascular tone and circulation."),
		list(BF_DEMAND, "Metabolic demand", BF_RULE_MULT, 1, 0, 4, "percent", "How much oxygen and fuel the tissues need."),
		list(BF_PROGRESSION, "Affliction progression", BF_RULE_MULT, 1, 0, 4, "percent", "How fast conditions worsen."),
		list(BF_METABOLISM, "Metabolism", BF_RULE_MULT, 1, 0, 10, "percent", "How fast reagents are processed and hunger grows."),
		list(BF_BLEEDING, "Bleeding", BF_RULE_MULT, 1, 0, 10, "percent", "How fast wounds bleed."),
		list(BF_HEALING, "Natural healing", BF_RULE_MULT, 1, 0, 10, "percent", "Natural regeneration."),
		list(BF_ANALGESIA, "Analgesia", BF_RULE_ADD, 0, -INFINITY, INFINITY, "points", "Pain relief."),
		list(BF_PAIN, "Pain", BF_RULE_ADD, 0, 0, INFINITY, "points", "Extra pain."),
		list(BF_SEDATION, "Sedation", BF_RULE_ADD, 0, 0, INFINITY, "points", "Lowered consciousness."),
		list(BF_ARRHYTHMIA_RISK, "Arrhythmia risk", BF_RULE_ADD, 0, 0, INFINITY, "points", "Risk that the heart rhythm deteriorates."),
		list(BF_HEART_RATE, "Heart rate", BF_RULE_ADD, 0, -INFINITY, INFINITY, "bpm", "Change in heart rate."),
		list(BF_TEMPERATURE, "Temperature", BF_RULE_ADD, 0, -INFINITY, INFINITY, "°C", "Change in core temperature."),
		list(BF_BP_SYSTOLIC, "Systolic pressure", BF_RULE_ADD, 0, -INFINITY, INFINITY, "mmHg", "Change in systolic blood pressure."),
		list(BF_BP_DIASTOLIC, "Diastolic pressure", BF_RULE_ADD, 0, -INFINITY, INFINITY, "mmHg", "Change in diastolic blood pressure."),
		list(BF_O2_SAT, "Oxygen saturation", BF_RULE_ADD, 0, -100, 100, "%", "Change in blood oxygen saturation."),
		list(BF_RESP_RATE, "Breathing rate", BF_RULE_ADD, 0, -INFINITY, INFINITY, "/min", "Change in breaths per minute."),
		list(BF_SLOWDOWN, "Slowdown", BF_RULE_ADD, 0, -10, 20, "points", "Movement delay; negative is faster."),
		list(BF_PENALTY_SCALE, "Movement penalties", BF_RULE_MULT, 1, 0, 4, "percent", "Scale on every movement penalty."),
		list(BF_HASTE, "Haste", BF_RULE_MAX, 0, 0, 1, "flag", "Ignores every slowdown."),
		list(BF_ACCURACY, "Accuracy", BF_RULE_ADD, 0, -INFINITY, INFINITY, "%", "Ranged accuracy."),
		list(BF_DISPERSION, "Dispersion", BF_RULE_ADD, 0, -INFINITY, INFINITY, "points", "How widely shots stray."),
		list(BF_EVASION, "Evasion", BF_RULE_ADD, 0, -INFINITY, INFINITY, "%", "Chance for attacks to miss."),
		list(BF_ATTACK_SPEED, "Attack delay", BF_RULE_MULT, 1, 0.1, 10, "percent", "Delay between attacks."),
		list(BF_MELEE_DAMAGE, "Melee damage", BF_RULE_MULT, 1, 0, 10, "percent", "Damage dealt in melee and unarmed."),
		list(BF_VISION, "Vision", BF_RULE_MULT, 1, 0, 2, "percent", "Visual acuity."),
		list(BF_HEARING, "Hearing", BF_RULE_MULT, 1, 0, 2, "percent", "Hearing."),
		list(BF_MOTOR_CONTROL, "Motor control", BF_RULE_MULT, 1, 0, 1, "percent", "Fine motor control; poor control drops held items."),
		list(BF_DARKSIGHT, "Darksight", BF_RULE_MAX, 0, 0, 1, "flag", "Sees in the dark."),
		list(BF_SIGHT_FLAGS, "Special sight", BF_RULE_FLAGS, 0, 0, INFINITY, "flags", "Sees through walls."),
		list(BF_ACTION_BLOCKS, "Blocked actions", BF_RULE_FLAGS, 0, 0, INFINITY, "flags", "Actions that can't be performed."),
		list(BF_INCOMING_ALL, "Injury taken", BF_RULE_MULT, 1, 0, 10, "percent", "Every injury taken."),
		list(BF_INCOMING_PHYSICAL, "Physical injury taken", BF_RULE_MULT, 1, 0, 10, "percent", "Blunt, cutting and piercing injury taken."),
		list(BF_INCOMING_THERMAL, "Thermal injury taken", BF_RULE_MULT, 1, 0, 10, "percent", "Burn, frostbite, corrosive and electrical injury taken."),
		list(BF_INCOMING_TOXIC, "Toxic injury taken", BF_RULE_MULT, 1, 0, 10, "percent", "Poisoning taken."),
		list(BF_INCOMING_GENETIC, "Genetic injury taken", BF_RULE_MULT, 1, 0, 10, "percent", "Radiation and cellular injury taken."),
		list(BF_INCOMING_NEURAL, "Neural injury taken", BF_RULE_MULT, 1, 0, 10, "percent", "Neural injury taken."),
		list(BF_INCOMING_PAIN, "Pain taken", BF_RULE_MULT, 1, 0, 10, "percent", "Pain inflicted by weapons."),
		list(BF_DISABLE_DURATION, "Disable duration", BF_RULE_MULT, 1, 0, 10, "percent", "How long stuns and knockdowns last."),
		list(BF_HEALING_RECEIVED, "Healing received", BF_RULE_MULT, 1, 0, 10, "percent", "Strength of every treatment received."),
		list(BF_ENDURANCE_FLAT, "Endurance", BF_RULE_ADD, 0, -INFINITY, INFINITY, "points", "Toughness."),
		list(BF_ENDURANCE_MULT, "Endurance scale", BF_RULE_MULT, 1, 0, 100, "percent", "Toughness."),
		list(BF_ICON_SCALE_X, "Width", BF_RULE_MULT, 1, 0.1, 10, "percent", "Sprite width."),
		list(BF_ICON_SCALE_Y, "Height", BF_RULE_MULT, 1, 0.1, 10, "percent", "Sprite height."),
		list(BF_PAIN_IMMUNITY, "Pain immunity", BF_RULE_MAX, 0, 0, 1, "flag", "Feels no pain."),
		list(BF_PULSE_SHIFT, "Pulse shift", BF_RULE_ADD, 0, -INFINITY, INFINITY, "points", "Shifts the pulse up or down."),
		list(BF_PULSE_SET, "Forced pulse", BF_RULE_MAX, -1, -1, INFINITY, "points", "Forces the pulse to a level."),
		list(BF_EMP_SHIFT, "EMP resistance", BF_RULE_ADD, 0, -INFINITY, INFINITY, "points", "Weakens EMPs (higher is weaker)."),
		list(BF_EXPLOSION_SHIFT, "Blast resistance", BF_RULE_ADD, 0, -INFINITY, INFINITY, "points", "Weakens explosions (higher is weaker)."),
		list(BF_HEAT_EXPOSURE, "Heat exposure", BF_RULE_MULT, 1, 0, 10, "percent", "Share of environmental heat that reaches the body."),
		list(BF_COLD_EXPOSURE, "Cold exposure", BF_RULE_MULT, 1, 0, 10, "percent", "Share of environmental cold that reaches the body."),
		list(BF_SIEMENS, "Conductivity", BF_RULE_MULT, 1, 0, 10, "percent", "Electrical conductivity."),
		list(BF_STABILIZATION, "Stabilisation", BF_RULE_ADD, 0, 0, INFINITY, "points", "Keeps the heart and breathing stable in crisis."),
		list(BF_ANTIMICROBIAL, "Antimicrobial", BF_RULE_ADD, 0, 0, INFINITY, "points", "Fights infection."),
		list(BF_BLOOD_REGEN, "Blood regeneration", BF_RULE_ADD, 0, 0, INFINITY, "points", "Blood rebuilt per tick."),
		list(BF_INTOXICATION, "Intoxication", BF_RULE_ADD, 0, 0, INFINITY, "points", "Alcohol intoxication."),
		list(BF_HEPATOTOXICITY, "Liver toxicity", BF_RULE_ADD, 0, 0, INFINITY, "points", "Alcohol poisoning of the liver."),
		list(BF_ANTIEMETIC, "Antiemetic", BF_RULE_ADD, 0, 0, INFINITY, "points", "Suppresses vomiting."),
		list(BF_ALLERGY, "Allergic reaction", BF_RULE_ADD, 0, 0, INFINITY, "points", "Strength of an allergic reaction."),
		list(BF_WITHDRAWAL, "Withdrawal", BF_RULE_ADD, 0, 0, INFINITY, "points", "Withdrawal strain on the organs."),
		list(BF_NEURAL_REPAIR, "Neural repair", BF_RULE_ADD, 0, 0, INFINITY, "points", "Extra brain repair per tick."),
		list(BF_IMMUNE_SUPPRESSION, "Immune suppression", BF_RULE_ADD, 0, 0, INFINITY, "points", "Suppresses the immune response."),
		list(BF_O2_CARRIAGE, "Oxygen carriage", BF_RULE_MULT, 1, 0, 2, "percent", "How much oxygen the blood carries."),
		list(BF_TISSUE_UPTAKE, "Tissue oxygen uptake", BF_RULE_MULT, 1, 0, 2, "percent", "How well the tissues use the oxygen that reaches them."),
		list(BF_STASIS, "Stasis", BF_RULE_MAX, 0, 0, 1, "points", "Share of life processes suspended: conditions, metabolism and breathing slow by this much."),
	)
	for(var/list/row as anything in rows)
		defs[row[1]] = new /datum/body_factor_def(row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8])
	for(var/kind in 1 to ARMOR_KIND_COUNT)
		var/kind_name = armor_kind_name(kind)
		defs[BF_ARMOR(kind)] = new /datum/body_factor_def(BF_ARMOR(kind), "[capitalize(kind_name)] armour", BF_RULE_ADD, 0, -INFINITY, INFINITY, "points", "Extra armour against [kind_name] harm.")
	for(var/id in 1 to BF_COUNT)
		if(!defs[id])
			stack_trace("body factor [id] has no definition")
	return defs

/// Flat list of baselines, indexed by BF_*. Shared: never mutate.
/proc/body_factor_baselines()
	var/static/list/baselines
	if(baselines)
		return baselines
	var/list/defs = body_factor_defs()
	baselines = new /list(BF_COUNT)
	for(var/id in 1 to BF_COUNT)
		var/datum/body_factor_def/D = defs[id]
		baselines[id] = D ? D.baseline : 0
	return baselines

/// Flat list of combine rules, indexed by BF_*. Shared: never mutate.
/proc/body_factor_rules()
	var/static/list/rules
	if(rules)
		return rules
	var/list/defs = body_factor_defs()
	rules = new /list(BF_COUNT)
	for(var/id in 1 to BF_COUNT)
		var/datum/body_factor_def/D = defs[id]
		rules[id] = D ? D.rule : BF_RULE_ADD
	return rules

/proc/body_factor_baseline(id)
	return body_factor_baselines()[id]

/// Fold one source's table into `acc` (a flat BF_COUNT list seeded with the
/// baselines) at `scale`. Returns `acc`, allocating it on the first
/// contribution. See the combine rules in code/__defines/body_factors.dm.
/proc/body_factor_accumulate(list/acc, alist/table, scale = 1)
	if(!length(table) || scale <= 0)
		return acc
	if(!acc)
		acc = body_factor_baselines().Copy()
	var/list/rules = body_factor_rules()
	for(var/id in table)
		if(!isnum(id) || id < 1 || id > BF_COUNT)
			stack_trace("invalid body factor id [id] in a factor table")
			continue
		var/value = table[id]
		switch(rules[id])
			if(BF_RULE_MULT)
				acc[id] *= max(0, 1 - (1 - value) * scale)
			if(BF_RULE_ADD)
				acc[id] += value * scale
			if(BF_RULE_MAX)
				acc[id] = max(acc[id], value * scale)
			if(BF_RULE_MIN)
				acc[id] = min(acc[id], value * scale)
			if(BF_RULE_FLAGS)
				acc[id] |= value
	return acc

/// Clamp `acc` to the factor bounds. Returns null when every factor sits at
/// its baseline, so healthy bodies keep no list.
/proc/body_factor_finalize(list/acc)
	if(!acc)
		return null
	var/list/defs = body_factor_defs()
	var/list/baselines = body_factor_baselines()
	var/at_baseline = TRUE
	for(var/id in 1 to BF_COUNT)
		var/datum/body_factor_def/D = defs[id]
		var/value = clamp(acc[id], D.min_value, D.max_value)
		acc[id] = value
		if(value != baselines[id])
			at_baseline = FALSE
	return at_baseline ? null : acc


// --- Mob-side queries ----------------------------------------------------------

/// The current value of body factor `id` (BF_*).
/mob/living/proc/factor(id)
	if(!body)
		return body_factor_baseline(id)
	return body.get_factor(id)

/// Mark this mob's factors stale.
/mob/living/proc/invalidate_factors()
	body?.invalidate(BODY_DIRTY_FACTORS)

/// Is `block` (ACTION_BLOCK_*) set on this mob?
/mob/living/proc/action_blocked(block)
	return (factor(BF_ACTION_BLOCKS) & block) ? TRUE : FALSE

/// Incoming multiplier for an INJURY_CATEGORY_*: the overall and the
/// per-category factor.
/mob/living/proc/incoming_injury_factor(category)
	. = factor(BF_INCOMING_ALL)
	if(category)
		. *= factor(BF_INCOMING(category))

// --- Body side ---------------------------------------------------------------------

/datum/body
	/// Flat list indexed by BF_*, or null when every factor is at baseline.
	var/list/factors

/datum/body/proc/get_factor(id)
	if(dirty & BODY_DIRTY_FACTORS)
		recompute_factors()
	return factors ? factors[id] : body_factor_baseline(id)

/// Rebuild `factors` from every source. Visits each source's static table
/// once; allocates only when something contributes.
/datum/body/proc/recompute_factors()
	dirty &= ~BODY_DIRTY_FACTORS
	var/list/acc = null
	for(var/datum/affliction/A as anything in afflictions)
		acc = A.accumulate_factors(acc)
	for(var/datum/modifier/M as anything in owner.modifiers)
		acc = body_factor_accumulate(acc, M.factors)
	acc = accumulate_reagent_factors(acc)
	acc = accumulate_plan_factors(acc)
	var/list/old = factors
	factors = body_factor_finalize(acc)
	if(!factors_equal(old, factors))
		// Pain and consciousness read analgesia, pain and sedation; the
		// physiology reads the oxygen-transport factors.
		invalidate(BODY_DIRTY_VITALS | BODY_DIRTY_PHYSIOLOGY)
		SEND_SIGNAL(owner, COMSIG_LIVING_FACTORS_CHANGED)

/datum/body/proc/factors_equal(list/a, list/b)
	if(a == b)
		return TRUE
	if(!a || !b)
		return FALSE
	for(var/id in 1 to BF_COUNT)
		if(a[id] != b[id])
			return FALSE
	return TRUE

/// Per-tick consequences of the current factors: poor motor control drops
/// held items, blocked hands can't hold anything.
/datum/body/proc/tick_factor_effects()
	if(!ishuman(owner) || owner.stat == DEAD)
		return
	var/mob/living/carbon/human/H = owner
	var/blocks = factors[BF_ACTION_BLOCKS]
	if((blocks & ACTION_BLOCK_HOLD_LEFT) && H.l_hand)
		to_chat(H, span_warning("Your left hand won't close around \the [H.l_hand]."))
		H.drop_l_hand()
	if((blocks & ACTION_BLOCK_HOLD_RIGHT) && H.r_hand)
		to_chat(H, span_warning("Your right hand won't close around \the [H.r_hand]."))
		H.drop_r_hand()
	var/motor = factors[BF_MOTOR_CONTROL]
	if(motor < 1 && prob(min(BF_MAX_DROP_CHANCE, (1 - motor) * 100)))
		dq_drop_random_held(H)

/// Reagent contributions: each reagent's table at its dose scale (from the
/// treatment snapshot's volumes).
/datum/body/proc/accumulate_reagent_factors(list/acc)
	if(dirty & BODY_DIRTY_TREATMENT)
		build_treatment_snapshot()
	if(!reagent_volumes)
		return acc
	for(var/reagent_id in reagent_volumes)
		var/datum/reagent/R = SSchemistry.chemical_reagents[reagent_id]
		if(!R)
			continue
		var/alist/table = R.get_factors(owner)
		var/scale = dq_chem_dose_scale(reagent_volumes[reagent_id])
		if(length(table) && scale > 0)
			acc = accumulate_scaled_reagent(acc, table, scale)
		acc = R.accumulate_special_factors(acc, owner, reagent_volumes[reagent_id])
	return acc

/// One reagent table. Plans scale individual factors (a species' analgesic
/// sensitivity) by overriding this.
/datum/body/proc/accumulate_scaled_reagent(list/acc, alist/table, scale)
	return body_factor_accumulate(acc, table, scale)

/// Plan-specific sources: species, traits, form, worn equipment. Base: none.
/datum/body/proc/accumulate_plan_factors(list/acc)
	return acc


// --- Source tables -------------------------------------------------------------------

/datum/affliction
	/// Body factors at severity 100, scaled by severity (BF_* -> value).
	var/alist/factors
	/// Severity band the factors were last computed at.
	var/tmp/factor_band = -1

/// The table this affliction contributes now. A staged affliction uses its
/// active stage's "factors" (applied at full value; a stage without one
/// contributes nothing); otherwise `factors`, scaled by severity.
/datum/affliction/proc/accumulate_factors(list/acc)
	factor_band = round(severity / BF_SEVERITY_BAND)
	if(stage)
		var/list/entry = get_stages()?[stage]
		if(entry)
			return body_factor_accumulate(acc, entry["factors"], 1)
	return body_factor_accumulate(acc, factors, severity / AFFLICTION_SEVERITY_TERMINAL)

/datum/reagent
	/// Body factors at the standard dose (DQ_CHEM_STANDARD_DOSE), scaled by
	/// the dose curve. BF_* -> value.
	var/alist/factors
	/// Per-species replacements for `factors`: reagent tag (IS_*) -> table.
	/// A tag mapped to null gets nothing (diona ignore most drugs).
	var/alist/species_factors

/// The table this reagent contributes to `L`: its species' entry in
/// `species_factors` if it has one, else `factors`. Null contributes nothing.
/datum/reagent/proc/get_factors(mob/living/L)
	if(species_factors)
		var/tag = L.reagent_tag()
		if(!isnull(tag) && (tag in species_factors))
			return species_factors[tag]
	return factors

/// Contributions that depend on the patient rather than the reagent: the
/// mob's allergies, and blood rebuilt from its own blood reagent. Called at
/// every factor recompute with the reagent's volume across the mob's holders.
/datum/reagent/proc/accumulate_special_factors(list/acc, mob/living/L, volume)
	if(!ishuman(L) || volume <= 0)
		return acc
	var/mob/living/carbon/human/H = L
	var/scale = dq_chem_dose_scale(volume)
	if((H.species.allergens & allergen_type) || (H.species.medallergens & medallergen_type))
		// REM: the old per-tick reaction came from the ~REM units metabolised.
		var/static/alist/allergy = alist(BF_ALLERGY = REM)
		acc = body_factor_accumulate(acc, allergy, allergen_factor * scale)
	if(id == H.species.blood_reagents)
		var/static/alist/blood_rebuild = alist(BF_BLOOD_REGEN = 1.6)
		acc = body_factor_accumulate(acc, blood_rebuild, scale)
	return acc

/// Reagent tag (IS_*) the mob metabolises as, or null.
/mob/living/proc/reagent_tag()
	return null

/mob/living/carbon/human/reagent_tag()
	return species?.reagent_tag

/datum/modifier
	/// Body factors applied at full value while the modifier exists.
	var/alist/factors

/// Replace this modifier's table at runtime (charge-dependent shields,
/// stacking effects). Marks the holder's factors stale.
/datum/modifier/proc/set_factors(alist/new_factors)
	factors = new_factors
	holder?.invalidate_factors()

/datum/form
	/// Body factors applied at full value while this form is worn.
	var/alist/factors

/obj/item
	/// Body factors applied while this item is equipped outside the hands.
	var/alist/worn_factors

/obj/item/equipped(mob/user, slot)
	. = ..()
	if(worn_factors && isliving(user))
		var/mob/living/L = user
		L.invalidate_factors()

/obj/item/dropped(mob/user)
	. = ..()
	if(worn_factors && isliving(user))
		var/mob/living/L = user
		L.invalidate_factors()


// --- Book text -------------------------------------------------------------------------

/// Human-readable lines for a factor table, e.g. "Airway: -80%". `suffix`
/// is appended to each line (" at full severity", " at a standard dose").
/proc/body_factor_describe(alist/table, suffix = "")
	. = list()
	if(!length(table))
		return
	var/list/defs = body_factor_defs()
	for(var/id in table)
		var/datum/body_factor_def/D = (isnum(id) && id >= 1 && id <= BF_COUNT) ? defs[id] : null
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
