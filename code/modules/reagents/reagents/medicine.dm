/* General medicine */

/datum/reagent/inaprovaline
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

/datum/reagent/inaprovaline/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		M.add_chemical_effect(CE_STABLE, 15)
		M.add_chemical_effect(CE_PAINKILLER, 10 * M.species.chem_strength_pain)
		M.remove_chemical_effect(CE_ALLERGEN)

/datum/reagent/inaprovaline/topical
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

/datum/reagent/inaprovaline/topical/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		..()
		M.adjustToxLoss(2 * removed)

/datum/reagent/inaprovaline/topical/affect_touch(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		M.add_chemical_effect(CE_STABLE, 20)
		M.add_chemical_effect(CE_PAINKILLER, 12 * M.species.chem_strength_pain)

/datum/reagent/bicaridine
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

/datum/reagent/bicaridine/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.75
	if(alien != IS_DIONA)
		M.heal_organ_damage(4 * removed * chem_effective, 0)

/datum/reagent/bicaridine/overdose(mob/living/carbon/M, alien, removed)
	..()
	var/wound_heal = 2.5 * removed
	M.eye_blurry = min(M.eye_blurry + wound_heal, 250)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/external/O in H.organs)
			for(var/datum/wound/W in O.wounds)
				if(W.bleeding())
					W.damage = max(W.damage - wound_heal, 0)
					if(W.damage <= 0)
						O.wounds -= W
				if(W.internal)
					W.damage = max(W.damage - wound_heal, 0)
					if(W.damage <= 0)
						O.wounds -= W

/datum/reagent/bicaridine/topical
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

/datum/reagent/bicaridine/topical/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.75
	if(alien != IS_DIONA)
		..(M, alien, removed * chem_effective)
		M.adjustToxLoss(2 * removed)

/datum/reagent/bicaridine/topical/affect_touch(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.75
	if(alien != IS_DIONA)
		M.heal_organ_damage(6 * removed * chem_effective, 0)

/datum/reagent/calciumcarbonate
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

/datum/reagent/calciumcarbonate/affect_blood(mob/living/carbon/M, alien, removed) // Why would you inject this.
	if(alien != IS_DIONA)
		M.adjustToxLoss(3 * removed)

/datum/reagent/calciumcarbonate/affect_ingest(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		M.add_chemical_effect(CE_ANTACID, 3)

/datum/reagent/kelotane
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

/datum/reagent/kelotane/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.5
		M.adjustBruteLoss(2 * removed) //Mends burns, but has negative effects with a Promethean's skeletal structure.
	if(alien != IS_DIONA)
		M.heal_organ_damage(0, 4 * removed * chem_effective)

/datum/reagent/dermaline
	name = REAGENT_DERMALINE
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

/datum/reagent/dermaline/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.75
	if(alien != IS_DIONA)
		M.heal_organ_damage(0, 8 * removed * chem_effective)

/datum/reagent/dermaline/topical
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

/datum/reagent/dermaline/topical/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.75
	if(alien != IS_DIONA)
		..(M, alien, removed * chem_effective)
		M.adjustToxLoss(2 * removed)

/datum/reagent/dermaline/topical/affect_touch(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.75
	if(alien != IS_DIONA)
		M.heal_organ_damage(0, 12 * removed * chem_effective)

/datum/reagent/dylovene
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

/datum/reagent/dylovene/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.66
		if(dose >= 15)
			M.druggy = max(M.druggy, 5)
	if(alien != IS_DIONA)
		M.drowsyness = max(0, M.drowsyness - 6 * removed * chem_effective)
		M.hallucination = max(0, M.hallucination - 9 * removed * chem_effective)
		M.adjustToxLoss(-4 * removed * chem_effective)
		if(prob(10))
			M.remove_a_modifier_of_type(/datum/modifier/poisoned)

/datum/reagent/carthatoline
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

/datum/reagent/carthatoline/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	if(M.getToxLoss() && prob(10))
		M.vomit(1)
	M.adjustToxLoss(-8 * removed * M.species.chem_strength_heal)
	if(prob(30))
		M.remove_a_modifier_of_type(/datum/modifier/poisoned)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/internal/liver/L = H.internal_organs_by_name[O_LIVER]
		if(istype(L))
			if(L.robotic >= ORGAN_ROBOT)
				return
			if(L.damage > 0)
				L.damage = max(L.damage - 2 * removed, 0)
		if(alien == IS_SLIME)
			H.druggy = max(M.druggy, 5)

/datum/reagent/carthatoline/overdose(mob/living/carbon/M, alien, removed)
	M.adjustHalLoss(2)
	var/mob/living/carbon/human/H = M
	var/obj/item/organ/internal/stomach/st = H.internal_organs_by_name[O_STOMACH]
	st?.take_damage(removed * 2) // Causes stomach contractions, makes sense for an overdose to make it much worse.

/datum/reagent/dexalin
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

/datum/reagent/dexalin/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_VOX)
		M.adjustToxLoss(removed * 24)
	else if(alien == IS_SLIME && dose >= 15)
		M.add_chemical_effect(CE_PAINKILLER, 15 * M.species.chem_strength_pain)
		if(prob(15))
			to_chat(M, span_notice("You have a moment of clarity as you collapse."))
			M.adjustBrainLoss(-20 * removed)
			M.Weaken(6)
	else if(alien != IS_DIONA)
		M.adjustOxyLoss(-15 * removed * M.species.chem_strength_heal)

	holder.remove_reagent(REAGENT_ID_LEXORIN, 8 * removed)

/datum/reagent/dexalinp
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

/datum/reagent/dexalinp/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_VOX)
		M.adjustToxLoss(removed * 9)
	else if(alien == IS_SLIME && dose >= 10)
		M.add_chemical_effect(CE_PAINKILLER, 25 * M.species.chem_strength_pain)
		if(prob(25))
			to_chat(M, span_notice("You have a moment of clarity, as you feel your tubes lose pressure rapidly."))
			M.adjustBrainLoss(-8 * removed)
			M.Weaken(3)
	else if(alien != IS_DIONA)
		M.adjustOxyLoss(-150 * removed * M.species.chem_strength_heal)

	holder.remove_reagent(REAGENT_ID_LEXORIN, 3 * removed)

/datum/reagent/tricordrazine
	name = REAGENT_TRICORDRAZINE
	id = REAGENT_ID_TRICORDRAZINE
	description = REAGENT_TRICORDRAZINE + " is a highly potent stimulant, originally derived from cordrazine. Can be used to treat a wide range of injuries."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#8040FF"
	overdose = REAGENTS_OVERDOSE * 4 //YW EDIT - TRICORD FUCKING KILLS YOU
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_TRICORD

/datum/reagent/tricordrazine/overdose(mob/living/carbon/M, alien) //YW EDIT START
	..()
	M.druggy = max(M.druggy, 5)
	M.Confuse(5) //YW EDIT END

/datum/reagent/tricordrazine/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		var/chem_effective = 1 * M.species.chem_strength_heal
		if(alien == IS_SLIME)
			chem_effective = 0.5
		M.adjustOxyLoss(-3 * removed * chem_effective)
		M.heal_organ_damage(1.5 * removed, 1.5 * removed * chem_effective)
		M.adjustToxLoss(-1.5 * removed * chem_effective)

/datum/reagent/tricordrazine/affect_touch(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		affect_blood(M, alien, removed * 0.4)

/datum/reagent/tricorlidaze
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

/datum/reagent/tricorlidaze/affect_touch(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		var/chem_effective = 1 * M.species.chem_strength_heal
		if(alien == IS_SLIME)
			chem_effective = 0.5
		M.adjustOxyLoss(-2 * removed * chem_effective)
		M.heal_organ_damage(1 * removed, 1 * removed * chem_effective)
		M.adjustToxLoss(-2 * removed * chem_effective)

/datum/reagent/tricorlidaze/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		M.adjustToxLoss(3 * removed)

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

/datum/reagent/cryoxadone/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.bodytemperature < 170)
		var/chem_effective = 1 * M.species.chem_strength_heal
		if(alien == IS_SLIME)
			chem_effective = 0.25
			to_chat(M, span_danger("It's cold. Something causes your cellular mass to harden occasionally, resulting in vibration."))
			M.Weaken(10)
			M.silent = max(M.silent, 10)
			M.make_jittery(4)
		M.adjustCloneLoss(-10 * removed * chem_effective)
		M.adjustOxyLoss(-10 * removed * chem_effective)
		M.heal_organ_damage(10 * removed, 10 * removed * chem_effective)
		M.adjustToxLoss(-10 * removed * chem_effective)

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

/datum/reagent/clonexadone/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.bodytemperature < 170)
		var/chem_effective = 1 * M.species.chem_strength_heal
		if(alien == IS_SLIME)
			if(prob(10))
				to_chat(M, span_danger("It's so cold. Something causes your cellular mass to harden sporadically, resulting in seizure-like twitching."))
			chem_effective = 0.5
			M.Weaken(20)
			M.silent = max(M.silent, 20)
			M.make_jittery(4)
		M.adjustCloneLoss(-30 * removed * chem_effective)
		M.adjustOxyLoss(-30 * removed * chem_effective)
		M.heal_organ_damage(30 * removed, 30 * removed * chem_effective)
		M.adjustToxLoss(-30 * removed * chem_effective)

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

/datum/reagent/mortiferin/on_mob_life(mob/living/carbon/M, alien, datum/reagents/metabolism/location)
	. = ..(M, alien, location)

/datum/reagent/mortiferin/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.bodytemperature < (T0C - 10) || (M.stat == DEAD))
		var/chem_effective = 1 * M.species.chem_strength_heal
		if(alien == IS_SLIME)
			if(prob(10))
				to_chat(M, span_danger("It's so cold. Something causes your cellular mass to solidify sporadically, resulting in uncontrollable twitching."))
			chem_effective = 0.5
			M.Weaken(10)
			M.silent = max(M.silent, 10)
			M.make_jittery(4)
		if(M.stat != DEAD)
			M.adjustCloneLoss(-5 * removed * chem_effective)
		M.adjustOxyLoss(-10 * removed * chem_effective)
		M.adjustToxLoss(-20 * removed * chem_effective)

		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			var/obj/item/organ/internal/liver/L = H.internal_organs_by_name[O_LIVER]
			if(istype(L) && prob(5))
				if(L.robotic >= ORGAN_ROBOT)
					return

				L.take_damage(rand(1,3) * removed)

