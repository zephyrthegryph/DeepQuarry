/mob/proc/say(message, datum/language/speaking = null, whispering = 0)
	return

// MUST BE NON-BLOCKING, signals can call this
/mob/proc/direct_say(message, datum/language/speaking = null, whispering = 0)
	SHOULD_NOT_SLEEP(TRUE)
	return

/mob/verb/whisper(message as text)
	set name = "Whisper"
	set hidden = 1
	if(forced_psay)
		psay(message)
		return

	say(message,whispering=1)

/mob/verb/say_verb(message as text)
	set name = "Say"
	set hidden = 1
	set instant = TRUE

	if(forced_psay)
		psay(message)
		return

	client?.stop_thinking()
	//queue this message because verbs are scheduled to process after SendMaps in the tick and speech is pretty expensive when it happens.
	//by queuing this for next tick the mc can compensate for its cost instead of having speech delay the start of the next tick
	if(message)
		QUEUE_OR_CALL_VERB_FOR(VERB_CALLBACK(src, TYPE_PROC_REF(/mob, say), message), SSspeech_controller)

/mob/verb/me_verb(message as message)
	set name = "Me"
	set desc = "Emote to nearby people (and your pred/prey)"
	set hidden = 1

	if(forced_psay)
		pme(message)
		return

	if(muffled)
		return me_verb_subtle(message)
	if(autowhisper)
		return me_verb_subtle(message)
	message = sanitize_or_reflect(message,src) //Reflect too-long messages (within reason)

	client?.stop_thinking()
	if(use_me)
		custom_emote(emote_type, message)
	else
		emote(message)

/mob/proc/say_dead(message)
	if(!client)
		return // Clientless mobs shouldn't be trying to talk in deadchat.

	if(!check_rights_for(client, R_HOLDER))
		if(!CONFIG_GET(flag/dsay_allowed))
			to_chat(src, span_danger("Deadchat is globally muted."))
			return

	if(!client?.prefs?.read_preference(/datum/preference/toggle/show_dsay))
		to_chat(src, span_danger("You have deadchat muted."))
		return

	message = encode_html_emphasis(message)

	say_dead_direct("[pick("complains","moans","whines","laments","blubbers")], " + span_message("\"[message]\""), src)

/mob/proc/say_understands(mob/other, datum/language/speaking = null)
	if(stat == DEAD)
		return TRUE

	//Universal speak makes everything understandable, for obvious reasons.
	else if(universal_speak || universal_understand)
		return TRUE

	if(isliving(src))
		var/mob/living/L = src
		if(isbelly(L.loc) && L.absorbed)
			var/mob/living/P = L.loc.loc
			if(P.say_understands(other, speaking))
				return TRUE

	//Languages are handled after.
	if(!speaking)
		if(!other)
			return TRUE
		if(other.universal_speak)
			return TRUE
		if(isAI(src) && ispAI(other))
			return TRUE
		if(istype(other, type) || istype(src, other.type))
			return TRUE
		return FALSE

	if(speaking.flags & INNATE)
		return TRUE

	//non-verbal languages are garbled if you can't see the speaker. Yes, this includes if they are inside a closet.
	if(speaking.flags & NONVERBAL)
		if(sdisabilities & BLIND || blinded)
			return FALSE
		if(!other)
			return FALSE
		// Fixes seeing non-verbal languages while being held
		if(istype(other.loc, /obj/item/holder))
			if(istype(src.loc, /obj/item/holder))
				if(!(other.loc in view(src.loc.loc)))
					return FALSE
			else if(!(other.loc in view(src)))
				return FALSE
		else if(istype(src.loc, /obj/item/holder))
			if((!other) in view(src.loc.loc))
				return FALSE
		else if((!other) in view(src))
			return FALSE

	//Language check.
	for(var/datum/language/L in languages)
		if(speaking.name == L.name)
			return TRUE

	return FALSE

/mob/proc/say_quote(message, datum/language/speaking = null)
	var/verb = "says"
	var/ending = copytext(message, length(message))

	if(speaking)
		verb = speaking.get_spoken_verb(ending)
	else
		if(ending == "!")
			verb = pick("exclaims", "shouts", "yells")
		else if(ending == "?")
			verb = "asks"
	return verb

/mob/proc/get_ear()
	// returns an atom representing a location on the map from which this
	// mob can hear things

	// should be overloaded for all mobs whose "ear" is separate from their "mob"

	return get_turf(src)

