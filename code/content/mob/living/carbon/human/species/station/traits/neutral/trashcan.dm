/datum/trait/neutral/trashcan
	name = "Trash Can"
	desc = "Allows you to dispose of some garbage on the go instead of having to look for a bin or littering like an animal."
	cost = 0
	custom_only = FALSE
	var_changes = list("trashcan" = 1)

	// Traitgenes made into a genetrait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your stomach feels strange."
	primitive_expression_messages=list("eats something off the ground.")

/datum/trait/neutral/trashcan/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/proc/eat_trash), src)
	grant(H, granted_verb(/mob/living/proc/toggle_trash_catching), src)

// Traitgenes made into a genetrait
/datum/trait/neutral/trashcan/unapply(datum/species/S, mob/living/carbon/human/H, trait_prefs)
	..()
	revoke(H, granted_verb(/mob/living/proc/eat_trash), src)
	revoke(H, granted_verb(/mob/living/proc/toggle_trash_catching), src)
