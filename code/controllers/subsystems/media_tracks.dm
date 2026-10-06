SYSTEM_DEF(media_tracks)
	name = "Media Tracks"
	init_stage = INITSTAGE_EARLY

	/// Every track, including secret
	var/list/all_tracks = list()
	/// Non-secret jukebox tracks
	var/list/jukebox_tracks = list()
	/// Lobby music tracks
	var/list/lobby_tracks = list()
	/// Casino jukebox tracks.
	var/list/casino_tracks = list()

/datum/system/media_tracks/initialize()
	load_tracks()
	sort_tracks()

/datum/system/media_tracks/proc/load_tracks()
	for(var/filename in CONFIG_GET(str_list/jukebox_track_files))
		report_progress("Loading jukebox track: [filename]")

		if(!fexists(filename))
			log_world("## ERROR File not found: [filename]")
			continue

		var/list/jsonData = json_decode(file2text(filename))

		if(!istype(jsonData))
			log_world("## ERROR Failed to read tracks from [filename], json_decode failed.")
			continue

		for(var/entry in jsonData)

			// Critical problems that will prevent the track from working
			if(!istext(entry["url"]))
				log_world("## ERROR Jukebox entry in [filename]: bad or missing 'url'. Tracks must have a URL.")
				continue
			if(!istext(entry["title"]))
				log_world("## ERROR Jukebox entry in [filename]: bad or missing 'title'. Tracks must have a title.")
				continue
			if(!isnum(entry["duration"]))
				log_world("## ERROR Jukebox entry in [filename]: bad or missing 'duration'. Tracks must have a duration (in deciseconds).")
				continue

			// Noncritical problems, we can keep going anyway, but warn so it can be fixed
			if(!istext(entry["artist"]))
				WARNING("Jukebox entry in [filename], [entry["title"]]: bad or missing 'artist'. Please consider crediting the artist.")
			if(!istext(entry["genre"]))
				WARNING("Jukebox entry in [filename], [entry["title"]]: bad or missing 'genre'. Please consider adding a genre.")

			var/datum/track/T = new(entry["url"], entry["title"], entry["duration"], entry["artist"], entry["genre"])

			T.secret = entry["secret"] ? 1 : 0
			T.lobby = entry["lobby"] ? 1 : 0

			T.casino = entry["casino"] ? 1 : 0

			all_tracks += T

/datum/system/media_tracks/proc/sort_tracks()
	report_progress("Sorting media tracks...")
	sortTim(all_tracks, GLOBAL_PROC_REF(cmp_media_track_asc))

	jukebox_tracks.Cut()
	lobby_tracks.Cut()
	casino_tracks.Cut()

	for(var/datum/track/T in all_tracks)
		if(!T.secret && !T.casino)
			jukebox_tracks += T
		if(T.lobby)
			lobby_tracks += T
		if(T.casino)
			casino_tracks += T

/datum/system/media_tracks/proc/manual_track_add(mob/user)
	if(!admin_require(user?.client, R_DEBUG|R_FUN, "check_rights in [callee?.proc]"))
		return

	om_flow_start(/datum/om/flow/media_track_add, user, null, tracks = src)

/// An admin adds a media track: the URL (or pasted JSON, which ends the questions), then the
/// title, duration, artist, genre and the secret/lobby/casino marks. A cancel ends it.
/datum/om/flow/media_track_add
	requires = PROMPT_ADMIN(R_DEBUG|R_FUN)
	var/datum/system/media_tracks/tracks
	var/url
	var/title
	var/duration
	var/artist
	var/genre
	var/secret
	var/lobby

/// The admin-only text questions of adding a track.
/datum/om/prompt/text/media_track
	requires = PROMPT_ADMIN(R_DEBUG|R_FUN)
	max_length = MAX_TGUI_INPUT

