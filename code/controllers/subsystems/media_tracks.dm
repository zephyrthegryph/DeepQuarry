SUBSYSTEM_DEF(media_tracks)
	name = "Media Tracks"
	flags = SS_NO_FIRE
	init_stage = INITSTAGE_EARLY

	/// Every track, including secret
	var/list/all_tracks = list()
	/// Non-secret jukebox tracks
	var/list/jukebox_tracks = list()
	/// Lobby music tracks
	var/list/lobby_tracks = list()
	/// CHOMPstation edit start: Jack - Injecting casino track into new jukebox subsystem
	var/list/casino_tracks = list()
	/// CHOMPstation edit end

/datum/controller/subsystem/media_tracks/Initialize()
	load_tracks()
	sort_tracks()
	return SS_INIT_SUCCESS

/datum/controller/subsystem/media_tracks/proc/load_tracks()
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

			/// CHOMPstation edit start: Jack - Injecting casino track into new jukebox subsystem
			T.casino = entry["casino"] ? 1 : 0
			/// CHOMPstation edit end

			all_tracks += T

/datum/controller/subsystem/media_tracks/proc/sort_tracks()
	report_progress("Sorting media tracks...")
	sortTim(all_tracks, GLOBAL_PROC_REF(cmp_media_track_asc))

	jukebox_tracks.Cut()
	lobby_tracks.Cut()
	/// CHOMPstation edit start: Jack - Injecting casino track into new jukebox subsystem
	casino_tracks.Cut()
	/// CHOMPstation edit end

	for(var/datum/track/T in all_tracks)
		/// CHOMPstation edit start: Jack - Injecting casino track into new jukebox subsystem
		if(!T.secret && !T.casino)
			jukebox_tracks += T
		if(T.lobby)
			lobby_tracks += T
		if(T.casino)
			casino_tracks += T
		/// CHOMPstation edit end

/datum/controller/subsystem/media_tracks/proc/manual_track_add()
	if(!check_rights(R_DEBUG|R_FUN))
		return

	om_prompt_sequence(src, usr, list(
		list("key" = "url", "kind" = "text", "message" = "REQUIRED: Provide URL for track, or paste JSON if you know what you're doing. See code comments.", "title" = "Track URL", "multiline" = TRUE),
		PROC_REF(manual_track_ask_title),
		PROC_REF(manual_track_ask_duration),
		PROC_REF(manual_track_ask_artist),
		PROC_REF(manual_track_ask_genre),
		PROC_REF(manual_track_ask_secret),
		PROC_REF(manual_track_ask_lobby),
		PROC_REF(manual_track_ask_casino),
	), PROC_REF(manual_track_entered), list("requires" = PROMPT_ADMIN(R_DEBUG|R_FUN)))

/// Pasted JSON skips the remaining questions.
/datum/controller/subsystem/media_tracks/proc/manual_track_is_json(datum/om/prompt/ask)
	var/url = ask.get("url")
	if(!url)
		return TRUE
	var/json
	try
		json = json_decode(url)
	catch // ALLOW(silent_catch): malformed input is the expected failure; the caller handles null
	return islist(json)

/datum/controller/subsystem/media_tracks/proc/manual_track_ask_title(mob/user, datum/om/prompt/ask)
	if(manual_track_is_json(ask))
		return PROMPT_STOP
	return list("key" = "title", "kind" = "text", "message" = "REQUIRED: Provide title for track", "title" = "Track Title")

/datum/controller/subsystem/media_tracks/proc/manual_track_ask_duration(mob/user, datum/om/prompt/ask)
	if(!ask.get("title"))
		return PROMPT_STOP
	return list("key" = "duration", "kind" = "number", "message" = "REQUIRED: Provide duration for track (in deciseconds, aka seconds*10)", "title" = "Track Duration")

/datum/controller/subsystem/media_tracks/proc/manual_track_ask_artist(mob/user, datum/om/prompt/ask)
	if(!ask.get("duration"))
		return PROMPT_STOP
	return list("key" = "artist", "kind" = "text", "message" = "Optional: Provide artist for track", "title" = "Track Artist")

