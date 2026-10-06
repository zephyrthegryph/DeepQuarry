/* General medicine */

/datum/reagent/inaprovaline
	// The station's resuscitation stabiliser (and the AllergyPen's payload):
	// a weaker vasopressor on top of circulatory support.
	treatment_tags = list(TREAT_CIRCULATORY = 1.0, TREAT_VASOPRESSOR = 0.5)
	factors = alist(BF_ANALGESIA = 10, BF_STABILIZATION = 15, BF_ALLERGY = -5)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_INAPROVALINE
	id = REAGENT_ID_INAPROVALINE
	description = REAGENT_INAPROVALINE + " is a synaptic stimulant and cardiostimulant. Commonly used to stabilize patients. Also counteracts allergic reactions."
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#00BFFF"
	overdose = REAGENTS_OVERDOSE * 2
	metabolism = REM * 0.2
	dermal_absorption = 0.2
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/inaprovaline/topical
	factors = alist(BF_ANALGESIA = 12, BF_STABILIZATION = 20, BF_ALLERGY = -5)
	name = REAGENT_INAPROVALAZE
	id = REAGENT_ID_INAPROVALAZE
	description = REAGENT_INAPROVALAZE + " is a topical variant of Inaprovaline."
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#00BFFF"
	overdose = REAGENTS_OVERDOSE * 2
	metabolism = REM * 0.2
	scannable = SCANNABLE_BENEFICIAL
	touch_met = REM * 0.3
	can_overdose_touch = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/inaprovaline/topical
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/inaprovaline/topical/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 2 * removed, source = src)

/datum/reagent/bicaridine
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.0, TREAT_BONE_REPAIR = 0.3, TREAT_HEMOSTATIC = 0.2)
	name = REAGENT_BICARIDINE
	id = REAGENT_ID_BICARIDINE
	description = REAGENT_BICARIDINE + " is an analgesic medication and can be used to treat blunt trauma."
	taste_description = "bitterness"
	taste_mult = 3
	reagent_state = LIQUID
	color = "#BF0000"
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 0.25
	dermal_absorption = 0.2
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_BICARD

// Bicaridine's trauma repair is its treatment_tags profile (body/treatment.dm).

/datum/reagent/bicaridine/overdose(mob/living/carbon/M, alien, removed)
	..()
	var/wound_heal = 2.5 * removed
	M.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + wound_heal, 250))
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/external/O in H.organs)
			dq_reagent_close_wounds(O, wound_heal)

/// Instant wound closure for overdose / clotting side effects (a burst, not a
/// continuous treatment). B13: goes through mend(), so the tags' biology gate
/// applies — a robotic limb is not clotted by a drug. Bleeding wounds take
/// tissue repair; internal (arterial) ones take vessel repair.
/proc/dq_reagent_close_wounds(obj/item/organ/external/O, amount, bleeding = TRUE, internal = TRUE)
	var/mob/living/L = O?.owner
	if(!L)
		return 0
	. = 0
	if(bleeding)
		. += L.mend(TREAT_TISSUE_REPAIR, amount, O)
	if(internal)
		. += L.mend(TREAT_VESSEL_REPAIR, amount, O)

/// B13: a reagent that knits a fracture outright (bone regrowth, calcium
/// miracles). Routed through mend(TREAT_BONE_SETTING) so only organic bone
/// knits, and refused while the limb is still too damaged to hold.
/proc/dq_reagent_knit_fracture(obj/item/organ/external/O)
	var/mob/living/L = O?.owner
	if(!L || !O.is_fractured())
		return 0
	if(O.get_trauma() > O.min_broken_damage * CONFIG_GET(number/organ_health_multiplier))
		return 0 // would just break again
	return L.mend(TREAT_BONE_SETTING, DQ_REAGENT_KNIT_AMOUNT, O)

/datum/reagent/bicaridine/topical
	treatment_tags = list(TREAT_HEMOSTATIC = 1.0, TREAT_BONE_REPAIR = 1.0, TREAT_TISSUE_REPAIR = 0.6, TREAT_NEURAL_REPAIR = 0.3)
	name = REAGENT_BICARIDAZE
	id = REAGENT_ID_BICARIDAZE
	description = REAGENT_BICARIDAZE + " is a topical variant of the chemical Bicaridine."
	taste_description = "bitterness"
	taste_mult = 3
	reagent_state = LIQUID
	color = "#BF0000"
	overdose = REAGENTS_OVERDOSE * 0.75
	scannable = SCANNABLE_BENEFICIAL
	touch_met = REM * 0.75
	can_overdose_touch = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	medallergen_type = MEDALLERGEN_BICARD

/datum/reagent/bicaridine/topical
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/bicaridine/topical/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 2 * removed, source = src)

/datum/reagent/calciumcarbonate
	factors = alist(BF_ANTIEMETIC = 3)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_CALCIUMCARBONATE
	id = REAGENT_ID_CALCIUMCARBONATE
	description = "Calcium carbonate is a calcium salt commonly used as an antacid."
	taste_description = "chalk"
	reagent_state = SOLID
	dermal_absorption = 0 //Solids don't penetrate.
	color = "#eae6e3"
	overdose = REAGENTS_OVERDOSE * 0.8
	metabolism = REM * 0.4
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/calciumcarbonate
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/calciumcarbonate/affect_blood(mob/living/carbon/M, alien, removed) // Why would you inject this.
	M.injure(INJURY_TOXIN, 3 * removed, source = src)

/datum/reagent/kelotane
	treatment_tags = list(TREAT_BURN_CARE = 0.6)
	name = REAGENT_KELOTANE
	id = REAGENT_ID_KELOTANE
	description = REAGENT_KELOTANE + " is a drug used to treat burns."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FFA800"
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_KELOTANE
	// Burn care is the treatment_tags profile. Mends burns, but has negative effects with a Promethean's skeletal structure.
	species_injuries_blood = alist(IS_SLIME = alist(INJURY_BLUNT = 2))

/datum/reagent/dermaline
	treatment_tags = list(TREAT_BURN_CARE = 1.0, TREAT_THERMOREGULATION = 0.2)
	id = REAGENT_ID_DERMALINE
	name = REAGENT_DERMALINE
	description = REAGENT_DERMALINE + " is the next step in burn medication. Works twice as good as kelotane and enables the body to restore even the direst heat-damaged tissue."
	taste_description = "bitterness"
	taste_mult = 1.5
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FF8000"
	overdose = REAGENTS_OVERDOSE * 0.5
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_KELOTANE


/datum/reagent/dermaline/topical
	// Dermalaze: stronger topical burn care (a distinct profile, so it treats).
	treatment_tags = list(TREAT_BURN_CARE = 1.3, TREAT_THERMOREGULATION = 0.2)
	name = REAGENT_DERMALAZE
	id = REAGENT_ID_DERMALAZE
	description = REAGENT_DERMALAZE + " is a topical variant of the chemical Dermaline."
	taste_description = "bitterness"
	taste_mult = 1.5
	reagent_state = LIQUID
	color = "#FF8000"
	overdose = REAGENTS_OVERDOSE * 0.4
	scannable = SCANNABLE_BENEFICIAL
	touch_met = REM * 0.75
	can_overdose_touch = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	medallergen_type = MEDALLERGEN_KELOTANE

/datum/reagent/dermaline/topical
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/dermaline/topical/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 2 * removed, source = src)

/datum/reagent/dylovene
	treatment_tags = list(TREAT_ANTITOXIN = 0.6)
	name = REAGENT_ANTITOXIN
	id = REAGENT_ID_ANTITOXIN
	description = REAGENT_ANTITOXIN + " is a broad-spectrum antitoxin."
	taste_description = "a roll of gauze"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#00A000"
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_DYLO
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)
	species_strength = alist(IS_SLIME = 0.66)

/datum/reagent/dylovene/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = M.species.chem_strength_heal * species_mult(M)
	// Kept: a dose-gated status effect, not a factor or a strength.
	if(alien == IS_SLIME && dose >= 15)
		M.status_at_least(STAT_DRUGGED, 5)
	M.status_adjust(STAT_DROWSY, -(6 * removed * chem_effective))
	M.status_adjust(STAT_HALLUCINATING, -(9 * removed * chem_effective))

/datum/reagent/carthatoline
	treatment_tags = list(TREAT_ANTITOXIN = 1.0, TREAT_HEPATORENAL = 0.4)
	name = REAGENT_CARTHATOLINE
	id = REAGENT_ID_CARTHATOLINE
	description = REAGENT_CARTHATOLINE + " is strong evacuant used to treat severe poisoning."
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#225722"
	scannable = SCANNABLE_BENEFICIAL
	overdose = REAGENTS_OVERDOSE * 0.5
	overdose_mod = 0 // Not used, but it shouldn't deal toxin damage anyways. Carth heals toxins!
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/carthatoline
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/carthatoline/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.injury_load(INJURY_CATEGORY_TOXIC) && prob(10))
		M.vomit(1)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/internal/liver/L = H.organ_in(O_LIVER)
		if(istype(L) && L.is_robotic())
			return
		// Liver repair is carthatoline's TREAT_HEPATORENAL tag (body/treatment.dm).
		if(alien == IS_SLIME)
			H.status_set(STAT_DRUGGED, max(M.status_units(STAT_DRUGGED), 5))

/datum/reagent/carthatoline/overdose(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_PAIN, 2, source = src)
	var/mob/living/carbon/human/H = M
	var/obj/item/organ/internal/stomach/st = H.organ_in(O_STOMACH)
	if(st)
		H.injure(INJURY_BLUNT, removed * 2, st, src, flags = INJURE_IGNORE_RESISTANCE) // Causes stomach contractions, makes sense for an overdose to make it much worse.

/datum/reagent/dexalin
	treatment_tags = list(TREAT_OXYGENATION = 0.5)
	// Loads the blood with oxygen: more carried per unit of saturation.
	factors = alist(BF_O2_CARRIAGE = 1.25)
	species_factors = alist(IS_SLIME = alist(BF_ANALGESIA = 15))
	name = REAGENT_DEXALIN
	id = REAGENT_ID_DEXALIN
	description = REAGENT_DEXALIN + " is used in the treatment of oxygen deprivation."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#0080FF"
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	metabolism = REM * 0.25
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG
	species_injuries_blood = alist(IS_VOX = alist(INJURY_TOXIN = 24))

/datum/reagent/dexalin/affect_blood(mob/living/carbon/M, alien, removed)
	// Oxygenation is the treatment_tags profile. Kept: a random dose-gated burst.
	if(alien == IS_SLIME && dose >= 15)
		if(prob(15))
			to_chat(M, span_notice("You have a moment of clarity as you collapse."))
			// Random burst, not a continuous effect: mend directly.
			M.mend(TREAT_NEURAL_REPAIR, 20 * removed)
			M.status_at_least(STAT_WEAKENED, 6)

	holder.remove_reagent(REAGENT_ID_LEXORIN, 8 * removed)

/datum/reagent/dexalinp
	treatment_tags = list(TREAT_OXYGENATION = 1.0)
	factors = alist(BF_O2_CARRIAGE = 1.5)
	species_factors = alist(IS_SLIME = alist(BF_ANALGESIA = 25))
	name = REAGENT_DEXALINP
	id = REAGENT_ID_DEXALINP
	description = REAGENT_DEXALINP + " is used in the treatment of oxygen deprivation. It is highly effective."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#0040FF"
	overdose = REAGENTS_OVERDOSE * 0.5
	overdose_mod = 1.25
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	species_injuries_blood = alist(IS_VOX = alist(INJURY_TOXIN = 9))

/datum/reagent/dexalinp/affect_blood(mob/living/carbon/M, alien, removed)
	// Oxygenation is the treatment_tags profile. Kept: a random dose-gated burst.
	if(alien == IS_SLIME && dose >= 10)
		if(prob(25))
			to_chat(M, span_notice("You have a moment of clarity, as you feel your tubes lose pressure rapidly."))
			// Random burst, not a continuous effect: mend directly.
			M.mend(TREAT_NEURAL_REPAIR, 8 * removed)
			M.status_at_least(STAT_WEAKENED, 3)

	holder.remove_reagent(REAGENT_ID_LEXORIN, 3 * removed)

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
	name = REAGENT_TRICORDRAZINE
	id = REAGENT_ID_TRICORDRAZINE
	description = REAGENT_TRICORDRAZINE + " is a highly potent stimulant, originally derived from cordrazine. Can be used to treat a wide range of injuries."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#8040FF"
	overdose = REAGENTS_OVERDOSE * 4 // TRICORD FUCKING KILLS YOU
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_TRICORD

/datum/reagent/tricordrazine/overdose(mob/living/carbon/M, alien)
	..()
	M.status_at_least(STAT_DRUGGED, 5)
	M.status_at_least(STAT_CONFUSED, 5)

