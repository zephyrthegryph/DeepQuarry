/datum/trait/neutral/colorblind/para_taj
	name = "Colorblindness (Para Taj)"
	desc = "You have a minor issue with blue colors and have difficulty recognizing them from red colors."
	cost = 0
	custom_only = FALSE

	// Traitgenes - Made into a gene trait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your eyes feel strange..."

/datum/trait/neutral/colorblind/para_taj/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.apply_body_effect(/datum/body_effect/trait/colorblind_taj)

// Traitgenes Made into a gene trait
/datum/trait/neutral/colorblind/para_taj/unapply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.remove_body_effect_stack(/datum/body_effect/trait/colorblind_taj)