/datum/controller/subsystem/media_tracks/proc/manual_track_ask_genre(mob/user, datum/om/prompt/ask)
	return list("key" = "genre", "kind" = "text", "message" = "Optional: Provide genre for track (try to match an existing one)", "title" = "Track Genre")

/datum/controller/subsystem/media_tracks/proc/manual_track_ask_secret(mob/user, datum/om/prompt/ask)
	return list("key" = "secret", "message" = "Optional: Mark track as secret?", "title" = "Track Secret", "choices" = list("Yes", "Cancel", "No"), "abort" = "Cancel")

/datum/controller/subsystem/media_tracks/proc/manual_track_ask_lobby(mob/user, datum/om/prompt/ask)
	return list("key" = "lobby", "message" = "Optional: Mark track as lobby music?", "title" = "Track Lobby", "choices" = list("Yes", "Cancel", "No"), "abort" = "Cancel")

/datum/controller/subsystem/media_tracks/proc/manual_track_ask_casino(mob/user, datum/om/prompt/ask)
	return list("key" = "casino", "message" = "Optional: Mark track as casino music?", "title" = "Track Casino", "choices" = list("Yes", "Cancel", "No"), "abort" = "Cancel")

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
/datum/controller/subsystem/media_tracks/proc/manual_track_entered(mob/user, datum/om/prompt/ask)
	var/url = ask.get("url")
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

	var/title = ask.get("title")
	var/duration = ask.get("duration")
	if(!title || !duration)
		return
	var/datum/track/T = new(url, title, duration, ask.get("artist"), ask.get("genre"))
	T.secret = ask.get("secret") == "Yes"
	T.lobby = ask.get("lobby") == "Yes"
	T.casino = ask.get("casino") == "Yes"

	all_tracks += T

	report_progress("New media track added by [user.client]: [title]")
	sort_tracks()

/datum/controller/subsystem/media_tracks/proc/manual_track_remove()
	if(!check_rights(R_DEBUG|R_FUN))
		return

	om_prompt(src, usr, list("kind" = "text", "message" = "Input track title or URL to remove (must be exact)", "title" = "Remove Track", "requires" = PROMPT_ADMIN(R_DEBUG|R_FUN)), PROC_REF(manual_track_removal_entered))

/datum/controller/subsystem/media_tracks/proc/manual_track_removal_entered(mob/user, track, datum/om/prompt/ask)
	if(!track)
		return

	for(var/datum/track/T in all_tracks)
		if(T.title == track || T.url == track)
			all_tracks -= T
			qdel(T)
			report_progress("Media track removed by [user.client]: [track]")
			sort_tracks()
			return

	to_chat(user, span_warning("Couldn't find a track matching the specified parameters."))

/datum/controller/subsystem/media_tracks/proc/add_track(mob/user, new_url, new_title, new_duration, new_artist, new_genre, new_secret, new_lobby)
	if(!check_rights(R_DEBUG|R_FUN))
		return
	var/datum/track/T = new(new_url, new_title, new_duration, new_artist, new_genre, new_secret, new_lobby)
	all_tracks += T
	report_progress("Media track added by [user]: [T.title]")
	sort_tracks()
	return

/datum/controller/subsystem/media_tracks/proc/remove_track(mob/user, datum/track/T)
	if(!check_rights(R_DEBUG|R_FUN))
		return

	if(!T)
		return

	report_progress("Media track removed by [user]: [T.title]")
	all_tracks -= T
	qdel(T)
	sort_tracks()
	return

/datum/controller/subsystem/media_tracks/vv_get_dropdown()
	. = ..()
	VV_DROPDOWN_OPTION("", "---")
	VV_DROPDOWN_OPTION("add_track", "Add New Track")
	VV_DROPDOWN_OPTION("remove_track", "Remove Track")

/datum/controller/subsystem/media_tracks/vv_do_topic(list/href_list)
	. = ..()
	IF_VV_OPTION("add_track")
		manual_track_add()
		href_list[VV_HK_DATUM_REFRESH] = "\ref[src]"
	IF_VV_OPTION("remove_track")
		manual_track_remove()
		href_list[VV_HK_DATUM_REFRESH] = "\ref[src]"
