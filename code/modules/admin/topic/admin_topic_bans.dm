// Admin panel href actions: bans, job bans, kicks, warnings and mutes.
//
// Each ban flow is an op (holder2.dm) whose questions are asks() steps in the order the admin answers them; a question that only some answers reach has a
// `when` (the temporary ban's length, the permanent ban's IP question), and the job-ban confirmations repeat. The ban is written once, by the op's handler, after the last
// answer, reading the answers by step name; a cancel at any step writes nothing.

MSG_DEF_SELF(admin_topic/ban_no_rights, "You do not have the appropriate permissions to add bans!")
MSG_DEF_SELF(admin_topic/jobban_no_rights, "You do not have the appropriate permissions to add job bans!")
MSG_DEF_SELF(admin_topic/mod_jobban_disabled, "Mod jobbanning is disabled!")
MSG_DEF_SELF(admin_topic/ban_target_admin, "Admins cannot be banned.")
MSG_DEF_SELF(admin_topic/ban_target_outranks, "You cannot perform this action. You must be of a higher administrative rank!")
MSG_DEF_SELF(admin_topic/jobban_not_ready, "Job Master has not been setup!")
MSG_DEF_SELF(admin_topic/jobban_no_target, "This can only be used on instances of type /mob")
MSG_DEF_SELF(admin_topic/boot_outranked, "You cannot kick someone who holds more rights than you.")

/// Where job-ban panel links look up their mob.
/datum/admins/proc/topic_registered_mobs()
	return REGISTRY_MEMBERS(REGISTRY_MOBS)

/// Whether `actor` holds one of `rights`. An admin-authority call (a forced op, a test) holds them all, as req_rights() does.
/proc/actor_admin_can(mob/actor, authority, rights)
	READS_FROM() // admin rights are an admin record, not round state
	if(authority & AUTH_ADMIN)
		return TRUE
	return admin_can(actor?.client, rights)

/// Whether `actor` may act on `M`'s admin standing: they hold admin rights and no more rights are held by `M` than by them.
/proc/actor_outranks(mob/actor, authority, mob/M)
	READS_FROM() // admin rights are an admin record, not round state
	if(!M)
		return FALSE
	if(authority & AUTH_ADMIN)
		return TRUE
	var/datum/admins/mine = admin_holder_of(actor?.client)
	if(!mine || !admin_can(actor.client, R_HOLDER))
		return FALSE
	var/datum/admins/theirs = admin_holder_of(M.client)
	if(!theirs)
		return TRUE
	return mine.check_if_greater_rights_than_holder(theirs)

/// The server's mods-may-jobban setting.
/proc/ban_mods_may_jobban()
	READS_FROM() // server configuration, not round state
	return !!CONFIG_GET(flag/mods_can_job_tempban)

/// Whether the server bans through the legacy savefile system.
/proc/ban_legacy_system_in_use()
	READS_FROM() // server configuration, not round state
	return !!CONFIG_GET(flag/ban_legacy_system)

/// Whether admins may jump and teleport.
/proc/admin_jumping_allowed()
	READS_FROM() // server configuration, not round state
	return !!CONFIG_GET(flag/allow_admin_jump)

/// The rights check of a handler that audits a denial.
/datum/admins/proc/ban_require(datum/act/op/A, rights, entry)
	if(A.authority & AUTH_ADMIN)
		return TRUE
	return admin_require(A.actor?.client, rights, entry, TRUE)

/// when: the "Temporary Ban?" step was answered Yes.
/datum/admins/proc/ban_is_temporary(datum/act/op/A)
	return A.step_value("temp") == "Yes"

/// when: the "Temporary Ban?" step was answered Yes or No (not Cancel): a reason is needed.
/datum/admins/proc/ban_needs_reason(datum/act/op/A)
	var/answer = A.step_value("temp")
	return answer == "Yes" || answer == "No"

/// when: the "Temporary Ban?" step was answered No: a permanent ban.
/datum/admins/proc/ban_is_permanent(datum/act/op/A)
	return A.step_value("temp") == "No"

// ---- unban ----

/datum/admins/proc/unbanf_question(datum/act/op/A)
	GLOB.banlist.cd = "/base/[A.args["unbanf"]]"
	var/key = GLOB.banlist["key"]
	GLOB.banlist.cd = "/base"
	return "Are you sure you want to unban [key]?"

