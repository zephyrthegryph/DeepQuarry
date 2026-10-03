/datum/tgui_ban_panel
	var/tmp/client/holder	//client of whoever is using this datum
	var/tmp/datum/admins/admin_datum
	var/playerckey
	var/adminckey
	var/playerip
	var/playercid
	var/dbbantype
	var/min_search = FALSE
	/// The last search's rows (om_sql_view: they arrive after the search is made).
	var/list/db_records

/datum/tgui_ban_panel/New(user, pckey, datum/admins/admind)//user can either be a client or a mob due to byondcode(tm)
	if (istype(user, /client))
		var/client/user_client = user
		rel_set(src, nameof(holder), user_client) //if its a client, assign it to holder
	else
		var/mob/user_mob = user
		rel_set(src, nameof(holder), user_mob.client) //if its a mob, assign the mob's client to holder
	playerckey = pckey
	rel_set(src, nameof(admin_datum), admind)
	database_lookup()

DECLARE_UI_STATE(/datum/tgui_ban_panel, ADMIN_STATE(R_BAN))

/datum/tgui_ban_panel/tgui_close()
	rel_clear(src, nameof(holder))
	rel_clear(src, nameof(admin_datum))
	qdel(src)

DECLARE_UI(/datum/tgui_ban_panel, "BanPanel", UI_TITLE("Ban Panel"))

/datum/tgui_ban_panel/tgui_static_data(mob/user)
	var/list/bantypes = list("traitor","changeling","operative","revolutionary","cultist","wizard") //For legacy bans.
	for(var/antag_type in SSantag.all_antag_types) // Grab other bans.
		var/datum/antagonist/antag = SSantag.all_antag_types[antag_type]
		bantypes |= antag.bantype

	var/list/data = list(
						"player_ckey" = playerckey,
						"admin_ckey" = adminckey,
						"player_ip" = playerip,
						"player_cid" = playercid,
						"bantype" = dbbantype,
						"possible_jobs" = get_all_jobs() + SSjob.get_job_titles_in_department(DEPARTMENT_SYNTHETIC) + bantypes,
						"database_records" = db_records
					)
	return data


UI_DATA_REPLACE(/datum/tgui_ban_panel, "merge:ui_data_datum_tgui_ban_panel{min_search:num}")

/// The computed part of /datum/tgui_ban_panel's window data (declared on its UI_DATA row).
/datum/tgui_ban_panel/proc/ui_data_datum_tgui_ban_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list(
							"min_search" = min_search,
						)
	return data

UI_ACT(/datum/tgui_ban_panel, "confirmBan", ui_act_confirmban, UI_ARG_TEXT("cid"), UI_ARG_TEXT("ckey"), UI_ARG_NUM("duration"), UI_ARG_TEXT("ip"), UI_ARG_TEXT("job"), UI_ARG_TEXT("reason"), UI_ARG_NUM("type"))
UI_ACT_PROC(/datum/tgui_ban_panel, ui_act_confirmban)

	var/bantype = params["type"]
	var/banip = params["ip"]
	var/banduration = params["duration"]
	var/banckey = ckey(params["ckey"])
	var/bancid = params["cid"]
	var/banjob = params["job"]
	var/banreason = params["reason"]

	switch(bantype)
		if(BANTYPE_PERMA)
			if(!banckey || !banreason)
				to_chat(usr, span_filter_adminlog("Not enough parameters (Requires ckey and reason)"))
				return
			banduration = null
			banjob = null
		if(BANTYPE_TEMP)
			if(!banckey || !banreason || !banduration)
				to_chat(usr, span_filter_adminlog("Not enough parameters (Requires ckey, reason and duration)"))
				return
			banjob = null
		if(BANTYPE_JOB_PERMA)
			if(!banckey || !banreason || !banjob)
				to_chat(usr, span_filter_adminlog("Not enough parameters (Requires ckey, reason and job)"))
				return
			banduration = null
		if(BANTYPE_JOB_TEMP)
			if(!banckey || !banreason || !banjob || !banduration)
				to_chat(usr, span_filter_adminlog("Not enough parameters (Requires ckey, reason and job)"))
				return

	var/mob/playermob

	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(M.ckey == banckey)
			playermob = M
			break

	banreason = "(MANUAL BAN) " + banreason

	if(!playermob)
		if(banip)
			banreason = "[banreason] (CUSTOM IP)"
		if(bancid)
			banreason = "[banreason] (CUSTOM CID)"
	else
		message_admins("Ban process: A mob matching [playermob.ckey] was found at location [playermob.x], [playermob.y], [playermob.z]. Custom ip and computer id fields replaced with the ip and computer id from the located mob")
	notes_add(banckey, banreason, ui.user)

	admin_datum().DB_ban_record(bantype, playermob, banduration, banreason, banjob, null, banckey, banip, bancid )
	if((bantype == BANTYPE_PERMA || bantype == BANTYPE_TEMP) && playermob?.client)
		qdel(playermob.client)

	return TRUE