/proc/say_test(text)
	var/ending = copytext(text, length(text))
	if(ending == "?")
		return "1"
	else if(ending == "!")
		return "2"
	return "0"

//parses the message mode code (e.g. :h, :w) from text, such as that supplied to say.
//returns the message mode string or null for no message mode.
//standard mode is the mode returned for the special ';' radio code.
/mob/proc/parse_message_mode(message, standard_mode = "headset")
	if(length(message) >= 1 && copytext(message, 1, 2) == ";")
		return standard_mode

	if(length(message) >= 2)
		var/channel_prefix = copytext(message, 1, 3)
		return GLOB.department_radio_keys[channel_prefix]

	return null

/datum/multilingual_say_piece
	var/datum/language/speaking = null
	var/message = ""

/datum/multilingual_say_piece/New(datum/language/new_speaking, new_message)
	. = ..()
	speaking = new_speaking
	if(new_message)
		message = new_message

/mob/proc/find_valid_prefixes(message)
	var/list/prefixes = list() // [["Common", start, end], ["Gutter", start, end]]
	for(var/i in 1 to length(message))
		// This grabs 3 character substrings, to allow for up to 1 prefix, 1 letter language key, and one post-key character to more strictly control where the language breaks happen
		var/selection = trim_right(copytext(message, i, i + 3)) // We use uppercase keys to avoid Polaris key duplication, but this had lowertext() in it
		// The first character in the selection will always be the prefix (if this is a valid language invocation)
		var/prefix = copytext(selection, 1, 2)
		var/language_key = copytext(selection, 2, 3)
		var/multilingual_mode = client?.prefs?.read_preference(/datum/preference/choiced/multilingual_mode)
		if(is_language_prefix(prefix))
			// Okay, we're definitely now trying to invoke a language (probably)
			// This "[]" is probably unnecessary but BYOND will runtime if a number is used
			var/datum/language/L = GLOB.language_keys["[language_key]"]
			if((language_key in language_keys) && language_keys[language_key])
				L = language_keys[language_key]

			// MULTILINGUAL_SPACE enforces a space after the language key
			if(client && (multilingual_mode == MULTILINGUAL_SPACE) && (text2ascii(copytext(selection, 3, 4)) != 32)) // If we're looking for a space and we don't find one
				continue

			// MULTILINGUAL_DOUBLE_DELIMITER enforces a delimiter (valid prefix) after the language key
			if(client && (multilingual_mode == MULTILINGUAL_DOUBLE_DELIMITER) && !is_language_prefix(copytext(selection, 3, 4)))
				continue

			if(client && (multilingual_mode in list(MULTILINGUAL_DEFAULT)))
				selection = copytext(selection, 1, 3) // These modes only use two characters, not three

			// It's kinda silly that we have to check L != null and this isn't done for us by can_speak (it runtimes instead), but w/e
			if(L && can_speak(L))
				// So we have a valid language invocation, and we can speak that language, let's make a piece for it
				// This language will be the language until the next prefixes[] index, or the end of the message if there are none.
				prefixes[++prefixes.len] = list(L, i, i + length(selection))
			else if(L)
				// We found a valid language, but they can't speak it. Let's make them speak gibberish instead.
				prefixes[++prefixes.len] = list(GLOB.all_languages[LANGUAGE_GIBBERISH], i, i + length(selection))
			continue
		if(i == 1)
			// This covers the case of "no prefixes in use."
			prefixes[++prefixes.len] = list(get_default_language(), i, i)

		// If multilingualism is disabled, then after the first pass we're guaranteed to have either found a language key at the start, or else there isn't one and we're using the default for the whole message
		if(client && (multilingual_mode == MULTILINGUAL_OFF))
			break

	return prefixes

/mob/proc/strip_prefixes(message, mob/prefixer = null)
	. = ""
	var/last_index = 1
	for(var/i in 1 to length(message))
		var/selection = trim_right(lowertext(copytext(message, i, i + 2)))
		// The first character in the selection will always be the prefix (if this is a valid language invocation)
		var/prefix = copytext(selection, 1, 2)
		var/language_key = copytext(selection, 2, 3)
		if(is_language_prefix(prefix))
			var/datum/language/L = GLOB.language_keys["[language_key]"]
			if(L)
				. += copytext(message, last_index, i)
				last_index = i + 2
		if(i + 1 > length(message))
			. += copytext(message, last_index)

