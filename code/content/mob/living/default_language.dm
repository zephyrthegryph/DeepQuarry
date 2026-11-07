/mob/living
	var/datum/language/default_language

/mob/living/proc/apply_default_language(language)
	if (only_species_language && language != GLOB.all_languages[species_language])
		to_chat(src, span_notice("You can only speak your species language, [species_language]."))
		return 0

	if(language == GLOB.all_languages[species_language])
		to_chat(src, span_notice("You will now speak your standard default language, [language], if you do not specify a language when speaking."))
	else if (language)

		if(language && !can_speak(language))
			to_chat(src, span_notice("You are unable to speak that language."))
			return

		to_chat(src, span_notice("You will now speak [language] if you do not specify a language when speaking."))
	else
		to_chat(src, span_notice("You will now speak whatever your standard default language is if you do not specify one when speaking."))
	rel_set(src, nameof(default_language), language)

// C
/mob/living/proc/check_default_language()
	if(default_language)
		to_chat(src, span_notice("You are currently speaking [default_language] by default."))
	else
		to_chat(src, span_notice("Your current default language is your species or mob type default."))

/mob/living/proc/check_default_language_op(datum/act/op/A)
	check_default_language()
