/datum/reagent/ethanol/pwine
	name = REAGENT_PWINE
	id = REAGENT_ID_PWINE
	description = "Is this even wine? Toxic! Hallucinogenic! Probably consumed in boatloads by your superiors!"
	color = "#000000"
	strength = 10
	druggy = 50
	halluci = 10

	glass_name = "???"
	glass_desc = "A black ichor with an oily purple sheer on top. Are you sure you should drink this?"
	allergen_type = ALLERGEN_FRUIT //Made from berries which are fruit

/datum/reagent/ethanol/pwine/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	if(!(HAS_SYNTHETIC_BIOLOGY(M)))
		if(dose > 30)
			M.injure(INJURY_TOXIN, 2 * removed, source = src)
		if(dose > 60 && ishuman(M) && prob(5))
			var/mob/living/carbon/human/H = M
			var/obj/item/organ/internal/heart/L = H.organ_in(O_HEART)
			if (L && istype(L))
				if(dose < 120)
					H.injure(INJURY_TOXIN, 10 * removed, L, src, flags = INJURE_IGNORE_RESISTANCE)
				else
					H.injure(INJURY_TOXIN, 100, L, src, flags = INJURE_IGNORE_RESISTANCE)
