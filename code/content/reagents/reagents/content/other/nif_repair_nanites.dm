/datum/reagent/nif_repair_nanites
	name = REAGENT_NIFREPAIRNANITES
	id = REAGENT_ID_NIFREPAIRNANITES
	description = "A thick grey slurry of NIF repair nanomachines."
	taste_description = "metallic"
	reagent_state = LIQUID
	color = "#333333"
	scannable = SCANNABLE_BENEFICIAL
	affects_robots = TRUE
	wiki_flag = WIKI_SPOILER

	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/nif_repair_nanites/affect_blood(mob/living/carbon/M, alien, removed)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.nif)
			var/obj/item/nif/nif = H.nif //L o c a l
			if(nif.stat == NIF_TEMPFAIL)
				nif.set_stat(NIF_INSTALLING)
			nif.repair(removed)
