/* Things that didn't fit anywhere else */

/datum/reagent/adminordrazine //An OP chemical for admins
	// Admin magic: restores every biology, surgical lesions included.
	treatment_tags = list(TREAT_RESTORATION = DQ_CHEM_DOSE_CAP)
	factors = alist(STAT_ANALGESIA = 200, STAT_STABILIZATION = 15, STAT_ANTIMICROBIAL = ANTIBIO_SUPER)
	name = REAGENT_ADMINORDRAZINE
	id = REAGENT_ID_ADMINORDRAZINE
	description = "It's magic. We don't have to explain it."
	taste_description = "bwoink"
	reagent_state = LIQUID
	color = "#C8A5DC"
	affects_dead = TRUE //This can even heal dead people.
	metabolism = 0.1
	scannable = SCANNABLE_UNSCANNABLE
	mrate_static = TRUE //Just in case

	glass_name = "liquid gold"
	glass_desc = "It's magic. We don't have to explain it."
	wiki_flag = WIKI_SPOILER

	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = "how did you get this?"

/datum/reagent/adminordrazine/affect_touch(mob/living/carbon/M, alien, removed)
	affect_blood(M, alien, removed)

/datum/reagent/adminordrazine/affect_blood(mob/living/carbon/M, alien, removed)
	// Admin chem: heals everything.
	M.fully_heal()
	M.status_set(STAT_HALLUCINATING, 0)
	M.set_disabilities(0)
	M.set_sdisabilities(0)
	M.status_set(STAT_BLURRY, 0)
	M.status_set(STAT_BLINDED, 0)
	M.status_set(STAT_WEAKENED, 0)
	M.status_set(STAT_STUNNED, 0)
	M.status_set(STAT_PARALYZED, 0)
	M.status_set(STAT_MUTED, 0)
	M.status_end(STAT_DIZZY)
	M.status_end(STAT_JITTERY)
	M.status_set(STAT_DROWSY, 0)
	M.status_set(STAT_STUTTERING, 0)
	M.status_set(STAT_CONFUSED, 0)
	M.status_set(STAT_SLEEPING, 0)
	M.purge_radiation(INFINITY)
	M.extinguish_mob()
	M.set_fire_stacks(0)
	M.mend(TREAT_ANTITOXIN, 100)
	if(M.body_temperature() > BODYTEMP_NORMAL)
		M.adjust_bodytemperature(-(40 * TEMPERATURE_DAMAGE_COEFFICIENT), min_temp = BODYTEMP_NORMAL)
	else if(M.body_temperature() < 311)
		M.adjust_bodytemperature(40 * TEMPERATURE_DAMAGE_COEFFICIENT, max_temp = BODYTEMP_NORMAL)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/wound_heal = 5
		// Organ repair is adminordrazine's TREAT_RESTORATION tag (body/treatment.dm).
		for(var/obj/item/organ/external/O in H.damaged_limbs())
			dq_reagent_knit_fracture(O)
			dq_reagent_close_wounds(O, wound_heal)