/datum/reagent/necroxadone
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

/datum/reagent/necroxadone/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(M.bodytemperature < 170 || (M.stat == DEAD && M.has_modifier_of_type(/datum/modifier/bloodpump_corpse)))
		if(alien == IS_SLIME)
			if(prob(10))
				to_chat(M, span_danger("It's so cold. Something causes your cellular mass to harden sporadically, resulting in seizure-like twitching."))
			chem_effective = 0.5
			M.Weaken(20)
			M.silent = max(M.silent, 20)
			M.make_jittery(4)
		if(M.stat != DEAD)
			M.adjustCloneLoss(-5 * removed * chem_effective)
		M.adjustOxyLoss(-20 * removed * chem_effective)
		M.adjustToxLoss(-40 * removed * chem_effective)
		M.adjustCloneLoss(-15 * removed * chem_effective)

	else
		M.adjustToxLoss(-25 * removed * chem_effective)
		M.adjustOxyLoss(-10 * removed * chem_effective)
		M.adjustCloneLoss(-7 * removed * chem_effective)

/* Painkillers */

/datum/reagent/paracetamol
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

/datum/reagent/paracetamol/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_pain
	if(alien == IS_SLIME)
		chem_effective = 0.75
	M.add_chemical_effect(CE_PAINKILLER, 25 * chem_effective)

/datum/reagent/paracetamol/overdose(mob/living/carbon/M, alien)
	..()
	if(alien == IS_SLIME)
		M.add_chemical_effect(CE_SLOWDOWN, 1)
	M.hallucination = max(M.hallucination, 2)

/datum/reagent/tramadol
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

/datum/reagent/tramadol/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_pain
	if(alien == IS_SLIME)
		chem_effective = 0.8
		M.add_chemical_effect(CE_SLOWDOWN, 1)
	M.add_chemical_effect(CE_PAINKILLER, 80 * chem_effective)

/datum/reagent/tramadol/overdose(mob/living/carbon/M, alien)
	..()
	M.hallucination = max(M.hallucination, 2)

/datum/reagent/oxycodone
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

/datum/reagent/oxycodone/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_pain
	if(alien == IS_SLIME)
		chem_effective = 0.75
		M.stuttering = min(50, max(0, M.stuttering + 5)) //If you can't feel yourself, and your main mode of speech is resonation, there's a problem.
	M.add_chemical_effect(CE_PAINKILLER, 200 * chem_effective)
	M.add_chemical_effect(CE_SLOWDOWN, 1)
	M.add_chemical_effect(CE_NARCOTICS, 1)
	M.eye_blurry = min(M.eye_blurry + 10, 250 * chem_effective)

/datum/reagent/oxycodone/overdose(mob/living/carbon/M, alien)
	..()
	M.druggy = max(M.druggy, 10)
	M.hallucination = max(M.hallucination, 3)

/* Other medicine */

/datum/reagent/synaptizine
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

/datum/reagent/synaptizine/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_DIONA)
		return
	if(alien == IS_SLIME)
		if(dose >= 5) //Not effective in small doses, though it causes toxloss at higher ones, it will make the regeneration for brute and burn more 'efficient' at the cost of more nutrition.
			M.adjust_nutrition(removed * 2)
			M.adjustBruteLoss(-2 * removed)
			M.adjustFireLoss(-1 * removed)
		chem_effective = 0.5
	M.drowsyness = max(M.drowsyness - 5, 0)
	M.AdjustParalysis(-1)
	M.AdjustStunned(-1)
	M.AdjustWeakened(-1)
	holder.remove_reagent(REAGENT_ID_MINDBREAKER, 5)
	M.hallucination = max(0, M.hallucination - 10)
	M.adjustToxLoss(10 * removed * chem_effective) // It used to be incredibly deadly due to an oversight. Not anymore!
	M.add_chemical_effect(CE_PAINKILLER, 20 * chem_effective * M.species.chem_strength_pain)

/datum/reagent/hyperzine
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

/datum/reagent/hyperzine/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_TAJARA)
		removed *= 1.25
	if(alien == IS_SLIME)
		M.make_jittery(4) //Hyperactive fluid pumping results in unstable 'skeleton', resulting in vibration.
		if(dose >= 5)
			M.adjust_nutrition(-removed * 2) // Sadly this movement starts burning food in higher doses.
	..()
	if(prob(5))
		M.emote(pick("twitch", "blink_r", "shiver"))
	M.add_chemical_effect(CE_SPEEDBOOST, 1)

/datum/reagent/hyperzine/overdose(mob/living/carbon/M, alien, removed)
	..()
	if(prob(5)) // 1 in 20
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/internal/heart/ht = H.internal_organs_by_name[O_HEART]
		ht?.take_damage(1)
		to_chat(M, span_warning("Huh... Is this what a heart attack feels like?"))

/datum/reagent/alkysine
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

/datum/reagent/alkysine/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.25
		if(M.brainloss >= 10)
			M.Weaken(5)
		if(dose >= 10 && M.paralysis < 40)
			M.AdjustParalysis(1) //Messing with the core with a simple chemical probably isn't the best idea.
	// base brain healing moved to dq_alkysine_brain_effect (see
	// code/modules/medical/organ_decay/). Alkysine still works
	// on mildly-damaged brains, but stops keeping up past the salvageable
	// threshold (~60% organ damage), at which point ongoing decay
	// outpaces the chem. The DQ proc is the single source of truth.
	dq_alkysine_brain_effect(M, removed, chem_effective)
	M.add_chemical_effect(CE_PAINKILLER, 10 * chem_effective * M.species.chem_strength_pain)

