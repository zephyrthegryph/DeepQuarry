// Humanoid body plan: /mob/living/carbon/human — organic, full-body
// prosthetic (FBP), nanoform and plant alike. Parts are the mob's organs;
// each part's biology comes from the organ, so a human with a robotic arm is
// organic at the chest and synthetic at the arm.
//
// Located injuries (blunt/cut/pierce/burn/…) are resolved by the limb
// (/obj/item/organ/external/proc/receive_injury → wound afflictions).
// Injuries aimed at an internal organ become lesions on it
// (receive_organ_injury, kind → lesion through one static table).
// Systemic injuries become systemic afflictions (toxic poisoning, genetic
// damage, acute pain) or brain lesions (neural). Lack of oxygen is not an
// injury: the humanoid physiology (code/modules/body/physiology.dm) computes
// it and grows tissue hypoxia from the oxygen debt.

/mob/living/carbon/human
	body_type = /datum/body/humanoid

/datum/body/humanoid
	plan_flag = BODY_PLAN_HUMANOID
	physiology_type = /datum/physiology/humanoid
	// Limb and organ state changes outside the body (surgery, organ procs),
	// and brainless bodies must still die.
	always_evaluate = TRUE

/datum/body/humanoid/proc/human()
	return owner

// --- Parts & biology ---------------------------------------------------------------

/datum/body/humanoid/resolve_zone(zone)
	if(!zone)
		return null
	if(istype(zone, /obj/item/organ))
		var/obj/item/organ/O = zone
		return O.owner == owner ? O : null
	var/mob/living/carbon/human/H = owner
	var/obj/item/organ/O = H.get_organ(check_zone(zone))
	if(O)
		return O
	return H.internal_organs_by_name?[zone]

/datum/body/humanoid/biology_of(location)
	var/obj/item/organ/O = location
	if(istype(O))
		if(O.robotic == ORGAN_NANOFORM)
			return BIOLOGY_NANOFORM
		if(O.robotic >= ORGAN_ROBOT)
			return BIOLOGY_SYNTHETIC
		return BIOLOGY_ORGANIC
	return owner.isSynthetic() ? BIOLOGY_SYNTHETIC : BIOLOGY_ORGANIC

/datum/body/humanoid/injury_multiplier(kind, location)
	var/mob/living/carbon/human/H = owner
	. = H.species ? H.species.injury_multiplier(kind, H) : 1
	if(H.nif)
		var/category = injury_category(kind)
		if(category == INJURY_CATEGORY_PHYSICAL && H.nif.flag_check(NIF_C_BRUTEARMOR, NIF_FLAGS_COMBAT))
			. *= 0.7
		else if(category == INJURY_CATEGORY_THERMAL && H.nif.flag_check(NIF_C_BURNARMOR, NIF_FLAGS_COMBAT))
			. *= 0.7
	if(kind == INJURY_BURN && (H.has_mutation(COLD_RESISTANCE)))
		. = 0
	. *= part_multiplier(kind, location)

/// The part's own multiplier: a limb's brute_mod for physical injury and
/// burn_mod for thermal injury (prosthetic models, species limbs).
/datum/body/humanoid/proc/part_multiplier(kind, obj/item/organ/external/E)
	if(!istype(E))
		return 1
	switch(injury_category(kind))
		if(INJURY_CATEGORY_PHYSICAL)
			return E.brute_mod
		if(INJURY_CATEGORY_THERMAL)
			return E.burn_mod
	return 1

/datum/body/humanoid/chem_heal_strength()
	var/mob/living/carbon/human/H = owner
	return H.species?.chem_strength_heal || 1

/// Natural regeneration (TREAT_REGENERATION): a living, fed body heals on
/// its own, twice as fast asleep. Scaled by the server's regeneration config.
/datum/body/humanoid/regeneration_level()
	var/mob/living/carbon/human/H = owner
	if(H.stat == DEAD || H.nutrition < REGENERATION_STARVING_NUTRITION)
		return 0
	. = REGENERATION_BASE_LEVEL * CONFIG_GET(number/organ_regeneration_multiplier)
	if(H.nutrition < REGENERATION_HUNGRY_NUTRITION)
		. *= REGENERATION_HUNGRY_MULT
	if(H.has_status(EFFECT_SLEEPING))
		. *= REGENERATION_SLEEP_MULT
	. *= get_factor(BF_HEALING)


// --- Injury resolution -----------------------------------------------------------------

