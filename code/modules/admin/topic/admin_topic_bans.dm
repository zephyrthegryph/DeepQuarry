// Admin panel href actions: bans, job bans, kicks, warnings and mutes.


/// Where job-ban panel links look up their mob.
/datum/admins/proc/topic_registered_mobs()
	return REGISTRY_MEMBERS(REGISTRY_MOBS)

/datum/admins/proc/topic_unbanf(datum/act/op/A, href_unbanf)
	var/mob/user = A.actor
	var/banfolder = href_unbanf
	GLOB.banlist.cd = "/base/[banfolder]"
	var/key = GLOB.banlist["key"]
	var/answer = ban_topic_ask(user, A.topic_href(), "a4", /datum/prompt/choice/admin_ban_topic, question = "Are you sure you want to unban [key]?", title = "Confirmation", choices = list("Yes", "No"))
	if(answer != "Yes")
		return
	if(!RemoveBan(banfolder, user))
		tgui_alert_async(user, "This ban has already been lifted / does not exist.", "Error")
	unbanpanel()

/datum/admins/proc/topic_warn(datum/act/op/A, href_warn)
	var/mob/user = A.actor
	user.client.warn(href_warn)

/datum/admins/proc/topic_unbane(datum/act/op/A, href_unbane)
	var/mob/user = A.actor
	UpdateTime()
	var/reason

	var/banfolder = href_unbane
	GLOB.banlist.cd = "/base/[banfolder]"
	var/reason2 = GLOB.banlist["reason"]
	var/temp = GLOB.banlist["temp"]

	var/minutes = GLOB.banlist["minutes"]

	var/banned_key = GLOB.banlist["key"]
	GLOB.banlist.cd = "/base"

	var/duration

	var/answer = ban_topic_ask(user, A.topic_href(), "a5", /datum/prompt/choice/admin_ban_topic, question = "Temporary Ban?", title = "Temporary Ban", choices = list("Yes","No"))
	switch(answer)
		if("Yes")
			temp = 1
			var/mins = 0
			if(minutes > GLOB.c_minutes)
				mins = minutes - GLOB.c_minutes
			mins = ban_topic_ask(user, A.topic_href(), "a6", /datum/prompt/number/admin_ban_topic, question = "How long (in minutes)? (Default: 1440)", title = "Ban time", default = mins ? mins : 1440)
			if(!mins)
				return
			mins = min(525599, mins)
			minutes = GLOB.c_minutes + mins
			duration = GetExp(minutes)
			reason = ban_topic_ask(user, A.topic_href(), "a7", /datum/prompt/text/admin_ban_topic, question = "Reason?", title = "reason", default = reason2)
			if(!reason)
				return
		if("No")
			temp = 0
			duration = "Perma"
			reason = ban_topic_ask(user, A.topic_href(), "a8", /datum/prompt/text/admin_ban_topic, question = "Reason?", title = "reason", default = reason2)
			if(!reason)
				return
		else
			return

	log_admin("[key_name(user)] edited [banned_key]'s ban. Reason: [reason] Duration: [duration]")
	ban_unban_log_save("[key_name(user)] edited [banned_key]'s ban. Reason: [reason] Duration: [duration]")
	message_admins(span_blue("[key_name_admin(user)] edited [banned_key]'s ban. Reason: [reason] Duration: [duration]"), 1)
	GLOB.banlist.cd = "/base/[banfolder]"
	GLOB.banlist["reason"] << reason
	GLOB.banlist["temp"] << temp
	GLOB.banlist["minutes"] << minutes
	GLOB.banlist["bannedby"] << user.ckey
	GLOB.banlist.cd = "/base"
	feedback_inc("ban_edit",1)
	unbanpanel()

/datum/admins/proc/topic_jobban2(datum/act/op/A, href_jobban2)
	var/mob/user = A.actor
	var/mob/M = href_jobban2
	if(!M.ckey)	//sanity
		to_chat(user, span_filter_adminlog("This mob has no ckey"))
		return
	if(!SSjob)
		to_chat(user, span_filter_adminlog("Job Master has not been setup!"))
		return

	// Job-Ban Panel opens a structured TGUI panel.
	dq_open_jobban_panel(M)