/datum/reagent/imidazoline
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
	M.eye_blurry = max(M.eye_blurry - 5, 0)
	M.AdjustBlinded(-5)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/internal/eyes/E = H.internal_organs_by_name[O_EYES]
		if(istype(E))
			if(E.robotic >= ORGAN_ROBOT)
				return
			if(E.damage > 0)
				E.damage = max(E.damage - 5 * removed, 0)
			if(E.damage <= 5 && E.organ_tag == O_EYES)
				H.sdisabilities &= ~BLIND

/datum/reagent/peridaxon
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
		for(var/obj/item/organ/I in H.internal_organs)
			if(I.robotic >= ORGAN_ROBOT)
				continue
			if(I.damage > 0) //Peridaxon heals only non-robotic organs
				I.damage = max(I.damage - removed, 0)
				H.Confuse(5)
			if(I.damage <= 5 && I.organ_tag == O_EYES)
				H.eye_blurry = min(M.eye_blurry + 10, 250) //Eyes need to reset, or something
				H.sdisabilities &= ~BLIND
		if(alien == IS_SLIME)
			H.add_chemical_effect(CE_PAINKILLER, 20 * M.species.chem_strength_pain)
			if(prob(33))
				H.Confuse(10)

/datum/reagent/peridaxon/overdose(mob/living/carbon/M, alien, removed)
	..()
	M.adjustHalLoss(5)
	M.hallucination = max(M.hallucination, 10)

/datum/reagent/osteodaxon
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

/datum/reagent/osteodaxon/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	M.heal_organ_damage(3 * removed, 0)	//Gives the bones a chance to set properly even without other meds
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/totalvol = 0
		if(H.ingested)
			for(var/datum/reagent/R in H.ingested.reagent_list)
				if(istype(R,/datum/reagent/osteodaxon))
					totalvol += R.volume
		totalvol += volume
		if(totalvol >= 1)
			for(var/obj/item/organ/external/O in H.bad_external_organs)
				if(O.status & ORGAN_BROKEN)
					O.mend_fracture()		//Only works if the bone won't rebreak, as usual
					H.custom_pain(span_danger(span_normal(span_bold("You feel a terrible agony tear through your [O.name]!"))),60,TRUE)
					H.AdjustWeakened(10)		//Bones being regrown will knock you over
					H.adjustHalLoss(60)
					H.AdjustStunned(1)		//Bones being regrown will knock you over

/datum/reagent/myelamine
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

/datum/reagent/myelamine/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	M.eye_blurry = min(M.eye_blurry + (repair_strength * removed), 250)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/wound_heal = removed * repair_strength
		for(var/obj/item/organ/external/O in H.organs)
			for(var/datum/wound/W in O.wounds)
				if(W.bleeding())
					W.bandage() //This is the ACTUAL clotting being performed.
					W.damage = max(W.damage - (wound_heal*3.5), 0) 	//Removed should be 0.15 (can be higher if you have high/apex metabolism). repair_strength is 6. Making wound_heal  .9. Multiply by 3.5 and that gives us a heal of 3.15 on our wounds.
					if(W.damage <= 0)								//We do this since this will only happen once per bleeding wound, as it's then bandaged (clotted). We do the heal as we want it to be somewhat like slapping them with an advanceed/bruise_pack. (Bruise packs heal 3.5 on application, as of the time of writing.)
						O.wounds -= W
					break //We only heal ONE external wound per go around.
			for(var/datum/wound/internal_bleeding/W in O.wounds)
				W.damage = max(W.damage - wound_heal, 0)
				if(W.damage <= 0)
					O.wounds -= W
				else if(dose >= 9.5 && dose < 11) //If you are in the 'sweet zone' of 9.5u to 11u, your internal wounds instantly heal. This is to prevent people from using a clotting pen or taking a 10u clotting pill from medical and it not actually fixing their wounds.
					W.damage = 0
					O.wounds -= W

/datum/reagent/myelamine/overdose(mob/living/carbon/M, alien, removed)
	//Heals slightly faster at the cost of high toxins. Honestly you should never do this, but whatever.
	..()
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/wound_heal = removed * repair_strength / 2
		for(var/obj/item/organ/external/O in H.bad_external_organs)
			for(var/datum/wound/internal_bleeding/W in O.wounds)
				W.damage = max(W.damage - wound_heal, 0)
				if(W.damage <= 0)
					O.wounds -= W

/datum/reagent/respirodaxon
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

/datum/reagent/respirodaxon/affect_blood(mob/living/carbon/M, alien, removed)
	var/repair_strength = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		repair_strength = 0.6
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/I in H.internal_organs)
			if(I.robotic >= ORGAN_ROBOT || !(I.organ_tag in list(O_LUNGS, O_VOICE, O_GBLADDER)))
				continue
			if(I.damage > 0)
				I.damage = max(I.damage - 4 * removed * repair_strength, 0)
				H.Confuse(2)
		if(M.reagents.has_reagent(REAGENT_ID_GASTIRODAXON) || M.reagents.has_reagent(REAGENT_ID_PERIDAXON))
			if(H.losebreath >= 15 && prob(H.losebreath))
				H.Stun(2)
			else
				H.losebreath = CLAMP(H.losebreath + 3, 0, 20)
		else
			H.losebreath = max(H.losebreath - 4, 0)

/datum/reagent/gastirodaxon
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

/datum/reagent/gastirodaxon/affect_blood(mob/living/carbon/M, alien, removed)
	var/repair_strength = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		repair_strength = 0.6
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/I in H.internal_organs)
			if(I.robotic >= ORGAN_ROBOT || !(I.organ_tag in list(O_APPENDIX, O_STOMACH, O_INTESTINE, O_NUTRIENT, O_PLASMA, O_POLYP)))
				continue
			if(I.damage > 0)
				I.damage = max(I.damage - 4 * removed * repair_strength, 0)
				H.Confuse(2)
		if(M.reagents.has_reagent(REAGENT_ID_HEPANEPHRODAXON) || M.reagents.has_reagent(REAGENT_ID_PERIDAXON))
			if(prob(10))
				H.vomit(1)
			else if(H.nutrition > 30)
				M.adjust_nutrition(-removed * 30)
		else
			H.adjustToxLoss(-10 * removed) // Carthatoline based, considering cost.

/datum/reagent/hepanephrodaxon
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

/datum/reagent/hepanephrodaxon/affect_blood(mob/living/carbon/M, alien, removed)
	var/repair_strength = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		repair_strength = 0.4
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/I in H.internal_organs)
			if(I.robotic >= ORGAN_ROBOT || !(I.organ_tag in list(O_LIVER, O_KIDNEYS, O_APPENDIX, O_ACID, O_HIVE)))
				continue
			if(I.damage > 0)
				I.damage = max(I.damage - 4 * removed * repair_strength, 0)
				H.Confuse(2)
		if(M.reagents.has_reagent(REAGENT_ID_CORDRADAXON) || M.reagents.has_reagent(REAGENT_ID_PERIDAXON))
			if(prob(5))
				H.vomit(1)
			else if(prob(5))
				to_chat(H, span_danger("Something churns inside you."))
				H.adjustToxLoss(10 * removed)
				H.vomit(0, 1)
		else
			H.adjustToxLoss(-12 * removed) // Carthatoline based, considering cost.

/datum/reagent/cordradaxon
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

