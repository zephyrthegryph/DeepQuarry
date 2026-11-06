/datum/trait/neutral/glowing_eyes
	name = "Glowing Eyes"
	desc = "Your eyes show up above darkness. SPOOKY! And kinda edgey too."
	cost = 0
	custom_only = FALSE
	var_changes = list("has_glowing_eyes" = 1)
	has_preferences = list("has_glowing_eyes" = list(TRAIT_PREF_TYPE_BOOLEAN, "Glowing on spawn", TRAIT_VAREDIT_TARGET_SPECIES))

	// Traitgenes Made into a genetrait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your eyes feel brighter."
	primitive_expression_messages=list("eyes twinkle.")

/datum/trait/neutral/glowing_eyes/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/carbon/human/proc/toggle_eye_glow), src)

// Traitgenes Made into a genetrait
/datum/trait/neutral/glowing_eyes/unapply(datum/species/S,mob/living/carbon/human/H)
	..()
	revoke(H, granted_verb(/mob/living/carbon/human/proc/toggle_eye_glow), src)