/// The job titles a jobban3 href value names: a department key, or one job title.
/datum/admins/proc/jobban_job_list(selection)
	var/list/joblist = list()
	var/list/departments
	switch(selection)
		if("commanddept")
			departments = list(DEPARTMENT_COMMAND)
		if("securitydept")
			departments = list(DEPARTMENT_SECURITY)
		if("engineeringdept")
			departments = list(DEPARTMENT_ENGINEERING)
		if("cargodept")
			departments = list(DEPARTMENT_CARGO)
		if("medicaldept")
			departments = list(DEPARTMENT_MEDICAL)
		if("sciencedept")
			departments = list(DEPARTMENT_RESEARCH)
		if("explorationdept")
			departments = list(DEPARTMENT_PLANET)
		if("offmapdept")
			departments = GLOB.offmap_departments
		if("civiliandept")
			departments = list(DEPARTMENT_CIVILIAN)
		if("nonhumandept")
			joblist += "pAI"
			departments = list(DEPARTMENT_SYNTHETIC)
		else
			joblist += selection
			return joblist
	for(var/dept in departments)
		for(var/jobPos in SSjob.get_job_titles_in_department(dept))
			if(!jobPos)
				continue
			var/datum/job/temp = SSjob.get_job(jobPos)
			if(!temp)
				continue
			joblist += temp.title
	return joblist

