/// Administrative and headless callers request the same next ticker-step behavior.
/datum/system/ticker/proc/request_immediate_start(enabled)
	start_immediately = enabled
	refresh_lobbies("immediate start [enabled ? "requested" : "cancelled"]")

/// Every transition of the round state goes through here: the lobby window shows Ready, Join or Initializing from the state, so
/// each connected new_player is told (the auto-start path used to leave them on Ready until they clicked something).
/datum/system/ticker/proc/set_current_state(new_state)
	if(current_state == new_state)
		return
	log_world("Ticker state [current_state] -> [new_state]")
	current_state = new_state
	tracked_changed(src, nameof(current_state))
	refresh_lobbies("state change to [new_state]")

SETTER(/datum/system/ticker, current_state)

/// Pushes the lobby window of every new_player; returns how many were pushed.
/datum/system/ticker/proc/refresh_lobbies(reason)
	lobby_refreshes++
	var/pushed = 0
	for(var/mob/new_player/player as anything in REGISTRY_MEMBERS(REGISTRY_NEW_PLAYERS))
		if(!player.client)
			continue
		pushed += SStgui.update_uis(player)
	log_tgui(null, "Lobby refresh ([reason]): pushed [pushed] window(s).", "ticker/refresh_lobbies")
	return pushed

/datum/system/ticker/proc/request_round_ending(reason)
	force_ending = reason

/datum/system/ticker/proc/set_round_end_delay(enabled)
	delay_end = enabled

/datum/system/ticker/proc/toggle_round_end_delay()
	delay_end = !delay_end

/// The roster uses its existing relation; repeated additions retain rel_add semantics.
/datum/system/ticker/proc/remember_mind(datum/mind/mind)
	rel_add(src, nameof(minds), mind)
