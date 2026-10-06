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

	var/datum/media_track_add/adding = new
	adding.ask_text(user, TYPE_PROC_REF(/datum/media_track_add, url_entered), "Track URL", "REQUIRED: Provide URL for track, or paste JSON if you know what you're doing. See code comments.", TRUE)

/// An admin adds a media track: the URL (or pasted JSON, which ends the questions), then the title, duration, artist, genre and the
/// secret/lobby/casino marks. Each question is a request this record owns (the open request keeps it, and its answerer is the admin);
/// a cancel, or an admin who lost the rights, ends it.
/datum/media_track_add
	var/url
	var/title
	var/duration
	var/artist
	var/genre
	var/secret
	var/lobby

/// The admin-only text questions of adding a track.
/datum/prompt/text/media_track
	max_len = MAX_TGUI_INPUT
	timeout = 0
	rights = R_DEBUG|R_FUN
	recheck_on_open = TRUE

/// The admin-only choices of adding a track.
/datum/prompt/choice/media_track
	buttons = TRUE
	timeout = 0
	rights = R_DEBUG|R_FUN
	recheck_on_open = TRUE

/datum/media_track_add/proc/ask_text(mob/user, handler, title, question, multiline = FALSE)
	open_request(src, /datum/prompt/text/media_track, handler, answerer = user, title = title, question = question, multiline = multiline)

/datum/media_track_add/proc/ask_mark(mob/user, handler, title, question)
	open_request(src, /datum/prompt/choice/media_track, handler, answerer = user, title = title, question = question, choices = list("Yes", "Cancel", "No"))

/datum/media_track_add/proc/url_entered(datum/act/request/A)
	url = A.answer?.value
	if(!url)
		return
	var/json
	try
		json = json_decode(url)
	catch // ALLOW(silent_catch): malformed input is the expected failure; the caller handles null
	if(islist(json))
		SSmedia_tracks.manual_track_entered(A.request.answerer, src)
		return
	ask_text(A.request.answerer, PROC_REF(title_entered), "Track Title", "REQUIRED: Provide title for track")

/datum/media_track_add/proc/title_entered(datum/act/request/A)
	title = A.answer?.value
	if(!title)
		return
	open_request(src, /datum/prompt/number, PROC_REF(duration_entered), answerer = A.request.answerer, title = "Track Duration", question = "REQUIRED: Provide duration for track (in deciseconds, aka seconds*10)", timeout = 0, rights = R_DEBUG|R_FUN, recheck_on_open = TRUE)

/datum/media_track_add/proc/duration_entered(datum/act/request/A)
	duration = A.answer?.value
	if(!duration)
		return
	ask_text(A.request.answerer, PROC_REF(artist_entered), "Track Artist", "Optional: Provide artist for track")

/datum/media_track_add/proc/artist_entered(datum/act/request/A)
	if(!A.answer)
		return
	artist = A.answer.value
	ask_text(A.request.answerer, PROC_REF(genre_entered), "Track Genre", "Optional: Provide genre for track (try to match an existing one)")

/datum/media_track_add/proc/genre_entered(datum/act/request/A)
	if(!A.answer)
		return
	genre = A.answer.value
	ask_mark(A.request.answerer, PROC_REF(secret_chosen), "Track Secret", "Optional: Mark track as secret?")

/datum/media_track_add/proc/secret_chosen(datum/act/request/A)
	var/choice = A.answer?.value
	if(!choice || choice == "Cancel")
		return
	secret = (choice == "Yes")
	ask_mark(A.request.answerer, PROC_REF(lobby_chosen), "Track Lobby", "Optional: Mark track as lobby music?")

/datum/media_track_add/proc/lobby_chosen(datum/act/request/A)
	var/choice = A.answer?.value
	if(!choice || choice == "Cancel")
		return
	lobby = (choice == "Yes")
	ask_mark(A.request.answerer, PROC_REF(casino_chosen), "Track Casino", "Optional: Mark track as casino music?")

/datum/media_track_add/proc/casino_chosen(datum/act/request/A)
	var/choice = A.answer?.value
	if(!choice || choice == "Cancel")
		return
	SSmedia_tracks.manual_track_entered(A.request.answerer, src, choice == "Yes")

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
/datum/system/media_tracks/proc/manual_track_entered(mob/user, datum/media_track_add/answers, casino = FALSE)
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

	open_request(src, /datum/prompt/text/media_track, PROC_REF(manual_track_removal_entered), answerer = user, title = "Remove Track", question = "Input track title or URL to remove (must be exact)")

/datum/system/media_tracks/proc/manual_track_removal_entered(datum/act/request/A)
	var/mob/user = A.request.answerer
	var/track = A.answer?.value
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
