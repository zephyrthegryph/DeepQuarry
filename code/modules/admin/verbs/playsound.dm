//world/proc/shelleo
#define SHELLEO_ERRORLEVEL 1
#define SHELLEO_STDOUT 2
#define SHELLEO_STDERR 3

GLOBAL_LIST_EMPTY(sounds_cache)

ADMIN_VERB(play_sound, R_SOUNDS, "Play Global Sound", "Plays a sound to all players.", ADMIN_CATEGORY_FUN_SOUNDS, S as sound)
	var/freq = 1
	var/vol = verb_prompt(user, "a1", list("kind" = "number", "message" = "What volume would you like the sound to play at?", "default" = 100, "max" = 100, "min" = 1), args)
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

	var/res = verb_prompt(user, "a2", list("message" = "Show the title of this song ([S]) to the players?\nOptions 'Yes' and 'No' will play the sound.", "choices" = list("Yes", "No", "Cancel")), args)
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
	var/mob/target_mob = verb_prompt(user, "a3", list("kind" = "list", "message" = "Choose a mob to play the sound to. Only they will hear it.", "title" = "Play Mob Sound", "choices" = sortNames(REGISTRY_MEMBERS(REGISTRY_PLAYERS))), args)
	if(isnull(target_mob))
		return
	if(QDELETED(target_mob))
		return
	log_admin("[key_name(user)] played a direct mob sound [S] to [target_mob].")
	message_admins("[key_name_admin(user)] played a direct mob sound [S] to [ADMIN_LOOKUPFLW(target_mob)].")
	SEND_SOUND(target_mob, S)
	feedback_add_details("admin_verb", "Play Direct Mob Sound")

ADMIN_VERB(play_z_sound, R_SOUNDS, "Play Z Sound", "Plays a sound to a single z-level.", ADMIN_CATEGORY_FUN_SOUNDS, S as sound)
	var/target_z = user.mob.z
	var/sound/uploaded_sound = sound(S, repeat = 0, wait = 1, channel = 777)
	uploaded_sound.priority = 250

	GLOB.sounds_cache += S

	var/_answer_a4 = verb_prompt(user, "a4", list("message" = "Do you ready?\nSong: [S]\nNow you can also play this sound using \"Play Server Sound\".", "title" = "Confirmation request", "choices" = list("Play","Cancel")), args)
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

	var/melody = verb_prompt(user, "a5", list("kind" = "list", "message" = "Select a sound from the server to play", "title" = "Server sound list", "choices" = sounds, "default" = "--CANCEL--"), args)
	if(isnull(melody))
		return

	if(!melody || melody == "--CANCEL--")
		return

	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/play_sound, melody)
	feedback_add_details("admin_verb", "Play Server Sound") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

///Takes an input from either proc/play_web_sound or the request manager and runs it through youtube-dl and prompts the user before playing it to the server.
/proc/web_sound(mob/user, input, credit)
	if(!check_rights(R_SOUNDS))
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
	var/list/output = world.shelleo("[ytdl] --geo-bypass --format \"bestaudio\[ext=mp3]/best\[ext=mp4]\[height <= 360]/bestaudio\[ext=m4a]/bestaudio\[ext=aac]\" --dump-single-json --no-playlist -- \"[shell_scrubbed_input]\"")
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
	catch(var/exception/e)
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
	// youtube-dl has answered; the questions come now, and web_sound_answered() plays it.
	om_prompt_sequence(user, user, list(
		duration > 10 MINUTES ? list("key" = "long", "message" = "This song is over 10 minutes long. Are you sure you want to play it?", "title" = "Length Warning!", "choices" = list("No", "Yes", "Cancel"), "confirm" = "Yes") : null,
		list("key" = "show", "message" = "Show the title of and link to this song to the players?\n[title]", "title" = "Show Info?", "choices" = list("Yes", "No", "Cancel"), "abort" = "Cancel"),
		list("key" = "anon", "message" = "Display who played the song?", "title" = "Credit Yourself?", "choices" = list("Yes", "No", "Cancel"), "abort" = "Cancel"),
	), GLOBAL_PROC_REF(web_sound_answered), list("requires" = PROMPT_ADMIN(R_SOUNDS), "data" = list("url" = web_sound_url, "extra" = music_extra_data, "page" = webpage_url, "title" = data["title"], "duration" = duration, "credit" = credit, "input" = input)))

