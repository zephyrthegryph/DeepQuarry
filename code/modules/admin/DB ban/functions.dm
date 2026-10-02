
//Either pass the mob you wish to ban in the 'banned_mob' attribute, or the banckey, banip and bancid variables. If both are passed, the mob takes priority! If a mob is not passed, banckey is the minimum that needs to be passed! banip and bancid are optional.
/// `unseen_ok`: the admin already confirmed banning a ckey the server hasn't seen.
/// Runs as a prompt flow (flow_io.dm): its reads re-run it when they arrive, re-checking the rights.
/datum/admins/proc/DB_ban_record(bantype, mob/banned_mob, duration = -1, reason, job = "", rounds = 0, banckey = null, banip = null, bancid = null, unseen_ok = FALSE)
	if(!GLOB.prompt_flow)
		// Take the target's identifiers now: the flow re-runs later, after the caller may have
		// kicked them (and a deleted mob would drop the re-run).
		if(ismob(banned_mob))
			banckey = banned_mob.ckey
			if(banned_mob.client)
				bancid = banned_mob.client.computer_id
				banip = banned_mob.client.address
			if(IsGuestKey(banned_mob.key))
				unseen_ok = TRUE
			banned_mob = null
		return prompt_flow(src, PROC_REF(DB_ban_record), list(bantype, null, duration, reason, job, rounds, banckey, banip, bancid, unseen_ok))

	if(!check_rights(R_MOD,0) && !check_rights(R_BAN))	return

	if(!SSdbcore.IsConnected())
		return

	var/serverip = "[world.internet_address]:[world.port]"
	var/bantype_pass = 0
	var/bantype_str
	switch(bantype)
		if(BANTYPE_PERMA)
			bantype_str = "PERMABAN"
			duration = -1
			bantype_pass = 1
		if(BANTYPE_TEMP)
			bantype_str = "TEMPBAN"
			bantype_pass = 1
		if(BANTYPE_JOB_PERMA)
			bantype_str = "JOB_PERMABAN"
			duration = -1
			bantype_pass = 1
		if(BANTYPE_JOB_TEMP)
			bantype_str = "JOB_TEMPBAN"
			bantype_pass = 1
	if( !bantype_pass ) return
	if( !istext(reason) ) return
	if( !isnum(duration) ) return

	var/ckey
	var/computerid
	var/ip

	if(ismob(banned_mob))
		ckey = banned_mob.ckey
		if(banned_mob.client)
			computerid = banned_mob.client.computer_id
			ip = banned_mob.client.address
	else if(banckey)
		ckey = ckey(banckey)
		computerid = bancid
		ip = banip

	var/datum/db_query/query = SSdbcore.NewQuery("SELECT id FROM erro_player WHERE ckey = :ckey", list("ckey" = ckey))
	query.Execute()
	var/validckey = 0
	if(query.NextRow())
		validckey = 1
	qdel(query)
	if(!validckey && !unseen_ok)
		if(!banned_mob || (banned_mob && !IsGuestKey(banned_mob.key))) // .
			// The answer records the ban again from the start, re-reading the target's identifiers.
			var/datum/om/prompt/confirm/unseen_ban/ask = om_ask(usr, /datum/om/prompt/confirm/unseen_ban, PROC_REF(unseen_ban_confirmed), ban_args = list(bantype, null, duration, reason, job, rounds, banned_mob ? banned_mob.ckey : banckey, banned_mob?.client ? banned_mob.client.address : banip, banned_mob?.client ? banned_mob.client.computer_id : bancid))
			if(ask && banned_mob)
				rel_set(ask, nameof(ask.banned_mob), banned_mob)
			return

	var/a_ckey
	var/a_computerid
	var/a_ip

	if(src.owner() && istype(src.owner(), /client))
		a_ckey = src.owner():ckey
		a_computerid = src.owner():computer_id
		a_ip = src.owner():address

	var/who
	for(var/client/C in GLOB.clients)
		if(!who)
			who = "[C]"
		else
			who += ", [C]"

	var/adminwho
	for(var/client/C in GLOB.admins)
		if(!adminwho)
			adminwho = "[C]"
		else
			adminwho += ", [C]"

	reason = sql_sanitize_text(reason)

	var/ban_duration_val = (duration) ? duration : 0
	var/ban_rounds_val = (rounds) ? rounds : 0
	var/ban_interval = (duration > 0) ? duration : 0
	var/sql = "INSERT INTO erro_ban (`id`,`bantime`,`serverip`,`bantype`,`reason`,`job`,`duration`,`rounds`,`expiration_time`,`ckey`,`computerid`,`ip`,`a_ckey`,`a_computerid`,`a_ip`,`who`,`adminwho`,`edits`,`unbanned`,`unbanned_datetime`,`unbanned_ckey`,`unbanned_computerid`,`unbanned_ip`) VALUES (null, Now(), :serverip, :bantype_str, :reason, :job, :ban_duration_val, :ban_rounds_val, Now() + INTERVAL :ban_interval MINUTE, :ckey, :computerid, :ip, :a_ckey, :a_computerid, :a_ip, :who, :adminwho, '', null, null, null, null, null)"
	sql_write(sql, list("serverip" = serverip, "bantype_str" = bantype_str, "reason" = reason, "job" = job, "ban_duration_val" = ban_duration_val, "ban_rounds_val" = ban_rounds_val, "ban_interval" = ban_interval, "ckey" = ckey, "computerid" = computerid, "ip" = ip, "a_ckey" = a_ckey, "a_computerid" = a_computerid, "a_ip" = a_ip, "who" = who, "adminwho" = adminwho))
	to_chat(usr, span_filter_adminlog("[span_blue("Ban saved to database.")]"))
	message_admins("[key_name_admin(usr)] has added a [bantype_str] for [ckey] [(job)?"([job])":""] [(duration > 0)?"([duration] minutes)":""] with the reason: \"[reason]\" to the ban database.")


