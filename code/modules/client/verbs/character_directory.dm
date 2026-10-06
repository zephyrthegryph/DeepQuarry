GLOBAL_DATUM(character_directory, /datum/character_directory)

/client/verb/show_character_directory()
	set name = "Character Directory"
	set category = VERB_CAT_OOC_GAME
	set desc = "Shows a listing of all active characters, along with their associated OOC notes, flavor text, and more."

	// This is primarily to stop malicious users from trying to lag the server by spamming this verb
	if(!usr.checkMoveCooldown())
		to_chat(usr, span_warning("Don't spam character directory refresh."))
		return
	usr.setMoveCooldown(10)

	if(!GLOB.character_directory)
		GLOB.character_directory = new
	GLOB.character_directory.tgui_interact(mob)


// This is a global singleton. Keep in mind that all operations should occur on usr, not src.
/datum/character_directory

CAPABILITIES(/datum/character_directory)
	interface("CharacterDirectory", title = "Character Directory", state = nameof(GLOB.tgui_always_state))
	op("refresh", ui_act("refresh"), then(PROC_REF(ui_act_refresh)))
	op("setTag", ui_act("setTag", arg("overwrite_prefs", bool())), then(PROC_REF(ui_act_directory_setting)))
	op("setErpTag", ui_act("setErpTag", arg("overwrite_prefs", bool())), then(PROC_REF(ui_act_directory_setting)))
	op("setVisible", ui_act("setVisible", arg("overwrite_prefs", bool())), then(PROC_REF(ui_act_directory_setting)))
	op("editAd", ui_act("editAd", arg("overwrite_prefs", bool())), then(PROC_REF(ui_act_directory_setting)))
	op("setGenderTag", ui_act("setGenderTag", arg("overwrite_prefs", bool())), then(PROC_REF(ui_act_directory_setting)))
	op("setSexualityTag", ui_act("setSexualityTag", arg("overwrite_prefs", bool())), then(PROC_REF(ui_act_directory_setting)))
	op("setEventTag", ui_act("setEventTag", arg("overwrite_prefs", bool())), then(PROC_REF(ui_act_directory_setting)))

/// /datum/character_directory's window data.
/datum/character_directory/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()

	if (user?.mind)
		data["personalVisibility"] = user.mind.show_in_directory
		data["personalTag"] = user.mind.directory_tag || "Unset"
		data["personalErpTag"] = user.mind.directory_erptag || "Unset"
		data["personalEventTag"] = GLOB.vantag_choices_list[user.mind.vantag_preference]
		data["personalGenderTag"] = user.mind.directory_gendertag || "Unset"
		data["personalSexualityTag"] = user.mind.directory_sexualitytag || "Unset"
	else if (user?.client?.prefs)
		// directory_* prefs migrated from bare vars to /datum/preference
		data["personalVisibility"] = user.client.prefs.read_preference(/datum/preference/toggle/human/show_in_directory)
		data["personalTag"] = user.client.prefs.read_preference(/datum/preference/choiced/human/directory_tag) || "Unset"
		data["personalErpTag"] = user.client.prefs.read_preference(/datum/preference/choiced/human/directory_erptag) || "Unset"
		data["personalEventTag"] = GLOB.vantag_choices_list[user.client.prefs.read_preference(/datum/preference/choiced/human/vantag_preference)]
		data["personalGenderTag"] = user.client.prefs.read_preference(/datum/preference/choiced/human/directory_gendertag) || "Unset"
		data["personalSexualityTag"] = user.client.prefs.read_preference(/datum/preference/choiced/human/directory_sexualitytag) || "Unset"

	return data

GLOBAL_LIST_EMPTY(chardirectory_photos)
/mob/proc/set_chardirectory_photo(base64)
	LAZYSET(GLOB.chardirectory_photos, REF(src), base64)

/mob/proc/get_chardirectory_photo()
	if(LAZYACCESS(GLOB.chardirectory_photos, REF(src)))
		return LAZYACCESS(GLOB.chardirectory_photos, REF(src))

	var/icon/F = getFlatIcon(src, defdir = SOUTH, no_anim = TRUE)
	var/new_base64 = "'data:image/png;base64,[icon2base64(F)]'"
	set_chardirectory_photo(new_base64)
	return new_base64

