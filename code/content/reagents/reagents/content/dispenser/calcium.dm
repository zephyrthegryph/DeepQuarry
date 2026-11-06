/datum/reagent/calcium
	name = REAGENT_CALCIUM
	id = REAGENT_ID_CALCIUM
	description = "A chemical element, the building block of bones."
	taste_description = "metallic chalk" // Apparently, calcium tastes like calcium.
	taste_mult = 1.3
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#e9e6e4"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/calcium/affect_ingest(mob/living/carbon/M, alien, removed)
	if(ishuman(M) && rand(1,10000) == 1)
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/external/O in H.damaged_limbs())
			if(dq_reagent_knit_fracture(O))
				H.custom_pain("You feel the agonizing power of calcium mending your bones!",60)
				H.status_adjust(STAT_WEAKENED, 1)
				break // Only mend one bone, whichever comes first in the list