/datum/admins/proc/topic_unbanf(datum/act/op/A, href_unbanf)
	var/mob/user = A.actor
	var/banfolder = href_unbanf
	if(A.step_value("confirm") != "Yes")
		return
	if(!RemoveBan(banfolder, user))
		tgui_alert_async(user, "This ban has already been lifted / does not exist.", "Error")
	unbanpanel()

/datum/admins/proc/topic_warn(datum/act/op/A, href_warn)
	var/mob/user = A.actor
	user.client.warn(href_warn)

// ---- edit a ban ----

/// A ban folder's editable state: list(reason, temp, minutes, key).
/datum/admins/proc/ban_edit_state(banfolder)
	UpdateTime()
	GLOB.banlist.cd = "/base/[banfolder]"
	var/list/state = list(GLOB.banlist["reason"], GLOB.banlist["temp"], GLOB.banlist["minutes"], GLOB.banlist["key"])
	GLOB.banlist.cd = "/base"
	return state

/datum/admins/proc/unbane_default_minutes(datum/act/op/A)
	var/list/state = ban_edit_state(A.args["unbane"])
	var/minutes = state[3]
	var/mins = 0
	if(minutes > GLOB.c_minutes)
		mins = minutes - GLOB.c_minutes
	return mins ? mins : 1440

/datum/admins/proc/unbane_default_reason(datum/act/op/A)
	var/list/state = ban_edit_state(A.args["unbane"])
	return state[1]

/datum/admins/proc/topic_unbane(datum/act/op/A, href_unbane)
	var/mob/user = A.actor
	var/banfolder = href_unbane
	var/list/state = ban_edit_state(banfolder)
	var/minutes = state[3]
	var/banned_key = state[4]
	var/temp
	var/duration
	var/reason = A.step_value("reason")
	switch(A.step_value("temp"))
		if("Yes")
			temp = 1
			var/mins = A.step_value("minutes")
			if(!mins)
				return
			mins = min(525599, mins)
			minutes = GLOB.c_minutes + mins
			duration = GetExp(minutes)
		if("No")
			temp = 0
			duration = "Perma"
		else
			return
	if(!reason)
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

// ---- job bans ----

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

/// The jobs of a jobban3 href that the target is not banned from.
/datum/admins/proc/jobban3_unbanned_jobs(datum/act/op/A)
	var/mob/M = A.args["jobban4"]
	. = list()
	if(!M || !SSjob)
		return
	for(var/job in jobban_job_list(A.args["jobban3"]))
		if(!jobban_isbanned(M, job))
			. += job

/// The jobs of a jobban3 href that the target is banned from.
/datum/admins/proc/jobban3_banned_jobs(datum/act/op/A)
	var/mob/M = A.args["jobban4"]
	. = list()
	if(!M || !SSjob)
		return
	for(var/job in jobban_job_list(A.args["jobban3"]))
		if(jobban_isbanned(M, job))
			. += job

/// when: there is a job left to ban, so the ban questions are asked.
/datum/admins/proc/jobban3_asks_ban(datum/act/op/A)
	return length(jobban3_unbanned_jobs(A)) > 0

/// when: every job is banned already and the legacy system can lift them one by one, so each is confirmed.
/datum/admins/proc/jobban3_asks_unban(datum/act/op/A)
	if(length(jobban3_unbanned_jobs(A)) || !ban_legacy_system_in_use())
		return FALSE
	return length(jobban3_banned_jobs(A)) > 0

/// repeats: another banned job is left to confirm.
/datum/admins/proc/jobban3_more_unbans(datum/act/op/A)
	return length(A.step_values("unjob")) < length(jobban3_banned_jobs(A))

/// The question of the next banned job to confirm.
/datum/admins/proc/jobban3_unban_question(datum/act/op/A)
	var/list/banned = jobban3_banned_jobs(A)
	if(!length(banned))
		return "Un-jobban?"
	var/job = banned[min(length(A.step_values("unjob")) + 1, length(banned))]
	var/mob/M = A.args["jobban4"]
	return "Job: '[job]' Reason: '[jobban_isbanned(M, job)]' Un-jobban?"

/datum/admins/proc/jobban3_has_rights(datum/act/op/A)
	return actor_admin_can(A.actor, A.authority, R_MOD) || actor_admin_can(A.actor, A.authority, R_ADMIN)

/datum/admins/proc/jobban3_mod_allowed(datum/act/op/A)
	return !(actor_admin_can(A.actor, A.authority, R_MOD) && !actor_admin_can(A.actor, A.authority, R_ADMIN) && !ban_mods_may_jobban())