// this returns a structured message with language sections
// list(/datum/multilingual_say_piece(common, "hi"), /datum/multilingual_say_piece(farwa, "squik"), /datum/multilingual_say_piece(common, "meow!"))
/mob/proc/parse_languages(message)
	. = list()

	// Noise language is a snowflake.
	if(copytext(message, 1, 2) == "!" && length(message) > 1)
		// Note that list() here is intended
		// Returning a raw /datum/multilingual_say_piece is supported, but only for hivemind languages
		// What we actually want is a normal say piece that's all noise lang
		return list(new /datum/multilingual_say_piece(GLOB.all_languages["Noise"], trim(strip_prefixes(copytext(message, 2)))))

	// Scan the message for prefixes
	var/list/prefix_locations = find_valid_prefixes(message)
	if(!LAZYLEN(prefix_locations)) // There are no prefixes... or at least, no _valid_ prefixes.
		. += new /datum/multilingual_say_piece(get_default_language(), trim(strip_prefixes(message))) // So we'll just strip those pesky things and still make the message.

	for(var/i in 1 to length(prefix_locations))
		var/current = prefix_locations[i] // ["Common", start, end]

		// There are a few things that will make us want to ignore all other languages in - namely, HIVEMIND languages.
		var/datum/language/L = current[1]
		if(L && (L.flags & HIVEMIND || L.flags & SIGNLANG || L.flags & INAUDIBLE))
			return new /datum/multilingual_say_piece(L, trim(sanitize(strip_prefixes(message))))

		if(i + 1 > length(prefix_locations)) // We are out of lookaheads, that means the rest of the message is in cur lang
			var/spoke_message = sanitize(handle_autohiss(trim(copytext(message, current[3])), L))
			. += new /datum/multilingual_say_piece(current[1], spoke_message)
		else
			var/next = prefix_locations[i + 1] // We look ahead at the next message to see where we need to stop.
			var/spoke_message = sanitize(handle_autohiss(trim(copytext(message, current[3], next[2])), L))
			. += new /datum/multilingual_say_piece(current[1], spoke_message)

/* These are here purely because it would be hell to try to convert everything over to using the multi-lingual system at once */
/proc/message_to_multilingual(message, datum/language/speaking = null)
	. = list(new /datum/multilingual_say_piece(speaking, message))

/proc/multilingual_to_message(list/message_pieces, requires_machine_understands = FALSE, with_capitalization = FALSE)
	. = ""
	for(var/datum/multilingual_say_piece/S in message_pieces)
		var/message_to_append = S.message
		if(S.speaking)
			if(with_capitalization)
				message_to_append = S.speaking.format_message_plain(S.message)
			if(requires_machine_understands && !S.speaking.machine_understands)
				message_to_append = S.speaking.scramble(S.message)
		. += message_to_append + " "
	. = trim_right(.)


// === merged from say_vr.dm during hard-fork de-suffix (chain-verified: prior definer is this file, nothing between) ===
//////////////////////////////////////////////////////
////////////////////SUBTLE COMMAND////////////////////
//////////////////////////////////////////////////////

/mob/verb/me_verb_subtle(message as message) // This would normally go in say.dm //
	set name = "Subtle"
	set desc = "Emote to nearby people (and your pred/prey)"
	set hidden = TRUE

	if(forced_psay)
		pme(message)
		return

	message = sanitize_or_reflect(message,src) // Reflect too-long messages (within reason)
	if(!message)
		return

	client?.stop_thinking()
	if(use_me)
		emote_vr("me",4,message)
	else
		emote_vr(message)

/mob/verb/me_verb_subtle_custom(message as message) // Literally same as above but with mode_selection set to true //
	set name = "Subtle (Custom)"
	set desc = "Emote to nearby people, with ability to choose which specific portion of people you wish to target."

	if(forced_psay)
		pme(message)
		return

	message = sanitize_or_reflect(message,src) // Reflect too-long messages (within reason)
	if(!message)
		return

	client?.stop_thinking()
	if(use_me)
		emote_vr("me",4,message,TRUE)
	else
		emote_vr(message)