/datum/reagent/cordradaxon/affect_blood(mob/living/carbon/M, alien, removed)
	var/repair_strength = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		repair_strength = 0.6
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/I in H.internal_organs)
			if(I.robotic >= ORGAN_ROBOT || !(I.organ_tag in list(O_HEART, O_SPLEEN, O_RESPONSE, O_ANCHOR, O_EGG)))
				continue
			if(I.damage > 0)
				I.damage = max(I.damage - 4 * removed * repair_strength, 0)
				H.Confuse(2)
		if(M.reagents.has_reagent(REAGENT_ID_HYRONALIN) || M.reagents.has_reagent(REAGENT_ID_PERIDAXON))
			H.losebreath = CLAMP(H.losebreath + 1, 0, 10)
		else
			H.adjustOxyLoss(-30 * removed) // Deals with blood oxygenation.

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

/datum/reagent/immunosuprizine/affect_blood(mob/living/carbon/M, alien, removed)
	var/strength_mod = 1 // * M.species.chem_strength_heal //Just removing the chem strength adjustment. It'd require division, which is best avoided.

	if(alien == IS_DIONA)	// It's a tree.
		strength_mod = 4

	if(alien == IS_SLIME)	// Diffculty bonding with internal cellular structure.
		strength_mod = 1.3

	if(alien == IS_UNATHI)	// Natural regeneration, robust biology.
		strength_mod = 0.6

	if(alien == IS_TAJARA)	// Highest metabolism.
		strength_mod = 0.5

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(alien != IS_DIONA)
			H.adjustToxLoss((30 * strength_mod) * removed)

		var/list/organtotal = list()
		organtotal |= H.organs
		organtotal |= H.internal_organs

		for(var/obj/item/organ/I in organtotal)	// Don't mess with robot bits, they don't reject.
			if(I.robotic >= ORGAN_ROBOT)
				organtotal -= I

		if(dose >= 15)
			for(var/obj/item/organ/I in organtotal)
				if(I.transplant_data && prob(round(15 * strength_mod)))	// Reset the rejection process, toggle it to not reject.
					I.rejecting = 0
					I.can_reject = FALSE

		if(H.reagents.has_reagent(REAGENT_ID_SPACEACILLIN) || H.reagents.has_reagent(REAGENT_ID_COROPHIZINE))	// Chemicals that increase your immune system's aggressiveness make this chemical's job harder.
			for(var/obj/item/organ/I in organtotal)
				if(I.transplant_data)
					var/rejectmem = I.can_reject
					I.can_reject = initial(I.can_reject)
					if(rejectmem != I.can_reject)
						H.adjustToxLoss((15 / strength_mod) * removed) //Someone forgot a * removed here in the past. It made it so 1u of this chem would do (baseline) 1245 toxins per unit, or 15 toxins per tick.
						I.take_damage(1)

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

/datum/reagent/skrellimmuno/affect_blood(mob/living/carbon/M, alien, removed)
	var/strength_mod = 0.5 * M.species.chem_strength_heal

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(alien != IS_SKRELL)
			H.adjustToxLoss(20 * removed)

		var/list/organtotal = list()
		organtotal |= H.organs
		organtotal |= H.internal_organs

		for(var/obj/item/organ/I in organtotal)	// Don't mess with robot bits, they don't reject.
			if(I.robotic >= ORGAN_ROBOT)
				organtotal -= I

		if(dose >= 15)
			for(var/obj/item/organ/I in organtotal)
				if(I.transplant_data && prob(round(15 * strength_mod)))
					I.rejecting = 0
					I.can_reject = FALSE

		if(H.reagents.has_reagent(REAGENT_ID_SPACEACILLIN) || H.reagents.has_reagent(REAGENT_ID_COROPHIZINE))
			for(var/obj/item/organ/I in organtotal)
				if(I.transplant_data)
					var/rejectmem = I.can_reject
					I.can_reject = initial(I.can_reject)
					if(rejectmem != I.can_reject)
						H.adjustToxLoss((10 / strength_mod))
						I.take_damage(1)

/datum/reagent/ryetalyn
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

/datum/reagent/ryetalyn/affect_blood(mob/living/carbon/M, alien, removed)
	//Ryetalyn is for genetics damage curing not resetting mutations, breaks traitgenes
	if(alien == IS_DIONA)
		return
	var/chem_effective = 1 * M.species.chem_strength_heal
	M.adjustCloneLoss(-2 * removed * chem_effective)

