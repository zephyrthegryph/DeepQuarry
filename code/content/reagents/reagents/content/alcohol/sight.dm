/datum/reagent/drink/coffee/nukie/mega/sight
	factors = alist(STAT_DARKSIGHT = 1)
	name = REAGENT_NUKIEMEGASIGHT
	id = REAGENT_ID_NUKIEMEGASIGHT
	color = "#f4fc03"
	taste_description = "seeing beyond the margins of this world"

/datum/reagent/drink/coffee/nukie/mega/sight/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(prob(1))
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
			if(istype(E))
				if(E.is_robotic())
					return
				if(E.damage < 100)
					H.injure(INJURY_BLUNT, 1 * removed, E, src, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