/mob/proc/custom_emote_vr(m_type=1,message = null,mode_selection = FALSE) //This would normally go in emote.dm
	if(stat || !use_me && usr == src)
		to_chat(src, "You are unable to emote.")
		return

	// ition Start
	if(forced_psay)
		pme(message)
		return
	// ition End

	var/muzzled = is_muzzled()
	if(m_type == 2 && muzzled) return

	var/subtle_mode
	if(autowhisper && autowhisper_mode && !mode_selection)
		if(autowhisper_mode != "Psay/Pme")	//This isn't actually a custom subtle mode, so we shouldn't use it!
			subtle_mode = autowhisper_mode
	if(mode_selection && !subtle_mode)
		subtle_mode = tgui_input_list(src, "Select Custom Subtle Mode", "Custom Subtle Mode", list("Adjacent Turfs (Default)", "My Turf", "My Table", "Current Belly (Prey)", "Specific Belly (Pred)", "Specific Person"))
	if(!subtle_mode)
		if(mode_selection)
			if(message)
				to_chat(src, span_warning("Subtle mode not selected. Your input has not been sent, but preserved:") + " [message]")
			return
		else
			subtle_mode = "Adjacent Turfs (Default)"

	var/input
	if(!message)
		input = sanitize_or_reflect(tgui_input_text(src,"Choose an emote to display.", encode = FALSE), src)
	else
		input = message

	if(input)
		src.log_message("(SUBTLE) [message]", LOG_EMOTE)
		message = span_emote_subtle(span_bold("[src]") + " " + span_italics("[input]"))
		if(src.absorbed && isbelly(src.loc))
			var/obj/belly/B = src.loc
			if(B.absorbedrename_enabled)
				var/formatted_name = B.absorbedrename_name
				formatted_name = replacetext(formatted_name,"%pred", B.owner)
				formatted_name = replacetext(formatted_name,"%belly", B.get_belly_name())
				formatted_name = replacetext(formatted_name,"%prey", name)
				message = span_emote_subtle(span_bold("[formatted_name]") + " " + span_italics("[input]"))
		if(!(subtle_mode == "Adjacent Turfs (Default)"))
			message = span_bold("(T) ") + message
	else
		return

	if (message)
		var/undisplayed_message = span_emote(span_bold("[src]") + " " + span_italics("does something too subtle for you to see."))
		message = encode_html_emphasis(message)

		var/list/vis
		var/list/vis_mobs
		var/list/vis_objs

		switch(subtle_mode)
			if("Adjacent Turfs (Default)")
				vis = get_mobs_and_objs_in_view_fast(get_turf(src),1,2)
				vis_mobs = vis["mobs"]
				vis_objs = vis["objs"]
			if("My Turf")
				vis = get_mobs_and_objs_in_view_fast(get_turf(src),0,2)
				vis_mobs = vis["mobs"]
				vis_objs = vis["objs"]
			if("My Table")
				vis = get_mobs_and_objs_in_view_fast(get_turf(src),7,2)
				vis_mobs = vis["mobs"]
				vis_objs = vis["objs"]
				var/list/tablelist = list()
				var/list/newmoblist = list()
				var/list/newobjlist = list()
				for(var/obj/structure/table/T in range(src, 1))
					if(istype(T) && !(T in tablelist) && !istype(T, /obj/structure/table/rack) && !istype(T, /obj/structure/table/bench))
						tablelist |= T.get_all_connected_tables()
				if(!(tablelist.len))
					to_chat(src, span_warning("No nearby tables detected. Your input has not been sent, but preserved:") + " [input]")
					return
				for(var/obj/structure/table/T in tablelist)
					for(var/mob/M in vis_mobs)
						var/dist = get_dist(T, M)
						if(dist >= 0 && dist <= 1)
							newmoblist |= M
					for(var/obj/O in vis_objs)
						var/dist = get_dist(T, O)
						if(dist >= 0 && dist <= 1)
							newobjlist |= O
				vis_mobs = newmoblist
				vis_objs = newobjlist
			if("Current Belly (Prey)")
				var/obj/belly/B = get_belly(src)
				if(!istype(B))
					to_chat(src, span_warning("You are currently not in the belly. Your input has not been sent, but preserved:") + " [input]")
					return
				vis = get_mobs_and_objs_in_view_fast(get_turf(src),0,2)
				vis_mobs = vis["mobs"]
				vis_objs = vis["objs"]
				for(var/mob/M in vis_mobs)			// Clean out everyone NOT in our specific belly
					if(M == B.owner)
						continue
					var/obj/belly/BB = get_belly(M)
					if(!(istype(BB)) || !(BB == B))
						vis_mobs -= M
				for(var/mob/M in vis_mobs)			// Re-add anything in bellies of people in our belly
					if(M == B.owner)
						continue
					vis_mobs |= get_all_prey_recursive(M, TRUE)
				for(var/obj/O in vis_objs)			// Clean out everyone NOT in our specific belly but for objs. No re-adding will happen there. Just don't be that deep and youre an obj anyway.
					var/obj/belly/BB = get_belly(O)
					if(!(istype(BB)) || !(BB == B))
						vis_objs -= O
			if("Specific Belly (Pred)")
				if(!isliving(src))
					to_chat(src, span_warning("You do not appear to be a living mob capable of having bellies. Your input has not been sent, but preserved:") + " [input]")
					return
				var/mob/living/L = src
				if(!(L.vore_organs) || !(L.vore_organs.len))
					to_chat(src, span_warning("You do not have any bellies. Your input has not been sent, but preserved:") + " [input]")
					return
				var/obj/belly/B = tgui_input_list(src, "Which belly do you want to sent the subtle to?","Select Belly", L.vore_organs)
				if(!B || !istype(B))
					to_chat(src, span_warning("You have not selected a valid belly. Your input has not been sent, but preserved:") + " [input]")
					return
				vis = get_mobs_and_objs_in_view_fast(get_turf(src),0,2)
				vis_mobs = vis["mobs"]
				vis_objs = vis["objs"]
				for(var/mob/M in vis_mobs)			// Clean out everyone NOT in our specific belly
					if(M == B.owner)
						continue
					var/obj/belly/BB = get_belly(M)
					if(!(istype(BB)) || !(BB == B))
						vis_mobs -= M
				for(var/mob/M in vis_mobs)			// Re-add anything in bellies of people in our belly
					if(M == B.owner)
						continue
					vis_mobs |= get_all_prey_recursive(M, TRUE)
				for(var/obj/O in vis_objs)			// Clean out everyone NOT in our specific belly but for objs. No re-adding will happen there. Just don't be that deep and youre an obj anyway.
					var/obj/belly/BB = get_belly(O)
					if(!(istype(BB)) || !(BB == B))
						vis_objs -= O
			if("Specific Person")
				vis = get_mobs_and_objs_in_view_fast(get_turf(src),1,2)
				vis_mobs = vis["mobs"]
				vis_objs = list()
				vis_mobs -= src
				for(var/mob/M in vis_mobs)			// ghosts get ye gone
					if(isobserver(M) || (M.stat == DEAD))
						vis_mobs -= M
				if(!(vis_mobs.len))
					to_chat(src, span_warning("No valid targets found. Your input has not been sent, but preserved:") + " [input]")
					return
				var/target = tgui_input_list(src, "Who do we send our message to?","Select Target", vis_mobs)
				if(!(target))
					to_chat(src, span_warning("No target selected. Your input has not been sent, but preserved:") + " [input]")
					return
				vis_mobs = list(target, src)

		for(var/mob/M as anything in vis_mobs)
			if(isnewplayer(M))
				continue
			if(src.client && M && !(get_z(src) == get_z(M)))
				message = span_multizsay("[message]")
			if(isobserver(M) && (!M.read_preference(/datum/preference/toggle/ghost_see_whisubtle) || \
			(!(read_preference(/datum/preference/toggle/whisubtle_vis) || (isbelly(M.loc) && src == M.loc:owner)) && !check_rights_for(M.client, R_HOLDER))))
				spawn(0)
					M.show_message(undisplayed_message, 2)
			else
				spawn(0)
					M.show_message(message, 2)
					if(M.Adjacent(src) && M.read_preference(/datum/preference/toggle/subtle_sounds)) // makes it so the sounds only play for ghosts when adjacent to the person making them
						if(voice_sounds_list) // changes to subtle emotes to use mob voice instead
							M << sound(pick(voice_sounds_list), volume = 25)

		for(var/obj/o in contents)
			vis_objs |= o

		for(var/obj/O as anything in vis_objs)
			spawn(0)
				O.see_emote(src, message, 2)