/*/datum/reagent/hyperzine
	name = REAGENT_HYPERZINE
	id = REAGENT_ID_HYPERZINE
	description = "Hyperzine is a highly effective, long lasting, muscle stimulant."
	reagent_state = LIQUID
	color = "#FF3300"
	metabolism = REM * 1
	mrate_static = TRUE
	overdose = REAGENTS_OVERDOSE * 0.5

/datum/reagent/hyperzine/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	if(prob(5))
		M.emote(pick("twitch", "blink_r", "shiver"))
	M.add_chemical_effect(CE_SPEEDBOOST, 1)
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

/datum/reagent/ethylredoxrazine/affect_ingest(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	M.clear_dizzy()
	M.drowsyness = 0
	M.stuttering = 0
	M.SetConfused(0)
	if(M.ingested)
		for(var/datum/reagent/R in M.ingested.reagent_list)
			if(istype(R, /datum/reagent/ethanol))
				R.remove_self(removed * 30)

/datum/reagent/ethylredoxrazine/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	M.clear_dizzy()
	M.drowsyness = 0
	M.stuttering = 0
	M.SetConfused(0)
	if(M.bloodstr)
		for(var/datum/reagent/R in M.bloodstr.reagent_list)
			if(istype(R, /datum/reagent/ethanol))
				R.remove_self(removed * 20)

/datum/reagent/hyronalin
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

/datum/reagent/hyronalin/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	M.radiation = max(M.radiation - 30 * removed * M.species.chem_strength_heal, 0)
	M.accumulated_rads = max(M.accumulated_rads - 30 * removed * M.species.chem_strength_heal, 0)

/datum/reagent/arithrazine
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

/datum/reagent/arithrazine/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	M.radiation = max(M.radiation - 70 * removed * M.species.chem_strength_heal, 0)
	M.accumulated_rads = max(M.accumulated_rads - 70 * removed * M.species.chem_strength_heal, 0)
	M.adjustToxLoss(-10 * removed)
	if(prob(60))
		M.take_organ_damage(4 * removed, 0)

/datum/reagent/spaceacillin
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
			if(world.time > data + delay)
				data = world.time
				to_chat(M, span_warning("Your senses feel unfocused, and divided."))
	M.add_chemical_effect(CE_ANTIBIOTIC, dose >= overdose ? ANTIBIO_OD : ANTIBIO_NORM)

/datum/reagent/spaceacillin/affect_touch(mob/living/carbon/M, alien, removed)
	affect_blood(M, alien, removed * 0.8) // Not 100% as effective as injections, though still useful.

/datum/reagent/corophizine
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
	M.add_chemical_effect(CE_ANTIBIOTIC, ANTIBIO_SUPER)

	var/mob/living/carbon/human/H = M

	if(ishuman(M) && alien == IS_SLIME) //Everything about them is treated like a targetted organism. Widespread bodily function begins to fail.
		if(volume <= 0.1 && data != -1)
			data = -1
			to_chat(M, span_notice("Your body ceases its revolt."))
		else
			var/delay = (3 MINUTES)
			if(world.time > data + delay)
				data = world.time
				to_chat(M, span_critical("It feels like your body is revolting!"))
		M.Confuse(7)
		M.adjustFireLoss(removed * 2)
		M.adjustToxLoss(removed * 2)
		if(dose >= 5 && M.toxloss >= 10) //It all starts going wrong.
			M.adjustBruteLoss(removed * 3)
			M.eye_blurry = min(20, max(0, M.eye_blurry + 10))
			if(prob(25))
				if(prob(25))
					to_chat(M, span_danger("Your pneumatic fluids seize for a moment."))
				M.Stun(2)
				spawn(30)
					M.Weaken(2)
		if(dose >= 10 || M.toxloss >= 25) //Internal skeletal tubes are rupturing, allowing the chemical to breach them.
			M.adjustToxLoss(removed * 4)
			M.make_jittery(5)
		if(dose >= 20 || M.toxloss >= 60) //Core disentigration, cellular mass begins treating itself as an enemy, while maintaining regeneration. Slime-cancer.
			M.adjustBrainLoss(2 * removed)
			M.adjust_nutrition(-20)
		if(M.bruteloss >= 60 && M.toxloss >= 60 && M.brainloss >= 30) //Total Structural Failure. Limbs start splattering.
			var/obj/item/organ/external/O = pick(H.organs)
			if(prob(20) && !istype(O, /obj/item/organ/external/chest/unbreakable/slime) && !istype(O, /obj/item/organ/external/groin/unbreakable/slime))
				to_chat(M, span_critical("You feel your [O] begin to dissolve, before it sloughs from your body."))
				O.droplimb(TRUE, DROPLIMB_ACID)
		return

	//Based roughly on Levofloxacin's rather severe side-effects
	if(prob(20))
		M.Confuse(5)
	if(prob(20))
		M.Weaken(5)
	if(prob(20))
		M.make_dizzy(5)
	if(prob(20))
		M.hallucination = max(M.hallucination, 10)

	//One of the levofloxacin side effects is 'spontaneous tendon rupture', which I'll immitate here. 1:1000 chance, so, pretty darn rare.
	if(ishuman(M) && rand(1,10000) == 1) //Adjusted to 1:10000
		var/obj/item/organ/external/eo = pick(H.organs) //Misleading variable name, 'organs' is only external organs
		eo.fracture()

/datum/reagent/spacomycaze
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
	M.add_chemical_effect(CE_PAINKILLER, 10 * M.species.chem_strength_pain)
	M.adjustToxLoss(3 * removed)

/datum/reagent/spacomycaze/affect_ingest(mob/living/carbon/M, alien, removed)
	affect_blood(M, alien, removed * 0.8)

/datum/reagent/spacomycaze/affect_touch(mob/living/carbon/M, alien, removed)
	if(alien == IS_SLIME)
		if(volume <= 0.1 && data != -1)
			data = -1
			to_chat(M, span_notice("The itching fades..."))
		else
			var/delay = (2 MINUTES)
			if(world.time > data + delay)
				data = world.time
				to_chat(M, span_warning("Your skin itches."))

	M.add_chemical_effect(CE_ANTIBIOTIC, dose >= overdose ? ANTIBIO_OD : ANTIBIO_NORM)
	M.add_chemical_effect(CE_PAINKILLER, 20 * M.species.chem_strength_pain) // 5 less than paracetamol.

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

/datum/reagent/sterilizine/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_SLIME)
		M.adjustFireLoss(removed)
		M.adjustToxLoss(2 * removed)
	return

/datum/reagent/sterilizine/affect_touch(mob/living/carbon/M, alien, removed)
	M.germ_level -= min(removed*20, M.germ_level)
	for(var/obj/item/I in M.contents)
		dq_set_was_bloodied(I, null)
	dq_set_was_bloodied(M, null)
	if(alien == IS_SLIME)
		M.adjustFireLoss(removed)
		M.adjustToxLoss(2 * removed)

/datum/reagent/sterilizine/touch_obj(obj/O)
	..()
	O.germ_level -= min(volume*200, O.germ_level)
	dq_set_was_bloodied(O, null)

/datum/reagent/sterilizine/touch_turf(turf/T)
	..()
	T.germ_level -= min(volume*200, T.germ_level)
	for(var/obj/item/I in T.contents)
		dq_set_was_bloodied(I, null)
	for(var/obj/effect/decal/cleanable/blood/B in T)
		qdel(B)

	if(istype(T, /turf/simulated))
		var/turf/simulated/S = T
		S.dirt = -50

/datum/reagent/sterilizine/touch_mob(mob/living/L, amount)
	..()
	if(istype(L))
		if(istype(L, /mob/living/simple_mob/slime))
			var/mob/living/simple_mob/slime/S = L
			S.adjustToxLoss(rand(15, 25) * amount)	// Does more damage than water.
			S.visible_message(span_warning("[S]'s flesh sizzles where the fluid touches it!"), span_danger("Your flesh burns in the fluid!"))
		remove_self(amount)

/datum/reagent/leporazine
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

/datum/reagent/leporazine/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	var/temp = 310
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		temp = H.species.body_temperature
	if(M.bodytemperature > temp)
		M.bodytemperature = max(temp, M.bodytemperature - (40 * TEMPERATURE_DAMAGE_COEFFICIENT))
	else if(M.bodytemperature < temp+1)
		M.bodytemperature = min(temp, M.bodytemperature + (40 * TEMPERATURE_DAMAGE_COEFFICIENT))

/datum/reagent/rezadone
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

/datum/reagent/rezadone/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	var/strength_mod = 1 * M.species.chem_strength_heal
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
	M.adjustCloneLoss(-20 * removed * strength_mod)
	M.adjustOxyLoss(-2 * removed * strength_mod)
	M.heal_organ_damage(20 * removed, 20 * removed * strength_mod)
	M.adjustToxLoss(-20 * removed * strength_mod)
	if(dose > 3)
		M.status_flags &= ~DISFIGURED
	if(dose > 10)
		M.make_dizzy(5)
		M.make_jittery(5)

// This exists to cut the number of chemicals a merc borg has to juggle on their hypo.
/datum/reagent/healing_nanites
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

/datum/reagent/healing_nanites/affect_blood(mob/living/carbon/M, alien, removed)
	M.heal_organ_damage(2 * removed, 2 * removed)
	M.adjustOxyLoss(-4 * removed)
	M.adjustToxLoss(-2 * removed)
	M.adjustCloneLoss(-2 * removed)

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
	M.heal_organ_damage (4 * removed, 4 * removed)
	M.adjustOxyLoss(-10 * removed)
	M.adjustToxLoss(-4 * removed)
	M.adjustCloneLoss(-2 * removed)
	M.druggy = max(M.druggy, 20)
	M.hallucination = max(M.hallucination, 3)
	M.adjustBrainLoss(1 * removed) //your life for your mind. The Earthmother's Tithe.


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
			M.adjustToxLoss( rand(1,4) )
			M.adjustBruteLoss( rand(1,4) )
			M.adjustOxyLoss( rand(1,4) )
	// proc side effect
	if(current_addiction <= 30)
		if(prob(3))
			M.Weaken(2)
			M.emote("vomit")
			M.add_chemical_effect(CE_WITHDRAWL, rand(9,14) * REM)
	else if(current_addiction <= 40)
		if(prob(3))
			M.emote("vomit")
			M.add_chemical_effect(CE_WITHDRAWL, rand(5,9) * REM)
	else if(current_addiction <= 50)
		if(prob(2))
			M.emote("vomit")
	// Sustenance requirements cannot be escaped!
	if(current_addiction <= 0)
		current_addiction = 40
	return current_addiction

/datum/reagent/tercozolam
	name = REAGENT_TERCOZOLAM
	id = REAGENT_ID_TERCOZOLAM
	color = "#afeb17"
	metabolism = 0.05
	scannable = SCANNABLE_BENEFICIAL
	dermal_absorption = 0.2
	description = "A well respected drug used for treatment of schizophrenia in specific."
	overdose = REAGENTS_OVERDOSE * 2
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG


// === merged from medicine_ch.dm during hard-fork de-suffix (verified no override-order change) ===
////////////////////////////////////
////////////   MEDICINE   /////////
//////////////////////////////////
/datum/reagent/claridyl
	name = REAGENT_CLARIDYL
	id = REAGENT_ID_CLARIDYL
	description = "Claridyl is an advanced medicine that cures all of your problems. Notice: Clarydil does not claim to fix marriages, car loans, student debt or insomnia and may cause severe pain."
	taste_description = "sugar"
	scannable = SCANNABLE_BENEFICIAL
	reagent_state = LIQUID
	color = "#AAAAFF"
	overdose = REAGENTS_OVERDOSE * 100
	metabolism = REM * 0.1
	dermal_absorption = 1
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/claridyl/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		M.add_chemical_effect(CE_STABLE, 30)
		M.add_chemical_effect(CE_PAINKILLER, 40)
		if(M.getBruteLoss())
			M.adjustBruteLoss(-1)
			M.adjustHalLoss(1.5)
		if(prob(0.0001))
			M.adjustToxLoss(50)//instant crit for tesh

		if(prob(0.1))
			pick(M.custom_pain("You suddenly feel inexplicably angry!",30),
			M.custom_pain("You suddenly lose your train of thought!",30),
			M.custom_pain("Your mouth feels dry!",30),
			M.make_dizzy(2),
			M.AdjustWeakened(10),
			M.AdjustStunned(1),
			M.AdjustParalysis(0.1),
			M.hallucination = max(M.hallucination, 2),
			M.flash_eyes(),
			M.custom_pain("Your vision becomes blurred!",30),
			M.add_chemical_effect(CE_ALCOHOL, 5),)

/datum/reagent/claridyl/bloodburn
	name = REAGENT_BLOODBURN
	id = REAGENT_ID_BLOODBURN
	description = "A chemical used to soak up any reagents inside someones stomach, injection is not advised, if you need to ask why please seek a new job."
	taste_description = "liquid void"
	dermal_absorption = 0
	color = "#000000"
	metabolism = REM * 5

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
	name = REAGENT_EDEN
	id = REAGENT_ID_EDEN
	description = "The ultimate anti toxin unrivaled, it corrects impurities within the body but punishes those who attain them with a burning sensation"
	taste_description = "peace"
	scannable = SCANNABLE_BENEFICIAL
	color = "#00FFBE"
	overdose = REAGENTS_OVERDOSE * 1
	metabolism = 0
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/eden/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_SLIME || alien == IS_DIONA)
		return
	if(M.getToxLoss())
		M.adjustFireLoss(1.2)
		M.adjustToxLoss(-1)

/datum/reagent/eden/snake
	name = REAGENT_EDENSNAKE
	id = REAGENT_ID_EDENSNAKE
	metabolism = 0.1
	description = "It used to be an anti toxin until it was tainted."
	taste_description = "hellfire"
	color = "#FF0000"

/datum/reagent/eden/snake/affect_blood(mob/living/carbon/M, alien, removed)
	M.adjustOxyLoss(1)
	M.adjustFireLoss(1)
	M.adjustBruteLoss(1)
	M.adjustToxLoss(1)

/datum/reagent/tercozolam
	name = REAGENT_TERCOZOLAM
	id = REAGENT_ID_TERCOZOLAM
	scannable = SCANNABLE_BENEFICIAL
	color = "#afeb17"
	metabolism = 0.05
	description = "A well respected drug used for treatment of schizophrenia in specific."
	overdose = REAGENTS_OVERDOSE * 2
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

///SAP REAGENTS////
//This is all a direct port from aeiou.

/datum/reagent/hannoa
	name = REAGENT_HANNOA
	id = REAGENT_ID_HANNOA
	scannable = SCANNABLE_BENEFICIAL
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
		for(var/obj/item/organ/external/O in H.bad_external_organs)
			for(var/datum/wound/W in O.wounds)
				if(W.bleeding())
					W.damage = max(W.damage - wound_heal, 0)
					if(W.damage <= 0)
						O.wounds -= W
		M.take_organ_damage(3 * removed, 0)
		if(M.losebreath < 15)
			M.AdjustLosebreath(1)
		H.custom_pain("It feels as if your veins are fusing shut!",60)

/datum/reagent/hannoa/affect_blood(mob/living/carbon/M, alien, removed) //Sleepy if not overdosing.
	..()
	var/effective_dose = dose
	if(effective_dose < 2)
		if(effective_dose == metabolism * 2 || prob(5))
			M.emote("yawn")
		else if(effective_dose < 5)
			M.eye_blurry = max(M.eye_blurry, 10)
		else if(effective_dose < 20)
			if(prob(50))
				M.Weaken(2)
			M.drowsyness = max(M.drowsyness, 20)
	else
		M.sleeping = max(M.sleeping, 20)


/datum/reagent/bullvalene //This is for the third sap. It converts Brute Oxy and burn into slightly less toxins.
	name = REAGENT_BULLVALENE
	id = REAGENT_ID_BULLVALENE
	scannable = SCANNABLE_BENEFICIAL
	description = "A catalytic chemical that can treat a wide variety of ailments at the cost of toxifying the host's body."
	taste_description = "sulfur"
	reagent_state = LIQUID
	color = "#163851"
	overdose = 8 //This many units starts killing you.
	scannable = 1 // Mechs can scan this ye
	metabolism = REM * 0.15 //Slow metabolism. This value was plucked out of nowhere. Can be changed.
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/bullvalene/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_SLIME || alien == IS_DIONA)
		return
	if(M.getBruteLoss() || M.getFireLoss() || M.getOxyLoss())
		M.adjustOxyLoss(-1)
		M.adjustFireLoss(-1)
		M.adjustBruteLoss(-1)
		M.adjustToxLoss(0.8)

/////SERAZINE REAGENTS///////

/datum/reagent/serazine
	name = REAGENT_SERAZINE
	id = REAGENT_ID_SERAZINE
	scannable = SCANNABLE_BENEFICIAL
	description = "A sweet tasting flower extract, it has very mild anti toxic properties, help with hallucinations and drowsyness, and can be used to make potent drugs."
	taste_description = "sweet nectar"
	reagent_state = LIQUID
	color = "#df9898"
	scannable = 1
	dermal_absorption = 0.25
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/serazine/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1
	if(alien != IS_DIONA)
		M.drowsyness = max(0, M.drowsyness - 3 * removed * chem_effective)
		M.hallucination = max(0, M.hallucination - 6 * removed * chem_effective)
		M.adjustToxLoss(-2 * removed * chem_effective)

/datum/reagent/alizene
	name = REAGENT_ALIZENE
	id = REAGENT_ID_ALIZENE
	scannable = SCANNABLE_BENEFICIAL
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

/datum/reagent/alizene/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1
	if(alien == IS_SLIME)
		chem_effective = 0.75
	if(alien != IS_DIONA)
		M.heal_organ_damage(12 * removed * chem_effective, 0)


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

/datum/reagent/adranol/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	if(M.confused)
		M.Confuse(-8*removed)
	if(M.eye_blurry)
		M.eye_blurry = max(M.eye_blurry - 25*removed, 0)
	M.make_jittery(-25*removed)

/datum/reagent/numbing_enzyme
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
	M.add_chemical_effect(CE_PAINKILLER, 200)
	if(prob(0.01)) //1 in 10000 chance per tick. Extremely rare.
		to_chat(M,span_warning("Your body feels numb as a light, tingly sensation spreads throughout it, like some odd warmth."))
	//Not noted here, but a movement debuff of 1.5 is handed out in human_movement.dm when numbing_enzyme is in a person's bloodstream!

/datum/reagent/numbing_enzyme/overdose(mob/living/carbon/M, alien)
	//..() //Add this if you want it to do toxin damage. Personally, let's allow them to have the horrid effects below without toxin damage.
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(prob(1))
			to_chat(H,span_warning("Your entire body feels numb and the sensation of pins and needles continually assaults you. You blink and the next thing you know, your legs give out momentarily!"))
			H.AdjustWeakened(5) //Fall onto the floor for a few moments.
			H.Confuse(15) //Be unable to walk correctly for a bit longer.
		if(prob(1))
			if(H.losebreath <= 1 && H.oxyloss <= 20) //Let's not suffocate them to the point that they pass out.
				to_chat(H,span_warning("You feel a sharp stabbing pain in your chest and quickly realize that your lungs have stopped functioning!")) //Let's scare them a bit.
				H.losebreath = 10
				H.adjustOxyLoss(5)
		if(prob(2))
			to_chat(H,span_warning("You feel a dull pain behind your eyes and at the back of your head..."))
			H.hallucination += 20 //It messes with your mind for some reason.
			H.eye_blurry += 20 //Groggy vision for a small bit.
		if(prob(3))
			to_chat(H,span_warning("You shiver, your body continually being assaulted by the sensation of pins and needles."))
			H.emote("shiver")
			H.make_jittery(10)
		if(prob(3))
			to_chat(H,span_warning("Your tongue feels numb and unresponsive."))
			H.stuttering += 20

/datum/reagent/vermicetol
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

/datum/reagent/vermicetol/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal //YW EDIT
	if(alien == IS_SLIME)
		chem_effective = 0.75
	if(alien != IS_DIONA)
		M.heal_organ_damage(8 * removed * chem_effective, 0)

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
	M.remove_a_modifier_of_type(/datum/modifier/resleeving_sickness)
	M.remove_a_modifier_of_type(/datum/modifier/faux_resleeving_sickness)
*/


