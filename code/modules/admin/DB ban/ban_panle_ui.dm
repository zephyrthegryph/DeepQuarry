/datum/tgui_ban_panel
	var/client/holder //client of whoever is using this datum
	var/datum/admins/admin_datum
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
		holder = user_client //if its a client, assign it to holder
	else
		var/mob/user_mob = user
		holder = user_mob.client //if its a mob, assign the mob's client to holder
	playerckey = pckey
	admin_datum = admind
	database_lookup()

/datum/tgui_ban_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_BAN)

/datum/tgui_ban_panel/tgui_close()
	holder = null
	admin_datum = null
	qdel(src)

/datum/tgui_ban_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "BanPanel", "Ban Panel")
		ui.open()

/datum/tgui_ban_panel/tgui_static_data(mob/user)
	var/list/bantypes = list("traitor","changeling","operative","revolutionary","cultist","wizard") //For legacy bans.
	for(var/antag_type in SSantag_job.all_antag_types) // Grab other bans.
		var/datum/antagonist/antag = SSantag_job.all_antag_types[antag_type]
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


/datum/tgui_ban_panel/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list(
							"min_search" = min_search,
						)
	return data

/datum/tgui_ban_panel/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		if("confirmBan")

			var/bantype = text2num(params["type"])
			var/banip = params["ip"]
			var/banduration = text2num(params["duration"])
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

			admin_datum.DB_ban_record(bantype, playermob, banduration, banreason, banjob, null, banckey, banip, bancid )
			if((bantype == BANTYPE_PERMA || bantype == BANTYPE_TEMP) && playermob?.client)
				qdel(playermob.client)

			return TRUE

		if("searchBans")
			playerckey = ckey(params["ckey"])
			adminckey = ckey(params["aCkey"])
			playerip = params["ip"]
			playercid = params["cid"]
			dbbantype = text2num(params["banType"])
			min_search = text2num(params["minMatch"])
			database_lookup()
			update_tgui_static_data(ui.user, ui)
			return TRUE

		if("banEdit")
			var/banedit = params["action"]
			var/banid = text2num(params["banid"])
			if(!banedit || !banid)
				return FALSE

			admin_datum.DB_ban_edit(ui.user.client, banid, banedit)
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
	if(!holder || !check_rights_for(holder, R_BAN))
		return
	var/list/all_bans = list()
	var/now = time2text(world.realtime, "YYYY-MM-DD hh:mm:ss") // MUST BE the same format as SQL gives us the dates in, and MUST be least to most specific (i.e. year, month, day not day, month, year)
	for(var/list/row as anything in rows)
		UNTYPED_LIST_ADD(all_bans, list("auto" = ((row[3] in list("TEMPBAN", "JOB_TEMPBAN")) && now > row[7]), "data_list" = row))
	db_records = all_bans
	update_static_data_for_all_viewers()
