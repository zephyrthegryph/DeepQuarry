// The lobby window watchdog system (was SSlobby_monitor): every 2 s in every runlevel it
// reinitializes lobby windows that failed to open; on shutdown it shows the restart animation.
SYSTEM_DEF(lobby_monitor)
	name = "Lobby Art"

	/// The clients who we've waited an interval to start working. If they haven't, we reboot them
	var/to_reinitialize = list()

/datum/system/lobby_monitor/reactions()
	. = ..()
	. += every(2 SECONDS, PROC_REF(watch_lobby), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/lobby_monitor/proc/watch_lobby(dt)
	var/list/new_players = REGISTRY_MEMBERS(REGISTRY_NEW_PLAYERS)

	for(var/mob/new_player/player as anything in to_reinitialize)
		if(!player.client)
			continue

		var/datum/tgui/ui = SStgui.get_open_ui(player, player)
		if(ui && player.lobby_window && player.lobby_window.status > TGUI_WINDOW_CLOSED)
			continue

		log_tgui(player, "Reinitialized [player.client.ckey]'s lobby window: [ui ? "ui" : "no ui"], status: [player.lobby_window?.status].", "lobby_monitor/Fire")
		INVOKE_ASYNC(src, PROC_REF(do_reinit), player) // ALLOW(scheduler): lobby window initialize may block on winexists/asset sends

	var/initialize_queue = list()
	for(var/mob/new_player/player as anything in new_players)
		if(!player.client)
			continue

		if(player in to_reinitialize)
			continue

		var/datum/tgui/ui = SStgui.get_open_ui(player, player)
		if(ui && player.lobby_window && player.lobby_window.status > TGUI_WINDOW_CLOSED)
			continue

		initialize_queue += player

	to_reinitialize = initialize_queue
	return STEP_DONE

/datum/system/lobby_monitor/proc/do_reinit(mob/new_player/player)
	var/datum/tgui/ui = SStgui.get_open_ui(player, player)
	if(ui && player.lobby_window && player.lobby_window.status > TGUI_WINDOW_CLOSED)
		return
	player.initialize_lobby_screen()

/datum/system/lobby_monitor/on_shutdown()
	var/datum/asset/our_asset = get_asset_datum(/datum/asset/simple/restart_animation)
	var/to_send = "<!DOCTYPE html><html lang='en'><head><meta http-equiv='X-UA-Compatible' content='IE=edge' /></head><body style='overflow: hidden;padding: 0 !important;margin: 0 !important'><div style='background-image: url([our_asset.get_url_mappings()["loading"]]);background-position:center;background-size:cover;position:absolute;width:100%;height:100%'></body></html>"

	for(var/client/client as anything in GLOB.clients)
		winset(client, SKIN_LOBBY_BROWSER, "is-disabled=false;is-visible=true")

		client << browse(to_send, "window=lobby_browser")
