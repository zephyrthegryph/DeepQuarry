
/// This is the custom_emote that you'll want to use if you want the mob to be able to input their emote.
/mob/proc/custom_emote(m_type = VISIBLE_MESSAGE, message, range = world.view, check_stat = TRUE)

	if((check_stat && (src && stat)) || is_paralyzed() || (!use_me && usr == src))
		to_chat(src, "You are unable to emote.")
		return

	var/input
	if(!message)
		input = tgui_input_text(src,"Choose an emote to display.", max_length = MAX_MESSAGE_LEN)
	else
		input = message
	process_normal_emote(src, m_type, input, input, range)

/// This is the custom_emote that you'll want to use if you're forcing something to custom emote with no input from the mob.
/// By default, we have a visible message, our range is world.view, and we do NOT check the stat.
/mob/proc/automatic_custom_emote(m_type = VISIBLE_MESSAGE, message, range = world.view, check_stat = FALSE)
	if(check_stat && (src && stat) || is_paralyzed())
		return
	var/input = message
	process_automatic_emote(src, m_type, message, input, range)

//The actual meat and potatoes of the emote processing.
/proc/process_normal_emote(mob/source, m_type = VISIBLE_MESSAGE, message, input, range = world.view)
	var/list/formatted
	var/runemessage
	if(input)
		formatted = format_emote(source, source, message)
		if(!islist(formatted))
			return
		message = formatted["pretext"] + formatted["nametext"] + formatted["subtext"]
		runemessage = formatted["subtext"]
		// This is just personal preference (but I'm objectively right) that custom emotes shouldn't have periods at the end in runechat
		runemessage = replacetext(runemessage,".","",length(runemessage),length(runemessage)+1)
	else
		return

	log_the_emote(source, m_type, message, input, range, runemessage)

/proc/process_automatic_emote(mob/source, m_type = VISIBLE_MESSAGE, message, input, range = world.view)
	var/list/formatted
	var/runemessage
	if(input)
		formatted = format_emote(source, source, message)
		if(!islist(formatted))
			return
		message = formatted["pretext"] + formatted["nametext"] + formatted["subtext"]
		runemessage = formatted["subtext"]
		// This is just personal preference (but I'm objectively right) that custom emotes shouldn't have periods at the end in runechat
		runemessage = replacetext(runemessage,".","",length(runemessage),length(runemessage)+1)
	else
		return

	build_the_emote(source, m_type, message, input, range, runemessage)

/proc/log_the_emote(mob/source, m_type, message, input, range, runemessage)
	source.log_message(message, LOG_EMOTE) //Log before we add junk
	build_the_emote(source, m_type, message, input, range, runemessage)

/proc/build_the_emote(mob/source, m_type, message, input, range, runemessage)
	if(source.client)
		message = span_emote(span_bold("[source]") + " [input]")
		if(source.absorbed && isbelly(source.loc))
			var/obj/belly/B = source.loc
			if(B.absorbedrename_enabled)
				var/formatted_name = B.absorbedrename_name
				formatted_name = replacetext(formatted_name,"%pred", B.owner)
				formatted_name = replacetext(formatted_name,"%belly", B.get_belly_name())
				formatted_name = replacetext(formatted_name,"%prey", source.name)
				message = span_emote(span_bold("[formatted_name]") + " [input]")
	else
		message = span_npc_emote(span_bold("[source]") + " [input]")

	if(message)
		send_the_emote(source, m_type, message, input, range, runemessage)

/proc/send_the_emote(mob/source, m_type, message, input, range, runemessage)

	message = encode_html_emphasis(message)
	var/turf/T = get_turf(source)

	if(!T) return

	if(source.client)
		switch(source.emote_sound_mode)
			if(EMOTE_SOUND_NO_FREQ)
				playsound(T, pick(GLOB.emote_sound), 75, TRUE, falloff = 1 , is_global = TRUE, frequency = 0, ignore_walls = TRUE, preference = /datum/preference/toggle/emote_sounds)
			if(EMOTE_SOUND_VOICE_FREQ)
				playsound(T, pick(GLOB.emote_sound), 75, TRUE, falloff = 1 , is_global = TRUE, frequency = source.voice_freq, ignore_walls = TRUE, preference = /datum/preference/toggle/emote_sounds)
			if(EMOTE_SOUND_VOICE_LIST)
				playsound(T, pick(source.voice_sounds_list), 75, TRUE, falloff = 1 , is_global = TRUE, frequency = source.voice_freq, ignore_walls = TRUE, preference = /datum/preference/toggle/emote_sounds)

	var/list/in_range = get_mobs_and_objs_in_view_fast(T,range,2,remote_ghosts = source.client ? TRUE : FALSE)
	var/list/m_viewers = in_range["mobs"]
	var/list/o_viewers = in_range["objs"]

	for(var/obj/o in source.contents)
		o_viewers |= o

	for(var/mob/M as anything in m_viewers)
		if(M)
			var/final_message = message
			if(isobserver(M))
				final_message = span_emote(span_bold("[source]") + " ([ghost_follow_link(source, M)]) [input]")
			if(source.client && M && !(get_z(source) == get_z(M)))
				final_message = span_multizsay("[final_message]")
			// If you are in the same tile, right next to, or being held by a person doing an emote, you should be able to see it while blind
			if(m_type != AUDIBLE_MESSAGE && (source.Adjacent(M) || (istype(source.loc, /obj/item/holder) && source.loc.loc == M)))
				M.show_message(final_message)
			else
				M.show_message(final_message, m_type)
			M.create_chat_message(source, "[runemessage]", FALSE, list("emote"), (m_type == AUDIBLE_MESSAGE))

	for(var/obj/O as anything in o_viewers)
		if(O)
			var/final_message = message
			if(source.client && O && !(get_z(source) == get_z(O)))
				final_message = span_multizsay("[final_message]")
			O.see_emote(source, final_message, m_type)

/// Conjugates the leading verb of a bare phrase to the third person singular:
/// "shudder" to "shudders", "wince at their arm" to "winces at their arm",
/// "wipe their brow" to "wipes their brow", "clutch" to "clutches", "cry" to "cries".
/proc/third_person_phrase(phrase)
	var/split = findtext(phrase, " ")
	var/verb_word = split ? copytext(phrase, 1, split) : phrase
	var/rest = split ? copytext(phrase, split) : ""
	var/last = copytext(verb_word, -1)
	var/last_two = copytext(verb_word, -2)
	if(last == "s" || last == "x" || last == "z" || last_two == "sh" || last_two == "ch")
		verb_word += "es"
	else if(last == "y" && !findtext("aeiou", copytext(verb_word, -2, -1)))
		verb_word = copytext(verb_word, 1, -1) + "ies"
	else
		verb_word += "s"
	return verb_word + rest