/mob/proc/emote_vr(act, type, message, mode_selection) //This would normally go in say.dm
	if(act == "me")
		return custom_emote_vr(type, message, mode_selection)

/proc/sanitize_or_reflect(message,user)
	//Way too long to send
	if(length(message) > MAX_HUGE_MESSAGE_LEN)
		fail_chat_message(user)
		return

	message = sanitize(message, max_length = MAX_HUGE_MESSAGE_LEN)

	//Came back still too long to send
	if(length(message) > MAX_MESSAGE_LEN)
		fail_chat_message(user,message)
		return null
	else
		return message

// returns true if it failed
/proc/reflect_if_needed(message, user)
	if(length(message) > MAX_HUGE_MESSAGE_LEN)
		fail_chat_message(user)
		return TRUE
	return FALSE

/proc/fail_chat_message(user,message)
	if(!message)
		to_chat(user, span_danger("Your message was NOT SENT, either because it was FAR too long, or sanitized to nothing at all."))
		return

	var/length = length(message)
	var/posts = CEILING((length/MAX_MESSAGE_LEN), 1)
	to_chat(user,message)
	to_chat(user, span_danger("^ This message was NOT SENT ^ -- It was [length] characters, and the limit is [MAX_MESSAGE_LEN]. It would fit in [posts] separate messages."))