/datum/reagent/prussian_blue //We don't have iodine, so prussian blue we go.
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

/datum/reagent/prussian_blue/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	if(prob(10)) //Miniscule chance of removing some toxins.
		M.adjustToxLoss(-10 * removed)

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
		M.weight -= 0.3

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
	M.adjust_nutrition(-20 * removed)
	if(M.weight < 500)
		M.weight += 0.3

/datum/reagent/polymorph
	name = REAGENT_POLYMORPH
	id = REAGENT_ID_POLYMORPH
	description = "A chemical that instantly transforms the consumer into another creature."
	taste_description = "luck"
	reagent_state = LIQUID
	scannable = SCANNABLE_SECRETIVE
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
	add_verb(target, /mob/living/carbon/human/proc/enter_cocoon)
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

/datum/reagent/change_drug/affect_blood(mob/living/carbon/human/M, alien, removed)
	if (!(alien == IS_DIONA || M.gender == gender_change || M.gender_change_cooldown == 1) && M.allow_spontaneous_tf)
		//set not to bug them because the chem is activating
		M.gender_change_cooldown = 1
		M.visible_message(
			span_notice("[M] suddenly twitches as some of their features seem to contort and reshape."),
			span_notice("You lose focus as warmth spreads throughout your chest and abdomen.")
		)
		//wait 30 seconds, growth takes time yo
		spawn(300)
			//allow it to bug them again now that we've waited
			M.gender_change_cooldown = 0
			//check if they want this to happen for pref sake
			if (alert(M,"This chemical will change your gender, proceed?", "Warning", "Yes", "No") == "Yes")
				M.change_gender_identity(gender_change)
				M.change_gender(gender_change)
				to_chat(M, span_warning("You feel like a new person."))

