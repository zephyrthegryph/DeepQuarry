// motion_track: lazy owned state of /mob (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, motion_track, field), write with motion_track_of(M).set_field(value), end it with motion_track_clear(M).

/datum/motion_track_state
	var/is_motion_tracking = FALSE
	var/wants_to_see_motion_echos = TRUE

/mob
	var/datum/motion_track_state/motion_track
