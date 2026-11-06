/datum/reagent/drugs/ambrosia_extract
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.8, TREAT_ANTITOXIN = 0.3, TREAT_OXYGENATION = 0.2)
	name = REAGENT_AMBROSIAEXTRACT
	id = REAGENT_ID_AMBROSIAEXTRACT
	description = "The extract from the plant family ambrosia, responsible for the more \"recreational\" effects."
	taste_description = "a strong-tasting plant"
	color = "#358f49"
	high_message_list = list("You feel so much more relaxed.",
	"You can't quite focus on anything.",
	"Colors around you seem much more intense.",
	"You could snack on something right now...",
	"You feel lightheaded and giggly.",
	"Everything seems so hilarious.",
	"You really could go for some takeout right now.",
	"You momentarily forget where you are.",
	"You have a mild urge to look over your shoulder.")
	sober_message_list = list("You feel the urge to just sit there and do nothing.",
	"Reality seems like a real pain in the ass to deal with right now.",
	"Things feel really colourless to you all of a sudden.",
	"You feel the urge to lie down and nap.")
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED // bonus
	industrial_use = REFINERYEXPORT_REASON_ILLDRUG

/datum/reagent/drugs/ambrosia_extract/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	var/drug_strength = 3
	if(M.species.chem_strength_tox > 0) //Closer to 0 means they're more resistant to toxins. Higher than 1 means they're weaker to toxins.
		drug_strength *= M.species.chem_strength_tox
	drug_strength *= species_mult(M)

	// Its restorative action is the treatment_tags profile.
	M.status_at_least(STAT_DRUGGED, drug_strength)
	M.status_adjust(STAT_STUNNED, -1)
	if(prob(5) && prob_proc == TRUE)
		M.emote("giggle")
		prob_proc = FALSE
	if(prob(10) && prob_proc == TRUE)
		M.adjust_nutrition(-10)
		prob_proc = FALSE
