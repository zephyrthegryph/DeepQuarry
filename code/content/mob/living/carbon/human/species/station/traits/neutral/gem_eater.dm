/datum/trait/neutral/gem_eater
	name = "Expensive Taste"
	desc = "You only gain nutrition from raw ore and refined minerals. There's nothing that sates the appetite better than precious gems, exotic or rare minerals and you have damn fine taste. Anything else is beneath you."
	cost = 0
	custom_only = FALSE
	var_changes = list("organic_food_coeff" = 0, "eat_minerals" = 1)

	// Traitgenes made into a genetrait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your stomach feels strange."
	primitive_expression_messages=list("picks up and eats something shiny off the ground.")

/datum/trait/neutral/gem_eater/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/proc/eat_minerals), src)

// Traitgenes made into a genetrait
/datum/trait/neutral/gem_eater/unapply(datum/species/S, mob/living/carbon/human/H, trait_prefs)
	..()
	revoke(H, granted_verb(/mob/living/proc/eat_minerals), src)