//Chemist expansion
//deathblood
/datum/reagent/cleansingagent
	name = REAGENT_CLEANSINGAGENT
	id = REAGENT_ID_CLEANSINGAGENT
	description = "An agent that purges one's body of toxins."
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#225722"
	scannable = 1
	dermal_absorption = 0.2
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 0
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/cleansingagent/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.66
	if(alien != IS_DIONA)
		M.druggy = max(M.druggy, 5)
		M.adjustToxLoss(-6 * removed * chem_effective)
		M.radiation = max(M.radiation - 15 * removed * M.species.chem_strength_heal, 0)
		M.accumulated_rads = max(M.accumulated_rads - 15 * removed * M.species.chem_strength_heal, 0)

/datum/reagent/purifyingagent
	name = REAGENT_PURIFYINGAGENT
	id = REAGENT_ID_PURIFYINGAGENT
	description = "An agent that purges one's body of rads and toxins."
	reagent_state = LIQUID
	scannable = SCANNABLE_BENEFICIAL
	color = "#225722"
	scannable = 1
	dermal_absorption = 0.2
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 0
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/purifyingagent/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.66
	if(alien != IS_DIONA)
		M.adjustToxLoss(-6 * removed * chem_effective)
		M.radiation = max(M.radiation - 15 * removed * M.species.chem_strength_heal, 0)
		M.accumulated_rads = max(M.accumulated_rads - 15 * removed * M.species.chem_strength_heal, 0)

//liquid fire
/datum/reagent/burncard
	name = REAGENT_BURNCARD
	id = REAGENT_ID_BURNCARD
	description = "A more powerful variation of bicard that also burns the subject."
	taste_description = "bitterness"
	scannable = SCANNABLE_BENEFICIAL
	taste_mult = 3
	reagent_state = LIQUID
	color = "#BF0000"
	overdose = REAGENTS_OVERDOSE * 0.2
	dermal_absorption = 0.2
	overdose_mod = 1.25
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/burncard/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.75
	if(alien != IS_DIONA)
		M.heal_organ_damage(13 * removed * chem_effective, 0)
		M.adjustFireLoss(1 * removed)

/datum/reagent/burncard/overdose(mob/living/carbon/M, alien, removed)
	..()
	var/wound_heal = 3 * removed
	M.eye_blurry = min(M.eye_blurry + wound_heal, 250)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/external/O in H.bad_external_organs)
			for(var/datum/wound/W in O.wounds)
				if(W.bleeding())
					W.damage = max(W.damage - wound_heal, 0)
					if(W.damage <= 0)
						O.wounds -= W
				if(W.internal)
					W.damage = max(W.damage - wound_heal, 0)
					if(W.damage <= 0)
						O.wounds -= W

/datum/reagent/flamecure
	name = REAGENT_FLAMECURE
	id = REAGENT_ID_FLAMECURE
	description = "Used to rapidly clot internal hemorrhages by burning the wounded areas"
	reagent_state = LIQUID
	scannable = SCANNABLE_BENEFICIAL
	color = "#4246C7"
	overdose = REAGENTS_OVERDOSE * 0.5
	dermal_absorption = 0.2
	scannable = 1
	var/repair_strength = 9
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/flamecure/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	M.eye_blurry = min(M.eye_blurry + (repair_strength * removed), 250)
	M.heal_organ_damage(0, -1 * removed)
	if(ishuman(M))
		M.heal_organ_damage(0, -1 * removed)
		var/mob/living/carbon/human/H = M
		var/wound_heal = removed * repair_strength
		for(var/obj/item/organ/external/O in H.bad_external_organs)
			for(var/datum/wound/W in O.wounds)
				if(W.bleeding())
					W.damage = max(W.damage - wound_heal, 0)
					if(W.damage <= 0)
						O.wounds -= W
				if(W.internal)
					W.damage = max(W.damage - wound_heal, 0)
					if(W.damage <= 0)
						O.wounds -= W

//neoliquidfire
/datum/reagent/neotane
	name = REAGENT_NEOTANE
	id = REAGENT_ID_NEOTANE
	description = "An advancement of kelotane that scars and breaks apart the user's flesh to remove the burnt tissue."
	taste_description = "bitterness"
	reagent_state = LIQUID
	scannable = SCANNABLE_BENEFICIAL
	color = "#FF6600"
	overdose = REAGENTS_OVERDOSE * 0.2
	dermal_absorption = 0.2
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/neotane/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 0.5
		M.adjustBruteLoss(3 * removed)
	if(alien != IS_DIONA)
		M.heal_organ_damage(0, 13 * removed * chem_effective)
		M.adjustBruteLoss(1 * removed)

/datum/reagent/bloodsealer
	name = REAGENT_BLOODSEALER
	id = REAGENT_ID_BLOODSEALER
	description = "A strange chemical that will stablize bloodflow by burning the subject"
	taste_description = "bitterness"
	reagent_state = LIQUID
	scannable = SCANNABLE_BENEFICIAL
	dermal_absorption = 0.2
	color = "#00BFFF"
	overdose = REAGENTS_OVERDOSE
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/bloodsealer/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		M.add_chemical_effect(CE_STABLE, 25)
		M.heal_organ_damage(0, -1 * removed)