///// PSAY /////

/mob/verb/psay(message as text)
	set name = "Psay"
	set desc = "Talk to people affected by complete absorbed or dominate predator/prey."

	if (src.client)
		if(client.prefs.muted & MUTE_IC)
			to_chat(src, span_warning("You cannot speak in IC (muted)."))
			return
	if (!message)
		message = tgui_input_text(src, "Type a message to say.","Psay", encode = FALSE)
	message = sanitize_or_reflect(message,src)
	if (!message)
		return
	message = capitalize(message)
	if (stat == DEAD)
		return say_dead(message)
	if(!isliving(src))
		forced_psay = FALSE
		return say(message)
	var/f = FALSE		//did we find someone to send the message to other than ourself?
	var/mob/living/pb	//predator body
	var/mob/living/M = src
	var/formatted_name = "\The [M]"
	if(istype(M, /mob/living/dominated_brain))
		var/mob/living/dominated_brain/db = M
		if(db.loc != db.pred_body)
			to_chat(db, span_danger("You aren't inside of a brain anymore!!!"))
			qdel(db)	//Oh no, dominated brains shouldn't exist outside of the body, so if we got here something went very wrong.
			return
		else
			pb = db.pred_body
			to_chat(pb, span_psay("The captive mind of \the [M] thinks, \"[message]\""))	//To our pred if dominated brain
			if(pb.read_preference(/datum/preference/toggle/subtle_sounds))
				if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
					pb << sound(pick(voice_sounds_list), volume = 25)
			f = TRUE
	else if(M.absorbed && isbelly(M.loc))
		pb = M.loc.loc
		var/obj/belly/B = M.loc
		if(B.absorbedrename_enabled)
			formatted_name = B.absorbedrename_name
			formatted_name = replacetext(formatted_name,"%pred", B.owner)
			formatted_name = replacetext(formatted_name,"%belly", B.get_belly_name())
			formatted_name = replacetext(formatted_name,"%prey", "\The [M]")
			to_chat(pb, span_psay("[formatted_name] thinks, \"[message]\""))
		else
			to_chat(pb, span_psay("\The [M] thinks, \"[message]\""))	//To our pred if absorbed
		if(pb.read_preference(/datum/preference/toggle/subtle_sounds))
			if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
				pb << sound(pick(voice_sounds_list), volume = 25)
		f = TRUE

	if(pb)	//We are prey, let's do the prey thing.

		for(var/I in pb.contents)
			if(istype(I, /mob/living/dominated_brain) && I != M)
				var/mob/living/dominated_brain/db = I
				to_chat(db, span_psay("The captive mind of \the [M] thinks, \"[message]\""))	//To any dominated brains in the pred
				if(db.read_preference(/datum/preference/toggle/subtle_sounds))
					if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
						db << sound(pick(voice_sounds_list), volume = 25)
				f = TRUE
		for(var/B in pb.vore_organs)
			for(var/mob/living/L in B)
				if(L.absorbed && L != M && L.ckey)
					to_chat(L, span_psay("[formatted_name] thinks, \"[message]\""))	//To any absorbed people in the pred
					if(L.read_preference(/datum/preference/toggle/subtle_sounds))
						if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
							L << sound(pick(voice_sounds_list), volume = 25)
					f = TRUE

	//Let's also check and see if there's anyone inside of us to send the message to.
	for(var/I in M.contents)
		if(istype(I, /mob/living/dominated_brain))
			var/mob/living/dominated_brain/db = I
			to_chat(db, span_psay(span_bold("[formatted_name] thinks, \"[message]\"")))	//To any dominated brains inside us
			if(db.read_preference(/datum/preference/toggle/subtle_sounds))
				if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
					db << sound(pick(voice_sounds_list), volume = 25)
			f = TRUE
	for(var/B in M.vore_organs)
		for(var/mob/living/L in B)
			if(L.absorbed)
				to_chat(L, span_psay(span_bold("[formatted_name] thinks, \"[message]\"")))	//To any absorbed people inside us
				if(L.read_preference(/datum/preference/toggle/subtle_sounds))
					if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
						L << sound(pick(voice_sounds_list), volume = 25)
				f = TRUE

	if(f)	//We found someone to send the message to
		if(pb)
			to_chat(M, span_psay("You think \"[message]\""))	//To us if we are the prey
			if(M.read_preference(/datum/preference/toggle/subtle_sounds))
				if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
					M << sound(pick(voice_sounds_list), volume = 25)
		else
			to_chat(M, span_psay(span_bold("You think \"[message]\"")))	//To us if we are the pred
			if(M.read_preference(/datum/preference/toggle/subtle_sounds))
				if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
					M << sound(pick(voice_sounds_list), volume = 25)
		for (var/mob/G in GLOB.player_list)
			if (isnewplayer(G))
				continue
			else if(isobserver(G) &&  G.client?.prefs?.read_preference(/datum/preference/toggle/ghost_ears) && \
			G.client?.prefs?.read_preference(/datum/preference/toggle/ghost_see_whisubtle))
				if(client?.prefs?.read_preference(/datum/preference/toggle/whisubtle_vis) || check_rights_for(G.client, R_HOLDER))
					to_chat(G, span_psay("[formatted_name] thinks, \"[message]\""))
		M.log_talk("(PSAY) [message]", LOG_SAY, color="#d900ff")
	else		//There wasn't anyone to send the message to, pred or prey, so let's just say it instead and correct our psay just in case.
		M.forced_psay = FALSE
		M.say(message)

