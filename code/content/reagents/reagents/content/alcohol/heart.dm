/datum/reagent/drink/coffee/nukie/mega/heart //Heals you pretty damn well but damages your heart
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.0, TREAT_BURN_CARE = 1.0)
	name = REAGENT_NUKIEMEGAHEART
	id = REAGENT_ID_NUKIEMEGAHEART
	color = "#fc03e7"
	taste_description = "the end is rapidly approaching, yet remains forever far"

/datum/reagent/drink/coffee/nukie/mega/heart/affect_ingest(mob/living/carbon/M, alien, removed)
	// Its trauma and burn repair is the treatment_tags profile.
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/internal/I in H.internal_organ_list())
			if(I.is_robotic() || !(I.organ_tag in list(O_HEART)))
				continue
			if(I.damage < 100 && prob(10))
				H.injure(INJURY_TOXIN, 0.2 * removed, I, src, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	..()
