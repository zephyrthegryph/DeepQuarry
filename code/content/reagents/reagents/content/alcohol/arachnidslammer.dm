//Arachnid slammer states - Jack

/datum/reagent/ethanol/arachnidslammer
	name = REAGENT_ARACHNIDSLAMMER
	id = REAGENT_ID_ARACHNIDSLAMMER
	description = "An adventurous mix of a cheap, powerful ale with an equally cheap, powerful energy drink and combat drugs. The result should have been undrikable, and yet it sure does put a spring in your step."
	taste_description = "hearty barley ale, almost illegal energy drink, combat stimulants, and the urge to go mine and wrestle a spider"
	color = "#594219"
	strength = 30
	nutriment_factor = 1

	glass_name = "arachnid slammer"
	glass_desc = "A freezing pint of delicious Araching Slammer, it foams constantly with the air crisp around it."
	allergen_type = ALLERGEN_GRAINS //Barley is grain

/datum/reagent/ethanol/arachnidslammer/affect_ingest(mob/living/carbon/M, alien, removed)
	.=..()
	M.reagents.add_reagent(REAGENT_ID_INFUSEDARACHNIDSLAMMER, removed * 5)

/datum/reagent/ethanol/arachnidslammer/affect_blood(mob/living/carbon/M, alien, removed)
	.=..()
	M.reagents.add_reagent(REAGENT_ID_INFUSEDARACHNIDSLAMMER, removed * 5)