// Tricordrazine's healing (blood or touch) is its treatment_tags profile.

/datum/reagent/tricorlidaze
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.3,
		TREAT_BURN_CARE = 0.3,
		TREAT_OXYGENATION = 0.3,
		TREAT_ANTITOXIN = 0.4,
		TREAT_ANTIMICROBIAL = 0.3,
	)
	name = REAGENT_TRICORLIDAZE
	id = REAGENT_ID_TRICORLIDAZE
	description = REAGENT_TRICORLIDAZE + " is a topical gel produced with tricordrazine and sterilizine."
	taste_description = "bitterness"
	reagent_state = SOLID
	color = "#B060FF"
	scannable = SCANNABLE_BENEFICIAL
	can_overdose_touch = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	medallergen_type = MEDALLERGEN_TRICORD

// Tricorlidaze's topical healing is its treatment_tags profile.
/datum/reagent/tricorlidaze
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/tricorlidaze/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 3 * removed, source = src)

/datum/reagent/tricorlidaze/touch_obj(obj/O)
	..()
	if(istype(O, /obj/item/stack/medical/bruise_pack) && round(volume) >= 5)
		var/obj/item/stack/medical/bruise_pack/C = O
		var/packname = C.name
		var/to_produce = min(C.get_amount(), round(volume / 5))

		var/obj/item/stack/medical/M = C.upgrade_stack(to_produce)

		if(M && M.get_amount())
			holder.my_atom.visible_message(span_infoplain(span_bold("\The [packname]") + " bubbles."))
			remove_self(to_produce * 5)

/datum/reagent/cryoxadone
	name = REAGENT_CRYOXADONE
	id = REAGENT_ID_CRYOXADONE
	description = "A chemical mixture with almost magical healing powers. Its main limitation is that the targets body temperature must be under 170K for it to metabolise correctly."
	taste_description = "overripe bananas"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#8080FF"
	metabolism = REM * 0.5
	mrate_static = TRUE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	species_strength = alist(IS_SLIME = 0.25)

/datum/reagent/cryoxadone/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.body_temperature() < 170)
		var/chem_effective = M.species.chem_strength_heal * species_mult(M)
		// Kept: temperature-gated status side effects.
		if(alien == IS_SLIME)
			to_chat(M, span_danger("It's cold. Something causes your cellular mass to harden occasionally, resulting in vibration."))
			M.status_at_least(STAT_WEAKENED, 10)
			M.status_at_least(STAT_MUTED, 10)
			M.status_adjust(STAT_JITTERY, 4)
		// Only works below 170K, a gate a continuous treatment tag can't
		// express, so the cryo-healing mends directly.
		dq_cryo_mend(M, 10 * removed * chem_effective)

/datum/reagent/clonexadone
	name = REAGENT_CLONEXADONE
	id = REAGENT_ID_CLONEXADONE
	description = "A liquid compound similar to that used in the cloning process. Can be used to 'finish' the cloning process when used in conjunction with a cryo tube."
	taste_description = "rotten bananas"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#80BFFF"
	metabolism = REM * 0.5
	mrate_static = TRUE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	species_strength = alist(IS_SLIME = 0.5)

/datum/reagent/clonexadone/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.body_temperature() < 170)
		var/chem_effective = M.species.chem_strength_heal * species_mult(M)
		// Kept: temperature-gated status side effects.
		if(alien == IS_SLIME)
			if(prob(10))
				to_chat(M, span_danger("It's so cold. Something causes your cellular mass to harden sporadically, resulting in seizure-like twitching."))
			M.status_at_least(STAT_WEAKENED, 20)
			M.status_at_least(STAT_MUTED, 20)
			M.status_adjust(STAT_JITTERY, 4)
		// Temperature-gated (see cryoxadone): mends directly.
		dq_cryo_mend(M, 30 * removed * chem_effective)

/// Cryo-chemical regeneration: every tissue mechanism at once. Only for the
/// temperature/death-gated cryo chems, whose gate a continuous tag can't express.
/proc/dq_cryo_mend(mob/living/carbon/M, amount)
	M.mend(TREAT_GENETIC_REPAIR, amount)
	M.mend(TREAT_OXYGENATION, amount)
	M.mend(TREAT_TISSUE_REPAIR, amount)
	M.mend(TREAT_BURN_CARE, amount)
	M.mend(TREAT_ANTITOXIN, amount)

/datum/reagent/mortiferin
	name = REAGENT_MORTIFERIN
	id = REAGENT_ID_MORTIFERIN
	description = "A liquid compound based upon those used in cloning. Utilized in cases of toxic shock. May cause liver damage."
	taste_description = "meat"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#6b4de3"
	metabolism = REM * 0.5
	mrate_static = TRUE
	affects_dead = FALSE //Clarifying this here since the original intent was this ONLY works on people that have the bloodpump_corpse modifier.
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_MASSINDUSTRY
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	species_strength = alist(IS_SLIME = 0.5)

/datum/reagent/mortiferin/on_mob_life(mob/living/carbon/M, alien, datum/reagents/metabolism/location)
	. = ..(M, alien, location)

/datum/reagent/mortiferin/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.body_temperature() < (T0C - 10) || (M.stat == DEAD))
		var/chem_effective = M.species.chem_strength_heal * species_mult(M)
		// Kept: cold-gated status side effects.
		if(alien == IS_SLIME)
			if(prob(10))
				to_chat(M, span_danger("It's so cold. Something causes your cellular mass to solidify sporadically, resulting in uncontrollable twitching."))
			M.status_at_least(STAT_WEAKENED, 10)
			M.status_at_least(STAT_MUTED, 10)
			M.status_adjust(STAT_JITTERY, 4)
		// Cold- or death-gated: mends directly (a tag can't express the gate).
		if(M.stat != DEAD)
			M.mend(TREAT_GENETIC_REPAIR, 5 * removed * chem_effective)
		M.mend(TREAT_OXYGENATION, 10 * removed * chem_effective)
		M.mend(TREAT_ANTITOXIN, 20 * removed * chem_effective)

		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			var/obj/item/organ/internal/liver/L = H.organ_in(O_LIVER)
			if(istype(L) && prob(5))
				if(L.is_robotic())
					return

				H.injure(INJURY_TOXIN, rand(1,3) * removed, L, src, flags = INJURE_IGNORE_RESISTANCE)

/datum/reagent/necroxadone
	// Baseline (warm, living) action; the cryo/corpse boost mends directly.
	treatment_tags = list(TREAT_ANTITOXIN = 0.45, TREAT_GENETIC_REPAIR = 0.3, TREAT_OXYGENATION = 0.2)
	name = REAGENT_NECROXADONE
	id = REAGENT_ID_NECROXADONE
	description = "A liquid compound based upon that which is used in the cloning process. Utilized primarily in severe cases of toxic shock."
	taste_description = "meat"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#94B21C"
	metabolism = REM * 0.5
	mrate_static = TRUE
	scannable = SCANNABLE_BENEFICIAL
	affects_dead = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	species_strength = alist(IS_SLIME = 0.5)

/datum/reagent/necroxadone/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = M.species.chem_strength_heal * species_mult(M)
	if(M.body_temperature() < 170 || (M.stat == DEAD && M.has_body_effect(/datum/body_effect/bloodpump_corpse)))
		// Kept: cold-gated status side effects.
		if(alien == IS_SLIME)
			if(prob(10))
				to_chat(M, span_danger("It's so cold. Something causes your cellular mass to harden sporadically, resulting in seizure-like twitching."))
			M.status_at_least(STAT_WEAKENED, 20)
			M.status_at_least(STAT_MUTED, 20)
			M.status_adjust(STAT_JITTERY, 4)
		// Cold/corpse-gated boost on top of the baseline treatment_tags
		// profile; the gate can't be a tag, so it mends directly.
		M.mend(TREAT_GENETIC_REPAIR, (M.stat != DEAD ? 20 : 15) * removed * chem_effective)
		M.mend(TREAT_OXYGENATION, 20 * removed * chem_effective)
		M.mend(TREAT_ANTITOXIN, 40 * removed * chem_effective)

/* Painkillers */

/datum/reagent/paracetamol
	treatment_tags = list(TREAT_ANALGESIC = 1.0)
	factors = alist(BF_ANALGESIA = 25)
	species_factors = alist(IS_SLIME = alist(BF_ANALGESIA = 18.75))
	name = REAGENT_PARACETAMOL
	id = REAGENT_ID_PARACETAMOL
	description = "Most probably know this as Tylenol, but this chemical is a mild, simple painkiller."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#C8A5DC"
	overdose = REAGENTS_OVERDOSE * 2
	overdose_mod = 0.75
	scannable = SCANNABLE_BENEFICIAL
	metabolism = 0.02
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/paracetamol/overdose(mob/living/carbon/M, alien)
	..()
	M.status_at_least(STAT_HALLUCINATING, 2)

/datum/reagent/tramadol
	factors = alist(BF_ANALGESIA = 80)
	species_factors = alist(IS_SLIME = alist(BF_ANALGESIA = 64, BF_SLOWDOWN = 1, BF_PENALTY_SCALE = 1.25))
	name = REAGENT_TRAMADOL
	id = REAGENT_ID_TRAMADOL
	description = "A simple, yet effective painkiller."
	taste_description = "sourness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#CB68FC"
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 0.75
	scannable = SCANNABLE_BENEFICIAL
	metabolism = 0.02
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/tramadol/overdose(mob/living/carbon/M, alien)
	..()
	M.status_at_least(STAT_HALLUCINATING, 2)

/datum/reagent/oxycodone
	factors = alist(BF_ANALGESIA = 200, BF_SLOWDOWN = 1, BF_PENALTY_SCALE = 1.25)
	species_factors = alist(IS_SLIME = alist(BF_ANALGESIA = 150, BF_SLOWDOWN = 1, BF_PENALTY_SCALE = 1.25))
	name = REAGENT_OXYCODONE
	id = REAGENT_ID_OXYCODONE
	description = "An effective and very addictive painkiller."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#800080"
	overdose = 20
	overdose_mod = 0.75
	scannable = SCANNABLE_BENEFICIAL
	metabolism = 0.02
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_MASSINDUSTRY
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	species_strength = alist(IS_SLIME = 0.75)

/datum/reagent/oxycodone/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = M.species.chem_strength_pain * species_mult(M)
	// Kept: a species-only status side effect.
	if(alien == IS_SLIME)
		M.status_set(STAT_STUTTERING, min(50, max(0, M.status_units(STAT_STUTTERING) + 5))) //If you can't feel yourself, and your main mode of speech is resonation, there's a problem.
	M.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + 10, 250 * chem_effective))

/datum/reagent/oxycodone/overdose(mob/living/carbon/M, alien)
	..()
	M.status_at_least(STAT_DRUGGED, 10)
	M.status_at_least(STAT_HALLUCINATING, 3)

/* Other medicine */

/datum/reagent/synaptizine
	treatment_tags = list(TREAT_NEURAL_REPAIR = 1.0)
	factors = alist(BF_ANALGESIA = 20)
	species_factors = alist(IS_DIONA = null, IS_SLIME = alist(BF_ANALGESIA = 10))
	name = REAGENT_SYNAPTIZINE
	id = REAGENT_ID_SYNAPTIZINE
	description = REAGENT_SYNAPTIZINE + " is used to treat various diseases."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#99CCFF"
	metabolism = REM * 0.05
	mrate_static = TRUE
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/synaptizine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13
	species_strength = alist(IS_SLIME = 0.5)

/datum/reagent/synaptizine/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = M.species.chem_strength_heal * species_mult(M)
	// Kept: a species-only, dose-gated regeneration burst.
	if(alien == IS_SLIME)
		if(dose >= 5) //Not effective in small doses, though it causes toxins at higher ones, it will make the regeneration for brute and burn more 'efficient' at the cost of more nutrition.
			// Species-specific dose-gated regeneration boost: mends directly.
			M.adjust_nutrition(removed * 2)
			M.mend(TREAT_TISSUE_REPAIR, 2 * removed)
			M.mend(TREAT_BURN_CARE, 1 * removed)
	M.status_adjust(STAT_DROWSY, -5)
	M.status_adjust(STAT_PARALYZED, -1)
	M.status_adjust(STAT_STUNNED, -1)
	M.status_adjust(STAT_WEAKENED, -1)
	holder.remove_reagent(REAGENT_ID_MINDBREAKER, 5)
	M.status_adjust(STAT_HALLUCINATING, -10)
	M.injure(INJURY_TOXIN, 10 * removed * chem_effective, source = src) // It used to be incredibly deadly due to an oversight. Not anymore!