/datum/admins/proc/topic_jobban3(datum/act/op/A, href_jobban3, href_jobban4)
	var/mob/user = A.actor
	if(!check_rights_for(user.client, R_MOD) && !check_rights_for(user.client, R_ADMIN))
		to_chat(user, span_filter_adminlog(span_warning("You do not have the appropriate permissions to add job bans!")))
		return

	if(check_rights_for(user.client, R_MOD) && !check_rights_for(user.client, R_ADMIN) && !CONFIG_GET(flag/mods_can_job_tempban)) // If mod and tempban disabled
		to_chat(user, span_filter_adminlog(span_warning("Mod jobbanning is disabled!")))
		return

	var/mob/M = href_jobban4
	if(!M)
		to_chat(user, span_filter_adminlog("This can only be used on instances of type /mob"))
		return

	if(M != user)																//we can jobban ourselves
		if(admin_can(M.client, R_BAN))		//they can ban too. So we can't ban them
			tgui_alert_async(user, "You cannot perform this action. You must be of a higher administrative rank!")
			return

	if(!SSjob)
		to_chat(user, span_filter_adminlog("Job Master has not been setup!"))
		return

	var/list/joblist = jobban_job_list(href_jobban3)

	//Create a list of unbanned jobs within joblist
	var/list/notbannedlist = list()
	for(var/job in joblist)
		if(!jobban_isbanned(M, job))
			notbannedlist += job

	//Banning comes first
	if(notbannedlist.len) //at least 1 unbanned job exists in joblist so we have stuff to ban.
		var/answer = ban_topic_ask(user, A.topic_href(), "a9", /datum/prompt/choice/admin_ban_topic, question = "Temporary Ban?", title = "Temporary Ban", choices = list("Yes","No","Cancel"))
		switch(answer)
			if("Yes")
				if(!check_rights_for(user.client, R_MOD) && !check_rights_for(user.client, R_BAN))
					to_chat(user, span_filter_adminlog(span_warning("You cannot issue temporary job-bans!")))
					return
				if(CONFIG_GET(flag/ban_legacy_system))
					to_chat(user, span_filter_adminlog(span_warning("Your server is using the legacy banning system, which does not support temporary job bans. Consider upgrading. Aborting ban.")))
					return
				var/mins = ban_topic_ask(user, A.topic_href(), "a10", /datum/prompt/number/admin_ban_topic, question = "How long (in minutes)?", title = "Ban time", default = 1440)
				if(!mins)
					return
				if(check_rights_for(user.client, R_MOD) && !check_rights_for(user.client, R_BAN) && mins > CONFIG_GET(number/mod_job_tempban_max))
					to_chat(user, span_filter_adminlog(span_warning("Moderators can only job tempban up to [CONFIG_GET(number/mod_job_tempban_max)] minutes!")))
					return
				var/reason = ban_topic_ask(user, A.topic_href(), "a11", /datum/prompt/text/admin_ban_topic, question = "Reason?", title = "Please State Reason")
				if(!reason)
					return

				var/msg
				for(var/job in notbannedlist)
					ban_unban_log_save("[key_name(user)] temp-jobbanned [key_name(M)] from [job] for [mins] minutes. reason: [reason]")
					log_admin("[key_name(user)] temp-jobbanned [key_name(M)] from [job] for [mins] minutes")
					feedback_inc("ban_job_tmp",1)
					DB_ban_record(BANTYPE_JOB_TEMP, M, mins, reason, job, 0, null, null, null, FALSE, user)
					feedback_add_details("ban_job_tmp","- [job]")
					jobban_fullban(M, job, "[reason]; By [user.ckey] on [time2text(world.realtime)]") //Legacy banning does not support temporary jobbans.
					if(!msg)
						msg = job
					else
						msg += ", [job]"
				notes_add(M.ckey, "Banned  from [msg] - [reason]", user)
				message_admins(span_blue("[key_name_admin(user)] banned [key_name_admin(M)] from [msg] for [mins] minutes"), 1)
				to_chat(M, span_filter_system(span_red(span_large(span_bold("You have been jobbanned by [user.client.ckey] from: [msg].")))))
				to_chat(M, span_filter_system(span_red(span_bold("The reason is: [reason]"))))
				to_chat(M, span_filter_system(span_red("This jobban will be lifted in [mins] minutes.")))
				return 1
			if("No")
				if(!admin_require(user.client, R_BAN, "topic_jobban3", TRUE))
					return
				var/reason = ban_topic_ask(user, A.topic_href(), "a12", /datum/prompt/text/admin_ban_topic, question = "Reason?", title = "Please State Reason")
				if(reason)
					var/msg
					for(var/job in notbannedlist)
						ban_unban_log_save("[key_name(user)] perma-jobbanned [key_name(M)] from [job]. reason: [reason]")
						log_admin("[key_name(user)] perma-banned [key_name(M)] from [job]")
						feedback_inc("ban_job",1)
						DB_ban_record(BANTYPE_JOB_PERMA, M, -1, reason, job, 0, null, null, null, FALSE, user)
						feedback_add_details("ban_job","- [job]")
						jobban_fullban(M, job, "[reason]; By [user.ckey] on [time2text(world.realtime)]")
						if(!msg)
							msg = job
						else
							msg += ", [job]"
					notes_add(M.ckey, "Banned  from [msg] - [reason]", user)
					message_admins(span_blue("[key_name_admin(user)] banned [key_name_admin(M)] from [msg]"), 1)
					to_chat(M, span_filter_system(span_red(span_large(span_bold("You have been jobbanned by [user.client.ckey] from: [msg].")))))
					to_chat(M, span_filter_system(span_red(span_bold("The reason is: [reason]"))))
					to_chat(M, span_filter_system(span_red("Jobban can be lifted only upon request.")))
					return 1
				return
			else
				return

	//Unbanning joblist
	//all jobs in joblist are banned already OR we didn't give a reason (implying they shouldn't be banned)
	if(joblist.len) //at least 1 banned job exists in joblist so we have stuff to unban.
		if(!CONFIG_GET(flag/ban_legacy_system))
			to_chat(user, span_filter_adminlog("Unfortunately, database based unbanning cannot be done through this panel"))
			DB_ban_panel(user.client, M.ckey)
			return
		var/msg
		for(var/job in joblist)
			var/reason = jobban_isbanned(M, job)
			if(!reason)
				continue //skip if it isn't jobbanned anyway
			var/answer = ban_topic_ask(user, A.topic_href(), "unjob_[job]", /datum/prompt/choice/admin_ban_topic, question = "Job: '[job]' Reason: '[reason]' Un-jobban?", title = "Please Confirm", choices = list("Yes","No"))
			if(isnull(answer))
				return
			if(answer != "Yes")
				continue
			ban_unban_log_save("[key_name(user)] unjobbanned [key_name(M)] from [job]")
			log_admin("[key_name(user)] unbanned [key_name(M)] from [job]")
			DB_ban_unban(M.ckey, BANTYPE_JOB_PERMA, job, user)
			feedback_inc("ban_job_unban",1)
			feedback_add_details("ban_job_unban","- [job]")
			jobban_unban(M, job)
			if(!msg)
				msg = job
			else
				msg += ", [job]"
		if(msg)
			message_admins(span_blue("[key_name_admin(user)] unbanned [key_name_admin(M)] from [msg]"), 1)
			to_chat(M, span_filter_system(span_red(span_large("You have been un-jobbanned by [user.client.ckey] from [msg]."))))
		return 1
	return 0 //we didn't do anything!

