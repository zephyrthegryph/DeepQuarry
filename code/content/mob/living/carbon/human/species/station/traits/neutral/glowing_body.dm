/datum/trait/neutral/glowing_body
	name = "Glowing Body"
	desc = "Your body glows about as much as a PDA light! Settable color and toggle in Abilities tab ingame."
	cost = 0
	custom_only = FALSE
	has_preferences = list("glow_toggle" = list(TRAIT_PREF_TYPE_BOOLEAN, "Glowing on spawn", TRAIT_VAREDIT_TARGET_MOB, FALSE), \
							"glow_color" = list(TRAIT_PREF_TYPE_COLOR, "Glow color", TRAIT_VAREDIT_TARGET_MOB))

	// Traitgenes Made into a genetrait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="You feel enlightened."
	primitive_expression_messages=list("shines and sparkles.")

/datum/trait/neutral/glowing_body/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/proc/glow_toggle), src)
	grant(H, granted_verb(/mob/living/proc/glow_color), src)

// Traitgenes Made into a genetrait
/datum/trait/neutral/glowing_body/unapply(datum/species/S,mob/living/carbon/human/H)
	..()
	revoke(H, granted_verb(/mob/living/proc/glow_toggle), src)
	revoke(H, granted_verb(/mob/living/proc/glow_color), src)
