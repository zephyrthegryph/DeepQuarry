//Universal translator
/obj/item/universal_translator
	name = "handheld translator"
	desc = "This handy device appears to translate the languages it hears into onscreen text for a user."
	icon = 'icons/obj/device.dmi'
	icon_state = "translator"
	w_class = ITEMSIZE_NORMAL
	var/mult_icons = 1	//Changes sprite when it translates
	var/visual = 1		//If you need to see to get the message
	var/audio = 0		//If you need to hear to get the message
	var/translation_enabled = 0
	var/datum/language/langset_static
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

TRACKED(/obj/item/universal_translator, translation_enabled)
TRACKED(/obj/item/universal_translator, langset_static)

CAPABILITIES(/obj/item/universal_translator)
	op("enable", in_hand(), label("Enable translator"), when(cond_not(nameof(translation_enabled))),
		needs(carried(), req(PROC_REF(language_supported))),
		asks(/datum/prompt/choice/translator_language, fields = list("timeout" = 0), keeps = 0),
		then(PROC_REF(language_picked)))
	op("disable", in_hand(), label("Disable translator"), when(nameof(translation_enabled)), then(PROC_REF(disabled)))

/// Snapshot the asking actor's languages when the actual native request is prepared.
/datum/prompt/choice/translator_language
	title = "Language Selection"
	question = "Translate to which of your languages?"

/datum/prompt/choice/translator_language/prepare(datum/act/A)
	. = ..()
	if(istype(A, /datum/act/op))
		var/datum/act/op/asking = A
		choices = asking.actor?.languages

/// Before opening a choice there is no answer; the final requirement checks the chosen shared language definition.
/obj/item/universal_translator/proc/language_supported(datum/act/op/A)
	if(!A.answer)
		return null
	var/datum/prompt/choice/picked = A.answer
	var/datum/language/language = picked.value // ALLOW(reads): the closed request stores its accepted answer once before this final requirement runs
	if(!istype(language))
		return span_warning("\The [src] cannot output that language.")
	return (!(language.flags & (NONVERBAL | HIVEMIND)) && language.machine_understands) ? null : span_warning("\The [src] cannot output that language.")

/obj/item/universal_translator/proc/language_picked(datum/act/op/A)
	var/datum/prompt/choice/picked = A.answer
	set_langset_static(picked.value)
	set_translation_enabled(TRUE)
	registry_join(REGISTRY_LISTENING_OBJECTS, src)
	if(mult_icons)
		icon_state = "[initial(icon_state)]1"
	to_chat(A.actor, span_notice("You enable \the [src], translating into [langset().name]."))
	return OP_OK

/obj/item/universal_translator/proc/disabled(datum/act/op/A)
	set_translation_enabled(FALSE)
	registry_leave(REGISTRY_LISTENING_OBJECTS, src)
	set_langset_static(null)
	icon_state = "[initial(icon_state)]"
	to_chat(A.actor, span_notice("You disable \the [src]."))
	return OP_OK

/obj/item/universal_translator/hear_talk(mob/M, list/message_pieces, verb)
	if(!translation_enabled || !istype(M))
		return

	//Show the "I heard something" animation.
	if(mult_icons)
		flick("[initial(icon_state)]2",src)

	//Handheld or pocket only.
	if(!isliving(loc))
		return

	var/mob/living/L = loc
	if(visual && ((L.sdisabilities & BLIND) || L.has_status(STAT_BLINDED)))
		return
	if(audio && ((L.sdisabilities & DEAF) || L.has_status(STAT_DEAFENED)))
		return

	// Using two for loops kinda sucks, but I think it's more efficient
	// to shortcut past string building if we're just going to discard the string
	// anyways.
	if(user_understands(M, L, message_pieces))
		return

	var/new_message = ""

	for(var/datum/multilingual_say_piece/S in message_pieces)
		if(S.speaking.flags & NONVERBAL)
			continue
		if(!S.speaking.machine_understands)
			new_message += stars(S.message) + " "
			continue

		new_message += (S.message + " ")

	if(!L.say_understands(null, langset()))
		new_message = langset().scramble(new_message)

	to_chat(L, span_filter_say(span_italics(span_bold("[src]") + " translates, ") + " \"<span class='[langset().colour]'>[new_message]</span>\""))

