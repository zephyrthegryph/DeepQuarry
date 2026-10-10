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

/// Renders in the lobby browser element (initialized when the lobby opens).
/mob/new_player/ui_window(mob/user)
	return lobby_window

/mob/new_player/ui_assets(mob/user)
	. = ..()
	. += get_asset_datum(/datum/asset/simple/lobby_files)

/mob/new_player/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["ready"] = ready
	var/list/merged_1 = ui_data_mob_new_player(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /mob/new_player's window data.
/mob/new_player/proc/ui_data_mob_new_player(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/displayed_name = world.name
	if(config && CONFIG_GET(string/servername))
		displayed_name = CONFIG_GET(string/servername)

	data["server_name"] = displayed_name
	data["map"] = using_map.full_name
	data["station_time"] = stationtime2text()
	data["display_loading"] = ticker_current_state() == GAME_STATE_STARTUP
	data["round_start"] = !ticker_mode() || ticker_current_state() <= GAME_STATE_PREGAME
	data["round_time"] = roundduration2text()
	data["new_news"] = client?.check_for_new_server_news()
	data["can_submit_feedback"] = SSsqlite.can_submit_feedback(client)
	data["show_station_news"] = GLOB.news_data.station_newspaper()
	data["new_station_news"] = client.prefs.lastlorenews != GLOB.news_data.newsindex
	data["new_changelog"] = read_preference(/datum/preference/text/lastchangelog) != GLOB.changelog_hash
	data["can_start_now"] = client.is_localhost() && check_rights_for(client, R_SERVER)
	data["immediate_start"] = ticker_start_immediately() || ticker_current_state() > GAME_STATE_PREGAME

	return data

/mob/new_player/tgui_static_data(mob/user)
	var/list/data = ..()

	data["bg"] = 'icons/misc/loading.dmi'
	data["bg_state"] = "loading"

	return data

/mob/new_player/proc/ui_act_character_setup(datum/act/op/A)
	client.prefs.ShowChoices(src)
	return TRUE

/mob/new_player/proc/ui_act_ready(datum/act/op/A)
	if(!ready && client?.login_hold_refuses()) // the login gate is still checking them
		return TRUE
	if(!SSticker || ticker_current_state() <= GAME_STATE_PREGAME)
		ready = !ready
	else
		ready = 0
	return TRUE

/mob/new_player/proc/ui_act_manifest(datum/act/op/A)
	ViewManifest()
	return TRUE

/mob/new_player/proc/ui_act_late_join(datum/act/op/A)
	var/mob/user = A.actor
	if(client?.login_hold_refuses())
		return TRUE
	if(!SSticker || ticker_current_state() != GAME_STATE_PLAYING)
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

/mob/new_player/proc/ui_act_observe(datum/act/op/A)
	if(QDELETED(src))
		return FALSE
	if(client?.login_hold_refuses())
		return TRUE
	if(!SSticker || ticker_current_state() == GAME_STATE_STARTUP)
		to_chat(src, span_warning("The game is still setting up, please try again later."))
		return TRUE
	if(A.step_value("observe") != "Yes")
		return TRUE
	return observe_apply()

/mob/new_player/proc/ui_act_give_feedback(datum/act/op/A)
	if(!SSsqlite.can_submit_feedback(persistent_client.client()))
		return

	if(client.feedback_form)
		client.feedback_form.display() // In case they closed the form early.
	else
		rel_set(client, nameof(/client::feedback_form), new /datum/managed_browser/feedback_form(client)) // the client owns its form
	return TRUE

/mob/new_player/proc/ui_act_open_station_news(datum/act/op/A)
	show_latest_news(GLOB.news_data.station_newspaper())
	return TRUE

/mob/new_player/proc/ui_act_open_changelog(datum/act/op/A)
	write_preference_directly(/datum/preference/text/lastchangelog, GLOB.changelog_hash)
	client.changes()
	return TRUE

/mob/new_player/proc/ui_act_keyboard(datum/act/op/A)
	var/mob/user = A.actor
	playsound_local(user, get_sfx(SFX_KEYBOARD), vol = 20)
	return TRUE

/mob/new_player/proc/ui_act_start_immediately(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.client.is_localhost() || !check_rights_for(user.client, R_SERVER))
		return FALSE

	SSticker.start_immediately = TRUE
	if(ticker_current_state() == GAME_STATE_STARTUP)
		to_chat(user, span_admin("The server is still setting up, but the round will be started as soon as possible."))

/datum/prompt/choice/lobby_observe
	choices = list("Yes", "No")
	buttons = TRUE
	timeout = 0

/// The observe question opens once the round is set up (the handler says why not otherwise).
/mob/new_player/proc/round_observable(datum/act/op/A)
	var/datum/system/ticker/service = SSticker
	return service && service.current_state != GAME_STATE_STARTUP

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
			grant(observer, granted_verb(/mob/observer/dead/verb/toggle_antagHUD, hidden = TRUE), verb_source(VERB_SOURCE_CONFIG)) // Poor guys, don't know what they are missing!

		observer.key = key

		observer.set_respawn_timer(time_till_respawn()) // Will keep their existing time if any, or return 0 and pass 0 into set_respawn_timer which will use the defaults
		observer.client.init_verbs()
		ended_with(mind, src) // mind is a relation view: the framework clears it as the mind dies
		replaced_by(src)

		// pAI notify if we have be pAI invite on
		SSpai.clear_pai_block_delay(REF(observer)) // Reset invite cooldown if we cancelled all invites for the round
		if(SSpai.invite_valid(observer))
			observer.pai_card_ping()

	return TRUE
