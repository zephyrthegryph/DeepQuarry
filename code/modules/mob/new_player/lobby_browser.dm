/mob/new_player/proc/initialize_lobby_screen()
	if(!client)
		return

	var/datum/tgui/ui = SStgui.get_open_ui(src, src)
	if(ui)
		ui.close()

	winset(src, SKIN_LOBBY_BROWSER, "is-disabled=false;is-visible=true")
	rel_set(src, nameof(lobby_window), new /datum/tgui_window(client, SKIN_LOBBY_BROWSER))
	lobby_window.initialize(
		assets = list(
			get_asset_datum(/datum/asset/simple/tgui)
		)
	)

	tgui_interact(src)

DECLARE_UI(/mob/new_player, "LobbyMenu", UI_PINNED, UI_PREINITIALIZED)

/// Renders in the lobby browser element (initialized when the lobby opens).
/mob/new_player/ui_window(mob/user)
	return lobby_window

DECLARE_UI_STATE(/mob/new_player, GLOB.tgui_always_state)

/mob/new_player/ui_assets(mob/user)
	. = ..()
	. += get_asset_datum(/datum/asset/simple/lobby_files)

UI_DATA(/mob/new_player, "ready:num", "merge:ui_data_mob_new_player{server_name:text,map:unknown,station_time:text,display_loading:bool,round_start:bool,round_time:text,new_news:unknown,can_submit_feedback:unknown,show_station_news:unknown,new_station_news:bool,new_changelog:bool,can_start_now:bool,immediate_start:bool}")