/datum/reagent/hyperzine
	treatment_tags = list(TREAT_STIMULANT = 1.0)
	factors = alist(BF_SLOWDOWN = -1, BF_PENALTY_SCALE = 0.5)
	name = REAGENT_HYPERZINE
	id = REAGENT_ID_HYPERZINE
	description = REAGENT_HYPERZINE + " is a highly effective, long lasting, muscle stimulant."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FF3300"
	overdose = REAGENTS_OVERDOSE * 0.5
	scannable = SCANNABLE_ADVANCED
	overdose_mod = 0.25
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_COMSTIM
	species_strength = alist(IS_TAJARA = 1.25)

/datum/reagent/hyperzine/affect_blood(mob/living/carbon/M, alien, removed)
	removed *= species_mult(M)
	// Kept: a species-only, dose-gated status/nutrition side effect.
	if(alien == IS_SLIME)
		M.status_adjust(STAT_JITTERY, 4) //Hyperactive fluid pumping results in unstable 'skeleton', resulting in vibration.
		if(dose >= 5)
			M.adjust_nutrition(-removed * 2) // Sadly this movement starts burning food in higher doses.
	..()
	if(prob(5))
		M.emote(pick("twitch", "blink_r", "shiver"))

/datum/reagent/hyperzine/overdose(mob/living/carbon/M, alien, removed)
	..()
	if(prob(5)) // 1 in 20
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/internal/heart/ht = H.organ_in(O_HEART)
		if(ht)
			H.injure(INJURY_BLUNT, 1, ht, src, flags = INJURE_IGNORE_RESISTANCE)
		to_chat(M, span_warning("Huh... Is this what a heart attack feels like?"))

/datum/reagent/alkysine
	treatment_tags = list(TREAT_NEURAL_REPAIR = 0.5)
	factors = alist(BF_ANALGESIA = 10)
	species_factors = alist(IS_DIONA = null, IS_SLIME = alist(BF_ANALGESIA = 2.5))
	name = REAGENT_ALKYSINE
	id = REAGENT_ID_ALKYSINE
	description = REAGENT_ALKYSINE + " is a drug used to lessen the damage to neurological tissue after a catastrophic injury. Can heal brain tissue."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FFFF66"
	metabolism = REM * 0.25
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/alkysine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/alkysine/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_SLIME)
		if(M.injury_load(INJURY_CATEGORY_NEURAL) >= 10)
			M.status_at_least(STAT_WEAKENED, 5)
		if(dose >= 10 && M.status_units(STAT_PARALYZED) < 40)
			M.status_adjust(STAT_PARALYZED, 1) //Messing with the core with a simple chemical probably isn't the best idea.
	// Brain repair is alkysine's TREAT_NEURAL_REPAIR tag (body/treatment.dm);
	// past the salvage band a swollen brain outpaces it (lesions.dm).

/datum/reagent/imidazoline
	treatment_tags = list(TREAT_OCULAR = 1.0)
	name = REAGENT_IMIDAZOLINE
	id = REAGENT_ID_IMIDAZOLINE
	description = "Heals eye damage"
	taste_description = "dull toxin"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#C8A5DC"
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/imidazoline/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_BLURRY, -5)
	M.status_adjust(STAT_BLINDED, -5)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
		if(istype(E))
			if(E.is_robotic())
				return
			// Eye repair is imidazoline's TREAT_OCULAR tag (body/treatment.dm).
			if(E.damage <= 5 && E.organ_tag == O_EYES)
				H.set_sdisabilities(H.sdisabilities & (~BLIND))

/datum/reagent/peridaxon
	// Generic organ support: weak on every organ-repair mechanism.
	treatment_tags = list(
		TREAT_OCULAR = 0.3,
		TREAT_RESPIRATORY = 0.3,
		TREAT_HEPATORENAL = 0.3,
		TREAT_CARDIAC = 0.3,
		TREAT_DIGESTIVE = 0.3,
	)
	species_factors = alist(IS_SLIME = alist(BF_ANALGESIA = 20))
	name = REAGENT_PERIDAXON
	id = REAGENT_ID_PERIDAXON
	description = "Used to encourage recovery of internal organs and nervous systems. Medicate cautiously."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#561EC3"
	overdose = 10
	overdose_mod = 1.5
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	medallergen_type = MEDALLERGEN_PERIDAX

/datum/reagent/peridaxon/affect_blood(mob/living/carbon/M, alien, removed)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/internal/I in H.internal_organ_list())
			if(I.is_robotic())
				continue
			if(I.damage > 0) // Repair is peridaxon's organ tags; the confusion is its side effect.
				H.status_at_least(STAT_CONFUSED, 5)
			if(I.damage <= 5 && I.organ_tag == O_EYES)
				H.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + 10, 250)) //Eyes need to reset, or something
				H.set_sdisabilities(H.sdisabilities & (~BLIND))
		if(alien == IS_SLIME)
			if(prob(33))
				H.status_at_least(STAT_CONFUSED, 10)

/datum/reagent/peridaxon/overdose(mob/living/carbon/M, alien, removed)
	..()
	M.injure(INJURY_PAIN, 5, source = src)
	M.status_at_least(STAT_HALLUCINATING, 10)

/datum/reagent/osteodaxon
	treatment_tags = list(TREAT_BONE_REPAIR = 1.0, TREAT_TISSUE_REPAIR = 0.3)
	name = REAGENT_OSTEODAXON
	id = REAGENT_ID_OSTEODAXON
	description = "An experimental drug used to heal bone fractures."
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#C9BCE3"
	metabolism = REM * 0.5
	overdose = REAGENTS_OVERDOSE * 0.5
	overdose_mod = 1.5
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_MASSINDUSTRY
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/osteodaxon
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/osteodaxon/affect_blood(mob/living/carbon/M, alien, removed)
	// Light tissue repair ("gives the bones a chance to set") is in the treatment_tags profile.
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/totalvol = 0
		if(H.ingested)
			for(var/datum/reagent/R in H.ingested.reagent_list)
				if(istype(R,/datum/reagent/osteodaxon))
					totalvol += R.volume
		totalvol += volume
		if(totalvol >= 1)
			for(var/obj/item/organ/external/O in H.damaged_limbs())
				if(dq_reagent_knit_fracture(O))
					H.custom_pain(span_danger(span_normal(span_bold("You feel a terrible agony tear through your [O.name]!"))),60,TRUE)
					H.status_adjust(STAT_WEAKENED, 10)		//Bones being regrown will knock you over
					H.injure(INJURY_PAIN, 60, O.organ_tag, source = src)
					H.status_adjust(STAT_STUNNED, 1)		//Bones being regrown will knock you over

/datum/reagent/myelamine
	// The clotting agent: runs down bleeds; its wound closure is affect_blood.
	treatment_tags = list(TREAT_HEMOSTATIC = 1.0)
	name = REAGENT_MYELAMINE
	id = REAGENT_ID_MYELAMINE
	description = "Used to rapidly clot hemorrhages by increasing the effectiveness of platelets. An ideal dosage of 10 units will fully heal any internal hemorrhages."
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#4246C7"
	metabolism = REM * 0.75
	overdose = REAGENTS_OVERDOSE * 0.5
	overdose_mod = 1.5
	scannable = SCANNABLE_BENEFICIAL
	var/repair_strength = 6
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/myelamine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/myelamine/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + (repair_strength * removed), 250))
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/wound_heal = removed * repair_strength
		// B13: clotting through mend(): one wound per limb dressed (the clot), its
		// damage repaired, and internal bleeds closed by vessel repair.
		var/sweet_zone = (dose >= 9.5 && dose < 11) // a 10u pen or pill fixes internal bleeding outright
		for(var/obj/item/organ/external/O as anything in H.organs)
			if(!LAZYLEN(O.get_wounds()))
				continue
			H.mend(TREAT_WOUND_PACKING, 1, O)
			H.mend(TREAT_TISSUE_REPAIR, wound_heal * 3.5, O)
			H.mend(TREAT_VESSEL_REPAIR, sweet_zone ? DQ_REAGENT_KNIT_AMOUNT : wound_heal, O)

/datum/reagent/myelamine/overdose(mob/living/carbon/M, alien, removed)
	//Heals slightly faster at the cost of high toxins. Honestly you should never do this, but whatever.
	..()
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/wound_heal = removed * repair_strength / 2
		for(var/obj/item/organ/external/O as anything in H.damaged_limbs())
			dq_reagent_close_wounds(O, wound_heal, bleeding = FALSE)

/// P2-D6 / P2-K6: the -daxon organ-repair family as data. Repair itself is
/// each drug's organ treatment tag; this shared body applies the side effects:
/// confusion while a targeted (organic) organ is damaged, then either the clash
/// with a partner reagent or the drug's solo effect. A drug sets its organ
/// targets and partners by overriding the two getters.
TYPE_TABLE_DECLARE(/datum/reagent, daxon_organs, null)

TYPE_TABLE_DECLARE(/datum/reagent, daxon_partners, null)

/datum/reagent/proc/daxon_clash(mob/living/carbon/human/H, removed)
	return

/datum/reagent/proc/daxon_alone(mob/living/carbon/human/H, removed)
	return

/datum/reagent/proc/daxon_affect(mob/living/carbon/M, removed)
	if(!ishuman(M))
		return
	var/mob/living/carbon/human/H = M
	var/list/targets = TYPE_TABLE_GET(src, daxon_organs)
	for(var/obj/item/organ/internal/I as anything in H.internal_organ_list())
		if(I.is_robotic() || !(I.organ_tag in targets))
			continue
		if(I.damage > 0)
			H.status_at_least(STAT_CONFUSED, 2)
			break
	for(var/partner in TYPE_TABLE_GET(src, daxon_partners))
		if(H.body?.reagent_volume(partner))
			daxon_clash(H, removed)
			return
	daxon_alone(H, removed)

/datum/reagent/respirodaxon/affect_blood(mob/living/carbon/M, alien, removed)
	daxon_affect(M, removed)

/datum/reagent/gastirodaxon/affect_blood(mob/living/carbon/M, alien, removed)
	daxon_affect(M, removed)

/datum/reagent/hepanephrodaxon/affect_blood(mob/living/carbon/M, alien, removed)
	daxon_affect(M, removed)

/datum/reagent/cordradaxon/affect_blood(mob/living/carbon/M, alien, removed)
	daxon_affect(M, removed)

/datum/reagent/respirodaxon
	treatment_tags = list(TREAT_RESPIRATORY = 1.0)
	name = REAGENT_RESPIRODAXON
	id = REAGENT_ID_RESPIRODAXON
	description = "Used to repair the tissue of the lungs and similar organs."
	taste_description = "metallic"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#4444FF"
	metabolism = REM * 1.5
	overdose = 10
	overdose_mod = 1.75
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

TYPE_TABLE(/datum/reagent/respirodaxon, daxon_organs, list(O_LUNGS, O_VOICE, O_GBLADDER))

TYPE_TABLE(/datum/reagent/respirodaxon, daxon_partners, list(REAGENT_ID_GASTIRODAXON, REAGENT_ID_PERIDAXON))

/datum/reagent/respirodaxon/daxon_clash(mob/living/carbon/human/H, removed)
	if(H.losebreath >= 15 && prob(H.losebreath))
		H.status_at_least(STAT_STUNNED, 2)
	else
		H.losebreath = CLAMP(H.losebreath + 3, 0, 20)

/datum/reagent/respirodaxon/daxon_alone(mob/living/carbon/human/H, removed)
	H.losebreath = max(H.losebreath - 4, 0)

/datum/reagent/gastirodaxon
	treatment_tags = list(TREAT_DIGESTIVE = 1.0, TREAT_ANTITOXIN = 0.6)
	name = REAGENT_GASTIRODAXON
	id = REAGENT_ID_GASTIRODAXON
	description = "Used to repair the tissues of the digestive system."
	taste_description = "chalk"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#8B4513"
	metabolism = REM * 1.5
	overdose = 10
	overdose_mod = 1.75
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

TYPE_TABLE(/datum/reagent/gastirodaxon, daxon_organs, list(O_APPENDIX, O_STOMACH, O_INTESTINE, O_NUTRIENT, O_PLASMA, O_POLYP))

TYPE_TABLE(/datum/reagent/gastirodaxon, daxon_partners, list(REAGENT_ID_HEPANEPHRODAXON, REAGENT_ID_PERIDAXON))

/datum/reagent/gastirodaxon/daxon_clash(mob/living/carbon/human/H, removed)
	if(prob(10))
		H.vomit(1)
	else if(H.nutrition > 30)
		H.adjust_nutrition(-removed * 30)

/datum/reagent/hepanephrodaxon
	treatment_tags = list(TREAT_HEPATORENAL = 1.0, TREAT_ANTITOXIN = 0.7)
	name = REAGENT_HEPANEPHRODAXON
	id = REAGENT_ID_HEPANEPHRODAXON
	description = "Used to repair the common tissues involved in filtration."
	taste_description = "glue"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#D2691E"
	metabolism = REM * 1.5
	overdose = 10
	overdose_mod = 1.75
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