/datum/om/flow/media_track_add/start()
	om_ask(actor, /datum/om/prompt/text/media_track, PROC_REF(url_entered), title = "Track URL", message = "REQUIRED: Provide URL for track, or paste JSON if you know what you're doing. See code comments.", multiline = TRUE)

/datum/om/flow/media_track_add/proc/url_entered(datum/om/prompt/text/media_track/ask)
	url = ask.text
	if(!url)
		return
	var/json
	try
		json = json_decode(url)
	catch // ALLOW(silent_catch): malformed input is the expected failure; the caller handles null
	if(islist(json))
		tracks.manual_track_entered(actor, src)
		return
	om_ask(actor, /datum/om/prompt/text/media_track, PROC_REF(title_entered), title = "Track Title", message = "REQUIRED: Provide title for track")

/datum/om/flow/media_track_add/proc/title_entered(datum/om/prompt/text/media_track/ask)
	title = ask.text
	if(!title)
		return
	om_ask(actor, /datum/om/prompt/number, PROC_REF(duration_entered), title = "Track Duration", message = "REQUIRED: Provide duration for track (in deciseconds, aka seconds*10)", requires = PROMPT_ADMIN(R_DEBUG|R_FUN))

/datum/om/flow/media_track_add/proc/duration_entered(datum/om/prompt/number/ask)
	duration = ask.number
	if(!duration)
		return
	om_ask(actor, /datum/om/prompt/text/media_track, PROC_REF(artist_entered), title = "Track Artist", message = "Optional: Provide artist for track")

/datum/om/flow/media_track_add/proc/artist_entered(datum/om/prompt/text/media_track/ask)
	artist = ask.text
	om_ask(actor, /datum/om/prompt/text/media_track, PROC_REF(genre_entered), title = "Track Genre", message = "Optional: Provide genre for track (try to match an existing one)")

/datum/om/flow/media_track_add/proc/genre_entered(datum/om/prompt/text/media_track/ask)
	genre = ask.text
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(secret_chosen), title = "Track Secret", message = "Optional: Mark track as secret?", requires = PROMPT_ADMIN(R_DEBUG|R_FUN), buttons = TRUE, choices = list("Yes", "Cancel", "No"))

/datum/om/flow/media_track_add/proc/secret_chosen(datum/om/prompt/choice/ask)
	if(ask.choice == "Cancel")
		return
	secret = (ask.choice == "Yes")
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(lobby_chosen), title = "Track Lobby", message = "Optional: Mark track as lobby music?", requires = PROMPT_ADMIN(R_DEBUG|R_FUN), buttons = TRUE, choices = list("Yes", "Cancel", "No"))

/datum/om/flow/media_track_add/proc/lobby_chosen(datum/om/prompt/choice/ask)
	if(ask.choice == "Cancel")
		return
	lobby = (ask.choice == "Yes")
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(casino_chosen), title = "Track Casino", message = "Optional: Mark track as casino music?", requires = PROMPT_ADMIN(R_DEBUG|R_FUN), buttons = TRUE, choices = list("Yes", "Cancel", "No"))

/datum/om/flow/media_track_add/proc/casino_chosen(datum/om/prompt/choice/ask)
	if(ask.choice == "Cancel")
		return
	tracks.manual_track_entered(actor, src, ask.choice == "Yes")

/**
 * Alternatively to using a series of inputs, you can use json and paste it in.
 * The json base element needs to be an array, even if it's only one song, so wrap it in []
 * The songs are json object literals inside the base array and use these keys:
 * "url": the url for the song (REQUIRED) (text)
 * "title": the title of the song (REQUIRED) (text)
 * "duration": duration of song in 1/10ths of a second (seconds * 10) (REQUIRED) (number)
 * "artist": artist of the song (text)
 * "genre": artist of the song, REALLY try to match an existing one (text)
 * "secret": only on hacked jukeboxes (true/false)
 * "lobby": plays in the lobby (true/false)
 * "casino": plays in the casino (true/false)
 */