/datum/admins/proc/topic_boot2(datum/act/op/A, href_boot2)
	var/mob/user = A.actor
	var/mob/M = href_boot2
	if(!check_if_greater_rights_than(M.client))
		return
	var/reason = ban_topic_ask(user, A.topic_href(), "a14", /datum/prompt/text/admin_ban_topic, question = "Please enter reason.", multiline = TRUE)
	if(!reason)
		return

	to_chat(M, span_filter_system(span_critical("You have been kicked from the server: [reason]")))
	log_admin("[key_name(user)] booted [key_name(M)] for reason: '[reason]'.")
	message_admins(span_blue("[key_name_admin(user)] booted [key_name_admin(M)] for reason '[reason]'."), 1)
	admin_action_message(user.key, M.key, "kicked", reason, 0)
	spent(M.client, user)

/datum/admins/proc/topic_removejobban(datum/act/op/A, href_removejobban)
	var/mob/user = A.actor
	var/t = href_removejobban
	if(!t)
		return
	var/answer = ban_topic_ask(user, A.topic_href(), "a15", /datum/prompt/choice/admin_ban_topic, question = "Do you want to unjobban [t]?", title = "Unjobban confirmation", choices = list("Yes", "No"))
	if(answer != "Yes") //No more misclicks! Unless you do it twice.
		return
	log_admin("[key_name(user)] removed [t]")
	message_admins(span_blue("[key_name_admin(user)] removed [t]"), 1)
	jobban_remove(t)
	var/t_split = splittext(t, " - ")
	var/key = t_split[1]
	var/job = t_split[2]
	DB_ban_unban(ckey(key), BANTYPE_JOB_PERMA, job, user)