TYPE_TABLE(/datum/reagent/hepanephrodaxon, daxon_organs, list(O_LIVER, O_KIDNEYS, O_APPENDIX, O_ACID, O_HIVE))

TYPE_TABLE(/datum/reagent/hepanephrodaxon, daxon_partners, list(REAGENT_ID_CORDRADAXON, REAGENT_ID_PERIDAXON))

/datum/reagent/hepanephrodaxon/daxon_clash(mob/living/carbon/human/H, removed)
	if(prob(5))
		H.vomit(1)
	else if(prob(5))
		to_chat(H, span_danger("Something churns inside you."))
		H.injure(INJURY_TOXIN, 10 * removed, source = src)
		H.vomit(0, 1)

/datum/reagent/cordradaxon
	treatment_tags = list(TREAT_CARDIAC = 1.0, TREAT_OXYGENATION = 0.6)
	name = REAGENT_CORDRADAXON
	id = REAGENT_ID_CORDRADAXON
	description = "Used to repair the specialized tissues involved in the circulatory system."
	taste_description = "rust"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FF4444"
	metabolism = REM * 1.5
	overdose = 10
	overdose_mod = 1.75
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

TYPE_TABLE(/datum/reagent/cordradaxon, daxon_organs, list(O_HEART, O_SPLEEN, O_RESPONSE, O_ANCHOR, O_EGG))

TYPE_TABLE(/datum/reagent/cordradaxon, daxon_partners, list(REAGENT_ID_HYRONALIN, REAGENT_ID_PERIDAXON))

/datum/reagent/cordradaxon/daxon_clash(mob/living/carbon/human/H, removed)
	H.losebreath = CLAMP(H.losebreath + 1, 0, 10)

/datum/reagent/immunosuprizine
	name = REAGENT_IMMUNOSUPRIZINE
	id = REAGENT_ID_IMMUNOSUPRIZINE
	description = "An experimental powder believed to have the ability to prevent any organ rejection."
	taste_description = "flesh"
	reagent_state = SOLID
	dermal_absorption = 0
	color = "#7B4D4F"
	overdose = 20
	overdose_mod = 1.5
	scannable = SCANNABLE_BENEFICIAL
	metabolism = REM * 0.06
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	// Diona: it's a tree. Slime: difficulty bonding with internal cellular structure.
	// Unathi: natural regeneration, robust biology. Tajara: highest metabolism.
	species_strength = alist(IS_DIONA = 4, IS_SLIME = 1.3, IS_UNATHI = 0.6, IS_TAJARA = 0.5)

/datum/reagent/immunosuprizine/affect_blood(mob/living/carbon/M, alien, removed)
	var/strength_mod = species_mult(M) // * M.species.chem_strength_heal //Just removing the chem strength adjustment. It'd require division, which is best avoided.

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!inert_for(H)) // inert_species (diona): no rejection toxin
			H.injure(INJURY_TOXIN, (30 * strength_mod) * removed, source = src)

		var/list/organtotal = list()
		organtotal |= H.organs
		organtotal |= H.internal_organ_list()

		for(var/obj/item/organ/I in organtotal)	// Don't mess with robot bits, they don't reject.
			if(I.is_robotic())
				organtotal -= I

		if(dose >= 15)
			for(var/obj/item/organ/I in organtotal)
				if(I.transplant_data && prob(round(15 * strength_mod)))	// Reset the rejection process, toggle it to not reject.
					I.rejecting = 0
					I.can_reject = FALSE

		if(H.body?.treatment_levels()?[TREAT_ANTIMICROBIAL]) // P2-K6: the mechanism, not the reagent IDs	// Chemicals that increase your immune system's aggressiveness make this chemical's job harder.
			for(var/obj/item/organ/I in organtotal)
				if(I.transplant_data)
					var/rejectmem = I.can_reject
					I.can_reject = initial(I.can_reject)
					if(rejectmem != I.can_reject)
						H.injure(INJURY_TOXIN, (15 / strength_mod) * removed, source = src) //Someone forgot a * removed here in the past. It made it so 1u of this chem would do (baseline) 1245 toxins per unit, or 15 toxins per tick.
						H.injure(INJURY_TOXIN, 1, I, src, flags = INJURE_IGNORE_RESISTANCE)

/datum/reagent/skrellimmuno //skrell exist?
	name = REAGENT_MALISHQUALEM
	id = REAGENT_ID_MALISHQUALEM
	description = "A strange, oily powder used by Malish-Katish to prevent organ rejection."
	taste_description = "mordant"
	reagent_state = SOLID
	dermal_absorption = 0
	color = "#84B2B0"
	metabolism = REM * 0.06
	overdose = 20
	overdose_mod = 1.5
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	/// Skrell take none of the rejection toxin (a multiplier on that toxin only).
	species_strength = alist(IS_SKRELL = 0)

/datum/reagent/skrellimmuno/affect_blood(mob/living/carbon/M, alien, removed)
	var/strength_mod = 0.5 * M.species.chem_strength_heal
	// B16: a species with no healing strength must not divide the rejection toxin by zero.
	var/toxin_divisor = max(strength_mod, 0.1)

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/toxin_mult = species_mult(H)
		if(toxin_mult)
			H.injure(INJURY_TOXIN, 20 * removed * toxin_mult, source = src)

		var/list/organtotal = list()
		organtotal |= H.organs
		organtotal |= H.internal_organ_list()

		for(var/obj/item/organ/I in organtotal)	// Don't mess with robot bits, they don't reject.
			if(I.is_robotic())
				organtotal -= I

		if(dose >= 15)
			for(var/obj/item/organ/I in organtotal)
				if(I.transplant_data && prob(round(15 * strength_mod)))
					I.rejecting = 0
					I.can_reject = FALSE

		if(H.body?.treatment_levels()?[TREAT_ANTIMICROBIAL]) // P2-K6: the mechanism, not the reagent IDs
			for(var/obj/item/organ/I in organtotal)
				if(I.transplant_data)
					var/rejectmem = I.can_reject
					I.can_reject = initial(I.can_reject)
					if(rejectmem != I.can_reject)
						H.injure(INJURY_TOXIN, (10 / toxin_divisor) * removed, source = src) // B16: per unit metabolised
						H.injure(INJURY_TOXIN, 1, I, src, flags = INJURE_IGNORE_RESISTANCE)

/datum/reagent/ryetalyn
	treatment_tags = list(TREAT_GENETIC_REPAIR = 0.5)
	name = REAGENT_RYETALYN
	id = REAGENT_ID_RYETALYN
	description = REAGENT_RYETALYN + " can cure DNA, Cloning, and genetic damage via a catalytic process."
	taste_description = "acid"
	reagent_state = SOLID
	dermal_absorption = 0
	scannable = SCANNABLE_BENEFICIAL
	color = "#004000"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG

// Ryetalyn's genetic repair is its treatment_tags profile. It is for genetic damage, not resetting mutations (breaks traitgenes).

/*/datum/reagent/hyperzine
	name = REAGENT_HYPERZINE
	id = REAGENT_ID_HYPERZINE
	description = "Hyperzine is a highly effective, long lasting, muscle stimulant."
	reagent_state = LIQUID
	color = "#FF3300"
	metabolism = REM * 1
	mrate_static = TRUE
	overdose = REAGENTS_OVERDOSE * 0.5

/datum/reagent/hyperzine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/hyperzine/affect_blood(mob/living/carbon/M, alien, removed)
	if(prob(5))
		M.emote(pick("twitch", "blink_r", "shiver"))
*/
/datum/reagent/ethylredoxrazine
	name = REAGENT_ETHYLREDOXRAZINE
	id = REAGENT_ID_ETHYLREDOXRAZINE
	description = "A powerful oxidizer that reacts with ethanol."
	taste_description = "bitterness"
	reagent_state = SOLID
	dermal_absorption = 0
	scannable = SCANNABLE_BENEFICIAL
	color = "#605048"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_RECDRUG

/datum/reagent/ethylredoxrazine
	immune_species_ingest = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/ethylredoxrazine/affect_ingest(mob/living/carbon/M, alien, removed)
	M.status_end(STAT_DIZZY)
	M.status_set(STAT_DROWSY, 0)
	M.status_set(STAT_STUTTERING, 0)
	M.status_set(STAT_CONFUSED, 0)
	if(M.ingested)
		for(var/datum/reagent/R in M.ingested.reagent_list)
			if(istype(R, /datum/reagent/ethanol))
				R.remove_self(removed * 30)

/datum/reagent/ethylredoxrazine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/ethylredoxrazine/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_end(STAT_DIZZY)
	M.status_set(STAT_DROWSY, 0)
	M.status_set(STAT_STUTTERING, 0)
	M.status_set(STAT_CONFUSED, 0)
	if(M.bloodstr)
		for(var/datum/reagent/R in M.bloodstr.reagent_list)
			if(istype(R, /datum/reagent/ethanol))
				R.remove_self(removed * 20)

/datum/reagent/hyronalin
	treatment_tags = list(TREAT_ANTIRADIATION = 0.5)
	name = REAGENT_HYRONALIN
	id = REAGENT_ID_HYRONALIN
	description = REAGENT_HYRONALIN + " is a medicinal drug used to counter the effect of radiation poisoning."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#408000"
	metabolism = REM * 0.25
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/hyronalin
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/hyronalin/affect_blood(mob/living/carbon/M, alien, removed)
	// B14: radiation purge is the TREAT_ANTIRADIATION tag (purge_radiation()).

/datum/reagent/arithrazine
	treatment_tags = list(TREAT_ANTIRADIATION = 1.0, TREAT_ANTITOXIN = 0.6)
	name = REAGENT_ARITHRAZINE
	id = REAGENT_ID_ARITHRAZINE
	description = REAGENT_ARITHRAZINE + " is an unstable medication used for the most extreme cases of radiation poisoning."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#008000"
	metabolism = REM * 0.25
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 1.25
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG

/datum/reagent/arithrazine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/arithrazine/affect_blood(mob/living/carbon/M, alien, removed)
	// B14: radiation purge is the TREAT_ANTIRADIATION tag (purge_radiation()).
	// Its antitoxin action is in the treatment_tags profile.
	if(prob(60))
		M.injure(INJURY_BLUNT, 4 * removed, source = src)

/datum/reagent/spaceacillin
	treatment_tags = list(TREAT_ANTIMICROBIAL = 1.0)
	factors = alist(BF_ANTIMICROBIAL = ANTIBIO_NORM)
	name = REAGENT_SPACEACILLIN
	id = REAGENT_ID_SPACEACILLIN
	description = "An all-purpose antiviral agent."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#C1C1C1"
	metabolism = REM * 0.25
	mrate_static = TRUE
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	data = 0
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_SPACACIL

/datum/reagent/spaceacillin/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(alien == IS_SLIME)
		if(volume <= 0.1 && data != -1)
			data = -1
			to_chat(M, span_notice("You regain focus..."))
		else
			var/delay = (5 MINUTES)
			if(ELAPSED_SINCE(src, data, CLOCK_WORLD) > delay)
				data = EXPIRY_AT(src, CLOCK_WORLD, 0) // ALLOW(sys_world_time_write): reagent `data` is an untyped per-reagent payload slot, not a declarable var
				to_chat(M, span_warning("Your senses feel unfocused, and divided."))

/datum/reagent/spaceacillin/affect_touch(mob/living/carbon/M, alien, removed)
	affect_blood(M, alien, removed * 0.8) // Not 100% as effective as injections, though still useful.

