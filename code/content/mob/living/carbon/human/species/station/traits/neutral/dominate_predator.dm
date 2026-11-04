/datum/trait/neutral/dominate_predator
	name = "Dominate Predator"
	desc = "Allows you to attempt to take control of a predator while inside of their belly."
	cost = 0
	custom_only = FALSE

	// Traitgenes made into a genetrait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your mind feels more powerful."

/datum/trait/neutral/dominate_predator/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/proc/dominate_predator), src)

// Traitgenes made into a genetrait
/datum/trait/neutral/dominate_predator/unapply(datum/species/S, mob/living/carbon/human/H, trait_prefs)
	..()
	revoke(H, granted_verb(/mob/proc/dominate_predator), src)
