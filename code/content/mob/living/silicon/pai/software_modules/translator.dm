/datum/pai_software/translator
	name = "Universal Translator"
	ram_cost = 35
	id = "translator"
	/// Languages the translator offers. A `/datum/pai_software/translator`
	/// instance is a single GLOBAL_LIST_EMPTY(pai_software_by_key) singleton
	/// shared by every pAI, so this must stay a read-only candidate list --
	/// per-pai state (what was actually granted) lives on the pai mob itself,
	/// in `translator_added_languages`.
	var/static/list/candidate_languages = list(
		LANGUAGE_UNATHI, LANGUAGE_SIIK, LANGUAGE_AKHANI, LANGUAGE_SKRELLIAN,
		LANGUAGE_ZADDAT, LANGUAGE_SCHECHI, LANGUAGE_DRUDAKAR, LANGUAGE_SLAVIC,
		LANGUAGE_BIRDSONG, LANGUAGE_SAGARU, LANGUAGE_CANILUNZT, LANGUAGE_ECUREUILIAN,
		LANGUAGE_DAEMON, LANGUAGE_ENOCHIAN, LANGUAGE_VESPINAE, LANGUAGE_SPACER,
		LANGUAGE_TAVAN, LANGUAGE_ECHOSONG, LANGUAGE_ROOTLOCAL, LANGUAGE_VOX,
		LANGUAGE_MINBUS, LANGUAGE_ALAI, LANGUAGE_PROMETHEAN, LANGUAGE_GIBBERISH,
		LANGUAGE_MOUSE, LANGUAGE_ANIMAL, LANGUAGE_TEPPI
	)

/datum/pai_software/translator/toggle(mob/living/silicon/pai/user)
	// 	Sol Common, Tradeband, Terminus and Gutter are added with New() and are therefore the current default, always active languages
	user.translator_on = !user.translator_on
	if(user.translator_on)
		// Only track (and later remove) languages the pai didn't already
		// know -- a pai that natively knows one of these must keep it after
		// toggling the translator off.
		for(var/language in candidate_languages)
			if(user.add_language(language))
				LAZYADD(user.translator_added_languages, language)
	else
		for(var/language in user.translator_added_languages)
			user.remove_language(language)
		user.translator_added_languages = null

/datum/pai_software/translator/is_active(mob/living/silicon/pai/user)
	return user.translator_on