/datum/reagent/corophizine
	treatment_tags = list(TREAT_ANTIMICROBIAL = 1.3)
	factors = alist(BF_ANTIMICROBIAL = ANTIBIO_SUPER)
	name = REAGENT_COROPHIZINE
	id = REAGENT_ID_COROPHIZINE
	description = "A wide-spectrum antibiotic drug. Powerful and uncomfortable in equal doses."
	taste_description = "burnt toast"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FFB0B0"
	mrate_static = TRUE
	overdose = 10
	overdose_mod = 1.5
	scannable = SCANNABLE_BENEFICIAL
	data = 0
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/corophizine/affect_blood(mob/living/carbon/M, alien, removed)
	..()

	var/mob/living/carbon/human/H = M

	if(ishuman(M) && alien == IS_SLIME) //Everything about them is treated like a targetted organism. Widespread bodily function begins to fail.
		if(volume <= 0.1 && data != -1)
			data = -1
			to_chat(M, span_notice("Your body ceases its revolt."))
		else
			var/delay = (3 MINUTES)
			if(ELAPSED_SINCE(src, data, CLOCK_WORLD) > delay)
				data = EXPIRY_AT(src, CLOCK_WORLD, 0) // ALLOW(sys_world_time_write): reagent `data` is an untyped per-reagent payload slot, not a declarable var
				to_chat(M, span_critical("It feels like your body is revolting!"))
		M.status_at_least(STAT_CONFUSED, 7)
		M.injure(INJURY_BURN, removed * 2, source = src)
		M.injure(INJURY_TOXIN, removed * 2, source = src)
		var/toxic_load = M.injury_load(INJURY_CATEGORY_TOXIC)
		if(dose >= 5 && toxic_load >= 10) //It all starts going wrong.
			M.injure(INJURY_BLUNT, removed * 3, source = src)
			M.status_set(STAT_BLURRY, min(20, max(0, M.status_units(STAT_BLURRY) + 10)))
			if(prob(25))
				if(prob(25))
					to_chat(M, span_danger("Your pneumatic fluids seize for a moment."))
				M.status_at_least(STAT_STUNNED, 2)
				after(M, 3 SECONDS, TYPE_PROC_REF(/datum, status_at_least), with = list(STAT_WEAKENED, 2))
		if(dose >= 10 || toxic_load >= 25) //Internal skeletal tubes are rupturing, allowing the chemical to breach them.
			M.injure(INJURY_TOXIN, removed * 4, source = src)
			M.status_adjust(STAT_JITTERY, 5)
		if(dose >= 20 || toxic_load >= 60) //Core disentigration, cellular mass begins treating itself as an enemy, while maintaining regeneration. Slime-cancer.
			M.injure(INJURY_NEURAL, 2 * removed, source = src)
			M.adjust_nutrition(-20)
		if(M.injury_load(INJURY_CATEGORY_PHYSICAL) >= 60 && toxic_load >= 60 && M.injury_load(INJURY_CATEGORY_NEURAL) >= 30) //Total Structural Failure. Limbs start splattering.
			var/obj/item/organ/external/O = pick(H.organs)
			if(prob(20) && !istype(O, /obj/item/organ/external/chest/unbreakable/slime) && !istype(O, /obj/item/organ/external/groin/unbreakable/slime))
				to_chat(M, span_critical("You feel your [O] begin to dissolve, before it sloughs from your body."))
				O.droplimb(TRUE, DROPLIMB_ACID)
		return

	//Based roughly on Levofloxacin's rather severe side-effects
	if(prob(20))
		M.status_at_least(STAT_CONFUSED, 5)
	if(prob(20))
		M.status_at_least(STAT_WEAKENED, 5)
	if(prob(20))
		M.status_adjust(STAT_DIZZY, 5)
	if(prob(20))
		M.status_at_least(STAT_HALLUCINATING, 10)

	//One of the levofloxacin side effects is 'spontaneous tendon rupture', which I'll immitate here. 1:1000 chance, so, pretty darn rare.
	if(ishuman(M) && rand(1,10000) == 1) //Adjusted to 1:10000
		var/obj/item/organ/external/eo = pick(H.organs) //Misleading variable name, 'organs' is only external organs
		// P2-K5: an injury the body resolves into a fracture, not a direct write.
		H.injure(INJURY_BLUNT, eo.min_broken_damage, eo, source = src, affliction = /datum/affliction/untreated_fracture)

/datum/reagent/spacomycaze
	treatment_tags = list(TREAT_ANTIMICROBIAL = 0.8)
	factors = alist(BF_ANALGESIA = 20, BF_ANTIMICROBIAL = ANTIBIO_NORM)
	name = REAGENT_SPACOMYCAZE
	id = REAGENT_ID_SPACOMYCAZE
	description = "An all-purpose painkilling antibiotic gel."
	taste_description = "oil"
	reagent_state = SOLID
	dermal_absorption = 0
	color = "#C1C1C8"
	metabolism = REM * 0.4
	mrate_static = TRUE
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	data = 0
	can_overdose_touch = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/spacomycaze/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 3 * removed, source = src)

/datum/reagent/spacomycaze/affect_ingest(mob/living/carbon/M, alien, removed)
	affect_blood(M, alien, removed * 0.8)

/datum/reagent/spacomycaze/affect_touch(mob/living/carbon/M, alien, removed)
	if(alien == IS_SLIME)
		if(volume <= 0.1 && data != -1)
			data = -1
			to_chat(M, span_notice("The itching fades..."))
		else
			var/delay = (2 MINUTES)
			if(ELAPSED_SINCE(src, data, CLOCK_WORLD) > delay)
				data = EXPIRY_AT(src, CLOCK_WORLD, 0) // ALLOW(sys_world_time_write): reagent `data` is an untyped per-reagent payload slot, not a declarable var
				to_chat(M, span_warning("Your skin itches."))

/datum/reagent/spacomycaze/touch_obj(obj/O)
	..()
	if(istype(O, /obj/item/stack/medical) && round(volume) >= 1)
		var/obj/item/stack/medical/C = O
		var/packname = C.name
		var/to_produce = min(C.get_amount(), round(volume))

		var/obj/item/stack/medical/M = C.upgrade_stack(to_produce)

		if(M && M.get_amount())
			holder.my_atom.visible_message(span_infoplain(span_bold("\The [packname]") + " bubbles."))
			remove_self(to_produce)

/datum/reagent/sterilizine
	name = REAGENT_STERILIZINE
	id = REAGENT_ID_STERILIZINE
	description = "Sterilizes wounds in preparation for surgery and thoroughly removes blood. Can additionally be used to prepare a surface for surgery to lower risk of infection."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0 //Custom touch handling.
	color = "#C8A5DC"
	scannable = SCANNABLE_BENEFICIAL
	touch_met = 5
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_CLEAN
	species_injuries_blood = alist(IS_SLIME = alist(INJURY_CORROSIVE = 1, INJURY_TOXIN = 2))
	species_injuries_touch = alist(IS_SLIME = alist(INJURY_CORROSIVE = 1, INJURY_TOXIN = 2))

/datum/reagent/sterilizine/affect_touch(mob/living/carbon/M, alien, removed)
	M.adjust_germ_level(-removed * 20)
	for(var/obj/item/I in contents_of(M))
		dq_set_was_bloodied(I, null)
	dq_set_was_bloodied(M, null)

/datum/reagent/sterilizine/touch_obj(obj/O)
	..()
	O.adjust_germ_level(-volume * 200)
	dq_set_was_bloodied(O, null)

/datum/reagent/sterilizine/touch_turf(turf/T)
	..()
	T.adjust_germ_level(-volume * 200)
	for(var/obj/item/I in turf_contents_of_type(T, /obj/item))
		dq_set_was_bloodied(I, null)
	for(var/obj/effect/decal/cleanable/blood/B in turf_contents_of_type(T, /obj/effect/decal/cleanable/blood))
		dissolved(B)

	if(istype(T, /turf/simulated))
		var/turf/simulated/S = T
		S.dirt = -50

/datum/reagent/sterilizine/touch_mob(mob/living/L, amount)
	..()
	if(istype(L))
		if(istype(L, /mob/living/simple_mob/slime))
			var/mob/living/simple_mob/slime/S = L
			S.injure(INJURY_CORROSIVE, rand(15, 25) * amount, source = src)	// Does more damage than water.
			act_message(S, null, MSG_SELF(span_danger("Your flesh burns in the fluid!")), \
				MSG_OTHERS(span_warning("%U%'s flesh sizzles where the fluid touches it!")))
		remove_self(amount)

/datum/reagent/leporazine
	treatment_tags = list(TREAT_THERMOREGULATION = 1.0)
	name = REAGENT_LEPORAZINE
	id = REAGENT_ID_LEPORAZINE
	description = "Leporazine can be use to stabilize an individuals body temperature."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#C8A5DC"
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	coolant_modifier = 0.5 // Okay substitute coolant

// B15: leporazine's temperature correction is its TREAT_THERMOREGULATION tag,
// applied by the thermoregulation life stage (no second, unscaled write here).

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
	name = REAGENT_REZADONE
	id = REAGENT_ID_REZADONE
	description = "A powder with almost magical properties, this substance can effectively treat genetic damage in humanoids, though excessive consumption has side effects."
	taste_description = "bitterness"
	reagent_state = SOLID
	dermal_absorption = 0 //solid powder
	color = "#669900"
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 2
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_MASSINDUSTRY
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG

/datum/reagent/rezadone
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/rezadone/affect_blood(mob/living/carbon/M, alien, removed)
	var/mob/living/carbon/human/H = M
	if(alien == IS_SLIME && istype(H))
		if(prob(50))
			if(H.r_skin)
				H.r_skin = round((H.r_skin + 50)/2)
			if(H.r_hair)
				H.r_hair = round((H.r_hair + 50)/2)
			if(H.r_facial)
				H.r_facial = round((H.r_facial + 50)/2)
		if(prob(50))
			if(H.g_skin)
				H.g_skin = round((H.g_skin + 50)/2)
			if(H.g_hair)
				H.g_hair = round((H.g_hair + 50)/2)
			if(H.g_facial)
				H.g_facial = round((H.g_facial + 50)/2)
		if(prob(50))
			if(H.b_skin)
				H.b_skin = round((H.b_skin + 50)/2)
			if(H.b_hair)
				H.b_hair = round((H.b_hair + 50)/2)
			if(H.b_facial)
				H.b_facial = round((H.b_facial + 50)/2)
	// Rezadone's regeneration is its treatment_tags profile.
	if(dose > 3)
		M.set_status_flags(M.status_flags & ~DISFIGURED)
	if(dose > 10)
		M.status_adjust(STAT_DIZZY, 5)
		M.status_adjust(STAT_JITTERY, 5)

// This exists to cut the number of chemicals a merc borg has to juggle on their hypo.
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
	name = REAGENT_HEALINGNANITES
	id = REAGENT_ID_HEALINGNANITES
	description = "Miniature medical robots that swiftly restore bodily damage."
	taste_description = "metal"
	reagent_state = SOLID
	color = "#555555"
	metabolism = REM * 4 // Nanomachines gotta go fast.
	scannable = SCANNABLE_BENEFICIAL
	affects_robots = TRUE
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

// Healing nanites' repair (organic and synthetic) is their treatment_tags profile.

/datum/reagent/menthol
	name = REAGENT_MENTHOL
	id = REAGENT_ID_MENTHOL
	description = "Tastes naturally minty, and imparts a very mild numbing sensation."
	taste_description = "mint"
	reagent_state = LIQUID
	color = "#80af9c"
	metabolism = REM * 0.002
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/earthsblood
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.6,
		TREAT_BURN_CARE = 0.6,
		TREAT_OXYGENATION = 0.5,
		TREAT_ANTITOXIN = 0.5,
		TREAT_GENETIC_REPAIR = 0.3,
	)
	name = REAGENT_EARTHSBLOOD
	id = REAGENT_ID_EARTHSBLOOD
	description = "A rare plant extract with immense, almost magical healing capabilities. Induces a potent psychoactive state, damaging neurons with prolonged use."
	taste_description = "honey and sunlight"
	reagent_state = LIQUID
	dermal_absorption = 0.25
	color = "#ffb500"
	overdose = REAGENTS_OVERDOSE * 0.50
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	scannable = SCANNABLE_BENEFICIAL

/datum/reagent/earthsblood/affect_blood(mob/living/carbon/M, alien, removed)
	// The healing is the treatment_tags profile; the Tithe is paid here.
	M.status_at_least(STAT_DRUGGED, 20)
	M.status_at_least(STAT_HALLUCINATING, 3)
	M.injure(INJURY_NEURAL, 1 * removed, source = src) //your life for your mind. The Earthmother's Tithe.


// Vat clone stablizer
/datum/reagent/acid/artificial_sustenance
	name = REAGENT_ASUSTENANCE
	id = REAGENT_ID_ASUSTENANCE
	description = "A drug used to stablize vat grown bodies. Often used to control the lifespan of biological experiments." // Who else remembers Cybersix?
	taste_description = "burning metal"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#31d422"
	overdose = 15
	overdose_mod = 1.2
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/acid/artificial_sustenance/affect_ingest(mob/living/carbon/M, alien, removed)
	// You need me...
	if(M.get_addiction_to_reagent(REAGENT_ID_ASUSTENANCE))
		return
	// Continue to acid damage, no changes on injection or splashing, as this is meant to be edible only to those pre-addicted to it! Not a snowflake acid that doesn't hurt you!
	. = ..()