///// PME /////

/mob/verb/pme(message as message)
	set name = "Pme"
	set desc = "Emote to people affected by complete absorbed or dominate predator/prey."

	if (src.client)
		if(client.prefs.muted & MUTE_IC)
			to_chat(src, span_warning("You cannot speak in IC (muted)."))
			return
	if (!message)
		message = tgui_input_text(src, "Type a message to emote.","Pme", encode = FALSE)
	message = sanitize_or_reflect(message,src)
	if (!message)
		return
	if (stat == DEAD)
		return say_dead(message)
	if(!isliving(src))
		forced_psay = FALSE
		return me_verb(message)
	var/f = FALSE		//did we find someone to send the message to other than ourself?
	var/mob/living/pb	//predator body
	var/mob/living/M = src
	var/formatted_name = "\The [M]"
	if(istype(M, /mob/living/dominated_brain))
		var/mob/living/dominated_brain/db = M
		if(db.loc != db.pred_body)
			to_chat(db, span_danger("You aren't inside of a brain anymore!!!"))
			qdel(db)	//Oh no, dominated brains shouldn't exist outside of the body, so if we got here something went very wrong.
			return
		else
			pb = db.pred_body
			to_chat(pb, span_pemote("\The [M] [message]"))	//To our pred if dominated brain
			if(pb.read_preference(/datum/preference/toggle/subtle_sounds))
				if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
					pb << sound(pick(voice_sounds_list), volume = 25)
			f = TRUE

	else if(M.absorbed && isbelly(M.loc))
		pb = M.loc.loc
		var/obj/belly/B = M.loc
		if(B.absorbedrename_enabled)
			formatted_name = B.absorbedrename_name
			formatted_name = replacetext(formatted_name,"%pred", B.owner)
			formatted_name = replacetext(formatted_name,"%belly", B.get_belly_name())
			formatted_name = replacetext(formatted_name,"%prey", "\The [M]")
			to_chat(pb, span_pemote("[formatted_name] [message]"))
		else
			to_chat(pb, span_pemote("\The [M] [message]"))	//To our pred if absorbed
		if(pb.read_preference(/datum/preference/toggle/subtle_sounds))
			if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
				pb << sound(pick(voice_sounds_list), volume = 25)
		f = TRUE

	if(pb)	//We are prey, let's do the prey thing.

		for(var/I in pb.contents)
			if(istype(I, /mob/living/dominated_brain) && I != M)
				var/mob/living/dominated_brain/db = I
				to_chat(db, span_pemote("[formatted_name] [message]"))	//To any dominated brains in the pred
				if(db.read_preference(/datum/preference/toggle/subtle_sounds))
					if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
						pb << sound(pick(voice_sounds_list), volume = 25)
				f = TRUE
		for(var/B in pb.vore_organs)
			for(var/mob/living/L in B)
				if(L.absorbed && L != M && L.ckey)
					to_chat(L, span_pemote("[formatted_name] [message]"))	//To any absorbed people in the pred
					if(L.read_preference(/datum/preference/toggle/subtle_sounds))
						if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
							L << sound(pick(voice_sounds_list), volume = 25)
					f = TRUE

	//Let's also check and see if there's anyone inside of us to send the message to.
	for(var/I in M.contents)
		if(istype(I, /mob/living/dominated_brain))
			var/mob/living/dominated_brain/db = I
			to_chat(db, span_pemote(span_bold("[formatted_name] [message]")))	//To any dominated brains inside us
			if(db.read_preference(/datum/preference/toggle/subtle_sounds))
				if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
					db << sound(pick(voice_sounds_list), volume = 25)
			f = TRUE
	for(var/B in M.vore_organs)
		for(var/mob/living/L in B)
			if(L.absorbed)
				to_chat(L, span_pemote(span_bold("[formatted_name] [message]")))	//To any absorbed people inside us
				if(L.read_preference(/datum/preference/toggle/subtle_sounds))
					if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
						L << sound(pick(voice_sounds_list), volume = 25)
				f = TRUE

	if(f)	//We found someone to send the message to
		if(pb)
			to_chat(M, span_pemote("[formatted_name] [message]"))	//To us if we are the prey
			if(M.read_preference(/datum/preference/toggle/subtle_sounds))
				if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
					M << sound(pick(voice_sounds_list), volume = 25)
		else
			to_chat(M, span_pemote(span_bold("\The [M] [message]")))	//To us if we are the pred
			if(M.read_preference(/datum/preference/toggle/subtle_sounds))
				if(voice_sounds_list) // changes subtle emote sound to use mob voice instead
					M << sound(pick(voice_sounds_list), volume = 25)
		for (var/mob/G in GLOB.player_list)
			if (isnewplayer(G))
				continue
			else if(isobserver(G) && G.client?.prefs?.read_preference(/datum/preference/toggle/ghost_ears) && \
			G.client?.prefs?.read_preference(/datum/preference/toggle/ghost_see_whisubtle))
				if(client?.prefs?.read_preference(/datum/preference/toggle/whisubtle_vis) || check_rights_for(G.client, R_HOLDER))
					to_chat(G, span_pemote("[formatted_name] [message]"))
		M.log_talk(message, LOG_SAY, color="#d900ff")
	else	//There wasn't anyone to send the message to, pred or prey, so let's just emote it instead and correct our psay just in case.
		M.forced_psay = FALSE
		M.me_verb(message)

