/datum/trait/neutral/submit_to_prey
	name = "Submit To Prey"
	desc = "Allow prey's mind to control your own body."
	cost = 0
	custom_only = FALSE

	// Traitgenes made into a genetrait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your mind feels more fluid."

/datum/trait/neutral/submit_to_prey/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/proc/lend_prey_control), src)

// Traitgenes made into a genetrait
/datum/trait/neutral/submit_to_prey/unapply(datum/species/S, mob/living/carbon/human/H, trait_prefs)
	..()
	revoke(H, granted_verb(/mob/living/proc/lend_prey_control), src)
