



/mob/proc/handle_autohiss(message, datum/language/L)
	return message // no autohiss at this level

/mob/living/carbon/human/handle_autohiss(message, datum/language/L)
	if(!client?.prefs)
		return message
	return autohiss_by_choice(message, L, client.prefs.read_preference(/datum/preference/text/human/autohiss))

/// `message` as this body says it under an autohiss choice: Off changes nothing, Default is whatever the species (with its traits) does, a named type applies on any species.
/mob/living/carbon/human/proc/autohiss_by_choice(message, datum/language/L, choice)
	var/list/picked = GLOB.autohiss_choices[choice]
	if(!picked || picked["mode"] == AUTOHISS_OFF)
		return message
	if(picked["species"])
		return species.handle_autohiss(message, L, picked["mode"])
	return apply_autohiss(message, L, picked["mode"], picked["basic"], picked["extra"], picked["exempt"])

/client/verb/toggle_autohiss()
	set name = "Toggle Auto-Hiss"
	set desc = "Choose how your speech is automatically changed: your species' way, off, or any other hiss."
	set category = VERB_CAT_OOC_GAME_SETTINGS

	mob?.ask_autohiss_choice()

/// Asks which autohiss to use; the answer is the character's saved choice.
/mob/proc/ask_autohiss_choice()
	open_request(src, /datum/prompt/choice, PROC_REF(autohiss_choice_answered), answerer = src, title = "Auto-Hiss", question = "How should your speech be changed? It is now: [read_preference(/datum/preference/text/human/autohiss)].", choices = assoc_to_keys(GLOB.autohiss_choices), timeout = 0)

/mob/proc/autohiss_choice_answered(datum/act/request/A)
	if(!A.answer || !client || !GLOB.autohiss_choices[A.answer.value])
		return
	write_preference_directly(/datum/preference/text/human/autohiss, A.answer.value)
	to_chat(src, "Auto-hiss is now [A.answer.value]: [GLOB.autohiss_choices[A.answer.value]["words"]]")

/// "s becomes ss, sss or ssss; x becomes ks": the map, in words.
/proc/autohiss_map_words(list/map)
	var/list/rules = list()
	for(var/from in map)
		rules += "[from] becomes [english_list(map[from], and_text = " or ", final_comma_text = "")]"
	return jointext(rules, "; ")

/// What a hiss does at a level, generated from its maps.
/proc/autohiss_type_words(list/basic, list/extra, list/exempt, mode)
	. = autohiss_map_words(basic)
	if(mode == AUTOHISS_FULL && length(extra))
		. += "; " + autohiss_map_words(extra)
	if(length(exempt))
		. += ". Not in " + english_list(exempt, and_text = " or ", final_comma_text = "")

/// One named hiss at one level; its maps are the trait's, and each species hiss has the same ones, so nothing is repeated.
/proc/autohiss_choice_entry(list/changes, mode)
	return list(
		"mode" = mode,
		"basic" = changes["autohiss_basic_map"],
		"extra" = changes["autohiss_extra_map"],
		"exempt" = changes["autohiss_exempt"],
		"words" = autohiss_type_words(changes["autohiss_basic_map"], changes["autohiss_extra_map"], changes["autohiss_exempt"], mode),
	)

/// The hisses anyone may choose, each read from the trait that carries it.
GLOBAL_LIST_INIT(autohiss_trait_types, list(
	"Unathi hiss" = /datum/trait/neutral/autohiss_unathi,
	"Tajaran r-roll" = /datum/trait/neutral/autohiss_tajaran,
	"Zaddat buzz" = /datum/trait/neutral/autohiss_zaddat,
	"Vasilissan buzz" = /datum/trait/neutral/autohiss_vassilian,
	"Yingish lisp" = /datum/trait/neutral/autohiss_yingish,
))

/proc/build_autohiss_choices()
	. = list(
		"Default (Basic)" = list("mode" = AUTOHISS_BASIC, "species" = TRUE, "words" = "Whatever your species does, basic level. Nothing, if it has no hiss."),
		AUTOHISS_DEFAULT_CHOICE = list("mode" = AUTOHISS_FULL, "species" = TRUE, "words" = "Whatever your species does, full level. Nothing, if it has no hiss."),
		"Off" = list("mode" = AUTOHISS_OFF, "words" = "Your speech is never changed."),
	)
	for(var/name in GLOB.autohiss_trait_types)
		var/path = GLOB.autohiss_trait_types[name]
		var/datum/trait/T = new path
		var/list/changes = T.var_changes
		if(length(changes["autohiss_extra_map"])) // a level appears only when a hiss has both
			.["[name] (Basic)"] = autohiss_choice_entry(changes, AUTOHISS_BASIC)
			.["[name] (Full)"] = autohiss_choice_entry(changes, AUTOHISS_FULL)
		else
			.[name] = autohiss_choice_entry(changes, AUTOHISS_BASIC)