/datum/body/humanoid/receive_injury(kind, amount, target, atom/source, affliction_type, flags)
	var/mob/living/carbon/human/H = owner
	var/obj/item/organ/part = resolve_zone(target)
	if(!part && istype(target, /obj/item/organ))
		return 0 // aimed at an organ this body no longer has
	if(istype(part, /obj/item/organ/internal))
		return receive_organ_injury(kind, amount, part, source, affliction_type, flags)

	if(injury_is_located(kind))
		if(istype(part, /obj/item/organ/external))
			var/obj/item/organ/external/E = part
			if(affliction_type)
				var/datum/affliction/A = afflict(affliction_type, E)
				return A ? A.receive_injury(amount, kind, source) : 0
			return E.receive_injury(kind, amount, source, flags)
		return spread_located_injury(kind, amount, source, flags)

	var/systemic_biology = biology_of(null)
	switch(kind)
		if(INJURY_TOXIN)
			if((H.species.flags & NO_POISON) || systemic_biology == BIOLOGY_SYNTHETIC)
				return 0
			return systemic_injury(affliction_type || /datum/affliction/toxic_poisoning, amount, kind, source)
		if(INJURY_CELLULAR)
			if((H.species.flags & NO_DNA) || systemic_biology == BIOLOGY_SYNTHETIC)
				return 0
			. = systemic_injury(affliction_type || /datum/affliction/genetic_damage, amount, kind, source)
			if(.)
				H.dq_genetic_damage_mutations(.)
			return
		if(INJURY_PAIN)
			if(!H.dq_feels_pain())
				return 0
			return systemic_injury(affliction_type || /datum/affliction/acute_pain, amount, kind, source)
		if(INJURY_NEURAL)
			if(!H.should_have_organ(O_BRAIN))
				return 0
			var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
			if(!B)
				return 0
			// Neural injury is brain tissue damage: a brain lesion.
			return receive_organ_injury(kind, amount, B, source, affliction_type, flags)
		if(INJURY_RADIATION)
			if(systemic_biology == BIOLOGY_SYNTHETIC)
				return 0
			H.radiation += amount
			return amount
	return 0

/// Lesion kind an injury of `kind` makes on an internal organ (null = the
/// organ can't be hurt that way). Indexed by INJURY_*.
/proc/organ_lesion_for_injury(kind)
	var/static/list/lesion_by_kind = list(
		/datum/affliction/lesion/contusion,       // blunt
		/datum/affliction/lesion/laceration,      // cut
		/datum/affliction/lesion/perforation,     // pierce (solid organs tear instead)
		/datum/affliction/lesion/contusion,       // burn
		/datum/affliction/lesion/ischemic_injury, // frostbite
		/datum/affliction/lesion/toxic_injury,    // corrosive
		/datum/affliction/lesion/contusion,       // electric
		/datum/affliction/lesion/toxic_injury,    // toxin
		/datum/affliction/lesion/toxic_injury,    // radiation
		/datum/affliction/lesion/toxic_injury,    // cellular
		/datum/affliction/lesion/contusion,       // neural
		null,                                     // pain
		/datum/affliction/lesion/toxic_injury,    // digestion
	)
	return lesion_by_kind[kind]

/// Injury aimed at an internal organ: a lesion. A lesion typepath as the
/// affliction picks the kind; any other affliction takes hold on the organ
/// alongside the default lesion for `kind`.
/datum/body/humanoid/proc/receive_organ_injury(kind, amount, obj/item/organ/internal/O, atom/source, affliction_type, flags)
	var/lesion_type
	if(ispath(affliction_type, /datum/affliction/lesion))
		lesion_type = affliction_type
	else
		if(affliction_type)
			afflict(affliction_type, O)
		lesion_type = organ_lesion_for_injury(kind)
	if(!lesion_type)
		return 0
	return O.apply_lesion_damage(amount, lesion_type, flags & INJURE_SILENT)

/datum/body/humanoid/proc/systemic_injury(affliction_type, amount, kind, atom/source)
	var/datum/affliction/A = afflict(affliction_type)
	return A ? A.receive_injury(amount, kind, source) : 0

/// Located injury with no zone: spread across damageable limbs in random
/// order, like the old take_overall_damage(). Each limb applies its own part
/// multiplier (resistance-ignoring injuries skip it).
/datum/body/humanoid/proc/spread_located_injury(kind, amount, atom/source, flags)
	var/mob/living/carbon/human/H = owner
	var/list/parts = H.get_damageable_organs()
	. = 0
	while(length(parts) && amount > 0)
		var/obj/item/organ/external/E = pick_n_take(parts)
		var/multiplier = (flags & INJURE_IGNORE_RESISTANCE) ? 1 : part_multiplier(kind, E)
		if(multiplier <= 0)
			continue
		var/applied = E.receive_injury(kind, amount * multiplier, source, flags)
		. += applied
		amount -= applied / multiplier


// --- Vitals ------------------------------------------------------------------------------