/datum/admins/proc/DB_ban_unban(ckey, bantype, job = "")
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(DB_ban_unban), args)

	if(!check_rights(R_BAN))
		return

	var/bantype_str
	if(bantype)
		var/bantype_pass = 0
		switch(bantype)
			if(BANTYPE_PERMA)
				bantype_str = "PERMABAN"
				bantype_pass = 1
			if(BANTYPE_TEMP)
				bantype_str = "TEMPBAN"
				bantype_pass = 1
			if(BANTYPE_JOB_PERMA)
				bantype_str = "JOB_PERMABAN"
				bantype_pass = 1
			if(BANTYPE_JOB_TEMP)
				bantype_str = "JOB_TEMPBAN"
				bantype_pass = 1
			if(BANTYPE_ANY_FULLBAN)
				bantype_str = "ANY"
				bantype_pass = 1
		if(!bantype_pass)
			return

	var/bantype_sql
	if(bantype_str == "ANY")
		bantype_sql = "(bantype = 'PERMABAN' OR (bantype = 'TEMPBAN' AND expiration_time > Now() ) )"
	else
		bantype_sql = "bantype = :bantype_str"

	var/sql = "SELECT id FROM erro_ban WHERE ckey = :ckey AND [bantype_sql] AND (unbanned is null OR unbanned = false)"
	var/list/sql_params = list("ckey" = ckey, "bantype_str" = bantype_str)
	if(job)
		sql += " AND job = :job"
		sql_params["job"] = job

	if(!SSdbcore.IsConnected())
		return

	var/ban_id
	var/ban_number = 0 //failsafe

	var/datum/db_query/query = SSdbcore.NewQuery(sql, sql_params)
	query.Execute()
	while(query.NextRow())
		ban_id = query.item[1]
		ban_number++;
	qdel(query)
	if(ban_number == 0)
		to_chat(usr, span_filter_adminlog("[span_red("Database update failed due to no bans fitting the search criteria. If this is not a legacy ban you should contact the database admin.")]"))
		return

	if(ban_number > 1)
		to_chat(usr, span_filter_adminlog("[span_red("Database update failed due to multiple bans fitting the search criteria. Note down the ckey, job and current time and contact the database admin.")]"))
		return

	if(istext(ban_id))
		ban_id = text2num(ban_id)
	if(!isnum(ban_id))
		to_chat(usr, span_filter_adminlog("[span_red("Database update failed due to a ban ID mismatch. Contact the database admin.")]"))
		return

	DB_ban_unban_by_id(ban_id)