/proc/web_sound_answered(mob/owner, mob/user, datum/om/prompt/ask)
	var/list/music_extra_data = ask.get("extra")
	var/res = ask.get("show")
	var/webpage_url = ask.get("page")
	if(res == "Yes")
		music_extra_data["title"] = ask.get("title")
	else
		music_extra_data["link"] = "Song Link Hidden"
		music_extra_data["title"] = "Song Title Hidden"
		music_extra_data["artist"] = "Song Artist Hidden"
		music_extra_data["upload_date"] = "Song Upload Date Hidden"
		music_extra_data["album"] = "Song Album Hidden"
	switch(ask.get("anon"))
		if("Yes")
			if(res == "Yes")
				to_chat(world, span_boldannounce("[user.key] played: [webpage_url]"), confidential = TRUE)
			else
				to_chat(world, span_boldannounce("[user.key] played a sound"), confidential = TRUE)
		if("No")
			if(res == "Yes")
				to_chat(world, span_boldannounce("An admin played: [webpage_url]"), confidential = TRUE)
	var/credit = ask.get("credit")
	if(credit)
		to_chat(world, span_boldannounce("[credit]"), confidential = TRUE)
	//SSblackbox.record_feedback("nested tally", "played_url", 1, list("[user.ckey]", "[input]"))
	log_admin("[key_name(user)] played web sound: [ask.get("input")]")
	message_admins("[key_name(user)] played web sound: [ask.get("input")]")
	if(ask.get("url"))
		web_sound_play(user, ask.get("url"), music_extra_data, ask.get("duration"))

/// Plays the web sound for everyone with admin music on, or stops it when `web_sound_url` is null.
/proc/web_sound_play(mob/user, web_sound_url, list/music_extra_data, duration)
	var/stop_web_sounds = !web_sound_url
	if(web_sound_url && !findtext(web_sound_url, GLOB.is_http_protocol))
		tgui_alert_async(user, "The media provider returned a content URL that isn't using the HTTP or HTTPS protocol. This is a security risk and the sound will not be played.", "Security Risk", list("OK"))
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

	S_TIMER_COOLDOWN_START(SStimer, COOLDOWN_INTERNET_SOUND, duration)

	feedback_add_details("admin_verb", "Play Internet Sound")

ADMIN_VERB(play_web_sound, R_SOUNDS, "Play Internet Sound", "Plays a sound from the internet to all players.", ADMIN_CATEGORY_FUN_SOUNDS)
	var/ytdl = CONFIG_GET(string/invoke_youtubedl)
	if(!ytdl)
		to_chat(user, span_boldwarning("Youtube-dl was not configured, action unavailable"), confidential = TRUE) //Check config.txt for the INVOKE_YOUTUBEDL value
		return

	if(S_TIMER_COOLDOWN_TIMELEFT(SStimer, COOLDOWN_INTERNET_SOUND))
		var/override = verb_prompt(user, "override", list("message" = "Someone else is already playing an Internet sound! It has [DisplayTimeText(S_TIMER_COOLDOWN_TIMELEFT(SStimer, COOLDOWN_INTERNET_SOUND), 1)] remaining. Would you like to override?", "title" = "Musicalis Interruptus", "choices" = list("No","Yes")), args)
		if(override != "Yes")
			return

	var/web_sound_input = verb_prompt(user, "a6", list("kind" = "text", "message" = "Enter content URL (supported sites only, leave blank to stop playing)", "title" = "Play Internet Sound"), args)
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

	S_TIMER_COOLDOWN_RESET(SStimer, COOLDOWN_INTERNET_SOUND)
	feedback_add_details("admin_verb", "Stop All Playing Sounds")

//world/proc/shelleo
#undef SHELLEO_ERRORLEVEL
#undef SHELLEO_STDOUT
#undef SHELLEO_STDERR