/datum/body/humanoid/recompute_vitals()
	dirty &= ~BODY_DIRTY_VITALS
	var/mob/living/carbon/human/H = owner
	var/worst_part = worst_vital_part_fraction()
	pain = compute_pain()
	H.traumatic_shock = pain
	consciousness = compute_consciousness(worst_part)
	vitality = compute_vitality(worst_part)

/// Pain: afflictions plus the raw wound load of limbs that can feel it, less
/// analgesia.
/datum/body/humanoid/proc/compute_pain()
	var/mob/living/carbon/human/H = owner
	if(!H.dq_feels_pain())
		return 0
	var/raw_pain = 0
	for(var/datum/affliction/A as anything in afflictions)
		raw_pain += A.pain_contribution()
	for(var/obj/item/organ/external/E as anything in H.organs)
		if(E.robotic >= ORGAN_ROBOT || !E.organ_can_feel_pain())
			continue
		raw_pain += PAIN_PER_LIMB_DAMAGE * (E.get_trauma() + E.get_burn())
		if(E.is_broken())
			raw_pain += PAIN_BROKEN_BONE
		else if(E.is_dislocated())
			raw_pain += PAIN_DISLOCATION
	raw_pain *= H.species.trauma_mod
	if(H.has_status(EFFECT_SLURRING))
		raw_pain -= PAIN_SLURRING_RELIEF
	raw_pain += get_factor(BF_PAIN)
	return max(0, raw_pain - get_factor(BF_ANALGESIA))

/// Consciousness: 100 less affliction penalties and pain above tolerance.
/// Patients who feel no pain drop out when a vital part fails structurally.
/datum/body/humanoid/proc/compute_consciousness(worst_part)
	var/mob/living/carbon/human/H = owner
	. = 100 - get_factor(BF_SEDATION)
	for(var/datum/affliction/A as anything in afflictions)
		. -= A.consciousness_penalty()
	if(H.dq_feels_pain())
		. -= max(0, pain - pain_tolerance())
	else if(worst_part >= DQ_VITAL_PART_CRIT_MULT)
		. = min(., CONSCIOUSNESS_THRESHOLD)

/// Vitality readout: the worst of vital-organ failure, vital-part
/// destruction, injury afflictions and lost consciousness.
/datum/body/humanoid/proc/compute_vitality(worst_part)
	var/mob/living/carbon/human/H = owner
	var/danger = worst_part / DQ_VITAL_PART_LETHAL_MULT
	for(var/obj/item/organ/internal/O as anything in H.internal_organs)
		if(O.vital && O.max_damage)
			danger = max(danger, O.damage / O.max_damage)
	// Only afflictions that are injuries count toward the readout; side
	// effects, interactions and GM flavour issues don't make you "hurt".
	for(var/datum/affliction/A as anything in afflictions)
		if(A.injury_category && !length(A.caused_by_chems))
			danger = max(danger, VITALITY_AFFLICTION_WEIGHT * A.severity / AFFLICTION_SEVERITY_TERMINAL)
	danger = max(danger, VITALITY_CONSCIOUSNESS_WEIGHT * clamp((100 - consciousness) / 100, 0, 1))
	return clamp(1 - danger, 0, 1)

/datum/body/humanoid/proc/pain_tolerance()
	var/mob/living/carbon/human/H = owner
	return H.species.total_health * PAIN_TOLERANCE_FRACTION * (H.species.crit_mod || 1)

/// Highest (trauma + burn) / max_damage across vital body parts.
/datum/body/humanoid/proc/worst_vital_part_fraction()
	. = 0
	var/mob/living/carbon/human/H = owner
	for(var/obj/item/organ/external/E as anything in H.organs)
		if(E.vital && E.max_damage)
			. = max(., (E.get_trauma() + E.get_burn()) / E.max_damage)

/datum/body/humanoid/is_dead()
	var/mob/living/carbon/human/H = owner
	if(H.should_have_organ(O_BRAIN) && (!H.has_brain() || H.is_brain_dead()))
		return TRUE
	return worst_vital_part_fraction() >= DQ_VITAL_PART_LETHAL_MULT

/datum/body/humanoid/restore()
	var/mob/living/carbon/human/H = owner
	H.restore_all_organs()


// --- Human helpers ------------------------------------------------------------------------

/mob/living/carbon/human/proc/dq_feels_pain()
	return can_feel_pain() || (isSynthetic() && synth_cosmetic_pain)