/obj/item/universal_translator/proc/user_understands(mob/M, mob/living/L, list/message_pieces)
	for(var/datum/multilingual_say_piece/S in message_pieces)
		if(S.speaking && !L.say_understands(M, S.speaking))
			return FALSE
	return TRUE

//Let's try an ear-worn version
/obj/item/universal_translator/ear
	name = "translator earpiece"
	desc = "This handy device appears to translate the languages it hears into another language for a user."
	icon_state = "earpiece"
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	visual = 0
	audio = 1

//////////////Single language translators


/obj/item/universal_translator/limited
	name = "handheld translator (galcom)"
	desc = "This handy device appears to translate specific languages that it hears into onscreen text for a user."
	icon_state = "translator_small"

TYPE_TABLE_DECLARE(/obj/item/universal_translator/limited, translator_languages, list(LANGUAGE_GALCOM))

/obj/item/universal_translator/limited/hear_talk(mob/M, list/message_pieces, verb)
	if(!translation_enabled || !istype(M))
		return

	//Handheld or pocket only.
	if(!isliving(loc))
		return

	var/mob/living/L = loc
	if(visual && ((L.sdisabilities & BLIND) || L.has_status(STAT_BLINDED)))
		return
	if(audio && ((L.sdisabilities & DEAF) || L.has_status(STAT_DEAFENED)))
		return

	// Using two for loops kinda sucks, but I think it's more efficient
	// to shortcut past string building if we're just going to discard the string
	// anyways.
	if(user_understands(M, L, message_pieces))
		return

	var/new_message = ""
	var/confirm = 0

	for(var/datum/multilingual_say_piece/S in message_pieces)
		if(S.speaking.name in TYPE_TABLE_GET(src, translator_languages))
			confirm = 1
			new_message += (S.message + " ")

	if(!L.say_understands(null, langset()))
		new_message = langset().scramble(new_message)

	//Show the "I heard something" animation, only if it's an appropriate language!
	if(mult_icons && confirm)
		flick("[initial(icon_state)]2",src)

	if(confirm) //Don't show a message at all if there's no recognised language, that'd just be annoying.
		to_chat(L, span_filter_say("<i><b>[src]</b> translates, </i>\"<span class='[langset().colour]'>[new_message]</span>\""))

/obj/item/universal_translator/limited/sol
	name = "handheld translator (solcom)"

TYPE_TABLE(/obj/item/universal_translator/limited/sol, translator_languages, list(LANGUAGE_SOL_COMMON))

/obj/item/universal_translator/limited/terminus
	name = "handheld translator (terminus)"

TYPE_TABLE(/obj/item/universal_translator/limited/terminus, translator_languages, list(LANGUAGE_TERMINUS))

/obj/item/universal_translator/limited/tradeband
	name = "handheld translator (tradeband)"

TYPE_TABLE(/obj/item/universal_translator/limited/tradeband, translator_languages, list(LANGUAGE_TRADEBAND))

/obj/item/universal_translator/limited/gutterband
	name = "handheld translator (gutterband)"

TYPE_TABLE(/obj/item/universal_translator/limited/gutterband, translator_languages, list(LANGUAGE_GUTTER))

/obj/item/universal_translator/limited/skrellian
	name = "handheld translator (skrellian)"

TYPE_TABLE(/obj/item/universal_translator/limited/skrellian, translator_languages, list(LANGUAGE_SKRELLIAN))

/obj/item/universal_translator/limited/unathi
	name = "handheld translator (sinta'unathi)"

TYPE_TABLE(/obj/item/universal_translator/limited/unathi, translator_languages, list(LANGUAGE_UNATHI))

/obj/item/universal_translator/limited/siik
	name = "handheld translator (siik)"

TYPE_TABLE(/obj/item/universal_translator/limited/siik, translator_languages, list(LANGUAGE_SIIK))