/datum/admins/proc/topic_newban(datum/act/op/A, href_newban)
	var/mob/user = A.actor
	if(!check_rights_for(user.client, R_MOD) && !check_rights_for(user.client, R_BAN))
		to_chat(user, span_warning("You do not have the appropriate permissions to add bans!"))
		return

	if(check_rights_for(user.client, R_MOD) && !check_rights_for(user.client, R_ADMIN) && !CONFIG_GET(flag/mods_can_job_tempban)) // If mod and tempban disabled
		to_chat(user, span_warning("Mod jobbanning is disabled!"))
		return

	var/mob/M = href_newban

	if(M.client && check_rights_for(M.client, R_HOLDER))
		return	//admins cannot be banned. Even if they could, the ban doesn't affect them anyway

	var/answer = ban_topic_ask(user, A.topic_href(), "a16", /datum/prompt/choice/admin_ban_topic, question = "Temporary Ban?", title = "Temporary Ban", choices = list("Yes","No","Cancel"))
	switch(answer)
		if("Yes")
			var/mins = ban_topic_ask(user, A.topic_href(), "a17", /datum/prompt/number/admin_ban_topic, question = "How long (in minutes)?", title = "Ban time", default = 1440)
			if(!mins)
				return
			if(check_rights_for(user.client, R_MOD) && !check_rights_for(user.client, R_BAN) && mins > CONFIG_GET(number/mod_tempban_max))
				to_chat(user, span_warning("Moderators can only job tempban up to [CONFIG_GET(number/mod_tempban_max)] minutes!"))
				return
			if(mins >= 525600)
				mins = 525599
			var/reason = ban_topic_ask(user, A.topic_href(), "a18", /datum/prompt/text/admin_ban_topic, question = "Reason?", title = "reason", default = "Griefer")
			if(!reason)
				return
			AddBan(M.ckey, M.computer_id, reason, user.ckey, 1, mins, user = user)
			ban_unban_log_save("[user.client.ckey] has banned [M.ckey]. - Reason: [reason] - This will be removed in [mins] minutes.")
			notes_add(M.ckey,"[user.client.ckey] has banned [M.ckey]. - Reason: [reason] - This will be removed in [mins] minutes.",user)
			to_chat(M, span_filter_system(span_critical("You have been banned by [user.client.ckey].\nReason: [reason].")))
			to_chat(M, span_filter_system(span_warning("This is a temporary ban, it will be removed in [mins] minutes.")))
			feedback_inc("ban_tmp",1)
			DB_ban_record(BANTYPE_TEMP, M, mins, reason, "", 0, null, null, null, FALSE, user)
			feedback_inc("ban_tmp_mins",mins)
			if(CONFIG_GET(string/banappeals))
				to_chat(M, span_filter_system(span_warning("To try to resolve this matter head to [CONFIG_GET(string/banappeals)]")))
			else
				to_chat(M, span_filter_system(span_warning("No ban appeals URL has been set.")))
			log_admin("[user.client.ckey] has banned [M.ckey].\nReason: [reason]\nThis will be removed in [mins] minutes.")
			message_admins(span_blue("[user.client.ckey] has banned [M.ckey].\nReason: [reason]\nThis will be removed in [mins] minutes."))
			var/datum/ticket/T = M.client ? M.client.current_ticket() : null
			if(T)
				T.Resolve(user)
			spent(M.client, user)
		if("No")
			if(!admin_require(user.client, R_BAN, "topic_newban", TRUE))
				return
			var/reason = ban_topic_ask(user, A.topic_href(), "a19", /datum/prompt/text/admin_ban_topic, question = "Reason?", title = "reason", default = "Griefer")
			if(!reason)
				return
			var/ip_answer = ban_topic_ask(user, A.topic_href(), "a20", /datum/prompt/choice/admin_ban_topic, question = "IP ban?", title = "IP Ban", choices = list("Yes","No","Cancel"))
			switch(ip_answer)
				if("Yes")
					AddBan(M.ckey, M.computer_id, reason, user.ckey, 0, 0, M.lastKnownIP, user)
				if("No")
					AddBan(M.ckey, M.computer_id, reason, user.ckey, 0, 0, user = user)
				else
					return
			to_chat(M, span_filter_system(span_critical("You have been banned by [user.client.ckey].\nReason: [reason].")))
			to_chat(M, span_filter_system(span_warning("This is a permanent ban.")))
			if(CONFIG_GET(string/banappeals))
				to_chat(M, span_filter_system(span_warning("To try to resolve this matter head to [CONFIG_GET(string/banappeals)]")))
			else
				to_chat(M, span_filter_system(span_warning("No ban appeals URL has been set.")))
			ban_unban_log_save("[user.client.ckey] has permabanned [M.ckey]. - Reason: [reason] - This is a permanent ban.")
			notes_add(M.ckey,"[user.client.ckey] has permabanned [M.ckey]. - Reason: [reason] - This is a permanent ban.",user)
			log_admin("[user.client.ckey] has banned [M.ckey].\nReason: [reason]\nThis is a permanent ban.")
			message_admins(span_blue("[user.client.ckey] has banned [M.ckey].\nReason: [reason]\nThis is a permanent ban."))
			feedback_inc("ban_perma",1)
			DB_ban_record(BANTYPE_PERMA, M, -1, reason, "", 0, null, null, null, FALSE, user)
			var/datum/ticket/T = M.client ? M.client.current_ticket() : null
			if(T)
				T.Resolve(user)
			spent(M.client, user)