/// Choice text -> list(mode, then species = TRUE for the species' own, or its maps; words = what it does).
GLOBAL_LIST_INIT(autohiss_choices, build_autohiss_choices())

/// Choice text -> what it does, for the option tooltips.
/proc/autohiss_choice_tooltips()
	. = list()
	for(var/choice in GLOB.autohiss_choices)
		.[choice] = GLOB.autohiss_choices[choice]["words"]

/datum/species
	var/list/autohiss_basic_map = null
	var/list/autohiss_extra_map = null
	var/list/autohiss_exempt = null

/datum/species/unathi
	autohiss_basic_map = list(
			"s" = list("ss", "sss", "ssss")
		)
	autohiss_extra_map = list(
			"x" = list("ks", "kss", "ksss")
		)
	autohiss_exempt = list(LANGUAGE_UNATHI)

/datum/species/tajaran
	autohiss_basic_map = list(
			"r" = list("rr", "rrr", "rrrr")
		)
	autohiss_exempt = list(LANGUAGE_SIIK,LANGUAGE_AKHANI,LANGUAGE_ALAI)

/datum/species/zaddat
	autohiss_basic_map = list(
			"f" = list("v","vh"),
			"ph" = list("v", "vh")
		)
	autohiss_extra_map = list(
			"s" = list("z", "zz", "zzz"),
			"ce" = list("z", "zz"),
			"ci" = list("z", "zz"),
			"v" = list("vv", "vvv")
		)
	autohiss_exempt = list(LANGUAGE_ZADDAT,LANGUAGE_VESPINAE)

/datum/species/zaddat
	autohiss_basic_map = list(
			"f" = list("v","vh"),
			"ph" = list("v", "vh")
		)
	autohiss_extra_map = list(
			"s" = list("z", "zz", "zzz"),
			"ce" = list("z", "zz"),
			"ci" = list("z", "zz"),
			"v" = list("vv", "vvv")
		)
	autohiss_exempt = list(LANGUAGE_ZADDAT)

//Yawn Wider Edit.
/datum/species/spider
	autohiss_basic_map = list(
			"s" = list("sz", "z", "zz"),
			"f" = list("zk")
		)
	autohiss_extra_map = list(
			"th" = list("zk", "szk"),
			"r" = list("rk")
		)
//over.

/datum/species/proc/handle_autohiss(message, datum/language/lang, mode)
	return apply_autohiss(message, lang, mode, autohiss_basic_map, autohiss_extra_map, autohiss_exempt)

/// The replacements of a hiss on `message`, unless the language is exempt from it or no spoken language at all.
/proc/apply_autohiss(message, datum/language/lang, mode, list/basic, list/extra, list/exempt)
	if(!basic)
		return message
	if(lang && (lang.flags & NO_STUTTER))		// Currently prevents EAL, Sign language, and emotes from autohissing
		return message
	if(lang && exempt && (lang.name in exempt))
		return message

	var/map = basic.Copy()
	if(mode == AUTOHISS_FULL && extra)
		map |= extra

	. = list()

	while(length(message))
		var/min_index = 10000 // if the message is longer than this, the autohiss is the least of your problems
		var/min_char = null
		for(var/char in map)
			var/i = findtext(message, char)
			if(!i) // no more of this character anywhere in the string, don't even bother searching next time
				map -= char
			else if(i < min_index)
				min_index = i
				min_char = char
		if(!min_char) // we didn't find any of the mapping characters
			. += message
			break
		. += copytext(message, 1, min_index)
		var/after = min_index + length(min_char) // a key may be several letters ("ph", "thi"): all of them are replaced
		if(copytext(message, min_index, min_index + 1) == uppertext(copytext(min_char, 1, 2)))
			switch(text2ascii(message, after))
				if(65 to 90) // A-Z, uppercase; uppercase R/S followed by another uppercase letter, uppercase the entire replacement string
					. += uppertext(pick(map[min_char]))
				else
					. += capitalize(pick(map[min_char]))
		else
			. += pick(map[min_char])
		message = copytext(message, after)

	return jointext(., null)