/mob/living/verb/player_narrate(message as message)
	set name = "Narrate (Player)"
	set desc = "Narrate an action or event! An alternative to emoting, for when your emote shouldn't start with your name!"

	if(src.client)
		if(client.prefs.muted & MUTE_IC)
			to_chat(src, span_warning("You cannot speak in IC (muted)."))
			return
	if(!message)
		message = tgui_input_text(src, "Type a message to narrate.","Narrate", encode = FALSE)
	message = sanitize_or_reflect(message,src)
	if(!message)
		return
	if(stat == DEAD)
		return say_dead(message)
	if(stat)
		to_chat(src, span_warning("You need to be concious to narrate: [message]"))
		return
	message = span_name("([name])") + " " +  span_pnarrate("[message]")

	//Below here stolen from emotes
	var/turf/T = get_turf(src)

	if(!T) return

	var/ourfreq = null
	if(voice_freq > 0 )
		ourfreq = voice_freq

	if(client)
		playsound(T, pick(GLOB.emote_sound), 25, TRUE, falloff = 1 , is_global = TRUE, frequency = ourfreq, ignore_walls = TRUE, preference = /datum/preference/toggle/emote_sounds) // ignore walls

	var/list/in_range = get_mobs_and_objs_in_view_fast(T,world.view,2,remote_ghosts = client ? TRUE : FALSE)
	var/list/m_viewers = in_range["mobs"]

	for(var/mob/M as anything in m_viewers)
		if(M)
			if(isnewplayer(M))
				continue
			if(M.stat == UNCONSCIOUS || M.sleeping > 0)
				continue
			to_chat(M, span_filter_say("[isobserver(M) ? "[message] ([ghost_follow_link(src, M)])" : message]"))
	log_message(message, LOG_EMOTE)

/mob/verb/select_speech_bubble()
	set name = "Select Speech Bubble"
	set category = "OOC.Chat Settings"

	var/new_speech_bubble = tgui_input_list(src, "Pick new voice (default for automatic selection)", "Character Preference", GLOB.selectable_speech_bubbles)
	if(new_speech_bubble)
		custom_speech_bubble = new_speech_bubble
		if(dna)
			dna.custom_speech_bubble = new_speech_bubble
