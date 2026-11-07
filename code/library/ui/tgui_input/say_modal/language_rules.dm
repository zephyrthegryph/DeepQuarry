/// tgui-say's preview parses on the client with no round trip per keystroke, from this data: the rules live here and in parse_languages,
/// the client holds none of its own. Sent when the window opens, since the mob, its languages and its keys can change between messages.
/datum/tgui_say/proc/send_language_rules()
	var/mob/M = client()?.mob
	if(M)
		window.send_message("languageRules", M.say_language_rules())

/// An autohiss map for the preview, or null for a mob with none.
/mob/proc/say_hiss_rules()
	return null

/mob/living/carbon/human/say_hiss_rules()
	var/list/picked = client?.prefs ? GLOB.autohiss_choices[(AUTOHISS_DEFAULT_CHOICE)] : null
	if(!picked || picked["mode"] == AUTOHISS_OFF)
		return null
	var/own = picked["species"]
	var/list/basic = own ? species?.autohiss_basic_map : picked["basic"]
	if(!basic)
		return null
	return list(
		"basic" = basic,
		"extra" = picked["mode"] == AUTOHISS_FULL ? (own ? species.autohiss_extra_map : picked["extra"]) : null,
		"exempt" = (own ? species.autohiss_exempt : picked["exempt"]) || list(),
	)

/mob/proc/say_language_info(datum/language/L)
	return list(
		"verbs" = list(L.speech_verb, L.ask_verb, L.exclaim_verb),
		"whisperVerb" = L.whisper_verb || "",
		"spoken" = can_speak(L) ? TRUE : FALSE,
		"whole" = (L.flags & (HIVEMIND | SIGNLANG | INAUDIBLE)) ? TRUE : FALSE,
		"innate" = (L.flags & INNATE) ? TRUE : FALSE,
		"noHiss" = (L.flags & NO_STUTTER) ? TRUE : FALSE,
	)

/mob/proc/say_language_rules()
	var/list/key_names = list()
	var/list/infos = list()
	for(var/key in GLOB.language_keys | language_keys) // whole prefixes
		var/datum/language/L = language_for_prefix(key)
		if(!L)
			continue
		key_names[key] = L.name
		infos[L.name] = say_language_info(L)

	var/datum/language/gibberish = GLOB.all_languages[LANGUAGE_GIBBERISH]
	var/datum/language/noise = GLOB.all_languages["Noise"]
	infos[gibberish.name] = say_language_info(gibberish)
	infos[noise.name] = say_language_info(noise)

	var/datum/language/preferred = get_default_language()
	if(preferred)
		infos[preferred.name] = say_language_info(preferred)

	// The Ctrl+number shortcuts: what this mob can speak and has a key for, in its language list's order.
	var/list/order = list()
	for(var/datum/language/L as anything in languages)
		if(can_speak(L) && !(L.flags & INNATE) && (L.name in key_names_values(key_names)))
			order += L.name

	var/list/custom_verbs = list("say" = "", "ask" = "", "exclaim" = "", "whisper" = "")
	if(bio)
		custom_verbs = list("say" = bio.custom_say || "", "ask" = bio.custom_ask || "", "exclaim" = bio.custom_exclaim || "", "whisper" = bio.custom_whisper || "")

	var/list/radio_keys = list()
	for(var/radio_key in GLOB.department_radio_keys)
		radio_keys += radio_key

	return list(
		"mode" = MULTILINGUAL_DEFAULT || MULTILINGUAL_DEFAULT,
		"name" = name,
		"defaultLanguage" = preferred?.name || "",
		"gibberish" = gibberish.name,
		"noise" = noise.name,
		"keys" = key_names,
		"languages" = infos,
		"order" = order,
		"markers" = GLOB.speech_toppings,
		"radioKeys" = radio_keys,
		"autopunctuation" = FALSE,
		"customVerbs" = custom_verbs,
		"hiss" = say_hiss_rules(),
	)

/proc/key_names_values(list/key_names)
	. = list()
	for(var/key in key_names)
		. |= key_names[key]