/obj/item/universal_translator/limited/schechi
	name = "handheld translator (schechi)"

TYPE_TABLE(/obj/item/universal_translator/limited/schechi, translator_languages, list(LANGUAGE_SCHECHI))

/obj/item/universal_translator/limited/vedaqh
	name = "handheld translator (vedaqh)"

TYPE_TABLE(/obj/item/universal_translator/limited/vedaqh, translator_languages, list(LANGUAGE_ZADDAT))

/obj/item/universal_translator/limited/birdsong
	name = "handheld translator (birdsong)"

TYPE_TABLE(/obj/item/universal_translator/limited/birdsong, translator_languages, list(LANGUAGE_BIRDSONG))

/obj/item/universal_translator/limited/sagaru
	name = "handheld translator (sagaru)"

TYPE_TABLE(/obj/item/universal_translator/limited/sagaru, translator_languages, list(LANGUAGE_SAGARU))

/obj/item/universal_translator/limited/canilunzt
	name = "handheld translator (canilunzt)"

TYPE_TABLE(/obj/item/universal_translator/limited/canilunzt, translator_languages, list(LANGUAGE_CANILUNZT))

/obj/item/universal_translator/limited/ecureuilian
	name = "handheld translator (ecureuilian)"

TYPE_TABLE(/obj/item/universal_translator/limited/ecureuilian, translator_languages, list(LANGUAGE_ECUREUILIAN))

/obj/item/universal_translator/limited/daemon
	name = "handheld translator (daemon)"

TYPE_TABLE(/obj/item/universal_translator/limited/daemon, translator_languages, list(LANGUAGE_DAEMON))

/obj/item/universal_translator/limited/enochian
	name = "handheld translator (enochian)"

TYPE_TABLE(/obj/item/universal_translator/limited/enochian, translator_languages, list(LANGUAGE_ENOCHIAN))

/obj/item/universal_translator/limited/vespinae
	name = "handheld translator (vespinae)"

TYPE_TABLE(/obj/item/universal_translator/limited/vespinae, translator_languages, list(LANGUAGE_VESPINAE))

/obj/item/universal_translator/limited/dragon
	name = "handheld translator (d'rudak'ar)"

TYPE_TABLE(/obj/item/universal_translator/limited/dragon, translator_languages, list(LANGUAGE_DRUDAKAR))

/obj/item/universal_translator/limited/spacer
	name = "handheld translator (spacer)"

TYPE_TABLE(/obj/item/universal_translator/limited/spacer, translator_languages, list(LANGUAGE_SPACER))

/obj/item/universal_translator/limited/tavan
	name = "handheld translator (tavan)"

TYPE_TABLE(/obj/item/universal_translator/limited/tavan, translator_languages, list(LANGUAGE_TAVAN))

/obj/item/universal_translator/limited/echosong
	name = "handheld translator (echo song)"

TYPE_TABLE(/obj/item/universal_translator/limited/echosong, translator_languages, list(LANGUAGE_ECHOSONG))

/obj/item/universal_translator/limited/akhani
	name = "handheld translator (akhani)"

TYPE_TABLE(/obj/item/universal_translator/limited/akhani, translator_languages, list(LANGUAGE_AKHANI))

/obj/item/universal_translator/limited/alai
	name = "handheld translator (alai)"

TYPE_TABLE(/obj/item/universal_translator/limited/alai, translator_languages, list(LANGUAGE_ALAI))

/obj/item/universal_translator/limited/glamour  //Admin spawn only, just here for utility
	name = "handheld translator (glamourspeak)"

TYPE_TABLE(/obj/item/universal_translator/limited/glamour, translator_languages, list(LANGUAGE_LLEILL))

/obj/item/universal_translator/limited/teppi  //Admin spawn only, just here for utility
	name = "handheld translator (teppi)"


TYPE_TABLE(/obj/item/universal_translator/limited/teppi, translator_languages, list(LANGUAGE_TEPPI))

/// A shared definition (registered: never owned or cleared).
/obj/item/universal_translator/proc/langset() as /datum/language
	return langset_static