/datum/reagent/acid/artificial_sustenance/handle_addiction(mob/living/carbon/M, alien)
	// A copy of the base with withdrawl, but with death, and different messages
	var/current_addiction = M.get_addiction_to_reagent(id)
	// slow degrade
	if(prob(2))
		current_addiction  -= 1
	// withdrawl mechanics
	if(prob(2))
		if(current_addiction <= 40)
			to_chat(M, span_danger("You're dying for some [name]!"))
		else if(current_addiction <= 60)
			to_chat(M, span_warning("You're really craving some [name]."))
		else if(current_addiction <= 100)
			to_chat(M, span_notice("You're feeling the need for some [name]."))
		// effects
		if(current_addiction < 60 && prob(20))
			M.emote(pick("pale","shiver","twitch"))
	// Agony and death!
	if(current_addiction <= 20)
		if(prob(12))
			M.injure(INJURY_TOXIN, rand(1,4), source = src)
			M.injure(INJURY_BLUNT, rand(1,4), source = src)
			M.AdjustLosebreath(rand(1,2)) // Withdrawal seizes the chest.
	// proc side effect
	if(current_addiction <= 30)
		if(prob(3))
			M.status_at_least(STAT_WEAKENED, 2)
			M.emote("vomit")
			M.apply_body_effect(/datum/body_effect/withdrawal_strain/severe, 3 SECONDS)
	else if(current_addiction <= 40)
		if(prob(3))
			M.emote("vomit")
			M.apply_body_effect(/datum/body_effect/withdrawal_strain/moderate, 3 SECONDS)
	else if(current_addiction <= 50)
		if(prob(2))
			M.emote("vomit")
	// Sustenance requirements cannot be escaped!
	if(current_addiction <= 0)
		current_addiction = 40
	return current_addiction


// === merged from medicine_ch.dm during hard-fork de-suffix (verified no override-order change) ===
////////////////////////////////////
////////////   MEDICINE   /////////
//////////////////////////////////
/datum/reagent/claridyl
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.25)
	factors = alist(BF_ANALGESIA = 40, BF_STABILIZATION = 30)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_CLARIDYL
	id = REAGENT_ID_CLARIDYL
	description = "Claridyl is an advanced medicine that cures all of your problems. Notice: Clarydil does not claim to fix marriages, car loans, student debt or insomnia and may cause severe pain."
	taste_description = "sugar"
	reagent_state = LIQUID
	color = "#AAAAFF"
	overdose = REAGENTS_OVERDOSE * 100
	metabolism = REM * 0.1
	dermal_absorption = 1
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/claridyl/affect_blood(mob/living/carbon/M, alien, removed)
	// Its trauma repair is the treatment_tags profile; mending hurts.
	if(M.injury_load(INJURY_CATEGORY_PHYSICAL))
		M.injure(INJURY_PAIN, 1.5, source = src)
	if(prob(0.0001))
		M.injure(INJURY_TOXIN, 50, source = src)//instant crit for tesh

	if(prob(0.1))
		claridyl_side_effect(M, rand(1, 10))

/// One of claridyl's rare side effects (B5: pick() used to evaluate all ten at once).
/datum/reagent/claridyl/proc/claridyl_side_effect(mob/living/carbon/M, which)
	switch(which)
		if(1)
			M.custom_pain("You suddenly feel inexplicably angry!",30)
		if(2)
			M.custom_pain("You suddenly lose your train of thought!",30)
		if(3)
			M.custom_pain("Your mouth feels dry!",30)
		if(4)
			M.status_adjust(STAT_DIZZY, 2)
		if(5)
			M.status_adjust(STAT_WEAKENED, 10)
		if(6)
			M.status_adjust(STAT_STUNNED, 1)
		if(7)
			M.status_adjust(STAT_PARALYZED, 0.1)
		if(8)
			M.status_set(STAT_HALLUCINATING, max(M.status_units(STAT_HALLUCINATING), 2))
		if(9)
			M.flash_eyes()
		else
			M.custom_pain("Your vision becomes blurred!",30)

/datum/reagent/claridyl/bloodburn
	treatment_tags = null
	name = REAGENT_BLOODBURN
	id = REAGENT_ID_BLOODBURN
	description = "A chemical used to soak up any reagents inside someones stomach, injection is not advised, if you need to ask why please seek a new job."
	taste_description = "liquid void"
	dermal_absorption = 0
	color = "#000000"
	metabolism = REM * 5
	// B19: a stomach-scouring agent, not a painkiller: none of claridyl's factors.
	factors = null
	species_factors = null
	immune_species_blood = 0

/datum/reagent/claridyl/bloodburn/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.bloodstr)//No seriously dont inject this wtf is wrong with you.
		for(var/datum/reagent/R in M.bloodstr.reagent_list)
			if(istype(R, /datum/reagent/blood))
				R.remove_self(removed * 15)

/datum/reagent/claridyl/bloodburn/affect_ingest(mob/living/carbon/M, alien, removed)
	if(M.ingested)
		for(var/datum/reagent/R in M.ingested.reagent_list)
			if(istype(R, /datum/reagent/ethanol))
				R.remove_self(removed * 5)

/datum/reagent/eden
	// Eden/snake inherits this identical list and is therefore skipped by the tag table.
	treatment_tags = list(TREAT_ANTITOXIN = 0.3)
	name = REAGENT_EDEN
	id = REAGENT_ID_EDEN
	description = "The ultimate anti toxin unrivaled, it corrects impurities within the body but punishes those who attain them with a burning sensation"
	taste_description = "peace"
	scannable = SCANNABLE_BENEFICIAL
	color = "#00FFBE"
	overdose = REAGENTS_OVERDOSE * 1
	// B8: it used to be 0, so a dose stayed in the blood forever.
	metabolism = REM * 0.5
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	immune_species_blood = SPECIES_TAG_BIT(IS_SLIME) | SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/eden/affect_blood(mob/living/carbon/M, alien, removed)
	// Antitoxin action is the treatment_tags profile; purging impurities burns.
	if(M.injury_load(INJURY_CATEGORY_TOXIC))
		M.injure(INJURY_BURN, 1.2, source = src)

/datum/reagent/eden/snake
	name = REAGENT_EDENSNAKE
	id = REAGENT_ID_EDENSNAKE
	metabolism = 0.1
	description = "It used to be an anti toxin until it was tainted."
	taste_description = "hellfire"
	color = "#FF0000"
	immune_species_blood = 0

/datum/reagent/eden/snake/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure_many(alist(INJURY_BURN = 1, INJURY_BLUNT = 1, INJURY_TOXIN = 1), source = src)
	M.AdjustLosebreath(1) // The taint chokes.

/datum/reagent/tercozolam
	name = REAGENT_TERCOZOLAM
	id = REAGENT_ID_TERCOZOLAM
	scannable = SCANNABLE_BENEFICIAL
	color = "#afeb17"
	metabolism = 0.05
	dermal_absorption = 0.2
	description = "A well respected drug used for treatment of schizophrenia in specific."
	overdose = REAGENTS_OVERDOSE * 2
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

///SAP REAGENTS////
//This is all a direct port from aeiou.

/datum/reagent/hannoa
	// B7: "a powerful clotting agent that treats brute damage very quickly".
	treatment_tags = list(TREAT_HEMOSTATIC = 1.0, TREAT_TISSUE_REPAIR = 1.0)
	name = REAGENT_HANNOA
	id = REAGENT_ID_HANNOA
	description = "A powerful clotting agent that treats brute damage very quickly but takes a long time to be metabolised. Overdoses easily, reacts badly with other chemicals."
	taste_description = "paint"
	reagent_state = LIQUID
	color = "#163851"
	overdose = 8
	scannable = 1
	metabolism = REM * 0.15
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/hannoa/overdose(mob/living/carbon/M, alien, removed)
	..()
	if(ishuman(M))
		var/wound_heal = 1.5 * removed
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/external/O in H.damaged_limbs())
			dq_reagent_close_wounds(O, wound_heal, internal = FALSE)
		M.injure(INJURY_BLUNT, 3 * removed, source = src)
		if(M.losebreath < 15)
			M.AdjustLosebreath(1)
		H.custom_pain("It feels as if your veins are fusing shut!",60)

/datum/reagent/hannoa/affect_blood(mob/living/carbon/M, alien, removed) //Sleepy if not overdosing.
	..()
	hannoa_sedation(M, dose)

/// Hannoa's sedation by dose (B7: one flat chain; the <5 and <20 bands used to be unreachable).
/datum/reagent/hannoa/proc/hannoa_sedation(mob/living/carbon/M, effective_dose)
	if(effective_dose < 2)
		if(effective_dose <= metabolism * 2 || prob(5))
			M.emote("yawn")
	else if(effective_dose < 5)
		M.status_at_least(STAT_BLURRY, 10)
	else if(effective_dose < 20)
		if(prob(50))
			M.status_at_least(STAT_WEAKENED, 2)
		M.status_at_least(STAT_DROWSY, 20)
	else
		M.status_at_least(STAT_SLEEPING, 20)


/datum/reagent/bullvalene //This is for the third sap. It converts Brute Oxy and burn into slightly less toxins.
	// Converts injury into toxin: the toxin side is injured in medicine.dm.
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.3,
		TREAT_BURN_CARE = 0.3,
		TREAT_OXYGENATION = 0.2,
	)
	name = REAGENT_BULLVALENE
	id = REAGENT_ID_BULLVALENE
	description = "A catalytic chemical that can treat a wide variety of ailments at the cost of toxifying the host's body."
	taste_description = "sulfur"
	reagent_state = LIQUID
	color = "#163851"
	overdose = 8 //This many units starts killing you.
	scannable = 1 // Mechs can scan this ye
	metabolism = REM * 0.15 //Slow metabolism. This value was plucked out of nowhere. Can be changed.
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/bullvalene
	immune_species_blood = SPECIES_TAG_BIT(IS_SLIME) | SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/bullvalene/affect_blood(mob/living/carbon/M, alien, removed)
	// Repair is the treatment_tags profile; the catalysis toxifies the host
	// while it has something to convert.
	if(M.injury_load(INJURY_CATEGORY_PHYSICAL) || M.injury_load(INJURY_CATEGORY_THERMAL) || M.oxygen_debt())
		M.injure(INJURY_TOXIN, 0.8, source = src)

/////SERAZINE REAGENTS///////

/datum/reagent/serazine
	treatment_tags = list(TREAT_ANTITOXIN = 0.3)
	name = REAGENT_SERAZINE
	id = REAGENT_ID_SERAZINE
	description = "A sweet tasting flower extract, it has very mild anti toxic properties, help with hallucinations and drowsyness, and can be used to make potent drugs."
	taste_description = "sweet nectar"
	reagent_state = LIQUID
	color = "#df9898"
	scannable = 1
	dermal_absorption = 0.25
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/serazine/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_DROWSY, -(3 * removed))
	M.status_adjust(STAT_HALLUCINATING, -(6 * removed))

/datum/reagent/alizene
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.5)
	name = REAGENT_ALIZENE
	id = REAGENT_ID_ALIZENE
	description = "A derivative from bicaridine enhanced by serazine to more effectively mend flesh, but is ineffective against internal hemorrhage."
	taste_description = "bittersweet"
	taste_mult = 3
	reagent_state = LIQUID
	color = "#b37979"
	overdose = REAGENTS_OVERDOSE
	scannable = 1
	dermal_absorption = 0.2
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

// Alizene's trauma repair is its treatment_tags profile.


// === merged from medicine_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/reagent/adranol
	name = REAGENT_ADRANOL
	id = REAGENT_ID_ADRANOL
	description = "A mild sedative that calms the nerves and relaxes the patient."
	taste_description = "milk"
	reagent_state = LIQUID
	dermal_absorption = 0.2 //Most medication has a much weaker effect as a patch.
	color = "#d5e2e5"
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/adranol
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/adranol/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.has_status(STAT_CONFUSED))
		M.status_at_least(STAT_CONFUSED, -8*removed)
	if(M.has_status(STAT_BLURRY))
		M.status_adjust(STAT_BLURRY, -(25*removed))
	M.status_adjust(STAT_JITTERY, -25*removed)

/datum/reagent/numbing_enzyme
	factors = alist(BF_ANALGESIA = 200)
	name = REAGENT_NUMBENZYME
	id = REAGENT_ID_NUMBENZYME
	description = "Some sort of organic painkiller."
	taste_description = "sourness"
	reagent_state = LIQUID
	color = "#800080"
	metabolism = 0.1 //Lasts up to 200 seconds if you give 20u which is OD.
	mrate_static = TRUE
	overdose = 20 //High OD. This is to make numbing bites have somewhat of a downside if you get bit too much. Have to go to medical for dialysis.
	scannable = SCANNABLE_ADVANCED //Let's not have medical mechs able to make an extremely strong organic painkiller
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/numbing_enzyme/affect_blood(mob/living/carbon/M, alien, removed)
	if(prob(0.01)) //1 in 10000 chance per tick. Extremely rare.
		to_chat(M,span_warning("Your body feels numb as a light, tingly sensation spreads throughout it, like some odd warmth."))
	//Not noted here, but a movement debuff of 1.5 is handed out in human_movement.dm when numbing_enzyme is in a person's bloodstream!

