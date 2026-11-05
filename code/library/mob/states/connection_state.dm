// connection: lazy owned state of /mob (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, connection, field), write with STATE_SET(M, connection, field, value), end it with connection_clear(M).

/datum/connection_state
	var/autowhisper = FALSE
	/// /mob
	var/autowhisper_mode
	var/away_from_keyboard = FALSE
	/// The computer id the mob's last client had, kept for the ban and multikey checks while it is offline.
	var/computer_id
	var/disconnect_time
	var/lastKnownIP
	var/manual_afk = FALSE

/mob
	var/datum/connection_state/connection