/datum/admins/proc/jobban3_has_target(datum/act/op/A)
	return !!A.args["jobban4"]

/datum/admins/proc/jobban3_target_not_higher(datum/act/op/A)
	var/mob/M = A.args["jobban4"]
	if(!M || M == A.actor || (A.authority & AUTH_ADMIN)) //we can jobban ourselves
		return TRUE
	return !admin_can(M.client, R_BAN) //they can ban too. So we can't ban them

/datum/admins/proc/jobban3_ready(datum/act/op/A)
	return !!SSjob

/// Writes a job ban for each of `jobs` and tells the player. `mins` is -1 for a permanent ban.
/datum/admins/proc/jobban_apply(mob/user, mob/M, list/jobs, mins, reason)
	var/msg
	for(var/job in jobs)
		if(mins > 0)
			ban_unban_log_save("[key_name(user)] temp-jobbanned [key_name(M)] from [job] for [mins] minutes. reason: [reason]")
			log_admin("[key_name(user)] temp-jobbanned [key_name(M)] from [job] for [mins] minutes")
			feedback_inc("ban_job_tmp",1)
			DB_ban_record(BANTYPE_JOB_TEMP, M, mins, reason, job, 0, null, null, null, FALSE, user)
			feedback_add_details("ban_job_tmp","- [job]")
		else
			ban_unban_log_save("[key_name(user)] perma-jobbanned [key_name(M)] from [job]. reason: [reason]")
			log_admin("[key_name(user)] perma-banned [key_name(M)] from [job]")
			feedback_inc("ban_job",1)
			DB_ban_record(BANTYPE_JOB_PERMA, M, -1, reason, job, 0, null, null, null, FALSE, user)
			feedback_add_details("ban_job","- [job]")
		jobban_fullban(M, job, "[reason]; By [user.ckey] on [time2text(world.realtime)]") //Legacy banning does not support temporary jobbans.
		if(!msg)
			msg = job
		else
			msg += ", [job]"
	notes_add(M.ckey, "Banned  from [msg] - [reason]", user)
	if(mins > 0)
		message_admins(span_blue("[key_name_admin(user)] banned [key_name_admin(M)] from [msg] for [mins] minutes"), 1)
	else
		message_admins(span_blue("[key_name_admin(user)] banned [key_name_admin(M)] from [msg]"), 1)
	to_chat(M, span_filter_system(span_red(span_large(span_bold("You have been jobbanned by [user.ckey] from: [msg].")))))
	to_chat(M, span_filter_system(span_red(span_bold("The reason is: [reason]"))))
	if(mins > 0)
		to_chat(M, span_filter_system(span_red("This jobban will be lifted in [mins] minutes.")))
	else
		to_chat(M, span_filter_system(span_red("Jobban can be lifted only upon request.")))

/// Lifts the job bans of `jobs` from `M` and tells the player.
/datum/admins/proc/jobban_lift(mob/user, mob/M, list/jobs)
	var/msg
	for(var/job in jobs)
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
	message_admins(span_blue("[key_name_admin(user)] unbanned [key_name_admin(M)] from [msg]"), 1)
	to_chat(M, span_filter_system(span_red(span_large("You have been un-jobbanned by [user.ckey] from [msg]."))))