/datum/om/prompt/confirm/unseen_ban
	title = "Confirm Badmin"
	message = "This ckey hasn't been seen, are you sure?"
	requires = PROMPT_ADMIN(R_MOD|R_BAN)
	/// DB_ban_record()'s arguments (the target's identifiers as they were when asked).
	var/list/ban_args
	/// The banned mob (a relation view): the ban goes ahead by ckey if the mob is gone meanwhile.
	var/mob/banned_mob

/datum/admins/proc/unseen_ban_confirmed(datum/om/prompt/confirm/unseen_ban/ask)
	var/mob/admin = ask.answerer
	var/list/ban_args = ask.ban_args
	var/mob/banned_mob = ask.banned_mob
	if(banned_mob)
		ban_args[2] = banned_mob
	usr = admin // DB_ban_record() reads usr for the banning admin, as when it asked.
	DB_ban_record(arglist(ban_args + TRUE))

/datum/admins/proc/DB_ban_edit(client/user, banid = null, param = null, value = null)
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(DB_ban_edit), args)

	if(!check_rights_for(user, R_BAN))
		return

	if(!isnum(banid) || !istext(param))
		to_chat(user, "Cancelled")
		return

	var/datum/db_query/query = SSdbcore.NewQuery("SELECT ckey, duration, reason FROM erro_ban WHERE id = :banid", list("banid" = banid))
	query.Execute()

	var/eckey = usr.ckey	//Editing admin ckey
	var/pckey				//(banned) Player ckey
	var/duration			//Old duration
	var/reason				//Old reason

	if(query.NextRow())
		pckey = query.item[1]
		duration = query.item[2]
		reason = query.item[3]
	else
		to_chat(user, span_filter_adminlog("Invalid ban id. Contact the database admin"))
		qdel(query)
		return

	qdel(query)
	reason = sql_sanitize_text(reason)
	switch(param)
		if("reason")
			if(!value)
				om_ask(user, /datum/om/prompt/text/ban_edit_reason, PROC_REF(ban_edit_value_entered), message = "Insert the new reason for [pckey]'s ban", default = "[reason]", banid = banid, param = param)
				return
			value = sql_sanitize_text(value)
			if(!value)
				to_chat(user, "Cancelled")
				return

			sql_write("UPDATE erro_ban SET reason = :value, edits = CONCAT(edits, CONCAT('- ', :eckey, ' changed ban reason from <cite><b>\"', :old_reason, '\"</b></cite> to <cite><b>\"', :value, '\"</b></cite><BR>')) WHERE id = :banid", list("value" = value, "eckey" = eckey, "old_reason" = reason, "banid" = banid))
			message_admins("[key_name_admin(user)] has edited a ban for [pckey]'s reason from [reason] to [value]")
			return
		if("duration")
			if(!value)
				om_ask(user, /datum/om/prompt/number/ban_edit_duration, PROC_REF(ban_edit_value_entered), message = "Insert the new duration (in minutes) for [pckey]'s ban", default = text2num(duration), banid = banid, param = param)
				return
			if(!isnum(value) || !value)
				to_chat(user, "Cancelled")
				return

			sql_write("UPDATE erro_ban SET duration = :value, edits = CONCAT(edits, CONCAT('- ', :eckey, ' changed ban duration from ', :old_duration, ' to ', :value, '<br>')), expiration_time = DATE_ADD(bantime, INTERVAL :value MINUTE) WHERE id = :banid", list("value" = value, "eckey" = eckey, "old_duration" = duration, "banid" = banid))
			message_admins("[key_name_admin(user)] has edited a ban for [pckey]'s duration from [duration] to [value]")
			return
		if("unban")
			if(value == "Yes")
				DB_ban_unban_by_id(banid)
				return
			if(!value)
				om_ask(user, /datum/om/prompt/confirm/ban_edit_unban, PROC_REF(ban_edit_value_entered), message = "Unban [pckey]?", banid = banid, param = param)
				return
	to_chat(user, span_filter_adminlog("Cancelled"))
	return

