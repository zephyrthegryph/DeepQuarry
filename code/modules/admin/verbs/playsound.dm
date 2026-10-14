/// When the current internet sound ends (a COOLDOWN): one at a time, server-wide.
GLOBAL_VAR_INIT(internet_sound_cooldown, 0)

//world/proc/shelleo
#define SHELLEO_ERRORLEVEL 1
#define SHELLEO_STDOUT 2
#define SHELLEO_STDERR 3

GLOBAL_LIST_EMPTY(sounds_cache) // ALLOW(cache): admin-uploaded sound list, not a keyed cache

ADMIN_VERB(play_sound, R_SOUNDS, "Play Global Sound", "Plays a sound to all players.", ADMIN_CATEGORY_FUN_SOUNDS, S as sound)
	// Replay only the actual ended request, through the public admin dispatcher.
	var/list/replay_answers = list()
	if(length(args) >= 3)
		var/datum/request/resumed = args[3]
		if((istype(resumed, /datum/prompt/choice/admin_global_sound_replay) || istype(resumed, /datum/prompt/number/admin_global_sound_replay)) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(play_sound_replay_answered) && S == resumed.captured["original_sound"])
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	var/freq = 1
	if(!("a1" in replay_answers))
		replay_answers["original_sound"] = args[2]
		open_request(src, /datum/prompt/number/admin_global_sound_replay, PROC_REF(play_sound_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a1", question = "What volume would you like the sound to play at?", default = 100, max_value = 100, min_value = 1)
		return
	var/vol = replay_answers["a1"]
	if(isnull(vol))
		return
	if(!vol)
		return
	vol = clamp(vol, 1, 100)

	var/sound/admin_sound = new()
	admin_sound.file = S
	admin_sound.priority = 250
	admin_sound.channel = 777
	admin_sound.frequency = freq
	admin_sound.wait = 1
	admin_sound.repeat = FALSE
	admin_sound.status = SOUND_STREAM
	admin_sound.volume = vol

	GLOB.sounds_cache += S

	if(!("a2" in replay_answers))
		replay_answers["original_sound"] = args[2]
		open_request(src, /datum/prompt/choice/admin_global_sound_replay, PROC_REF(play_sound_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a2", question = "Show the title of this song ([S]) to the players?\nOptions 'Yes' and 'No' will play the sound.", choices = list("Yes", "No", "Cancel"))
		return
	var/res = replay_answers["a2"]
	if(isnull(res))
		return
	if(!res)
		return
	switch(res)
		if("Yes")
			to_chat(world, span_boldannounce("An admin played: [S]"), confidential = TRUE)
		if("Cancel")
			return

	log_admin("[key_name(user)] played sound [S]")
	message_admins("[key_name_admin(user)] played sound [S]", 1)

	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(M.read_preference(/datum/preference/toggle/play_admin_midis))
			admin_sound.volume = vol * M.client.admin_music_volume
			SEND_SOUND(M, admin_sound)
			admin_sound.volume = vol

	feedback_add_details("admin_verb", "Play Global Sound")

ADMIN_VERB(play_local_sound, R_SOUNDS, "Play Local Sound", "Plays a sound around your own mob.", ADMIN_CATEGORY_FUN_SOUNDS, S as sound)
	log_admin("[key_name(user)] played a local sound [S]")
	message_admins("[key_name_admin(user)] played a local sound [S]", 1)
	playsound(user.mob, S, 50, 0, 0)
	feedback_add_details("admin_verb", "Play Local Sound")

ADMIN_VERB(play_direct_mob_sound, R_SOUNDS, "Play Direct Mob Sound", "Plays a sound to a single mob.", ADMIN_CATEGORY_FUN_SOUNDS, S as sound)
	var/mob/target_mob = verb_ask(user, "a3", args, /datum/prompt/choice, question = "Choose a mob to play the sound to. Only they will hear it.", title = "Play Mob Sound", choices = sortNames(REGISTRY_MEMBERS(REGISTRY_PLAYERS)))
	if(isnull(target_mob))
		return
	if(QDELETED(target_mob))
		return
	log_admin("[key_name(user)] played a direct mob sound [S] to [target_mob].")
	message_admins("[key_name_admin(user)] played a direct mob sound [S] to [ADMIN_LOOKUPFLW(target_mob)].")
	SEND_SOUND(target_mob, S)
	feedback_add_details("admin_verb", "Play Direct Mob Sound")

ADMIN_VERB(play_z_sound, R_SOUNDS, "Play Z Sound", "Plays a sound to a single z-level.", ADMIN_CATEGORY_FUN_SOUNDS, S as sound)
	// Replay only the actual ended request, through the public admin dispatcher.
	var/list/replay_answers = list()
	if(length(args) >= 3)
		var/datum/request/resumed = args[3]
		if((istype(resumed, /datum/prompt/choice/admin_z_sound_replay)) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(play_z_sound_replay_answered) && S == resumed.captured["original_sound"])
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	var/target_z = user.mob.z
	var/sound/uploaded_sound = sound(S, repeat = 0, wait = 1, channel = 777)
	uploaded_sound.priority = 250

	GLOB.sounds_cache += S

	if(!("a4" in replay_answers))
		replay_answers["original_sound"] = args[2]
		open_request(src, /datum/prompt/choice/admin_z_sound_replay, PROC_REF(play_z_sound_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a4", question = "Do you ready?\nSong: [S]\nNow you can also play this sound using \"Play Server Sound\".", title = "Confirmation request", choices = list("Play", "Cancel"))
		return
	var/_answer_a4 = replay_answers["a4"]
	if(isnull(_answer_a4))
		return
	if(_answer_a4 != "Play")
		return

	log_admin("[key_name(user)] played sound [S] on Z[target_z]")
	message_admins("[key_name_admin(user)] played sound [S] on Z[target_z]", 1)
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(M.read_preference(/datum/preference/toggle/play_admin_midis) && M.z == target_z)
			M << uploaded_sound

	feedback_add_details("admin_verb", "Play Z Sound") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(play_server_sound, R_SOUNDS, "Play Server Sound", "Plays a sound from the server to play.", ADMIN_CATEGORY_FUN_SOUNDS, S as sound)
	var/list/sounds = world.file2list("sound/serversound_list.txt");
	sounds += "--CANCEL--"
	sounds += GLOB.sounds_cache

	open_request(src, /datum/prompt/choice/admin_server_sound, PROC_REF(server_sound_answered), answerer = user.mob, choices = sounds, default = "--CANCEL--")

/datum/prompt/choice/admin_server_sound
	rights = R_SOUNDS
	timeout = 0
	recheck_on_open = TRUE
	question = "Select a sound from the server to play"
	title = "Server sound list"

/datum/admin_verb/play_server_sound/proc/server_sound_answered(datum/act/request/A)
	if(!A.answer || !A.answer.value || A.answer.value == "--CANCEL--")
		return
	var/client/user = A.request.answerer.client
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/play_sound, A.answer.value)
	feedback_add_details("admin_verb", "Play Server Sound") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

///Takes an input from either proc/play_web_sound or the request manager and runs it through youtube-dl and prompts the user before playing it to the server.
/proc/web_sound(mob/user, input, credit)
	if(!admin_require(user.client, R_SOUNDS, "web_sound", TRUE))
		return
	var/ytdl = CONFIG_GET(string/invoke_youtubedl)
	if(!ytdl)
		to_chat(user, span_boldwarning("Youtube-dl was not configured, action unavailable"), confidential = TRUE) //Check config.txt for the INVOKE_YOUTUBEDL value
		return
	if(!istext(input))
		//pressed ok with blank
		log_admin("[key_name(user)] stopped web sounds.")
		message_admins("[key_name(user)] stopped web sounds.")
		web_sound_play(user, null, list(), 0)
		return
	var/shell_scrubbed_input = shell_url_scrub(input)
	// youtube-dl is an OS process: DX-exec runs it and web_sound_resolved() gets its output.
	dx_shelleo(null, "[ytdl] --geo-bypass --format \"bestaudio\[ext=mp3]/best\[ext=mp4]\[height <= 360]/bestaudio\[ext=m4a]/bestaudio\[ext=aac]\" --dump-single-json --no-playlist -- \"[shell_scrubbed_input]\"", GLOBAL_PROC_REF(web_sound_resolved), user, input, credit)

/// dx_shelleo() callback: youtube-dl has answered for web_sound().
/proc/web_sound_resolved(list/output, mob/user, input, credit)
	if(!user?.client || !check_rights_for(user.client, R_SOUNDS))
		return
	var/errorlevel = output[SHELLEO_ERRORLEVEL]
	var/stdout = output[SHELLEO_STDOUT]
	var/stderr = output[SHELLEO_STDERR]
	if(errorlevel)
		to_chat(user, span_boldwarning("Youtube-dl URL retrieval FAILED:"), confidential = TRUE)
		to_chat(user, span_warning("[stderr]"), confidential = TRUE)
		return
	var/list/data
	try
		data = json_decode(stdout)
	catch(var/exception/e) // ALLOW(silent_catch): the parse failure is shown to the admin
		to_chat(user, span_boldwarning("Youtube-dl JSON parsing FAILED:"), confidential = TRUE)
		to_chat(user, span_warning("[e]: [stdout]"), confidential = TRUE)
		return
	var/web_sound_url = data["url"] || ""
	var/title = "[data["title"]]"
	var/webpage_url = title
	if (data["webpage_url"])
		webpage_url = "<a href=\"[data["webpage_url"]]\">[title]</a>"
	var/list/music_extra_data = list()
	music_extra_data["duration"] = DisplayTimeText(data["duration"] * 1 SECONDS)
	music_extra_data["link"] = data["webpage_url"]
	music_extra_data["artist"] = data["artist"]
	music_extra_data["upload_date"] = data["upload_date"]
	music_extra_data["album"] = data["album"]
	var/duration = data["duration"] * 1 SECONDS
	// youtube-dl has answered; the questions come now, and the flow plays it.
	user.ask_web_sound(web_sound_url, music_extra_data, webpage_url, data["title"], duration, credit, input)

/// The original admin mob owns each question; a cancel stops without playing or broadcasting.
/datum/prompt/choice/web_sound
	buttons = TRUE
	timeout = 0
	rights = R_SOUNDS
	var/url
	var/list/extra
	var/page
	var/song_title
	var/duration
	var/credit
	var/input
	var/show
	recheck_on_open = TRUE

/mob/proc/ask_web_sound(url, list/extra, page, song_title, duration, credit, input)
	if(duration > 10 MINUTES)
		open_request(src, /datum/prompt/choice/web_sound, PROC_REF(web_sound_length_answered), answerer = src, url = url, extra = extra, page = page, song_title = song_title, duration = duration, credit = credit, input = input, title = "Length Warning!", question = "This song is over 10 minutes long. Are you sure you want to play it?", choices = list("No", "Yes", "Cancel"))
		return
	ask_web_sound_show(url, extra, page, song_title, duration, credit, input)

/mob/proc/web_sound_length_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/web_sound/ask = A.answer
	if(ask.value == "Yes")
		ask_web_sound_show(ask.url, ask.extra, ask.page, ask.song_title, ask.duration, ask.credit, ask.input)

/mob/proc/ask_web_sound_show(url, list/extra, page, song_title, duration, credit, input)
	open_request(src, /datum/prompt/choice/web_sound, PROC_REF(web_sound_show_answered), answerer = src, url = url, extra = extra, page = page, song_title = song_title, duration = duration, credit = credit, input = input, title = "Show Info?", question = "Show the title of and link to this song to the players?\n[song_title]", choices = list("Yes", "No", "Cancel"))

/mob/proc/web_sound_show_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/web_sound/ask = A.answer
	if(ask.value == "Cancel")
		return
	open_request(src, /datum/prompt/choice/web_sound, PROC_REF(web_sound_anon_answered), answerer = src, url = ask.url, extra = ask.extra, page = ask.page, song_title = ask.song_title, duration = ask.duration, credit = ask.credit, input = ask.input, show = ask.value, title = "Credit Yourself?", question = "Display who played the song?", choices = list("Yes", "No", "Cancel"))

/mob/proc/web_sound_anon_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/web_sound/ask = A.answer
	if(ask.value == "Cancel")
		return
	var/mob/user = src
	var/list/music_extra_data = ask.extra
	var/show = ask.show
	var/song_title = ask.song_title
	var/page = ask.page
	var/credit = ask.credit
	var/input = ask.input
	var/url = ask.url
	var/duration = ask.duration
	if(show == "Yes")
		music_extra_data["title"] = song_title
	else
		music_extra_data["link"] = "Song Link Hidden"
		music_extra_data["title"] = "Song Title Hidden"
		music_extra_data["artist"] = "Song Artist Hidden"
		music_extra_data["upload_date"] = "Song Upload Date Hidden"
		music_extra_data["album"] = "Song Album Hidden"
	switch(ask.value)
		if("Yes")
			if(show == "Yes")
				to_chat(world, span_boldannounce("[user.key] played: [page]"), confidential = TRUE)
			else
				to_chat(world, span_boldannounce("[user.key] played a sound"), confidential = TRUE)
		if("No")
			if(show == "Yes")
				to_chat(world, span_boldannounce("An admin played: [page]"), confidential = TRUE)
	if(credit)
		to_chat(world, span_boldannounce("[credit]"), confidential = TRUE)
	log_admin("[key_name(user)] played web sound: [input]")
	message_admins("[key_name(user)] played web sound: [input]")
	if(url)
		web_sound_play(user, url, music_extra_data, duration)

/// Plays the web sound for everyone with admin music on, or stops it when `web_sound_url` is null.
/proc/web_sound_play(mob/user, web_sound_url, list/music_extra_data, duration)
	var/stop_web_sounds = !web_sound_url
	if(web_sound_url && !findtext(web_sound_url, GLOB.is_http_protocol))
		var/mob/notification_actor
		if(istext(user))
			stack_trace("tgui_alert() received text for user instead of list")
		else if(istype(user, /mob))
			notification_actor = user
		else if(istype(user, /client))
			var/client/notification_client = user
			notification_actor = notification_client.mob
		if(notification_actor)
			open_request(notification_actor, /datum/prompt/choice/web_sound_security_notification, null, answerer = notification_actor, question = "The media provider returned a content URL that isn't using the HTTP or HTTPS protocol. This is a security risk and the sound will not be played.", title = "Security Risk", choices = list("OK"))
		to_chat(user, span_boldwarning("BLOCKED: Content URL not using HTTP(S) Protocol!"), confidential = TRUE)
		return
	for(var/m in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		var/mob/M = m
		var/client/C = M.client
		if(!C)
			continue
		if(C.prefs?.read_preference(/datum/preference/toggle/play_admin_midis))
			if(!stop_web_sounds)
				C.tgui_panel?.play_music(web_sound_url, music_extra_data)
			else
				C.tgui_panel?.stop_music()

	COOLDOWN_START(GLOB, internet_sound_cooldown, duration)

	feedback_add_details("admin_verb", "Play Internet Sound")

ADMIN_VERB(play_web_sound, R_SOUNDS, "Play Internet Sound", "Plays a sound from the internet to all players.", ADMIN_CATEGORY_FUN_SOUNDS)
	// Only this verb's actual ended native request supplies replay answers.
	var/list/replay_answers = list()
	if(length(args) > 1)
		var/datum/request/resumed = args[2]
		if((istype(resumed, /datum/prompt/choice/admin_web_sound_replay) || istype(resumed, /datum/prompt/text/admin_web_sound_replay)) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(play_web_sound_replay_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	var/ytdl = CONFIG_GET(string/invoke_youtubedl)
	if(!ytdl)
		to_chat(user, span_boldwarning("Youtube-dl was not configured, action unavailable"), confidential = TRUE) //Check config.txt for the INVOKE_YOUTUBEDL value
		return

	if(COOLDOWN_TIMELEFT(GLOB, internet_sound_cooldown))
		if(!("override" in replay_answers))
			open_request(src, /datum/prompt/choice/admin_web_sound_replay, PROC_REF(play_web_sound_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "override", buttons = TRUE, question = "Someone else is already playing an Internet sound! It has [DisplayTimeText(COOLDOWN_TIMELEFT(GLOB, internet_sound_cooldown), 1)] remaining. Would you like to override?", title = "Musicalis Interruptus", choices = list("No","Yes"))
			return
		var/override = replay_answers["override"]
		if(override != "Yes")
			return

	if(!("a6" in replay_answers))
		open_request(src, /datum/prompt/text/admin_web_sound_replay, PROC_REF(play_web_sound_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a6", question = "Enter content URL (supported sites only, leave blank to stop playing)", title = "Play Internet Sound")
		return
	var/web_sound_input = replay_answers["a6"]
	if(isnull(web_sound_input))
		return

	if(length(web_sound_input))
		web_sound_input = trim(web_sound_input)
		if(findtext(web_sound_input, ":") && !findtext(web_sound_input, GLOB.is_http_protocol))
			to_chat(user, span_boldwarning("Non-http(s) URIs are not allowed."), confidential = TRUE)
			to_chat(user, span_warning("For youtube-dl shortcuts like ytsearch: please use the appropriate full URL from the website."), confidential = TRUE)
			return
		web_sound(user.mob, web_sound_input)
	else
		web_sound(user.mob, null)

ADMIN_VERB(stop_sounds, R_SOUNDS, "Stop All Playing Sounds", "Stops all playing sounds.", ADMIN_CATEGORY_FUN_SOUNDS)
	log_and_message_admins("stopped all currently playing sounds.", user)
	for(var/mob/current_mob in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		SEND_SOUND(current_mob, sound(null))
		var/client/current_client = current_mob.client
		current_client?.tgui_panel?.stop_music()

	COOLDOWN_RESET(GLOB, internet_sound_cooldown)
	feedback_add_details("admin_verb", "Stop All Playing Sounds")

//world/proc/shelleo
#undef SHELLEO_ERRORLEVEL
#undef SHELLEO_STDOUT
#undef SHELLEO_STDERR


/datum/prompt/choice/admin_web_sound_replay
	timeout = 0
	rights = R_SOUNDS
	recheck_on_open = TRUE

/datum/prompt/choice/admin_web_sound_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_web_sound_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_web_sound_replay/refusal(given)
	return null

/datum/prompt/text/admin_web_sound_replay
	timeout = 0
	rights = R_SOUNDS
	recheck_on_open = TRUE

/datum/prompt/text/admin_web_sound_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/text/admin_web_sound_replay/normalize(given)
	return istext(given) ? given : null

/datum/admin_verb/play_web_sound/proc/play_web_sound_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)

/datum/prompt/choice/admin_global_sound_replay
	timeout = 0
	rights = R_SOUNDS
	buttons = TRUE
	recheck_on_open = TRUE

/datum/prompt/choice/admin_global_sound_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_global_sound_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_global_sound_replay/refusal(given)
	return null

/datum/admin_verb/play_sound/proc/play_sound_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer.captured["original_sound"], A.answer)

/datum/prompt/choice/admin_z_sound_replay
	timeout = 0
	rights = R_SOUNDS
	buttons = TRUE
	recheck_on_open = TRUE

/datum/prompt/choice/admin_z_sound_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_z_sound_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_z_sound_replay/refusal(given)
	return null

/datum/admin_verb/play_z_sound/proc/play_z_sound_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer.captured["original_sound"], A.answer)

/datum/prompt/number/admin_global_sound_replay
	timeout = 0
	rights = R_SOUNDS
	recheck_on_open = TRUE

/datum/prompt/number/admin_global_sound_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/number/admin_global_sound_replay/normalize(given)
	return isnum(given) ? given : null

/datum/prompt/number/admin_global_sound_replay/refusal(given)
	return null

/datum/prompt/choice/web_sound_security_notification
	timeout = 0
	buttons = TRUE
	recheck_on_open = TRUE

/datum/prompt/choice/web_sound_security_notification/recheck_extra()
	return answerer?.client ? null : "gone"