/datum/reagent/numbing_enzyme/overdose(mob/living/carbon/M, alien)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(prob(1))
			to_chat(H,span_warning("Your entire body feels numb and the sensation of pins and needles continually assaults you. You blink and the next thing you know, your legs give out momentarily!"))
			H.status_adjust(STAT_WEAKENED, 5) //Fall onto the floor for a few moments.
			H.status_at_least(STAT_CONFUSED, 15) //Be unable to walk correctly for a bit longer.
		if(prob(1))
			if(H.losebreath <= 1 && H.oxygen_debt() <= 20) //Let's not suffocate them to the point that they pass out.
				to_chat(H,span_warning("You feel a sharp stabbing pain in your chest and quickly realize that your lungs have stopped functioning!")) //Let's scare them a bit.
				H.losebreath = 10
		if(prob(2))
			to_chat(H,span_warning("You feel a dull pain behind your eyes and at the back of your head..."))
			H.status_adjust(STAT_HALLUCINATING, 20) //It messes with your mind for some reason.
			H.status_adjust(STAT_BLURRY, 20) //Groggy vision for a small bit.
		if(prob(3))
			to_chat(H,span_warning("You shiver, your body continually being assaulted by the sensation of pins and needles."))
			H.emote("shiver")
			H.status_adjust(STAT_JITTERY, 10)
		if(prob(3))
			to_chat(H,span_warning("Your tongue feels numb and unresponsive."))
			H.status_adjust(STAT_STUTTERING, 20)

/datum/reagent/vermicetol
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.3)
	name = REAGENT_VERMICETOL
	id = REAGENT_ID_VERMICETOL
	description = "A potent chemical that treats physical damage at an exceptional rate."
	taste_description = "sparkles"
	taste_mult = 3
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#750404"
	overdose = REAGENTS_OVERDOSE * 0.5
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

// Vermicetol's trauma repair is its treatment_tags profile.

/*
/datum/reagent/sleevingcure
	name = REAGENT_SLEEVINGCURE
	id = REAGENT_ID_SLEEVINGCURE
	description = "A rare medication provided by Vey-Med that helps counteract negative side effects of using imperfect resleeving machinery."
	taste_description = "chocolate peanut butter"
	taste_mult = 2
	reagent_state = LIQUID
	color = "#b4dcdc"
	overdose = 5
	scannable = SCANNABLE_BENEFICIAL

	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/sleevingcure/affect_blood(mob/living/carbon/M, alien, removed)
	M.remove_body_effect_stack(/datum/body_effect/resleeving_sickness)
	M.remove_body_effect_stack(/datum/body_effect/faux_resleeving_sickness)
*/


/datum/reagent/prussian_blue //We don't have iodine, so prussian blue we go.
	treatment_tags = list(TREAT_ANTITOXIN = 0.1)
	name = REAGENT_PRUSSIANBLUE
	id = REAGENT_ID_PRUSSIANBLUE
	description = "Prussian Blue is a medication used to temporarily pause the effects of radiation poisoning to allow for treatment. Does not treat radiation sickness on its own."
	taste_description = "salt"
	reagent_state = SOLID
	dermal_absorption = 0.2 //While it /is/ a solid, it's a beneficial medical reagent that should have some use if put into a patch.
	color = "#003153" //Blue!
	metabolism = REM * 0.25//20 ticks to do things per unit injected. This means injecting 30u will give you 10 minutes to do what you need.
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG
	metabolized_traits = list(TRAIT_HALT_RADIATION_EFFECTS)

// Prussian blue's miniscule antitoxin action is its treatment_tags profile.

/datum/reagent/lipozilase // The anti-nutriment that rapidly removes weight.
	name = REAGENT_LIPOZILASE
	id = REAGENT_ID_LIPOZILASE
	description = "A chemical compound that causes a dangerously powerful fat-burning reaction."
	taste_description = "blandness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	scannable = SCANNABLE_BENEFICIAL
	color = "#47AD6D"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DIET

/datum/reagent/lipozilase/affect_blood(mob/living/carbon/M, alien, removed)
	M.adjust_nutrition(-20 * removed)
	if(M.weight > 50)
		M.weight = max(50, M.weight - 1.5 * removed) // B23: 0.3 a tick at REM, scaled by what was metabolised

/datum/reagent/lipostipo // The drug that rapidly increases weight.
	name = REAGENT_LIPOSTIPO
	id = REAGENT_ID_LIPOSTIPO
	description = "A chemical compound that causes a dangerously powerful fat-adding reaction."
	taste_description = "blubber"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#61731C"
	scannable = SCANNABLE_BENEFICIAL
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DIET

/datum/reagent/lipostipo/affect_blood(mob/living/carbon/M, alien, removed)
	// B23: the weight-gain drug feeds (it was a copy of lipozilase and starved you).
	M.adjust_nutrition(20 * removed)
	if(M.weight < 500)
		M.weight = min(500, M.weight + 1.5 * removed)

/datum/reagent/polymorph
	name = REAGENT_POLYMORPH
	id = REAGENT_ID_POLYMORPH
	description = "A chemical that instantly transforms the consumer into another creature."
	taste_description = "luck"
	reagent_state = LIQUID
	color = "#a754de"
	scannable = 1
	var/tf_type = /mob/living/simple_mob/animal/passive/mouse
	var/tf_possible_types = list(
		"mouse" = /mob/living/simple_mob/animal/passive/mouse,
		"rat" = /mob/living/simple_mob/animal/passive/mouse/rat,
		"giant rat" = /mob/living/simple_mob/vore/aggressive/rat,
		"dust jumper" = /mob/living/simple_mob/vore/alienanimals/dustjumper,
		"woof" = /mob/living/simple_mob/vore/woof,
		"corgi" = /mob/living/simple_mob/animal/passive/dog/corgi,
		"cat" = /mob/living/simple_mob/animal/passive/cat,
		"chicken" = /mob/living/simple_mob/animal/passive/chicken,
		"cow" = /mob/living/simple_mob/animal/passive/cow,
		"lizard" = /mob/living/simple_mob/animal/passive/lizard,
		"rabbit" = /mob/living/simple_mob/vore/rabbit,
		"fox" = /mob/living/simple_mob/animal/passive/fox,
		"fennec" = /mob/living/simple_mob/vore/fennec,
		"cute fennec" = /mob/living/simple_mob/animal/passive/fennec,
		"fennix" = /mob/living/simple_mob/vore/fennix,
		"red panda" = /mob/living/simple_mob/vore/redpanda,
		"opossum" = /mob/living/simple_mob/animal/passive/opossum,
		"horse" = /mob/living/simple_mob/vore/horse,
		"goose" = /mob/living/simple_mob/animal/space/goose,
		"sheep" = /mob/living/simple_mob/vore/sheep,
		"space bumblebee" = /mob/living/simple_mob/vore/bee,
		"space bear" = /mob/living/simple_mob/animal/space/bear,
		"voracious lizard" = /mob/living/simple_mob/vore/aggressive/dino,
		"giant frog" = /mob/living/simple_mob/vore/aggressive/frog,
		"jelly blob" = /mob/living/simple_mob/vore/jelly,
		"wolf" = /mob/living/simple_mob/vore/wolf,
		"direwolf" = /mob/living/simple_mob/vore/wolf/direwolf,
		"great wolf" = /mob/living/simple_mob/vore/greatwolf,
		"sect queen" = /mob/living/simple_mob/vore/sect_queen,
		"sect drone" = /mob/living/simple_mob/vore/sect_drone,
		"panther" = /mob/living/simple_mob/vore/aggressive/panther,
		"giant snake" = /mob/living/simple_mob/vore/aggressive/giant_snake,
		"deathclaw" = /mob/living/simple_mob/vore/aggressive/deathclaw,
		"otie" = /mob/living/simple_mob/vore/otie,
		"mutated otie" =/mob/living/simple_mob/vore/otie/feral,
		"red otie" = /mob/living/simple_mob/vore/otie/red,
		"defanged xenomorph" = /mob/living/simple_mob/vore/xeno_defanged,
		"catslug" = /mob/living/simple_mob/vore/alienanimals/catslug,
		"monkey" = /mob/living/carbon/human/monkey,
		"wolpin" = /mob/living/carbon/human/wolpin,
		"sparra" = /mob/living/carbon/human/sparram,
		"saru" = /mob/living/carbon/human/sergallingm,
		"sobaka" = /mob/living/carbon/human/sharkm,
		"farwa" = /mob/living/carbon/human/farwa,
		"neaera" = /mob/living/carbon/human/neaera,
		"stok" = /mob/living/carbon/human/stok,
		"weretiger" = /mob/living/simple_mob/vore/weretiger,
		"dragon" = /mob/living/simple_mob/vore/bigdragon/friendly,
		"leopardmander" = /mob/living/simple_mob/vore/leopardmander
		)
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED // bonus
	industrial_use = REFINERYEXPORT_REASON_WEAPONS

/datum/reagent/polymorph/affect_blood(mob/living/carbon/target, removed)
	var/mob/living/M = target
	if(!istype(M))
		return
	if(!M.allow_spontaneous_tf)
		return
	if(M.tf_mob_holder)
		M.revert_mob_tf()
		return
	else
		if(M.stat == DEAD)	//We can let it undo the TF, because the person will be dead, but otherwise things get weird.
			return
		var/mob/living/new_mob = spawn_mob(M)

		M.tf_into(new_mob)
	target.bloodstr.clear_reagents() //Got to clear all reagents to make sure mobs don't keep spawning.
	target.ingested.clear_reagents()
	target.touching.clear_reagents()

/datum/reagent/polymorph/proc/spawn_mob(mob/living/target)
	var/choice = pick(tf_possible_types)
	tf_type = tf_possible_types[choice]
	if(!ispath(tf_type))
		return
	var/new_mob = new tf_type(get_turf(target))
	return new_mob

/datum/reagent/glamour
	name = REAGENT_GLAMOUR
	id = REAGENT_ID_GLAMOUR
	description = "This material is from somewhere else, just being near produces changes."
	taste_description = "change"
	dermal_absorption = 1 //Magic liquid stuff. It immediately clears itself in your system the moment it touches you, so whatever.
	reagent_state = LIQUID
	color = "#ffffff"
	scannable = SCANNABLE_SECRETIVE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_COSMETIC

/datum/reagent/glamour/affect_blood(mob/living/carbon/target, removed)
	grant(target, granted_verb(/mob/living/carbon/human/proc/enter_cocoon), target)
	target.bloodstr.clear_reagents() //instantly clears reagents afterwards
	target.ingested.clear_reagents()
	target.touching.clear_reagents()


// === merged from medicine_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
///GENDER CHANGE REAGENTS////

/datum/reagent/change_drug //base chemical
	name = REAGENT_AMORPHOROVIR //always the same name
	id = REAGENT_ID_AMORPHOROVIR
	metabolism = 100 //set high enough that it does not process multiple times(delay implemented below)
	description = "the bloods DNA in this seems aggressive"
	scannable = SCANNABLE_BENEFICIAL
	taste_description = "this shouldn't be here" //unobtainable ingame
	color = "#7F0000"
	var/gender_change = null //set the gender variable here so we can set it to others in varients
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/change_drug/male //inherits base chemical properties listed above
	name = REAGENT_ANDROROVIR
	id = REAGENT_ID_ANDROROVIR //unique ID for each varient
	taste_description = "old spice odor blocker and body wash"
	reagent_state = LIQUID
	description = \
		"A medical concoction, capable of rapidly altering genetic and physical structure of the body. This one seems\
		to realign the target's gender to be male."
	color = "#428AFF"
	gender_change = "male"
	scannable = 1

/datum/reagent/change_drug/female
	name = REAGENT_GYNOROVIR
	id = REAGENT_ID_GYNOROVIR
	description = \
		"A medical concoction, capable of rapidly altering genetic and physical structure of the body. This one seems\
		to realign the target's gender to be female."
	taste_description = "spiced honey"
	reagent_state = LIQUID
	color = "#FFA0FA"
	gender_change = "female"
	scannable = 1

/datum/reagent/change_drug/intersex
	name = REAGENT_ANDROGYNOROVIR
	id = REAGENT_ID_ANDROGYNOROVIR
	description = \
		"A medical concoction, capable of rapidly altering genetic and physical structure of the body. This one seems\
		to realign the target's gender to be mixed."
	taste_description = "something salty and sweet"
	reagent_state = LIQUID
	color = "#CB9EFF"
	gender_change = "plural"
	scannable = 1

/datum/reagent/change_drug
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/change_drug/affect_blood(mob/living/carbon/human/M, alien, removed)
	if (!(M.gender == gender_change || M.gender_change_cooldown == 1) && M.allow_spontaneous_tf)
		//set not to bug them because the chem is activating
		M.gender_change_cooldown = 1
		act_message(M, null, MSG_SELF(span_notice("You lose focus as warmth spreads throughout your chest and abdomen.")), \
			MSG_OTHERS(span_notice("%U% suddenly twitches as some of their features seem to contort and reshape.")))
		//wait 30 seconds, growth takes time yo
		after(M, 30 SECONDS, GLOBAL_PROC_REF(change_drug_ask), with = list(M, gender_change))

