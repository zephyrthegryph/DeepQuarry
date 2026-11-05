/datum/trait/neutral/personal_space
	name = "Personal Space Bubble"
	desc = "You are adept at avoiding unwanted physical contact and dodge it with ease. You will reflexively dodge any attempt to hug, pat, boop, lick, sniff you, shake your hand, or pick you up. These can be toggled independently."
	cost = 0
	custom_only = FALSE
	has_preferences = list("bubble_toggle" = list(TRAIT_PREF_TYPE_BOOLEAN, "Dodge physical contact on spawn", TRAIT_NO_VAREDIT_TARGET, TRUE),
						"pickup_dodge_toggle" = list(TRAIT_PREF_TYPE_BOOLEAN, "Dodge pickup attempts on spawn", TRAIT_NO_VAREDIT_TARGET, TRUE))

/datum/trait/neutral/personal_space/apply(datum/species/S, mob/living/carbon/human/H, list/trait_prefs)
	..()
	if(trait_prefs && trait_prefs["bubble_toggle"])
		living_misc_of(H).set_touch_reaction_flags(STATE_GET(H, living_misc, touch_reaction_flags) | (SPECIES_TRAIT_PERSONAL_BUBBLE))
	if(trait_prefs && trait_prefs["pickup_dodge_toggle"])
		living_misc_of(H).set_touch_reaction_flags(STATE_GET(H, living_misc, touch_reaction_flags) | (SPECIES_TRAIT_PICKUP_DODGE))
	grant(H, granted_verb(/mob/living/proc/toggle_personal_space), src)
	grant(H, granted_verb(/mob/living/proc/toggle_pickup_dodge), src)