/// Visible limb mutation tracks genetic damage.
/mob/living/carbon/human/proc/dq_genetic_damage_mutations(amount)
	var/cellular = injury_load(INJURY_CATEGORY_GENETIC)
	if(amount > 0 && prob(min(80, cellular + 10)))
		var/list/obj/item/organ/external/candidates = list()
		for(var/obj/item/organ/external/O in organs)
			if(!(O.status & ORGAN_MUTATED))
				candidates += O
		if(length(candidates))
			var/obj/item/organ/external/O = pick(candidates)
			O.mutate()
			to_chat(src, span_notice("Something is not right with your [O.name]..."))

/// Species immunities (mitigation stage 4). The NO_* flags are checked live
/// because traits can grant flags after setup. Graded species resistances are
/// body factors (factor_baseline BF_INCOMING_*, stage 3).
/datum/species/proc/injury_multiplier(kind, mob/living/carbon/human/H)
	switch(kind)
		if(INJURY_TOXIN)
			if(flags & NO_POISON)
				return 0
		if(INJURY_CELLULAR)
			if(flags & NO_DNA)
				return 0
		if(INJURY_PAIN)
			if(flags & NO_PAIN)
				return 0
	return 1

// --- Body factors ---------------------------------------------------------------------------

/// Species and trait baselines, the current form, and equipment worn
/// outside the hands.
/datum/body/humanoid/accumulate_plan_factors(list/acc)
	var/mob/living/carbon/human/H = owner
	if(H.species)
		acc = body_factor_accumulate(acc, H.species.factor_baseline)
		for(var/alist/table as anything in H.species.granted_factors)
			acc = body_factor_accumulate(acc, table)
	var/datum/form/F = H.current_form()
	if(F)
		acc = body_factor_accumulate(acc, F.factors)
	// The worn slots (BODY_SLOT_WORN, code/modules/body/slots.dm): the same set the worn protection cache reads.
	for(var/obj/item/I as anything in H.body_slot_items(BODY_SLOT_WORN))
		if(I.worn_factors)
			acc = body_factor_accumulate(acc, I.worn_factors)
	return acc

/// The species' analgesic sensitivity (chem_strength_pain) scales every
/// reagent's analgesia.
/datum/body/humanoid/accumulate_scaled_reagent(list/acc, alist/table, scale)
	acc = ..()
	var/mob/living/carbon/human/H = owner
	var/strength = H.species?.chem_strength_pain
	var/analgesia = table[BF_ANALGESIA]
	if(acc && analgesia && !isnull(strength) && strength != 1)
		acc[BF_ANALGESIA] += analgesia * scale * (strength - 1)
	return acc

/// Grant a factor table (a trait's or perk's) to this species instance.
/datum/species/proc/grant_factors(alist/table)
	if(!length(table))
		return
	LAZYINITLIST(granted_factors)
	granted_factors[++granted_factors.len] = table

/datum/species/proc/revoke_factors(alist/table)
	if(!granted_factors)
		return
	granted_factors -= list(table)
	UNSETEMPTY(granted_factors)

/// The species' own value of a factor (baseline plus traits), without any
/// other source. Feral movement compresses everything above it.
/datum/species/proc/baseline_factor(id)
	var/list/acc = body_factor_accumulate(null, factor_baseline)
	for(var/alist/table as anything in granted_factors)
		acc = body_factor_accumulate(acc, table)
	return acc ? acc[id] : body_factor_baseline(id)

/// Life() applies humanoid unconsciousness itself (with its blinding / crit
/// HUD bookkeeping); evaluate_status only handles death here.
/datum/body/humanoid/update_consciousness()
	return

/// Humanoid load: limb wounds for physical/thermal, brain integrity for
/// neural, affliction severity for everything else.
/datum/body/humanoid/injury_load(category)
	var/mob/living/carbon/human/H = owner
	switch(category)
		if(INJURY_CATEGORY_PHYSICAL)
			. = 0
			for(var/obj/item/organ/external/E as anything in H.organs)
				. += E.get_trauma()
			return
		if(INJURY_CATEGORY_THERMAL)
			. = 0
			for(var/obj/item/organ/external/E as anything in H.organs)
				. += E.get_burn()
			return
		if(INJURY_CATEGORY_NEURAL)
			var/obj/item/organ/internal/brain/B = H.internal_organs_by_name?[O_BRAIN]
			return B ? B.damage : (H.should_have_organ(O_BRAIN) ? 200 : 0)
	return ..()

/datum/body/humanoid/is_injured()
	return ..() || injury_load(INJURY_CATEGORY_PHYSICAL) || injury_load(INJURY_CATEGORY_THERMAL)

/// Mending runs the one shared pass (wounds heal their own damage through
/// receive_tagged_treatment); the limbs just redraw.
/datum/body/humanoid/mend(tag, amount, target = null)
	. = ..()
	if(.)
		var/mob/living/carbon/human/H = owner
		H.UpdateDamageIcon()
