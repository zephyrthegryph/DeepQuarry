/// Ordered selections are detached, but refer to the same track datums.
/datum/system/media_tracks/proc/tracks_for_jukebox(unrestricted = FALSE)
	return unrestricted ? all_tracks.Copy() : jukebox_tracks.Copy()

/datum/system/media_tracks/proc/tracks_for_casino()
	return casino_tracks.Copy()

/datum/system/media_tracks/proc/has_lobby_tracks()
	return length(lobby_tracks) > 0
