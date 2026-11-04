/datum/trait/neutral/dominate_prey
	name = "Dominate Prey"
	desc = "Connect to and dominate the brain of your prey."
	cost = 0
	custom_only = FALSE

	// Traitgenes made into a genetrait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your mind feels more powerful."

/datum/trait/neutral/dominate_prey/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/proc/dominate_prey), src)

// Traitgenes made into a genetrait
/datum/trait/neutral/dominate_prey/unapply(datum/species/S, mob/living/carbon/human/H, trait_prefs)
	..()
	revoke(H, granted_verb(/mob/living/proc/dominate_prey), src)
