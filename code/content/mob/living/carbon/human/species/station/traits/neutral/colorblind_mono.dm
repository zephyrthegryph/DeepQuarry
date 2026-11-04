// Alcohol Traits End Here.

/datum/trait/neutral/colorblind/mono
	name = "Colorblindness (Monochromancy)"
	desc = "You simply can't see colors at all, period. You are 100% colorblind."
	cost = 0
	custom_only = FALSE

	// Traitgenes Made into a gene trait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your eyes feel strange..."

/datum/trait/neutral/colorblind/mono/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.apply_body_effect(/datum/body_effect/trait/colorblind_monochrome)

// Traitgenes Made into a gene trait
/datum/trait/neutral/colorblind/mono/unapply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.remove_body_effect_stack(/datum/body_effect/trait/colorblind_monochrome)
