//Vore/kink reagents go here.
/datum/reagent/sorbitol
	name = REAGENT_SORBITOL
	id = REAGENT_ID_SORBITOL
	description = "A frothy green liquid, for causing cellular-level hetrogenous structure merging."
	reagent_state = LIQUID
	color = "#10881A"
	scannable = SCANNABLE_BENEFICIAL
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_ILLDRUG

/datum/reagent/sorbitol/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_DIZZY, 1)

	for(var/obj/belly/B as anything in M.vore_organs)

		if(B.digest_mode == DM_UNABSORB) //Don't affect bellies set to unabsorb
			continue

		for(var/mob/living/P in B)
			if(P.absorbed || !P.absorbable)
				continue

			else if(prob(10))
				B.absorb_living(P)
				//absorption reagent production
				if(B.show_liquids && B.reagent_mode_flags & DM_FLAG_REAGENTSABSORB && B.reagents.total_volume < B.reagents.maximum_volume)
					B.GenerateBellyReagents_absorbed()


// === merged from vore_vr.dm during hard-fork de-suffix (verified no override-order change) ===

////////////////////////////
/// NW's shrinking serum ///
////////////////////////////

/datum/reagent/macrocillin
	name = REAGENT_MACROCILLIN
	id = REAGENT_ID_MACROCILLIN
	description = "Glowing yellow liquid."
	reagent_state = LIQUID
	color = "#FFFF00" // rgb: 255, 255, 0
	metabolism = 0.01
	dermal_absorption = 1 //Grow patches.
	scannable = SCANNABLE_BENEFICIAL
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_GODTIER
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/macrocillin/affect_blood(mob/living/carbon/M, alien, removed)
	var/new_size = clamp((M.size_multiplier + 0.01), RESIZE_MINIMUM_DORMS, RESIZE_MAXIMUM_DORMS)
	M.resize(new_size, animate = FALSE, uncapped = M.has_large_resize_bounds()) //Incrrease 1% per tick. //don't do fancy animates. Unnecessary on 1% changes. Laggy.
	return

/datum/reagent/microcillin
	name = REAGENT_MICROCILLIN
	id = REAGENT_ID_MICROCILLIN
	scannable = SCANNABLE_BENEFICIAL
	description = "Murky purple liquid."
	reagent_state = LIQUID
	color = "#800080"
	metabolism = 0.01
	dermal_absorption = 1 //Shrink patches
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_GODTIER
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/microcillin/affect_blood(mob/living/carbon/M, alien, removed)
	var/new_size = clamp((M.size_multiplier - 0.01), RESIZE_MINIMUM_DORMS, RESIZE_MAXIMUM_DORMS)
	M.resize(new_size, animate = FALSE, uncapped = M.has_large_resize_bounds()) //Decrease 1% per tick. //don't do fancy animates. Unnecessary on 1% changes. Laggy.
	return


/datum/reagent/normalcillin
	name = REAGENT_NORMALCILLIN
	id = REAGENT_ID_NORMALCILLIN
	scannable = SCANNABLE_BENEFICIAL
	description = "Translucent cyan liquid."
	reagent_state = LIQUID
	color = "#00FFFF"
	metabolism = 0.01 //One unit will be just enough to bring someone from 200% to 100%
	dermal_absorption = 1
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_GODTIER
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/normalcillin/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.size_multiplier > RESIZE_NORMAL)
		M.resize(M.size_multiplier-0.01, FALSE) //Decrease by 1% size per tick. //don't do fancy animates. Unnecessary on 1% changes. Laggy.
	else if(M.size_multiplier < RESIZE_NORMAL)
		M.resize(M.size_multiplier+0.01, FALSE) //Increase 1% per tick. //don't do fancy animates. Unnecessary on 1% changes. Laggy.
	return


/datum/reagent/sizeoxadone
	name = REAGENT_SIZEOXADONE
	id = REAGENT_ID_SIZEOXADONE
	scannable = SCANNABLE_BENEFICIAL
	description = "A volatile liquid used as a precursor to size-altering chemicals. Causes dizziness if taken unprocessed."
	reagent_state = LIQUID
	color = "#1E90FF"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_PEAK
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/sizeoxadone/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_DIZZY, 1)
	M.status_at_least(STAT_CONFUSED, 20)
	return


////////////////////////// Anti-Noms Drugs //////////////////////////

/datum/reagent/ickypak
	name = REAGENT_ICKYPAK
	id = REAGENT_ID_ICKYPAK
	scannable = SCANNABLE_BENEFICIAL
	description = "A foul-smelling green liquid, for inducing muscle contractions to expel accidentally ingested things."
	reagent_state = LIQUID
	color = "#0E900E"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_WEAPONS

/datum/reagent/ickypak/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_DIZZY, 1)
	M.injure(INJURY_PAIN, 2, source = src)

	for(var/obj/belly/B as anything in M.vore_organs)
		for(var/atom/movable/A in B)
			if(isliving(A))
				var/mob/living/P = A
				if(P.absorbed)
					continue
			if(prob(5))
				play_sfx(M, SFX_EFFECTS_SPLAT)
				B.release_specific_contents(A)

