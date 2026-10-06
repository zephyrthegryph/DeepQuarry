//A very, very simple mob that exists inside other objects to talk and has zero influence on the world.
/mob/living/voice
	name = "unknown person"
	desc = "How are you examining me?"
	see_invisible = SEE_INVISIBLE_LIVING
	var/obj/item/communicator/comm = null
	var/item_tf = FALSE

	emote_type = 2 //This lets them emote through containers.  The communicator has a image feed of the person calling them so...

/mob/living/voice/Initialize(mapload)
	add_language(LANGUAGE_GALCOM)
	apply_default_language(GLOB.all_languages[LANGUAGE_GALCOM])

	if(istype(loc, /obj/item/communicator))
		rel_set(src, nameof(comm), loc) // the communicator carrying us
	. = ..()

// Proc: transfer_identity()
// Parameters: 1 (speaker - the mob (usually an observer) to copy information from)
// Description: Copies the mob's icons, overlays, TOD, gender, currently loaded character slot, and languages, to src.
/mob/living/voice/proc/transfer_identity(mob/speaker)
	if(ismob(speaker))
		icon = speaker.icon
		icon_state = speaker.icon_state
		overlays = speaker.overlays
		timeofdeath = speaker.timeofdeath

		alpha = 127 //Maybe we'll have hologram calls later.
		if(speaker.client && speaker.client.prefs)
			var/datum/preferences/p = speaker.client.prefs
			name = p.read_preference(/datum/preference/name/real_name)
			real_name = name
			gender = p.read_preference(/datum/preference/choiced/gender/identifying)

			for(var/language in p.read_preference(/datum/preference/alternate_languages)) // migrated
				add_language(language)

// Proc: Login()
// Parameters: None
// Description: Adds a static overlay to the client's screen.
/mob/living/voice/Login()
	..()
	client.screen |= GLOB.global_hud.whitense
	client.screen |= GLOB.global_hud.darkMask

// Proc: ghostize()
// Parameters: None
// Description: Sets a timeofdeath variable, to fix the free respawn bug.
/mob/living/voice/ghostize()
	EXPIRY_STAMP(src, timeofdeath, CLOCK_WORLD)
	. = ..()

// Verb: hang_up()
// Parameters: None
// Description: Disconnects the voice mob from the communicator.
/mob/living/voice/verb/hang_up()
	set name = "Hang Up"
	set category = VERB_CAT_COMMUNICATOR
	set desc = "Disconnects you from whoever you're talking to."
	set src = usr

	if(comm)
		comm.close_connection(user = src, target = src, reason = "[src] hung up")
	else
		to_chat(src, "You appear to not be inside a communicator.  This is a bug and you should report it.")

// Verb: change_name()
// Parameters: None
// Description: Allows the voice mob to change their name, assuming it is valid.
/mob/living/voice/verb/change_name()
	set name = "Change Name"
	set category = VERB_CAT_COMMUNICATOR
	set desc = "Changes your name."
	set src = usr

	open_request(src, /datum/prompt/text, PROC_REF(voice_name_entered), answerer = src, title = "Communicator", question = "Who would you like to be now?", default = src.client.prefs.read_preference(/datum/preference/name/real_name), max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE, timeout = 0)

/mob/living/voice/proc/voice_name_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/new_name = sanitizeSafe(A.answer.value, MAX_NAME_LEN)
	if(new_name)
		if(comm)
			comm.visible_message(span_notice("[icon2html(comm,viewers(comm))] [src.name] has left, and now you see [new_name]."))
		//Do a bit of logging in-case anyone tries to impersonate other characters for whatever reason.
		var/msg = "[src.client.key] ([src]) has changed their communicator identity's name to [new_name]."
		message_admins(msg)
		log_game(msg)
		src.name = new_name
	else
		to_chat(src, span_warning("Invalid name.  Rejected."))

// Proc: Life()
// Parameters: None
// Description: Checks the active variable on the Exonet node, and kills the mob if it goes down or stops existing.
/mob/living/voice/life_type_pre_due()
	return TRUE

/mob/living/voice/life_type_pre(datum/seq_frame/life/F)
	if(src.comm)
		if(!src.comm.node || !src.comm.node.on || !src.comm.node.allow_external_communicators)
			src.comm.close_connection(user = src, target = src, reason = "Connection to telecommunications array timed out")
	..()

// Proc: say()
// Parameters: 4 (generic say() arguments)
// Description: Adds a speech bubble to the communicator device, then calls ..() to do the real work.
/mob/living/voice/say(message, datum/language/speaking = null, whispering = 0)
	//Speech bubbles.
	if(comm)
		var/speech_bubble_test = say_test(message)
		var/speech_type = custom_speech_bubble
		if(!speech_type || speech_type == "default")
			speech_type = speech_bubble_appearance()
		var/image/speech_bubble = generate_speech_bubble(comm, "[speech_type][speech_bubble_test]")
		after(src, 3 SECONDS, GLOBAL_PROC_REF(qdel), with = list(speech_bubble))

		for(var/mob/M in hearers(comm)) //simplifed since it's just a speech bubble
			M << speech_bubble
		src << speech_bubble

	..() //mob/living/say() can do the actual talking.

// Proc: speech_bubble_appearance()
// Parameters: 0
// Description: Gets the correct icon_state information for chat bubbles to work.
/mob/living/voice/speech_bubble_appearance()
	return "comm"

/mob/living/voice/say_understands(other, datum/language/speaking = null)
	//These only pertain to common. Languages are handled by mob/say_understands()
	if(!speaking)
		if(iscarbon(other))
			return TRUE
		if(issilicon(other))
			return TRUE
		if(isbrain(other))
			return TRUE
	return ..()

/mob/living/voice/custom_emote(m_type = VISIBLE_MESSAGE, message = null, range = world.view)
	if(comm)
		..(m_type,message,comm.video_range)
	else if(item_tf)
		..(m_type,message,range)

// Emotes!
/mob/living/voice/get_available_emotes()
	LAZYOR(., GLOB.simple_mob_default_emotes)

/mob/living/voice
	no_vore = TRUE
	can_pain_emote = FALSE

CAPABILITIES(/mob/living/voice)
	ref_one(nameof(comm))