/datum/admins/proc/topic_mute(datum/act/op/A, href_mute, href_mute_type)
	var/mob/user = A.actor
	var/mob/M = href_mute
	if(!M.client)
		return
	var/mute_type = href_mute_type
	if(!isnum(mute_type))
		return
	cmd_admin_mute(M, mute_type, FALSE, user)

/// Native answers replay the original raw href through the full public admin gate.
/datum/admins/proc/ban_topic_ask(mob/user, list/href, key, kind, question, title, default, list/choices, multiline = FALSE)
	var/list/answers = list()
	var/datum/request/replayed = href["ban_topic_request"]
	if((istype(replayed, /datum/prompt/choice/admin_ban_topic) || istype(replayed, /datum/prompt/number/admin_ban_topic) || istype(replayed, /datum/prompt/text/admin_ban_topic)) && replayed.owner == src && replayed.answerer == user && replayed.outcome == REQ_ANSWERED && !replayed.is_open() && !QDELETED(replayed) && replayed.handler == PROC_REF(ban_topic_answered))
		var/list/previous = replayed.captured["answers"]
		answers = previous.Copy()
		answers[replayed.step_name] = replayed.value
	if(key in answers)
		return answers[key]
	var/list/saved_href = href.Copy()
	saved_href -= "ban_topic_request"
	var/list/captured = list("href" = saved_href, "answers" = answers)
	if(kind == /datum/prompt/choice/admin_ban_topic)
		open_request(src, /datum/prompt/choice/admin_ban_topic, PROC_REF(ban_topic_answered), answerer = user, captured = captured, step_name = key, question = question, title = title, choices = choices)
	else if(kind == /datum/prompt/number/admin_ban_topic)
		open_request(src, /datum/prompt/number/admin_ban_topic, PROC_REF(ban_topic_answered), answerer = user, captured = captured, step_name = key, question = question, title = title, default = default)
	else
		open_request(src, /datum/prompt/text/admin_ban_topic, PROC_REF(ban_topic_answered), answerer = user, captured = captured, step_name = key, question = question, title = title, default = default, multiline = multiline)
	return null

/datum/admins/proc/ban_topic_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/list/original_href = A.answer.captured["href"]
	var/list/replayed_href = original_href.Copy()
	replayed_href["ban_topic_request"] = A.answer
	world.push_usr(A.request.answerer, new /datum/callback(GLOBAL_PROC, GLOBAL_PROC_REF(topic_dispatch)), src, A.request.answerer, replayed_href)

/datum/prompt/choice/admin_ban_topic
	timeout = 0
	recheck_on_open = TRUE
	buttons = TRUE

/datum/prompt/choice/admin_ban_topic/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return null

/datum/prompt/choice/admin_ban_topic/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_ban_topic/refusal(given)
	return null

/datum/prompt/number/admin_ban_topic
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/number/admin_ban_topic/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return null

/datum/prompt/number/admin_ban_topic/normalize(given)
	return isnum(given) ? given : null

/datum/prompt/number/admin_ban_topic/refusal(given)
	return null

/datum/prompt/text/admin_ban_topic
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/admin_ban_topic/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return null

/datum/prompt/text/admin_ban_topic/normalize(given)
	return istext(given) ? given : null

/datum/prompt/text/admin_ban_topic/refusal(given)
	return null

/datum/prompt/choice/unban_error_notification
	timeout = 0
	buttons = TRUE
	recheck_on_open = TRUE

/datum/prompt/choice/unban_error_notification/recheck_extra()
	return answerer?.client ? null : "gone"
