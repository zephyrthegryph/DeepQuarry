// Everything else

/datum/reagent/drink/milk
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.1)
	name = REAGENT_MILK
	id = REAGENT_ID_MILK
	description = "An opaque white liquid produced by the mammary glands of mammals."
	taste_description = "milk"
	color = "#DFDFDF"

	glass_name = REAGENT_ID_MILK
	glass_desc = "White and nutritious goodness!"

	cup_icon_state = "cup_cream"
	cup_name = REAGENT_ID_MILK
	cup_desc = "White and nutritious goodness!"
	allergen_type = ALLERGEN_DAIRY //Milk is dairy

/datum/reagent/drink/milk/chocolate
	name =  REAGENT_CHOCOLATEMILK
	id = REAGENT_ID_CHOCOLATEMILK
	description = "A delicious mixture of perfectly healthy mix and terrible chocolate."
	taste_description = "chocolate milk"
	color = "#74533b"

	cup_icon_state = "cup_brown"
	cup_name = "chocolate milk"
	cup_desc = "Deliciously fattening!"

	glass_name = "chocolate milk"
	glass_desc = "Deliciously fattening!"
	allergen_type = ALLERGEN_CHOCOLATE

/datum/reagent/drink/milk/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(inert_for(M))
		return
	// Milk's light tissue repair is its treatment_tags profile.
	holder.remove_reagent(REAGENT_ID_CAPSAICIN, 10 * removed)
	if(ishuman(M) && rand(1,10000) == 1)
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/external/O in H.damaged_limbs())
			if(dq_reagent_knit_fracture(O))
				H.custom_pain("You feel the agonizing power of calcium mending your bones!",60)
				H.injure(INJURY_PAIN, 60, O.organ_tag, source = src)
				H.status_adjust(STAT_STUNNED, 1) // Crawling again, weakened to stunned
				break // Only mend one bone, whichever comes first in the list

/datum/reagent/drink/milk/cream
	name = REAGENT_CREAM
	id = REAGENT_ID_CREAM
	description = "The fatty, still liquid part of milk. Why don't you mix this with sum scotch, eh?"
	taste_description = "thick milk"
	color = "#DFD7AF"

	glass_name = REAGENT_ID_CREAM
	glass_desc = "Ewwww..."

	cup_icon_state = "cup_cream"
	cup_name = REAGENT_ID_CREAM
	cup_desc = "Ewwww..."
	allergen_type = ALLERGEN_DAIRY //Cream is dairy

/datum/reagent/drink/milk/soymilk
	name = REAGENT_SOYMILK
	id = REAGENT_ID_SOYMILK
	description = "An opaque white liquid made from soybeans."
	taste_description = "soy milk"
	color = "#DFDFC7"

	glass_name = "soy milk"
	glass_desc = "White and nutritious soy goodness!"

	cup_icon_state = "cup_cream"
	cup_name = REAGENT_ID_MILK
	cup_desc = "White and nutritious goodness!"
	allergen_type = ALLERGEN_BEANS //Would be made from soy beans

/datum/reagent/drink/milk/foam
	name = REAGENT_MILKFOAM
	id = REAGENT_ID_MILKFOAM
	description = "Light and airy foamed milk."
	taste_description = "airy milk"
	color = "#eeebdf"

	glass_name = "foam"
	glass_desc = "Fluffy..."

	cup_icon_state = "cup_cream"
	cup_name = "foam"
	cup_desc = "Fluffy..."
	allergen_type = ALLERGEN_DAIRY //Cream is dairy
