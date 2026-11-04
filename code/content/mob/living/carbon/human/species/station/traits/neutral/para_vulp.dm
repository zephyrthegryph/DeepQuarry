/datum/trait/neutral/colorblind/para_vulp
	name = "Colorblindness (Para Vulp)"
	desc = "You have a severe issue with green colors and have difficulty recognizing them from red colors."
	cost = 0
	custom_only = FALSE

	// Traitgenes Made into a gene trait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your eyes feel strange..."

/datum/trait/neutral/colorblind/para_vulp/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.apply_body_effect(/datum/body_effect/trait/colorblind_vulp)

// Traitgenes Made into a gene trait
/datum/trait/neutral/colorblind/para_vulp/unapply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.remove_body_effect_stack(/datum/body_effect/trait/colorblind_vulp)
