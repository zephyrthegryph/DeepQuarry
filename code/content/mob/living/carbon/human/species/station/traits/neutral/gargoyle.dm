/datum/trait/neutral/gargoyle
	name = "Gargoyle (Adjustable)"
	desc = "You turn into a statue (or similar) at will, but also whenever you run out of energy. Being a statue replenishes your energy slowly."
	cost = 0
	custom_only = FALSE //slimes, xenochimera, diona, proteans, etc, basically anything but custom doesn't make sense (as much as I wanna play a petrifying slime)
	//Nah makes perfect sense, they could just be gene modded, not to mention we can expand this to have the statue and description of it renameable as well as color adjustable, to support general petrification
	has_preferences = list("identifier" = list(TRAIT_PREF_TYPE_STRING, "Identifier", TRAIT_NO_VAREDIT_TARGET, "statue"),
							"material" = list(TRAIT_PREF_TYPE_STRING, "Material", TRAIT_NO_VAREDIT_TARGET, "stone"),
							"tint" = list(TRAIT_PREF_TYPE_COLOR, "Statue color", TRAIT_NO_VAREDIT_TARGET, "#FFFFFF"),
							"adjective" = list(TRAIT_PREF_TYPE_STRING, "Adjective", TRAIT_NO_VAREDIT_TARGET, "hardens")/*
							"pickupable" = list(TRAIT_PREF_TYPE_BOOLEAN, "Can be picked up", TRAIT_NO_VAREDIT_TARGET, FALSE)*/)
	added_component_path = /datum/trait_state/gargoyle

/datum/trait/neutral/gargoyle/apply(datum/species/S,mob/living/carbon/human/H, list/trait_prefs)
	..()
	var/datum/trait_state/gargoyle/G = H.get_trait_state(added_component_path)
	if(trait_prefs)
		G.tint = trait_prefs["tint"]
		G.material = lowertext(trait_prefs["material"])
		G.identifier = lowertext(trait_prefs["identifier"])
		G.adjective = lowertext(trait_prefs["adjective"])

/datum/trait/neutral/gargoyle/apply_sanitization_to_string(pref, input)
	if (has_preferences[pref][1] != TRAIT_PREF_TYPE_STRING || length(input) <= 0)
		return
	input = sanitizeSafe(input, 25)
	if (length(input) <= 0)
		return default_value_for_pref(pref)
	input = lowertext(input)
	if (pref == "adjective")
		if (copytext_char(input, -1) != "s")
			switch(copytext_char(input, -2))
				if ("ss")
					input += "es"
				if ("sh")
					input += "es"
				if ("ch")
					input += "es"
				else
					switch(copytext_char(input, -1))
						if("s", "x", "z")
							input += "es"
						else
							input += "s"
	return input