/datum/character_directory/tgui_static_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	var/list/directory_mobs = list()
	for(var/client/C in GLOB.clients)
		// Allow opt-out.
		if(C?.mob?.mind ? !C.mob.mind.show_in_directory : !C?.prefs?.read_preference(/datum/preference/toggle/human/show_in_directory)) // show_in_directory migrated
			continue

		// These are the three vars we're trying to find
		// The approach differs based on the mob the client is controlling
		var/name = null
		var/species = null
		var/ooc_notes = null
		var/ooc_notes_favs = null
		var/ooc_notes_likes = null
		var/ooc_notes_maybes = null
		var/ooc_notes_dislikes = null
		var/ooc_notes_style = null
		var/gendertag = null
		var/sexualitytag = null
		var/eventtag = GLOB.vantag_choices_list[VANTAG_NONE]
		var/flavor_text = null
		var/custom_link = null
		var/tag
		var/erptag
		var/character_ad
		var/photo = C.mob?.get_chardirectory_photo()
		if (C.mob?.mind) //could use ternary for all three but this is more efficient
			tag = C.mob.mind.directory_tag || "Unset"
			erptag = C.mob.mind.directory_erptag || "Unset"
			character_ad = C.mob.mind.directory_ad
			gendertag = C.mob.mind.directory_gendertag || "Unset"
			sexualitytag = C.mob.mind.directory_sexualitytag || "Unset"
			eventtag = GLOB.vantag_choices_list[C.mob.mind.vantag_preference]
		else
			// directory_* prefs migrated to /datum/preference
			tag = C.prefs.read_preference(/datum/preference/choiced/human/directory_tag) || "Unset"
			erptag = C.prefs.read_preference(/datum/preference/choiced/human/directory_erptag) || "Unset"
			character_ad = C.prefs.read_preference(/datum/preference/text/human/directory_ad)
			gendertag = C.prefs.read_preference(/datum/preference/choiced/human/directory_gendertag) || "Unset"
			sexualitytag = C.prefs.read_preference(/datum/preference/choiced/human/directory_sexualitytag) || "Unset"
			eventtag = GLOB.vantag_choices_list[C.prefs.read_preference(/datum/preference/choiced/human/vantag_preference)]

		if(ishuman(C.mob))
			var/mob/living/carbon/human/H = C.mob
			var/strangername = H.real_name
			if(GLOB.data_core && GLOB.data_core.general)
				if(!find_general_record("name", H.real_name))
					if(!find_record("name", H.real_name, GLOB.data_core.hidden_general))
						strangername = "unknown"
			name = strangername
			species = "[H.custom_species ? H.custom_species : H.species.name]"
			ooc_notes = H.identity().ooc_notes
			if(H.identity().ooc_notes_style && (H.identity().ooc_notes_favs || H.identity().ooc_notes_likes || H.identity().ooc_notes_maybes || H.identity().ooc_notes_dislikes))
				ooc_notes = H.identity().ooc_notes + "\n\n"
				ooc_notes_favs = H.identity().ooc_notes_favs
				ooc_notes_likes = H.identity().ooc_notes_likes
				ooc_notes_maybes = H.identity().ooc_notes_maybes
				ooc_notes_dislikes = H.identity().ooc_notes_dislikes
				ooc_notes_style = H.identity().ooc_notes_style
			else
				if(H.identity().ooc_notes_favs)
					ooc_notes += "\n\nFAVOURITES\n\n[H.identity().ooc_notes_favs]"
				if(H.identity().ooc_notes_likes)
					ooc_notes += "\n\nLIKES\n\n[H.identity().ooc_notes_likes]"
				if(H.identity().ooc_notes_maybes)
					ooc_notes += "\n\nMAYBES\n\n[H.identity().ooc_notes_maybes]"
				if(H.identity().ooc_notes_dislikes)
					ooc_notes += "\n\nDISLIKES\n\n[H.identity().ooc_notes_dislikes]"
			if(LAZYLEN(H.flavor_texts))
				flavor_text = H.flavor_texts["general"]
			if(H.custom_link)
				custom_link = H.custom_link

		if(isAI(C.mob))
			var/mob/living/silicon/ai/A = C.mob
			name = A.name
			species = "Artificial Intelligence"
			ooc_notes = A.identity().ooc_notes
			if(A.identity().ooc_notes_style && (A.identity().ooc_notes_favs || A.identity().ooc_notes_likes || A.identity().ooc_notes_maybes || A.identity().ooc_notes_dislikes))
				ooc_notes = A.identity().ooc_notes + "\n\n"
				ooc_notes_favs = A.identity().ooc_notes_favs
				ooc_notes_likes = A.identity().ooc_notes_likes
				ooc_notes_maybes = A.identity().ooc_notes_maybes
				ooc_notes_dislikes = A.identity().ooc_notes_dislikes
				ooc_notes_style = A.identity().ooc_notes_style
			else
				if(A.identity().ooc_notes_favs)
					ooc_notes += "\n\nFAVOURITES\n\n[A.identity().ooc_notes_favs]"
				if(A.identity().ooc_notes_likes)
					ooc_notes += "\n\nLIKES\n\n[A.identity().ooc_notes_likes]"
				if(A.identity().ooc_notes_maybes)
					ooc_notes += "\n\nMAYBES\n\n[A.identity().ooc_notes_maybes]"
				if(A.identity().ooc_notes_dislikes)
					ooc_notes += "\n\nDISLIKES\n\n[A.identity().ooc_notes_dislikes]"

			flavor_text = null // No flavor text for AIs :c

		if(isrobot(C.mob))
			var/mob/living/silicon/robot/R = C.mob
			if(R.scrambledcodes || (R.module && R.module.hide_on_manifest))
				continue
			name = R.name
			species = "[R.modtype] [R.braintype]"
			ooc_notes = R.identity().ooc_notes
			if(R.identity().ooc_notes_style && (R.identity().ooc_notes_favs || R.identity().ooc_notes_likes || R.identity().ooc_notes_maybes || R.identity().ooc_notes_dislikes))
				ooc_notes = R.identity().ooc_notes + "\n\n"
				ooc_notes_favs = R.identity().ooc_notes_favs
				ooc_notes_likes = R.identity().ooc_notes_likes
				ooc_notes_maybes = R.identity().ooc_notes_maybes
				ooc_notes_dislikes = R.identity().ooc_notes_dislikes
				ooc_notes_style = R.identity().ooc_notes_style
			else
				if(R.identity().ooc_notes_favs)
					ooc_notes += "\n\nFAVOURITES\n\n[R.identity().ooc_notes_favs]"
				if(R.identity().ooc_notes_likes)
					ooc_notes += "\n\nLIKES\n\n[R.identity().ooc_notes_likes]"
				if(R.identity().ooc_notes_maybes)
					ooc_notes += "\n\nMAYBES\n\n[R.identity().ooc_notes_maybes]"
				if(R.identity().ooc_notes_dislikes)
					ooc_notes += "\n\nDISLIKES\n\n[R.identity().ooc_notes_dislikes]"

			flavor_text = R.flavor_text

		if(ispAI(C.mob))
			var/mob/living/silicon/pai/P = C.mob
			name = P.name
			species = "pAI"
			ooc_notes = P.identity().ooc_notes
			if(P.identity().ooc_notes_style && (P.identity().ooc_notes_favs || P.identity().ooc_notes_likes || P.identity().ooc_notes_maybes || P.identity().ooc_notes_dislikes))
				ooc_notes = P.identity().ooc_notes + "\n\n"
				ooc_notes_favs = P.identity().ooc_notes_favs
				ooc_notes_likes = P.identity().ooc_notes_likes
				ooc_notes_maybes = P.identity().ooc_notes_maybes
				ooc_notes_dislikes = P.identity().ooc_notes_dislikes
				ooc_notes_style = P.identity().ooc_notes_style
			else
				if(P.identity().ooc_notes_favs)
					ooc_notes += "\n\nFAVOURITES\n\n[P.identity().ooc_notes_favs]"
				if(P.identity().ooc_notes_likes)
					ooc_notes += "\n\nLIKES\n\n[P.identity().ooc_notes_likes]"
				if(P.identity().ooc_notes_maybes)
					ooc_notes += "\n\nMAYBES\n\n[P.identity().ooc_notes_maybes]"
				if(P.identity().ooc_notes_dislikes)
					ooc_notes += "\n\nDISLIKES\n\n[P.identity().ooc_notes_dislikes]"
			flavor_text = P.flavor_text

		if(isanimal(C.mob))
			var/mob/living/simple_mob/S = C.mob
			name = S.name
			species = S.character_directory_species()
			ooc_notes = S.identity().ooc_notes
			if(S.identity().ooc_notes_style && (S.identity().ooc_notes_favs || S.identity().ooc_notes_likes || S.identity().ooc_notes_maybes || S.identity().ooc_notes_dislikes))
				ooc_notes = S.identity().ooc_notes + "\n\n"
				ooc_notes_favs = S.identity().ooc_notes_favs
				ooc_notes_likes = S.identity().ooc_notes_likes
				ooc_notes_maybes = S.identity().ooc_notes_maybes
				ooc_notes_dislikes = S.identity().ooc_notes_dislikes
				ooc_notes_style = S.identity().ooc_notes_style
			else
				if(S.identity().ooc_notes_favs)
					ooc_notes += "\n\nFAVOURITES\n\n[S.identity().ooc_notes_favs]"
				if(S.identity().ooc_notes_likes)
					ooc_notes += "\n\nLIKES\n\n[S.identity().ooc_notes_likes]"
				if(S.identity().ooc_notes_maybes)
					ooc_notes += "\n\nMAYBES\n\n[S.identity().ooc_notes_maybes]"
				if(S.identity().ooc_notes_dislikes)
					ooc_notes += "\n\nDISLIKES\n\n[S.identity().ooc_notes_dislikes]"
			flavor_text = S.desc

		// It's okay if we fail to find OOC notes and flavor text
		// But if we can't find the name, they must be using a non-compatible mob type currently.
		if(!name)
			continue

		directory_mobs.Add(list(list(
			"name" = name,
			"species" = species,
			"ooc_notes_favs" = ooc_notes_favs,
			"ooc_notes_likes" = ooc_notes_likes,
			"ooc_notes_maybes" = ooc_notes_maybes,
			"ooc_notes_dislikes" = ooc_notes_dislikes,
			"ooc_notes_style" = ooc_notes_style,
			"gendertag" = gendertag,
			"sexualitytag" = sexualitytag,
			"eventtag" = eventtag,
			"ooc_notes" = ooc_notes,
			"tag" = tag,
			"erptag" = erptag,
			"character_ad" = character_ad,
			"flavor_text" = flavor_text,
			"custom_link" = custom_link,
			"photo" = photo,
		)))

	data["directory"] = directory_mobs

	return data


