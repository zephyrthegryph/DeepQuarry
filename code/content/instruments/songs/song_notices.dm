// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// Sent to the instrument when a song stops playing
ACTION(instrument_end, finished, FIXED, notice = /datum/notice/instrument_end)

/// Sent to the instrument when a song starts playing: (datum/starting_song, atom/player)
ACTION(instrument_start, starting_song, player, FIXED, notice = /datum/notice/instrument_start)