/// The computed part of /mob/new_player's window data (declared on its UI_DATA row).
/mob/new_player/proc/ui_data_mob_new_player(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/displayed_name = world.name
	if(config && CONFIG_GET(string/servername))
		displayed_name = CONFIG_GET(string/servername)

	data["server_name"] = displayed_name
	data["map"] = using_map.full_name
	data["station_time"] = stationtime2text()
	data["display_loading"] = SSticker.current_state == GAME_STATE_STARTUP
	data["round_start"] = !SSticker.mode || SSticker.current_state <= GAME_STATE_PREGAME
	data["round_time"] = roundduration2text()
	data["new_news"] = client?.check_for_new_server_news()
	data["can_submit_feedback"] = SSsqlite.can_submit_feedback(client)
	data["show_station_news"] = GLOB.news_data.station_newspaper()
	data["new_station_news"] = client.prefs.lastlorenews != GLOB.news_data.newsindex
	data["new_changelog"] = read_preference(/datum/preference/text/lastchangelog) != GLOB.changelog_hash
	data["can_start_now"] = client.is_localhost() && check_rights_for(client, R_SERVER)
	data["immediate_start"] = SSticker.start_immediately || SSticker.current_state > GAME_STATE_PREGAME

	return data

/mob/new_player/tgui_static_data(mob/user)
	var/list/data = ..()

	data["bg"] = 'icons/misc/loading.dmi'
	data["bg_state"] = "loading"

	return data

UI_ACT(/mob/new_player, "character_setup", ui_act_character_setup)
UI_ACT_PROC(/mob/new_player, ui_act_character_setup)
	client.prefs.ShowChoices(src)
	return TRUE

UI_ACT(/mob/new_player, "ready", ui_act_ready)
UI_ACT_PROC(/mob/new_player, ui_act_ready)
	if(!ready && client?.login_hold_refuses()) // the login gate is still checking them
		return TRUE
	if(!SSticker || SSticker.current_state <= GAME_STATE_PREGAME)
		ready = !ready
	else
		ready = 0
	return TRUE

UI_ACT(/mob/new_player, "manifest", ui_act_manifest)
UI_ACT_PROC(/mob/new_player, ui_act_manifest)
	ViewManifest()
	return TRUE

UI_ACT(/mob/new_player, "late_join", ui_act_late_join)
UI_ACT_PROC(/mob/new_player, ui_act_late_join)
	if(client?.login_hold_refuses())
		return TRUE
	if(!SSticker || SSticker.current_state != GAME_STATE_PLAYING)
		to_chat(user, span_red("The round is either not ready, or has already finished..."))
		return TRUE

	var/time_till_respawn = time_till_respawn()
	if(time_till_respawn == -1) // Special case, never allowed to respawn
		to_chat(user, span_warning("Respawning is not allowed!"))
	else if(time_till_respawn) // Nonzero time to respawn
		to_chat(user, span_warning("You can't respawn yet! You need to wait another [round(time_till_respawn/10/60, 0.1)] minutes."))
		return TRUE
	LateChoices()
	return TRUE

UI_ACT(/mob/new_player, "observe", ui_act_observe)
UI_ACT_PROC(/mob/new_player, ui_act_observe)
	if(QDELETED(src))
		return FALSE
	if(client?.login_hold_refuses())
		return TRUE
	if(!SSticker || SSticker.current_state == GAME_STATE_STARTUP)
		to_chat(src, span_warning("The game is still setting up, please try again later."))
		return TRUE
	open_request(src, /datum/prompt/choice/lobby_observe, PROC_REF(observe_confirmed), answerer = src, title = "Observe Round?", question = "Are you sure you wish to observe? If you do, make sure to not use any knowledge gained from observing if you decide to join later.")
	return TRUE

UI_ACT(/mob/new_player, "give_feedback", ui_act_give_feedback)
UI_ACT_PROC(/mob/new_player, ui_act_give_feedback)
	if(!SSsqlite.can_submit_feedback(persistent_client.client()))
		return

	if(client.feedback_form)
		client.feedback_form.display() // In case they closed the form early.
	else
		rel_set(client, nameof(/client::feedback_form), new /datum/managed_browser/feedback_form(client)) // the client owns its form
	return TRUE

UI_ACT(/mob/new_player, "open_station_news", ui_act_open_station_news)
UI_ACT_PROC(/mob/new_player, ui_act_open_station_news)
	show_latest_news(GLOB.news_data.station_newspaper())
	return TRUE

UI_ACT(/mob/new_player, "open_changelog", ui_act_open_changelog)
UI_ACT_PROC(/mob/new_player, ui_act_open_changelog)
	write_preference_directly(/datum/preference/text/lastchangelog, GLOB.changelog_hash)
	client.changes()
	return TRUE

UI_ACT(/mob/new_player, "keyboard", ui_act_keyboard)
UI_ACT_PROC(/mob/new_player, ui_act_keyboard)
	playsound_local(ui.user, get_sfx(SFX_KEYBOARD), vol = 20)
	return TRUE

UI_ACT(/mob/new_player, "start_immediately", ui_act_start_immediately)
UI_ACT_PROC(/mob/new_player, ui_act_start_immediately)
	if(!ui.user.client.is_localhost() || !check_rights_for(ui.user.client, R_SERVER))
		return FALSE

	SSticker.start_immediately = TRUE
	if(SSticker.current_state == GAME_STATE_STARTUP)
		to_chat(user, span_admin("The server is still setting up, but the round will be started as soon as possible."))

/datum/prompt/choice/lobby_observe
	choices = list("Yes", "No")
	buttons = TRUE
	timeout = 0

/mob/new_player/proc/observe_confirmed(datum/act/request/A)
	if(!A.answer || A.answer.value != "Yes")
		return
	return observe_apply()

/mob/new_player/proc/observe_apply()
	if(!spawning)
		if(QDELETED(src) || !client)
			return TRUE

		//Make a new mannequin quickly, and allow the observer to take the appearance
		var/mob/living/carbon/human/dummy/mannequin = get_mannequin(client.ckey)
		client.prefs.dress_preview_mob(mannequin)
		var/mob/observer/dead/observer = new(mannequin)
		observer.moveToNullspace() //Let's not stay in our doomed mannequin

		spawning = 1
		if(client.media)
			client.media.stop_music() // MAD JAMS cant last forever yo

		observer.started_as_observer = 1
		close_spawn_windows()
		var/obj/O = locate("landmark*Observer-Start")
		if(istype(O))
			to_chat(src, span_notice("Now teleporting."))
			observer.forceMove(O.loc)
		else
			to_chat(src, span_danger("Could not locate an observer spawn point. Use the Teleport verb to jump to the station map."))

		announce_ghost_joinleave(src)

		if(client.prefs.read_preference(/datum/preference/toggle/human/name_is_always_random))
			client.prefs.update_preference_by_type(/datum/preference/name/real_name, random_name(client.prefs.read_preference(/datum/preference/choiced/gender/identifying)))
		observer.real_name = client.prefs.read_preference(/datum/preference/name/real_name)
		observer.name = observer.real_name
		if(!check_rights_for(client, R_HOLDER) && !CONFIG_GET(flag/antag_hud_allowed))           // For new ghosts we remove the verb from even showing up if it's not allowed.
			om_grant(observer, GRANT_VERB_HIDE, /mob/observer/dead/verb/toggle_antagHUD, verb_source(VERB_SOURCE_CONFIG)) // Poor guys, don't know what they are missing!

		observer.key = key

		observer.set_respawn_timer(time_till_respawn()) // Will keep their existing time if any, or return 0 and pass 0 into set_respawn_timer which will use the defaults
		observer.client.init_verbs()
		consumed(mind, src) // mind is a relation view: the framework clears it as the mind dies
		spent(src)

		// pAI notify if we have be pAI invite on
		SSpai.clear_pai_block_delay(REF(observer)) // Reset invite cooldown if we cancelled all invites for the round
		if(SSpai.invite_valid(observer))
			observer.pai_card_ping()

	return TRUE