/datum/system/media_tracks/proc/manual_track_entered(mob/user, datum/om/flow/media_track_add/answers, casino = FALSE)
	var/url = answers.url
	if(!url)
		return
	var/list/json
	try
		json = json_decode(url)
	catch // ALLOW(silent_catch): malformed input is the expected failure; the caller handles null

	if(islist(json))
		for(var/song in json)
			if(!islist(song))
				to_chat(user, span_warning("Song appears to be malformed."))
				continue
			var/list/songdata = song
			if(!songdata["url"] || !songdata["title"] || !songdata["duration"])
				to_chat(user, span_warning("URL, Title, or Duration was missing from a song. Skipping."))
				continue
			var/datum/track/T = new(songdata["url"], songdata["title"], songdata["duration"], songdata["artist"], songdata["genre"], songdata["secret"], songdata["lobby"], songdata["casino"])
			all_tracks += T

			report_progress("New media track added by [user.client]: [T.title]")
		sort_tracks()
		return

	var/title = answers.title
	var/duration = answers.duration
	if(!title || !duration)
		return
	var/datum/track/T = new(url, title, duration, answers.artist, answers.genre)
	T.secret = answers.secret
	T.lobby = answers.lobby
	T.casino = casino

	all_tracks += T

	report_progress("New media track added by [user.client]: [title]")
	sort_tracks()

/datum/system/media_tracks/proc/manual_track_remove(mob/user)
	if(!admin_require(user?.client, R_DEBUG|R_FUN, "check_rights in [callee?.proc]"))
		return

	om_ask(user, /datum/om/prompt/text/media_track, PROC_REF(manual_track_removal_entered), title = "Remove Track", message = "Input track title or URL to remove (must be exact)")

/datum/system/media_tracks/proc/manual_track_removal_entered(datum/om/prompt/text/media_track/ask)
	var/mob/user = ask.answerer
	var/track = ask.text
	if(!track)
		return

	for(var/datum/track/T in all_tracks)
		if(T.title == track || T.url == track)
			all_tracks -= T
			spent(T)
			report_progress("Media track removed by [user.client]: [track]")
			sort_tracks()
			return

	to_chat(user, span_warning("Couldn't find a track matching the specified parameters."))

/datum/system/media_tracks/proc/add_track(mob/user, new_url, new_title, new_duration, new_artist, new_genre, new_secret, new_lobby)
	if(!admin_require(user.client, R_DEBUG|R_FUN, "add_track", TRUE))
		return
	var/datum/track/T = new(new_url, new_title, new_duration, new_artist, new_genre, new_secret, new_lobby)
	all_tracks += T
	report_progress("Media track added by [user]: [T.title]")
	sort_tracks()
	return

/datum/system/media_tracks/proc/remove_track(mob/user, datum/track/T)
	if(!admin_require(user.client, R_DEBUG|R_FUN, "remove_track", TRUE))
		return

	if(!T)
		return

	report_progress("Media track removed by [user]: [T.title]")
	all_tracks -= T
	spent(T, user)
	sort_tracks()
	return

/datum/system/media_tracks/vv_get_dropdown()
	. = ..()
	VV_DROPDOWN_OPTION("", "---")
	VV_DROPDOWN_OPTION("add_track", "Add New Track")
	VV_DROPDOWN_OPTION("remove_track", "Remove Track")

VV_TOPIC_ACTION(/datum/system/media_tracks, "add_track", PROC_REF(vv_topic_add_track))
VV_TOPIC_ACTION(/datum/system/media_tracks, "remove_track", PROC_REF(vv_topic_remove_track))

/datum/system/media_tracks/proc/vv_topic_add_track(mob/user, list/args)
	manual_track_add(user)
	user.client?.debug_variables(src)
	return TRUE

/datum/system/media_tracks/proc/vv_topic_remove_track(mob/user, list/args)
	manual_track_remove(user)
	user.client?.debug_variables(src)
	return TRUE