//meteroidliquid
/datum/reagent/livingagent
	name = REAGENT_LIVINGAGENT
	id = REAGENT_ID_LIVINGAGENT
	scannable = SCANNABLE_BENEFICIAL
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
	M.druggy = max(M.druggy, 5)
	M.Confuse(5)

/datum/reagent/livingagent/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		var/chem_effective = 1 * M.species.chem_strength_heal
		if(alien == IS_SLIME)
			chem_effective = 0.5
		M.adjustOxyLoss(-4 * removed * chem_effective)
		M.heal_organ_damage(2 * removed, 2 * removed * chem_effective)
		M.adjustToxLoss(-3 * removed * chem_effective)
		M.add_chemical_effect(CE_PAINKILLER, -20 * M.species.chem_strength_pain)

/datum/reagent/performancepeaker
	name = REAGENT_PERFORMANCEPEAKER
	id = REAGENT_ID_PERFORMANCEPEAKER
	description = "A chemical created to bring a body to peak condition. Highly toxic"
	scannable = SCANNABLE_ADVANCED
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#006666"
	scannable = 1
	dermal_absorption = 0 //This chem is a stronger poison than a benefical chem, with a strength of 15.
	overdose = REAGENTS_OVERDOSE * 0.5
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/performancepeaker/affect_blood(mob/living/carbon/M, alien, removed)
	M.add_chemical_effect(CE_SPEEDBOOST, 0.5)
	M.AdjustParalysis(-1)
	M.AdjustStunned(-1)
	M.AdjustWeakened(-1)
	M.add_chemical_effect(CE_PAINKILLER, 10 * M.species.chem_strength_pain)
	M.adjustToxLoss(15 * removed)

//advanced crafting
//tier 1
/datum/reagent/souldew
	name = REAGENT_SOULDEW
	id = REAGENT_ID_SOULDEW
	description = "An experimental drug that solely works upon dead bodies"
	taste_description = "ash"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
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
		M.adjustOxyLoss(-3 * removed * chem_effective)
		M.heal_organ_damage(3 * removed * chem_effective, 3 * removed * chem_effective)
		M.adjustToxLoss(-3 * removed * chem_effective)

/datum/reagent/quadcord
	name = REAGENT_QUADCORD
	id = REAGENT_ID_QUADCORD
	description = "An experimental drug that is meant to further enhance tricord"
	taste_description = "bitterness"
	scannable = SCANNABLE_BENEFICIAL
	reagent_state = LIQUID
	color = "#FF3399"
	scannable = 1
	overdose = REAGENTS_OVERDOSE * 2
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI
/datum/reagent/quadcord/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		var/chem_effective = 1 * M.species.chem_strength_heal
		if(alien == IS_SLIME)
			chem_effective = 0.5
		M.adjustOxyLoss(-0.5 * removed * chem_effective)
		M.heal_organ_damage(0.5 * removed * chem_effective, 0.5 * removed * chem_effective)
		M.adjustToxLoss(-0.5 * removed * chem_effective)
		M.adjustBrainLoss(-1 * removed * chem_effective)

//tier 2


/datum/reagent/curea
	name = REAGENT_CUREA
	id = REAGENT_ID_CUREA
	description = "An experimental that removes many ailments, such as poison and stiffening of muscles via frost"
	taste_description = "bitterness"
	reagent_state = LIQUID
	scannable = SCANNABLE_BENEFICIAL
	color = "#660066"
	scannable = 1
	dermal_absorption = 1
	overdose = REAGENTS_OVERDOSE * 0.5
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/curea/affect_blood(mob/living/carbon/M, alien, removed)
	M.remove_a_modifier_of_type(/datum/modifier/poisoned)
	M.remove_a_modifier_of_type(/datum/modifier/chilled)
	M.remove_a_modifier_of_type(/datum/modifier/doomed)
	M.remove_a_modifier_of_type(/datum/modifier/invulnerable)
	M.remove_a_modifier_of_type(/datum/modifier/elemental_vulnerability)
	M.remove_a_modifier_of_type(/datum/modifier/grievous_wounds)
	M.remove_a_modifier_of_type(/datum/modifier/deep_wounds)
	M.remove_a_modifier_of_type(/datum/modifier/hivebot_weaken)
	M.extinguish_mob()
	M.remove_a_modifier_of_type(/datum/modifier/berserk_exhaustion)
	M.remove_a_modifier_of_type(/datum/modifier/entangled)
	M.remove_a_modifier_of_type(/datum/modifier/wizfire)
	M.remove_a_modifier_of_type(/datum/modifier/wizpoison)

//tier 3
/datum/reagent/modapplying/liquidhealer
	name = REAGENT_LIQUIDHEALER
	id = REAGENT_ID_LIQUIDHEALER
	description = "An experimental drug that mimics rapid regeneration seen in squishy creatures."
	taste_description = "sweet"
	reagent_state = LIQUID
	scannable = SCANNABLE_BENEFICIAL
	color = "#00CCFF"
	scannable = 1
	overdose = REAGENTS_OVERDOSE * 0.5
	modifier_to_add = /datum/modifier/liquidhealer
	modifier_duration = 3 SECONDS
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/modifier/liquidhealer
	name = REAGENT_ID_LIQUIDHEALER
	desc = "You are filled with an overwhelming healing."

	on_created_text = span_critical("You feel your body's natural healing quick into overdrive!")
	on_expired_text = span_notice("Your body returns to normal.")

	incoming_healing_percent = 1.2

/datum/modifier/liquidhealer/tick()
	if(holder.stat == DEAD)
		expire()

	if(ishuman(holder)) // Robolimbs need this code sadly.
		var/mob/living/carbon/human/H = holder
		for(var/obj/item/organ/external/E in H.organs)
			var/obj/item/organ/external/O = E
			O.heal_damage(1, 1, 0, 1)
	else
		holder.adjustBruteLoss(-1)
		holder.adjustFireLoss(-1)

	holder.adjustToxLoss(-1)
	holder.adjustOxyLoss(-1)
	holder.adjustCloneLoss(-1)


/datum/reagent/modapplying/phoenixbreath
	name = REAGENT_PHOENIXBREATH
	id = REAGENT_ID_PHOENIXBREATH
	description = "An experimental chem that will bring those back from the brink, with severe side effects"
	taste_description = "ash"
	reagent_state = LIQUID
	scannable = SCANNABLE_BENEFICIAL
	color = "#fcac00"
	scannable = 1
	overdose = REAGENTS_OVERDOSE
	mrate_static = TRUE
	metabolism = 0.1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI
	modifier_to_add = /datum/modifier/life_cloak
	modifier_duration = 3 SECONDS


/datum/reagent/dryagent
	name = REAGENT_DRYAGENT
	id = REAGENT_ID_DRYAGENT
	description = "A desiccant. Can be used to dry things."
	taste_description = "dryness"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#A70FFF"
	scannable = 1
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_INDUSTRY

/datum/reagent/dryagent/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(alien == IS_SLIME)
		chem_effective = 1.25
		M.adjustFireLoss(2 * removed * chem_effective) // Why are you giving this to Prometheans or Dionas. You're going to DRY them.

/datum/reagent/dryagent/touch_obj(obj/O, amount)
	if(istype(O, /obj/item/clothing/shoes/galoshes) && O.loc)
		new /obj/item/clothing/shoes/dry_galoshes(O.loc)
		qdel(O)
		remove_self(10)

/datum/reagent/dryagent/touch_turf(turf/T)
	..()
	if(volume >= 5)
		if(istype(T, /turf/simulated/floor))
			var/turf/simulated/floor/F = T
			if(F.wet)
				F.wet = 0
	return