/// The value asked for re-enters DB_ban_edit(), which re-reads the ban.
/datum/om/prompt/text/ban_edit_reason
	title = "New Reason"
	max_length = MAX_MESSAGE_LEN
	requires = PROMPT_ADMIN(R_BAN)
	var/banid
	var/param

/datum/om/prompt/number/ban_edit_duration
	title = "New Duration"
	requires = PROMPT_ADMIN(R_BAN)
	var/banid
	var/param

/datum/om/prompt/confirm/ban_edit_unban
	title = "Unban?"
	answer_on_no = TRUE
	requires = PROMPT_ADMIN(R_BAN)
	var/banid
	var/param

/datum/admins/proc/ban_edit_value_entered(datum/om/prompt/ask)
	var/mob/admin = ask.answerer
	if(!admin.client)
		return
	var/value
	var/banid
	var/param
	if(istype(ask, /datum/om/prompt/text/ban_edit_reason))
		var/datum/om/prompt/text/ban_edit_reason/reason_ask = ask
		value = reason_ask.text
		banid = reason_ask.banid
		param = reason_ask.param
	else if(istype(ask, /datum/om/prompt/number/ban_edit_duration))
		var/datum/om/prompt/number/ban_edit_duration/duration_ask = ask
		value = duration_ask.number
		banid = duration_ask.banid
		param = duration_ask.param
	else
		var/datum/om/prompt/confirm/ban_edit_unban/unban_ask = ask
		value = unban_ask.yes ? "Yes" : "No"
		banid = unban_ask.banid
		param = unban_ask.param
	usr = admin // DB_ban_edit() reads usr for the editing admin.
	DB_ban_edit(admin.client, banid, param, value)

/datum/admins/proc/DB_ban_unban_by_id(id)
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(DB_ban_unban_by_id), args)

	if(!check_rights(R_BAN))	return

	if(!SSdbcore.IsConnected())
		return

	var/ban_number = 0 //failsafe

	var/pckey
	var/datum/db_query/query = SSdbcore.NewQuery("SELECT ckey FROM erro_ban WHERE id = :id", list("id" = id))
	query.Execute()
	while(query.NextRow())
		pckey = query.item[1]
		ban_number++;
	qdel(query)
	if(ban_number == 0)
		to_chat(usr, span_filter_adminlog("[span_red("Database update failed due to a ban id not being present in the database.")]"))
		return

	if(ban_number > 1)
		to_chat(usr, span_filter_adminlog("[span_red("Database update failed due to multiple bans having the same ID. Contact the database admin.")]"))
		return

	if(!src.owner() || !istype(src.owner(), /client))
		return

	var/unban_ckey = src.owner():ckey
	var/unban_computerid = src.owner():computer_id
	var/unban_ip = src.owner():address
	message_admins("[key_name_admin(usr)] has lifted [pckey]'s ban.")

	sql_write("UPDATE erro_ban SET unbanned = 1, unbanned_datetime = Now(), unbanned_ckey = :unban_ckey, unbanned_computerid = :unban_computerid, unbanned_ip = :unban_ip WHERE id = :id", list("unban_ckey" = unban_ckey, "unban_computerid" = unban_computerid, "unban_ip" = unban_ip, "id" = id))


/client/proc/DB_ban_panel()
	set category = VERB_CAT_ADMIN_MODERATION
	set name = "Banning Panel"
	set desc = "Edit admin permissions"

	if(!holder)
		return

	holder.DB_ban_panel(src)


/datum/admins/proc/DB_ban_panel(client/user, playerckey = null)
	if(!user)
		return

	if(!check_rights_for(user, R_BAN))
		return

	if(!SSdbcore.IsConnected())
		to_chat(usr, span_filter_adminlog("[span_red("Failed to establish database connection")]"))
		return

	var/datum/tgui_ban_panel/tgui = new(user, playerckey, src)
	tgui.tgui_interact(user.mob)