/datum/reagent/unsorbitol
	name = REAGENT_UNSORBITOL
	id = REAGENT_ID_UNSORBITOL
	scannable = SCANNABLE_BENEFICIAL
	description = "A frothy pink liquid, for causing cellular-level hetrogenous structure separation."
	reagent_state = LIQUID
	color = "#EF77E5"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/unsorbitol/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_DIZZY, 1)
	M.injure(INJURY_PAIN, 1, source = src)
	M.status_set(STAT_CONFUSED, max(M.status_units(STAT_CONFUSED), 20))
	M.status_at_least(STAT_HALLUCINATING, 20) //This used to be += 15 resulting in INFINITE HALLUCINATION

	for(var/obj/belly/B as anything in M.vore_organs)

		if(B.digest_mode == DM_ABSORB) //Turn off absorbing on bellies
			B.digest_mode = DM_HOLD

		for(var/mob/living/P in B)
			if(!P.absorbed)
				continue

			else if(prob(1))
				play_sfx(M, SFX_VORE_SCHLORP, 0.5, vary = TRUE)
				P.set_absorbed(0)
				act_message(M, null, others = span_infoplain(span_green(span_bold("Something spills into %U%'s [lowertext(B.name)]!"))))

////////////////////////// Misc Drugs //////////////////////////

/datum/reagent/drugs/rainbow_toxin /// Replaces Space Drugs.
	name = REAGENT_RAINBOWTOXIN
	id = REAGENT_ID_RAINBOWTOXIN
	description = "Known for providing a euphoric high, this psychoactive drug is often injected into unknowing prey by serpents and other fanged beasts. Highly valuable and frequently sought after by hypno-enthusiasts and party-goers."
	taste_description = "mixed euphoria"
	taste_mult = 0.8 //You ARE going to taste this!
	scannable = 1	//Sure! If you manage to milk a snake for some of this, go ahead and scan it and mass produce it. Your local club will love you!

/datum/reagent/drugs/rainbow_toxin/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	var/drug_strength = 20
	if(M.species.chem_strength_tox > 0)
		drug_strength *= M.species.chem_strength_tox
	drug_strength *= species_mult(M)
	M.status_at_least(STAT_DRUGGED, drug_strength)

/datum/reagent/drugs/rainbow_toxin/overdose(mob/living/M as mob)
	if(prob_proc == TRUE && prob(20))
		M.status_at_least(STAT_HALLUCINATING, 5)
		prob_proc = FALSE
	M.injure(INJURY_NEURAL, 0.25*REM, source = src) //Too much isn't good for your long term health...
	M.injure(INJURY_TOXIN, 0.01*REM, source = src)	//Enough that it'll make your HUD dummy update, but not enough that you'll vomit mid scene. (Sorry emetophiliacs!)
	..()

/datum/reagent/paralysis_toxin
	name = REAGENT_PARALYSISTOXIN
	id = REAGENT_ID_PARALYSISTOXIN
	scannable = SCANNABLE_ADVANCED
	description = "A potent toxin commonly found in a plethora of species. When exposed to the toxin, causes extreme, paralysis for a prolonged period, with only essential functions of the body being unhindered. Commonly used by covert operatives and used as a crowd control tool."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0 //Too strong.
	color = "#37007f"
	metabolism = REM * 0.25
	overdose = REAGENTS_OVERDOSE
	scannable = 1 //As I found out, this only means if you can detect it or not. Sad.
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_WEAPONS

/datum/reagent/paralysis_toxin/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.status_units(STAT_WEAKENED) < 50 || M.status_units(STAT_STUNNED) <50 ) // Let's not leave them PERMA stuck, after all. // stun accounting for crawl
		M.status_adjust(STAT_WEAKENED, 5) //Stand in for paralyze so you can still talk/emote/see
		M.status_adjust(STAT_STUNNED, 5) // stun accounting for crawl

/datum/reagent/pain_enzyme
	factors = alist(BF_ANALGESIA = -200)
	name = REAGENT_PAINENZYME
	id = REAGENT_ID_PAINENZYME
	scannable = SCANNABLE_ADVANCED
	description = "An enzyme found in a variety of species. When exposed to the toxin, will cause severe, agonizing pain. The effects can last for hours depending on the dose. Only known cure is an equally strong painkiller or dialysis."
	taste_description = "sourness"
	reagent_state = LIQUID
	color = "#04b8fa" //Light blue in honor of Perry.
	metabolism = 0.1 //Lasts up to 50 seconds if you give 5 units.
	mrate_static = TRUE
	overdose = 100 //There is no OD. You already are taking the worst of it.
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_WEAPONS

/datum/reagent/pain_enzyme/affect_blood(mob/living/carbon/M, alien, removed)
	if(prob(0.01)) //1 in 10000 chance per tick. Extremely rare.
		to_chat(M,span_warning("Your body feels as though it's on fire!"))

/datum/reagent/aphrodisiac
	name = REAGENT_APHRODISIAC
	id = REAGENT_ID_APHRODISIAC
	scannable = SCANNABLE_ADVANCED
	description = "You so horny."
	taste_description = "sweetness"
	reagent_state = LIQUID
	color = "#FF9999"
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_DRUG


/datum/reagent/aphrodisiac/affect_blood(mob/living/carbon/M, alien, removed)
	if(!M)	return

	if(prob(3))
		M.emote(pick("blush", "moan", "moan", "giggle"))
