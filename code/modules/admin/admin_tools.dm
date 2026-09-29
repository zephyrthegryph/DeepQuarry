ADMIN_VERB_ONLY_CONTEXT_MENU(cmd_admin_check_player_logs, R_ADMIN|R_MOD, "Check Mob Logs", mob/living/player in  REGISTRY_MEMBERS(REGISTRY_MOBS))
	user.show_cmd_admin_check_player_logs(player.logging, player.name, player.ckey, player.mind?.special_role)

//Views specific attack logs belonging to one player.
/client/proc/show_cmd_admin_check_player_logs(list/mob_data, target_name, target_ckey, target_special, is_client)
	var/datum/player_log_viwer/log_view = new(mob_data, target_name, target_ckey, target_special, is_client)
	log_view.tgui_interact(mob)

ADMIN_VERB(persistent_client_logs, R_ADMIN|R_MOD, "Check Player Logs", "Displays the client logs of the selected ckey.", ADMIN_CATEGORY_LOGS)
	var/mob/living/selected_key = verb_ask(user, "a1", args, /datum/om/prompt/choice, message = "Select a ckey to check their logs", title = "Ckey", choices = GLOB.persistent_clients_by_ckey)
	if(isnull(selected_key))
		return
	if(!selected_key)
		return

	var/datum/persistent_client/selected = GLOB.persistent_clients_by_ckey[selected_key]

	user.show_cmd_admin_check_player_logs(selected.logging, selected.mob()?.name, selected_key, selected.mob()?.mind?.special_role, TRUE)

/datum/player_log_viwer
	var/list/log_data
	var/target_name
	var/target_ckey
	var/special_role
	var/last_refresh
	var/client_view

/datum/player_log_viwer/tgui_close(mob/user)
	. = ..()
	log_data = null

/datum/player_log_viwer/New(list/data, name, ckey, special, is_client)
	. = ..()
	log_data = data
	target_name = name
	target_ckey = ckey
	special_role = special
	last_refresh = world.time
	client_view = is_client
	if(!islist(log_data))
		log_data = list()
	refresh_data()

/datum/player_log_viwer/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PlayerLogViewer")
		ui.open()

/datum/player_log_viwer/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_MOD)

/datum/player_log_viwer/tgui_static_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return list(
		"entries" = log_data,
		"name" = target_name,
		"ckey" = target_ckey,
		"special" = special_role,
		"view_client" = client_view
	)

/datum/player_log_viwer/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return list(
		"on_cooldown" = refresh_cooldown(),
		"all_clients" = GLOB.persistent_clients_by_ckey,
	)

/datum/player_log_viwer/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		if("refresh")
			if(refresh_cooldown())
				return FALSE
			refresh_data()
			last_refresh = world.time
			update_tgui_static_data(ui.user)
			return TRUE
		if("select_client")
			if(refresh_cooldown())
				return FALSE
			var/new_ckey = params["ckey"]
			if(!(new_ckey in GLOB.persistent_clients_by_ckey))
				return FALSE
			target_ckey = new_ckey
			var/datum/persistent_client/selected = GLOB.persistent_clients_by_ckey[new_ckey]
			log_data = selected.logging
			target_name = selected.mob()?.name
			special_role = selected.mob()?.mind?.special_role
			client_view = TRUE
			refresh_data()
			last_refresh = world.time
			update_tgui_static_data(ui.user)
			return TRUE

/datum/player_log_viwer/proc/refresh_cooldown()
	return (ELAPSED_SINCE(src, last_refresh, CLOCK_WORLD) < 5 SECONDS)

/// Adds the player's logged dialog from the database (om_io: the rows arrive later and the
/// window's static data is resent then).
/datum/player_log_viwer/proc/refresh_data()
	if(!CONFIG_GET(flag/database_logging))
		return
	om_sql_view(src, "dialog", "SELECT mid,time,ckey,mob,area,color,type,message from erro_dialog WHERE ckey = :t_ckey", list("t_ckey" = target_ckey), PROC_REF(sql_rows_arrived))

/datum/player_log_viwer/proc/sql_rows_arrived(list/result, error, key)
	var/list/rows = om_sql_view_rows(result, error, key, src)
	if(!length(open_tguis)) // closed meanwhile
		return
	if(error)
		for(var/datum/tgui/ui as anything in open_tguis)
			to_chat(ui.user, span_admin("Database query error"))
		return
	if(!islist(log_data))
		log_data = list()
	log_data.Cut()
	for(var/list/row as anything in rows)
		var/list/timestamped_message = list(
			"event_id" = row[1],
			"time" = row[2],
			"ckey" = row[3],
			"name" = row[4],
			"loc" = row[5],
			"color" = row[6],
			"message" = row[8]
		)
		var/entry_type = row[7]
		if(!islist(log_data[entry_type]))
			log_data[entry_type] = list()
		UNTYPED_LIST_ADD(log_data[entry_type], timestamped_message)
	client_view = TRUE
	update_static_data_for_all_viewers()