/datum/admins/proc/topic_jobban3(datum/act/op/A, href_jobban3, href_jobban4)
	var/mob/user = A.actor
	var/mob/M = href_jobban4
	if(!M)
		return

	var/list/notbannedlist = jobban3_unbanned_jobs(A)

	//Banning comes first
	if(notbannedlist.len) //at least 1 unbanned job exists in joblist so we have stuff to ban.
		switch(A.step_value("temp"))
			if("Yes")
				if(!actor_admin_can(A.actor, A.authority, R_MOD) && !actor_admin_can(A.actor, A.authority, R_BAN))
					to_chat(user, span_filter_adminlog(span_warning("You cannot issue temporary job-bans!")))
					return
				if(CONFIG_GET(flag/ban_legacy_system))
					to_chat(user, span_filter_adminlog(span_warning("Your server is using the legacy banning system, which does not support temporary job bans. Consider upgrading. Aborting ban.")))
					return
				var/mins = A.step_value("mins")
				if(!mins)
					return
				if(actor_admin_can(A.actor, A.authority, R_MOD) && !actor_admin_can(A.actor, A.authority, R_BAN) && mins > CONFIG_GET(number/mod_job_tempban_max))
					to_chat(user, span_filter_adminlog(span_warning("Moderators can only job tempban up to [CONFIG_GET(number/mod_job_tempban_max)] minutes!")))
					return
				var/reason = A.step_value("reason")
				if(!reason)
					return
				jobban_apply(user, M, notbannedlist, mins, reason)
				return 1
			if("No")
				if(!ban_require(A, R_BAN, "topic_jobban3"))
					return
				var/reason = A.step_value("reason")
				if(reason)
					jobban_apply(user, M, notbannedlist, -1, reason)
					return 1
				return
			else
				return

	//Unbanning joblist
	//all jobs in joblist are banned already OR we didn't give a reason (implying they shouldn't be banned)
	var/list/banned = jobban3_banned_jobs(A)
	if(banned.len) //at least 1 banned job exists in joblist so we have stuff to unban.
		if(!CONFIG_GET(flag/ban_legacy_system))
			to_chat(user, span_filter_adminlog("Unfortunately, database based unbanning cannot be done through this panel"))
			DB_ban_panel(user.client, M.ckey)
			return
		var/list/answers = A.step_values("unjob")
		var/list/lifted = list()
		for(var/i in 1 to min(length(answers), length(banned)))
			if(answers[i] == "Yes")
				lifted += banned[i]
		if(length(lifted))
			jobban_lift(user, M, lifted)
		return 1
	return 0 //we didn't do anything!

/datum/admins/proc/removejobban_question(datum/act/op/A)
	return "Do you want to unjobban [A.args["removejobban"]]?"

/datum/admins/proc/topic_removejobban(datum/act/op/A, href_removejobban)
	var/mob/user = A.actor
	var/t = href_removejobban
	if(!t)
		return
	if(A.step_value("confirm") != "Yes") //No more misclicks! Unless you do it twice.
		return
	log_admin("[key_name(user)] removed [t]")
	message_admins(span_blue("[key_name_admin(user)] removed [t]"), 1)
	jobban_remove(t)
	var/t_split = splittext(t, " - ")
	var/key = t_split[1]
	var/job = t_split[2]
	DB_ban_unban(ckey(key), BANTYPE_JOB_PERMA, job, user)

// ---- kick ----

/// A kick needs a target who does not hold more rights than the actor.
/datum/admins/proc/boot_target_ok(datum/act/op/A)
	return actor_outranks(A.actor, A.authority, A.args["boot2"])

/datum/admins/proc/topic_boot2(datum/act/op/A, href_boot2)
	var/mob/user = A.actor
	var/mob/M = href_boot2
	var/reason = A.step_value("reason")
	if(!reason || QDELETED(M))
		return

	to_chat(M, span_filter_system(span_critical("You have been kicked from the server: [reason]")))
	log_admin("[key_name(user)] booted [key_name(M)] for reason: '[reason]'.")
	message_admins(span_blue("[key_name_admin(user)] booted [key_name_admin(M)] for reason '[reason]'."), 1)
	admin_action_message(user.key, M.key, "kicked", reason, 0)
	spent(M.client, user)

// ---- ban ----

/datum/admins/proc/newban_has_rights(datum/act/op/A)
	return actor_admin_can(A.actor, A.authority, R_MOD) || actor_admin_can(A.actor, A.authority, R_BAN)

/datum/admins/proc/newban_mod_allowed(datum/act/op/A)
	return !(actor_admin_can(A.actor, A.authority, R_MOD) && !actor_admin_can(A.actor, A.authority, R_ADMIN) && !ban_mods_may_jobban())

/datum/admins/proc/newban_target_ok(datum/act/op/A)
	var/mob/M = A.args["newban"]
	if(!M)
		return FALSE
	return !(M.client && admin_can(M.client, R_HOLDER)) //admins cannot be banned. Even if they could, the ban doesn't affect them anyway

