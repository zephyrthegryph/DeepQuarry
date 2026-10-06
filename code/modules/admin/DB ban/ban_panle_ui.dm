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

/datum/tgui_ban_panel/tgui_close()
	rel_clear(src, nameof(holder))
	rel_clear(src, nameof(admin_datum))
	spent(src)

CAPABILITIES(/datum/tgui_ban_panel)
	interface("BanPanel", title = "Ban Panel", rights = R_BAN)
	op("confirmBan", ui_act("confirmBan", arg("cid", schema_text(4096)), arg("ckey", schema_text(4096)), arg("duration", num()), arg("ip", schema_text(4096)), arg("job", schema_text(4096)), arg("reason", schema_text(4096)), arg("type", num())), then(PROC_REF(ui_act_confirmban)))
	op("searchBans", ui_act("searchBans", arg("aCkey", schema_text(4096)), arg("banType", num()), arg("cid", schema_text(4096)), arg("ckey", schema_text(4096)), arg("ip", schema_text(4096)), arg("minMatch", num())), then(PROC_REF(ui_act_searchbans)))
	op("banEdit", ui_act("banEdit", arg("action", schema_text(4096)), arg("banid", num())), then(PROC_REF(ui_act_banedit)))

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


/// /datum/tgui_ban_panel's window data.
/datum/tgui_ban_panel/ui_data(datum/act/eval/A)
	var/list/data = list(
							"min_search" = min_search,
						)
	return data

/datum/tgui_ban_panel/proc/ui_act_confirmban(datum/act/op/A, cid, ckey_arg, duration, ip, job, reason, type)
	var/mob/user = A.actor

	var/bantype = type
	var/banip = ip
	var/banduration = duration
	var/banckey = ckey(ckey_arg)
	var/bancid = cid
	var/banjob = job
	var/banreason = reason

	switch(bantype)
		if(BANTYPE_PERMA)
			if(!banckey || !banreason)
				to_chat(user, span_filter_adminlog("Not enough parameters (Requires ckey and reason)"))
				return
			banduration = null
			banjob = null
		if(BANTYPE_TEMP)
			if(!banckey || !banreason || !banduration)
				to_chat(user, span_filter_adminlog("Not enough parameters (Requires ckey, reason and duration)"))
				return
			banjob = null
		if(BANTYPE_JOB_PERMA)
			if(!banckey || !banreason || !banjob)
				to_chat(user, span_filter_adminlog("Not enough parameters (Requires ckey, reason and job)"))
				return
			banduration = null
		if(BANTYPE_JOB_TEMP)
			if(!banckey || !banreason || !banjob || !banduration)
				to_chat(user, span_filter_adminlog("Not enough parameters (Requires ckey, reason and job)"))
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
	notes_add(banckey, banreason, user)

	admin_datum().DB_ban_record(bantype, playermob, banduration, banreason, banjob, null, banckey, banip, bancid, FALSE, user)
	if((bantype == BANTYPE_PERMA || bantype == BANTYPE_TEMP) && playermob?.client)
		spent(playermob.client)

	return TRUE

/datum/tgui_ban_panel/proc/ui_act_searchbans(datum/act/op/A, aCkey, banType, cid, ckey_arg, ip, minMatch)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	playerckey = ckey(ckey_arg)
	adminckey = ckey(aCkey)
	playerip = ip
	playercid = cid
	dbbantype = banType
	min_search = minMatch
	database_lookup()
	update_tgui_static_data(user, ui)
	return TRUE

/datum/tgui_ban_panel/proc/ui_act_banedit(datum/act/op/A, action_arg, banid_arg)
	var/mob/user = A.actor
	var/banedit = action_arg
	var/banid = banid_arg
	if(!banedit || !banid)
		return FALSE

	admin_datum().DB_ban_edit(user.client, banid, banedit)
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
