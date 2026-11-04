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
		if(M.losebreath() < 15)
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