UI_ACT(/datum/tgui_ban_panel, "searchBans", ui_act_searchbans, UI_ARG_TEXT("aCkey"), UI_ARG_NUM("banType"), UI_ARG_TEXT("cid"), UI_ARG_TEXT("ckey"), UI_ARG_TEXT("ip"), UI_ARG_NUM("minMatch"))
UI_ACT_PROC(/datum/tgui_ban_panel, ui_act_searchbans)
	playerckey = ckey(params["ckey"])
	adminckey = ckey(params["aCkey"])
	playerip = params["ip"]
	playercid = params["cid"]
	dbbantype = params["banType"]
	min_search = params["minMatch"]
	database_lookup()
	update_tgui_static_data(ui.user, ui)
	return TRUE

UI_ACT(/datum/tgui_ban_panel, "banEdit", ui_act_banedit, UI_ARG_TEXT("action"), UI_ARG_NUM("banid"))
UI_ACT_PROC(/datum/tgui_ban_panel, ui_act_banedit)
	var/banedit = params["action"]
	var/banid = params["banid"]
	if(!banedit || !banid)
		return FALSE

	admin_datum().DB_ban_edit(ui.user.client, banid, banedit)
	return TRUE

/// Starts the ban search for the current filters; the rows arrive in sql_rows_arrived().
/datum/tgui_ban_panel/proc/database_lookup()
	db_records = null
	if(!adminckey && !playerckey && !playerip && !playercid && !dbbantype)
		return

	var/adminsearch
	var/playersearch
	var/ipsearch
	var/cidsearch
	var/list/search_params = list()
	if(min_search)
		if(adminckey && length(adminckey) >= 3)
			adminsearch = "AND a_ckey LIKE :adminckey "
			search_params["adminckey"] = "[adminckey]%"
		if(playerckey && length(playerckey) >= 3)
			playersearch = "AND ckey LIKE :playerckey "
			search_params["playerckey"] = "[playerckey]%"
		if(playerip && length(playerip) >= 3)
			ipsearch  = "AND ip LIKE :playerip "
			search_params["playerip"] = "[playerip]%"
		if(playercid && length(playercid) >= 7)
			cidsearch  = "AND computerid LIKE :playercid "
			search_params["playercid"] = "[playercid]%"
	else
		if(adminckey)
			adminsearch = "AND a_ckey = :adminckey "
			search_params["adminckey"] = adminckey
		if(playerckey)
			playersearch = "AND ckey = :playerckey "
			search_params["playerckey"] = playerckey
		if(playerip)
			ipsearch  = "AND ip = :playerip "
			search_params["playerip"] = playerip
		if(playercid)
			cidsearch  = "AND computerid = :playercid "
			search_params["playercid"] = playercid

	var/bantypesearch
	if(dbbantype)
		bantypesearch = "AND bantype = "

		switch(dbbantype)
			if(BANTYPE_TEMP)
				bantypesearch += "'TEMPBAN' "
			if(BANTYPE_JOB_PERMA)
				bantypesearch += "'JOB_PERMABAN' "
			if(BANTYPE_JOB_TEMP)
				bantypesearch += "'JOB_TEMPBAN' "
			else
				bantypesearch += "'PERMABAN' "


	om_sql_view(src, "bans", "SELECT id, bantime, bantype, reason, job, duration, expiration_time, ckey, a_ckey, unbanned, unbanned_ckey, unbanned_datetime, edits, ip, computerid FROM erro_ban WHERE 1 [playersearch] [adminsearch] [ipsearch] [cidsearch] [bantypesearch] ORDER BY bantime DESC LIMIT 100", search_params, PROC_REF(sql_rows_arrived))

/datum/tgui_ban_panel/proc/sql_rows_arrived(list/result, error, key)
	var/list/rows = om_sql_view_rows(result, error, key, src)
	if(!holder() || !check_rights_for(holder(), R_BAN))
		return
	var/list/all_bans = list()
	var/now = time2text(world.realtime, "YYYY-MM-DD hh:mm:ss") // MUST BE the same format as SQL gives us the dates in, and MUST be least to most specific (i.e. year, month, day not day, month, year)
	for(var/list/row as anything in rows)
		UNTYPED_LIST_ADD(all_bans, list("auto" = ((row[3] in list("TEMPBAN", "JOB_TEMPBAN")) && now > row[7]), "data_list" = row))
	db_records = all_bans
	update_static_data_for_all_viewers()

/// The admin_datum this refers to (a relation view: null once that is deleted).
/datum/tgui_ban_panel/proc/admin_datum() as /datum/admins
	return admin_datum

/// Client of whoever is using this datum (a relation view: null once that is deleted).
/datum/tgui_ban_panel/proc/holder() as /client
	return holder