/// Writes a temporary ban of `M` for `mins` minutes and tells the player and the admins.
/datum/admins/proc/ban_commit_temp(mob/user, mob/M, mins, reason)
	AddBan(M.ckey, M.computer_id, reason, user.ckey, 1, mins, user = user)
	ban_unban_log_save("[user.ckey] has banned [M.ckey]. - Reason: [reason] - This will be removed in [mins] minutes.")
	notes_add(M.ckey,"[user.ckey] has banned [M.ckey]. - Reason: [reason] - This will be removed in [mins] minutes.",user)
	to_chat(M, span_filter_system(span_critical("You have been banned by [user.ckey].\nReason: [reason].")))
	to_chat(M, span_filter_system(span_warning("This is a temporary ban, it will be removed in [mins] minutes.")))
	feedback_inc("ban_tmp",1)
	DB_ban_record(BANTYPE_TEMP, M, mins, reason, "", 0, null, null, null, FALSE, user)
	feedback_inc("ban_tmp_mins",mins)
	if(CONFIG_GET(string/banappeals))
		to_chat(M, span_filter_system(span_warning("To try to resolve this matter head to [CONFIG_GET(string/banappeals)]")))
	else
		to_chat(M, span_filter_system(span_warning("No ban appeals URL has been set.")))
	log_admin("[user.ckey] has banned [M.ckey].\nReason: [reason]\nThis will be removed in [mins] minutes.")
	message_admins(span_blue("[user.ckey] has banned [M.ckey].\nReason: [reason]\nThis will be removed in [mins] minutes."))
	var/datum/ticket/T = M.client ? M.client.current_ticket() : null
	if(T)
		T.Resolve(user)
	spent(M.client, user)

/// Writes a permanent ban of `M` (with their address too when `ip_ban`) and tells the player and the admins.
/datum/admins/proc/ban_commit_perm(mob/user, mob/M, reason, ip_ban)
	if(ip_ban)
		AddBan(M.ckey, M.computer_id, reason, user.ckey, 0, 0, M.lastKnownIP, user)
	else
		AddBan(M.ckey, M.computer_id, reason, user.ckey, 0, 0, user = user)
	to_chat(M, span_filter_system(span_critical("You have been banned by [user.ckey].\nReason: [reason].")))
	to_chat(M, span_filter_system(span_warning("This is a permanent ban.")))
	if(CONFIG_GET(string/banappeals))
		to_chat(M, span_filter_system(span_warning("To try to resolve this matter head to [CONFIG_GET(string/banappeals)]")))
	else
		to_chat(M, span_filter_system(span_warning("No ban appeals URL has been set.")))
	ban_unban_log_save("[user.ckey] has permabanned [M.ckey]. - Reason: [reason] - This is a permanent ban.")
	notes_add(M.ckey,"[user.ckey] has permabanned [M.ckey]. - Reason: [reason] - This is a permanent ban.",user)
	log_admin("[user.ckey] has banned [M.ckey].\nReason: [reason]\nThis is a permanent ban.")
	message_admins(span_blue("[user.ckey] has banned [M.ckey].\nReason: [reason]\nThis is a permanent ban."))
	feedback_inc("ban_perma",1)
	DB_ban_record(BANTYPE_PERMA, M, -1, reason, "", 0, null, null, null, FALSE, user)
	var/datum/ticket/T = M.client ? M.client.current_ticket() : null
	if(T)
		T.Resolve(user)
	spent(M.client, user)

/datum/admins/proc/topic_newban(datum/act/op/A, href_newban)
	var/mob/user = A.actor
	var/mob/M = href_newban
	if(!M)
		return

	switch(A.step_value("temp"))
		if("Yes")
			var/mins = A.step_value("mins")
			if(!mins)
				return
			if(actor_admin_can(A.actor, A.authority, R_MOD) && !actor_admin_can(A.actor, A.authority, R_BAN) && mins > CONFIG_GET(number/mod_tempban_max))
				to_chat(user, span_warning("Moderators can only job tempban up to [CONFIG_GET(number/mod_tempban_max)] minutes!"))
				return
			if(mins >= 525600)
				mins = 525599
			var/reason = A.step_value("reason")
			if(!reason)
				return
			ban_commit_temp(user, M, mins, reason)
		if("No")
			if(!ban_require(A, R_BAN, "topic_newban"))
				return
			var/reason = A.step_value("reason")
			if(!reason)
				return
			var/ip_answer = A.step_value("ip")
			if(ip_answer != "Yes" && ip_answer != "No")
				return
			ban_commit_perm(user, M, reason, ip_answer == "Yes")

/datum/admins/proc/topic_mute(datum/act/op/A, href_mute, href_mute_type)
	var/mob/user = A.actor
	var/mob/M = href_mute
	if(!M.client)
		return
	var/mute_type = href_mute_type
	if(!isnum(mute_type))
		return
	cmd_admin_mute(M, mute_type, FALSE, user)

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