/datum/character_directory/proc/ui_act_refresh(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	// This is primarily to stop malicious users from trying to lag the server by spamming this verb
	if(!user.checkMoveCooldown())
		to_chat(user, span_warning("Don't spam character directory refresh."))
		return
	user.setMoveCooldown(10)
	update_tgui_static_data(user, ui)
	return TRUE

/datum/character_directory/proc/ui_act_directory_setting(datum/act/op/A, overwrite_prefs)
	var/mob/user = A.actor
	var/action = A.window_action()
	return check_for_mind_or_prefs(user, action, overwrite_prefs)

/datum/character_directory/proc/check_for_mind_or_prefs(mob/user, action, overwrite_prefs, selected_value = null)
	if (!user.client)
		return
	var/can_set_prefs = overwrite_prefs && !!user.client.prefs
	var/can_set_mind = !!user.mind
	if (!can_set_prefs && !can_set_mind)
		if (!overwrite_prefs && !!user.client.prefs)
			to_chat(user, span_warning("You cannot change these settings if you don't have a mind to save them to. Enable overwriting prefs and switch to a slot you're fine with overwriting."))
		return
	switch(action)
		if ("setTag")
			if(isnull(selected_value))
				open_directory_choice(user, action, overwrite_prefs, "Pick a new Vore tag for the character directory", "Character Tag", GLOB.char_directory_tags, null)
				return
			var/list/new_tag = selected_value
			if(isnull(new_tag))
				return
			if(!new_tag)
				return
			return set_for_mind_or_prefs(user, action, new_tag, can_set_prefs, can_set_mind)
		if ("setErpTag")
			if(isnull(selected_value))
				open_directory_choice(user, action, overwrite_prefs, "Pick a new ERP tag for the character directory", "Character ERP Tag", GLOB.char_directory_erptags, null)
				return
			var/list/new_erptag = selected_value
			if(isnull(new_erptag))
				return
			if(!new_erptag)
				return
			return set_for_mind_or_prefs(user, action, new_erptag, can_set_prefs, can_set_mind)
		if ("setVisible")
			var/visible = TRUE
			if (can_set_mind)
				visible = user.mind.show_in_directory
			else if (can_set_prefs)
				visible = user.client.prefs.read_preference(/datum/preference/toggle/human/show_in_directory) // show_in_directory migrated
			to_chat(user, span_notice("You are now [!visible ? "shown" : "not shown"] in the directory."))
			return set_for_mind_or_prefs(user, action, !visible, can_set_prefs, can_set_mind)
		if ("editAd")
			var/current_ad = (can_set_mind ? user.mind.directory_ad : null) || (can_set_prefs ? user.client.prefs.read_preference(/datum/preference/text/human/directory_ad) : null) // directory_ad migrated
			if(isnull(selected_value))
				open_request(src, /datum/prompt/text/directory_ad, PROC_REF(directory_ad_entered), answerer = user, default = current_ad, directory_action = action, overwrite_prefs = overwrite_prefs)
				return
			var/new_ad = selected_value
			if(isnull(new_ad))
				return
			if(isnull(new_ad))
				return
			return set_for_mind_or_prefs(user, action, new_ad, can_set_prefs, can_set_mind)
		if("setGenderTag")
			if(isnull(selected_value))
				open_directory_choice(user, action, overwrite_prefs, "Pick a new Gender tag for the character directory. This is YOUR gender, not what you prefer.", "Character Gender Tag", GLOB.char_directory_gendertags, null)
				return
			var/list/new_gendertag = selected_value
			if(isnull(new_gendertag))
				return
			if(!new_gendertag)
				return
			return set_for_mind_or_prefs(user, action, new_gendertag, can_set_prefs, can_set_mind)
		if("setSexualityTag")
			if(isnull(selected_value))
				open_directory_choice(user, action, overwrite_prefs, "Pick a new Sexuality/Orientation tag for the character directory", "Character Sexuality/Orientation Tag", GLOB.char_directory_sexualitytags, null)
				return
			var/list/new_sexualitytag = selected_value
			if(isnull(new_sexualitytag))
				return
			if(!new_sexualitytag)
				return
			return set_for_mind_or_prefs(user, action, new_sexualitytag, can_set_prefs, can_set_mind)
		if("setEventTag")
			var/list/names_list = list()
			for(var/C in GLOB.vantag_choices_list)
				names_list[GLOB.vantag_choices_list[C]] = C
			if(isnull(selected_value))
				open_directory_choice(user, action, overwrite_prefs, "Pick your preference for event involvement", "Event Preference Tag", names_list, user?.client?.prefs?.read_preference(/datum/preference/choiced/human/vantag_preference))
				return
			var/_answer_k329 = selected_value
			if(isnull(_answer_k329))
				return
			var/list/new_eventtag = _answer_k329 // migrated pref
			if(!new_eventtag)
				return
			return set_for_mind_or_prefs(user, action, names_list[new_eventtag], can_set_prefs, can_set_mind)

/datum/character_directory/proc/set_for_mind_or_prefs(mob/user, action, new_value, can_set_prefs, can_set_mind)
	can_set_prefs &&= !!user.client.prefs
	can_set_mind &&= !!user.mind
	if (!can_set_prefs && !can_set_mind)
		to_chat(user, span_warning("You seem to have lost either your mind, or your current preferences, while changing the values.[action == "editAd" ? " Here is your ad that you wrote. [new_value]" : null]"))
		return
	// all directory pref writes routed through update_preference_by_type
	switch(action)
		if ("setTag")
			if (can_set_prefs)
				user.client.prefs.update_preference_by_type(/datum/preference/choiced/human/directory_tag, new_value)
			if (can_set_mind)
				user.mind.directory_tag = new_value
			return TRUE
		if ("setErpTag")
			if (can_set_prefs)
				user.client.prefs.update_preference_by_type(/datum/preference/choiced/human/directory_erptag, new_value)
			if (can_set_mind)
				user.mind.directory_erptag = new_value
			return TRUE
		if ("setVisible")
			if (can_set_prefs)
				user.client.prefs.update_preference_by_type(/datum/preference/toggle/human/show_in_directory, new_value)
			if (can_set_mind)
				user.mind.show_in_directory = new_value
			return TRUE
		if ("editAd")
			if (can_set_prefs)
				// The prefs path strips HTML in /datum/preference/text/sanitize_input;
				// mirror that here so the mind write can't store raw markup.
				user.client.prefs.update_preference_by_type(/datum/preference/text/human/directory_ad, new_value)
			if (can_set_mind)
				user.mind.directory_ad = STRIP_HTML_SIMPLE(new_value, MAX_MESSAGE_LEN)
			return TRUE
		if ("setEventTag")
			if (can_set_prefs)
				user.client.prefs.update_preference_by_type(/datum/preference/choiced/human/vantag_preference, new_value)
			if (can_set_mind)
				user.mind.vantag_preference = new_value
		if ("setGenderTag")
			if (can_set_prefs)
				user.client.prefs.update_preference_by_type(/datum/preference/choiced/human/directory_gendertag, new_value)
			if (can_set_mind)
				user.mind.directory_gendertag = new_value
		if ("setSexualityTag")
			if (can_set_prefs)
				user.client.prefs.update_preference_by_type(/datum/preference/choiced/human/directory_sexualitytag, new_value)
			if (can_set_mind)
				user.mind.directory_sexualitytag = new_value

/datum/character_directory/proc/open_directory_choice(mob/user, action, overwrite_prefs, question, title, list/choices, default_value)
	open_request(src, /datum/prompt/choice/directory_setting, PROC_REF(directory_choice_entered), answerer = user, directory_action = action, overwrite_prefs = overwrite_prefs, question = question, title = title, choices = choices, default = default_value)

/datum/character_directory/proc/directory_choice_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/directory_setting/request = A.request
	finish_directory_answer(A, request.directory_action, request.overwrite_prefs)

/datum/character_directory/proc/directory_ad_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/text/directory_ad/request = A.request
	finish_directory_answer(A, request.directory_action, request.overwrite_prefs)

/datum/character_directory/proc/finish_directory_answer(datum/act/request/A, action, overwrite_prefs)
	apply_directory_answer(A.request.answerer, action, overwrite_prefs, A.answer.value)
	SStgui.update_uis(src)

/datum/character_directory/proc/apply_directory_answer(mob/user, action, overwrite_prefs, selected_value)
	return check_for_mind_or_prefs(user, action, overwrite_prefs, selected_value)

/datum/prompt/choice/directory_setting
	timeout = 0
	var/directory_action
	var/overwrite_prefs

/datum/prompt/text/directory_ad
	question = "Change your character ad"
	title = "Character Ad"
	timeout = 0
	max_len = MAX_MESSAGE_LEN
	multiline = TRUE
	encode = TRUE
	name_text = FALSE
	var/directory_action
	var/overwrite_prefs

/datum/prompt/choice/directory_setting/recheck_extra()
	. = ..()
	if(.)
		return
	if(QDELETED(answerer))
		return "gone"
	return null

/datum/prompt/text/directory_ad/recheck_extra()
	. = ..()
	if(.)
		return
	if(QDELETED(answerer))
		return "gone"
	return null