/// The gender change drug asks before it acts, for pref sake.
/proc/change_drug_ask(mob/living/carbon/human/M, gender_change)
	if(QDELETED(M))
		return
	//allow it to bug them again now that we've waited
	M.gender_change_cooldown = 0
	open_request(M, /datum/prompt/yes_no/gender_change_drug, TYPE_PROC_REF(/mob/living/carbon/human, gender_change_drug_answered), answerer = M, gender_change = gender_change, timeout = 0)

/datum/prompt/yes_no/gender_change_drug
	recheck_on_open = TRUE
	title = "Warning"
	question = "This chemical will change your gender, proceed?"
	var/gender_change

/mob/living/carbon/human/proc/gender_change_drug_answered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/datum/prompt/yes_no/gender_change_drug/ask = A.answer
	change_gender_identity(ask.gender_change)
	change_gender(ask.gender_change)
	to_chat(src, span_warning("You feel like a new person."))

//Chemist expansion
//deathblood
/datum/reagent/cleansingagent
	treatment_tags = list(TREAT_ANTITOXIN = 0.8, TREAT_ANTIRADIATION = 0.5)
	name = REAGENT_CLEANSINGAGENT
	id = REAGENT_ID_CLEANSINGAGENT
	description = "An agent that purges one's body of toxins."
	reagent_state = LIQUID
	color = "#225722"
	scannable = 1
	dermal_absorption = 0.2
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 0
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/cleansingagent
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/cleansingagent/affect_blood(mob/living/carbon/M, alien, removed)
	// Antitoxin action is the treatment_tags profile.
	M.status_at_least(STAT_DRUGGED, 5)

/datum/reagent/purifyingagent
	treatment_tags = list(TREAT_ANTITOXIN = 0.8, TREAT_ANTIRADIATION = 0.5)
	name = REAGENT_PURIFYINGAGENT
	id = REAGENT_ID_PURIFYINGAGENT
	description = "An agent that purges one's body of rads and toxins."
	reagent_state = LIQUID
	color = "#225722"
	scannable = 1
	dermal_absorption = 0.2
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 0
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

// Purifying agent's antitoxin and anti-radiation action are its treatment_tags profile.

//liquid fire
/datum/reagent/burncard
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.5)
	name = REAGENT_BURNCARD
	id = REAGENT_ID_BURNCARD
	description = "A more powerful variation of bicard that also burns the subject."
	taste_description = "bitterness"
	taste_mult = 3
	reagent_state = LIQUID
	color = "#BF0000"
	overdose = REAGENTS_OVERDOSE * 0.2
	dermal_absorption = 0.2
	overdose_mod = 1.25
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/burncard
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/burncard/affect_blood(mob/living/carbon/M, alien, removed)
	// Trauma repair is the treatment_tags profile; liquid fire still burns.
	M.injure(INJURY_BURN, 1 * removed, source = src)

/datum/reagent/burncard/overdose(mob/living/carbon/M, alien, removed)
	..()
	var/wound_heal = 3 * removed
	M.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + wound_heal, 250))
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/external/O in H.damaged_limbs())
			dq_reagent_close_wounds(O, wound_heal)

/datum/reagent/flamecure
	name = REAGENT_FLAMECURE
	id = REAGENT_ID_FLAMECURE
	description = "Used to rapidly clot internal hemorrhages by burning the wounded areas"
	reagent_state = LIQUID
	color = "#4246C7"
	overdose = REAGENTS_OVERDOSE * 0.5
	dermal_absorption = 0.2
	scannable = 1
	var/repair_strength = 9
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/flamecure
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/flamecure/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + (repair_strength * removed), 250))
	// The legacy negative burn-heal here was a burn (twice for humans).
	M.injure(INJURY_BURN, (ishuman(M) ? 2 : 1) * removed, source = src)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/wound_heal = removed * repair_strength
		for(var/obj/item/organ/external/O in H.damaged_limbs())
			dq_reagent_close_wounds(O, wound_heal)

//neoliquidfire
/datum/reagent/neotane
	treatment_tags = list(TREAT_BURN_CARE = 1.5)
	name = REAGENT_NEOTANE
	id = REAGENT_ID_NEOTANE
	description = "An advancement of kelotane that scars and breaks apart the user's flesh to remove the burnt tissue."
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#FF6600"
	overdose = REAGENTS_OVERDOSE * 0.2
	dermal_absorption = 0.2
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/neotane
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)
	species_injuries_blood = alist(IS_SLIME = alist(INJURY_BLUNT = 3))

/datum/reagent/neotane/affect_blood(mob/living/carbon/M, alien, removed)
	// Burn care is the treatment_tags profile; the side effects stay here.
	M.injure(INJURY_BLUNT, 1 * removed, source = src)

/datum/reagent/bloodsealer
	factors = alist(BF_STABILIZATION = 25)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_BLOODSEALER
	id = REAGENT_ID_BLOODSEALER
	description = "A strange chemical that will stablize bloodflow by burning the subject"
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#00BFFF"
	overdose = REAGENTS_OVERDOSE
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/bloodsealer
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/bloodsealer/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_BURN, 1 * removed, source = src) // the legacy negative burn-heal: a burn

//meteroidliquid
/datum/reagent/livingagent
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.5,
		TREAT_BURN_CARE = 0.5,
		TREAT_OXYGENATION = 0.4,
		TREAT_ANTITOXIN = 0.4,
	)
	factors = alist(BF_ANALGESIA = -20)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_LIVINGAGENT
	id = REAGENT_ID_LIVINGAGENT
	description = "Fill the body with life, while making it more senstive to stimulus."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#8040FF"
	scannable = 1
	overdose = REAGENTS_OVERDOSE * 3
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/livingagent/overdose(mob/living/carbon/M, alien)
	..()
	M.status_at_least(STAT_DRUGGED, 5)
	M.status_at_least(STAT_CONFUSED, 5)

/datum/reagent/performancepeaker
	factors = alist(BF_ANALGESIA = 10, BF_SLOWDOWN = -0.5, BF_PENALTY_SCALE = 0.5)
	name = REAGENT_PERFORMANCEPEAKER
	id = REAGENT_ID_PERFORMANCEPEAKER
	description = "A chemical created to bring a body to peak condition. Highly toxic"
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#006666"
	scannable = 1
	dermal_absorption = 0 //This chem is a stronger poison than a benefical chem, with a strength of 15.
	overdose = REAGENTS_OVERDOSE * 0.5
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/performancepeaker/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_PARALYZED, -1)
	M.status_adjust(STAT_STUNNED, -1)
	M.status_adjust(STAT_WEAKENED, -1)
	M.injure(INJURY_TOXIN, 15 * removed, source = src)

//advanced crafting
//tier 1
/datum/reagent/souldew
	name = REAGENT_SOULDEW
	id = REAGENT_ID_SOULDEW
	description = "An experimental drug that solely works upon dead bodies"
	taste_description = "ash"
	reagent_state = LIQUID
	color = "#666699"
	scannable = 1
	overdose = REAGENTS_OVERDOSE * 2
	affects_dead = TRUE
	mrate_static = TRUE
	metabolism = 0.5
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/souldew/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(M.stat == DEAD)
		// Only works on the dead, which a continuous tag can't express: mends directly.
		M.mend(TREAT_OXYGENATION, 3 * removed * chem_effective)
		M.mend(TREAT_TISSUE_REPAIR, 3 * removed * chem_effective)
		M.mend(TREAT_BURN_CARE, 3 * removed * chem_effective)
		M.mend(TREAT_ANTITOXIN, 3 * removed * chem_effective)

/datum/reagent/quadcord
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.2,
		TREAT_BURN_CARE = 0.2,
		TREAT_OXYGENATION = 0.1,
		TREAT_ANTITOXIN = 0.1,
		TREAT_NEURAL_REPAIR = 0.3,
	)
	name = REAGENT_QUADCORD
	id = REAGENT_ID_QUADCORD
	description = "An experimental drug that is meant to further enhance tricord"
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#FF3399"
	scannable = 1
	overdose = REAGENTS_OVERDOSE * 2
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI
// Quadcord's healing is its treatment_tags profile.

//tier 2


/datum/reagent/curea
	name = REAGENT_CUREA
	id = REAGENT_ID_CUREA
	description = "An experimental that removes many ailments, such as poison and stiffening of muscles via frost"
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#660066"
	scannable = 1
	dermal_absorption = 1
	overdose = REAGENTS_OVERDOSE * 0.5
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/curea/affect_blood(mob/living/carbon/M, alien, removed)
	M.mend(TREAT_ANTITOXIN, 100)
	M.remove_body_effect(/datum/body_effect/chilled)
	M.remove_body_effect(/datum/body_effect/doomed)
	M.remove_body_effect(/datum/body_effect/invulnerable)
	M.remove_body_effect(/datum/body_effect/elemental_vulnerability)
	M.remove_body_effect(/datum/body_effect/grievous_wounds)
	M.remove_body_effect(/datum/body_effect/deep_wounds)
	M.remove_body_effect(/datum/body_effect/hivebot_weaken)
	M.extinguish_mob()
	M.remove_body_effect(/datum/body_effect/berserk_exhaustion)
	M.remove_body_effect(/datum/body_effect/entangled)
	M.remove_body_effect_stack(/datum/body_effect/wizfire)
	M.remove_body_effect_stack(/datum/body_effect/wizpoison)

//tier 3
/datum/reagent/modapplying/liquidhealer
	name = REAGENT_LIQUIDHEALER
	id = REAGENT_ID_LIQUIDHEALER
	description = "An experimental drug that mimics rapid regeneration seen in squishy creatures."
	taste_description = "sweet"
	reagent_state = LIQUID
	color = "#00CCFF"
	scannable = 1
	overdose = REAGENTS_OVERDOSE * 0.5
	modifier_to_add = /datum/body_effect/liquidhealer
	modifier_duration = 3 SECONDS
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/body_effect/liquidhealer
	stacks = MODIFIER_STACK_FORBID
	tick_interval = 2 SECONDS
	name = REAGENT_ID_LIQUIDHEALER
	desc = "You are filled with an overwhelming healing."

	on_created_text = span_critical("You feel your body's natural healing quick into overdrive!")
	on_expired_text = span_notice("Your body returns to normal.")

	factors = alist(BF_HEALING_RECEIVED = 1.2)

/datum/body_effect/liquidhealer/on_tick(mob/living/L)
	if(L.stat == DEAD)
		L.end_body_effect(type)
		return

	// A regeneration power, not a reagent: it mends by mechanism, organic
	// and synthetic alike (the old code repaired robolimbs too).
	L.mend(TREAT_TISSUE_REPAIR, 1)
	L.mend(TREAT_BURN_CARE, 1)
	L.mend(TREAT_PLATING_REPAIR, 1)
	L.mend(TREAT_WIRING_REPAIR, 1)
	L.mend(TREAT_ANTITOXIN, 1)
	L.mend(TREAT_OXYGENATION, 1)
	L.mend(TREAT_GENETIC_REPAIR, 1)


/datum/reagent/modapplying/phoenixbreath
	name = REAGENT_PHOENIXBREATH
	id = REAGENT_ID_PHOENIXBREATH
	description = "An experimental chem that will bring those back from the brink, with severe side effects"
	taste_description = "ash"
	reagent_state = LIQUID
	color = "#fcac00"
	scannable = 1
	overdose = REAGENTS_OVERDOSE
	mrate_static = TRUE
	metabolism = 0.1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI
	modifier_to_add = /datum/body_effect/life_cloak
	modifier_duration = 3 SECONDS


/datum/reagent/dryagent
	name = REAGENT_DRYAGENT
	id = REAGENT_ID_DRYAGENT
	description = "A desiccant. Can be used to dry things."
	taste_description = "dryness"
	reagent_state = LIQUID
	color = "#A70FFF"
	scannable = 1
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_INDUSTRY

/datum/reagent/dryagent
	// Why are you giving this to Prometheans or Dionas. You're going to DRY them. (2 burn x 1.25)
	species_injuries_blood = alist(IS_SLIME = alist(INJURY_BURN = 2.5))

/datum/reagent/dryagent/touch_obj(obj/O, amount)
	if(istype(O, /obj/item/clothing/shoes/galoshes) && O.loc)
		replace_with(O, /obj/item/clothing/shoes/dry_galoshes)
		remove_self(10)

/datum/reagent/dryagent/touch_turf(turf/T)
	..()
	if(volume >= 5)
		if(istype(T, /turf/simulated/floor))
			var/turf/simulated/floor/F = T
			if(F.wet)
				F.wet = 0
	return
