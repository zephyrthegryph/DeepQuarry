// Admin panel href actions: tickets, permissions, round control, notes and misc panels.
// The owner + href-token gate is /datum/admins/topic_allowed() (code/modules/admin/topic.dm).

TOPIC_ACTION(/datum/admins, "ticket", PROC_REF(topic_ticket), TOPIC_RIGHTS(R_ADMIN|R_MOD|R_DEBUG|R_EVENT|R_MENTOR), TOPIC_REF("ticket", /datum/ticket), TOPIC_TEXT("ticket_action"))
TOPIC_ACTION(/datum/admins, "tickets", PROC_REF(topic_tickets), TOPIC_NUM("tickets"))
TOPIC_ACTION(/datum/admins, "editrightsbrowser", PROC_REF(topic_editrightsbrowser), TOPIC_RIGHTS(R_PERMISSIONS))
TOPIC_ACTION(/datum/admins, "editrightsbrowserranks", PROC_REF(topic_editrightsbrowserranks), TOPIC_RIGHTS(R_PERMISSIONS), TOPIC_TEXT("editrightsaddrank"), TOPIC_TEXT("editrightsremoverank"), TOPIC_TEXT("editrightseditrank"))
TOPIC_ACTION(/datum/admins, "editrightsbrowserlogging", PROC_REF(topic_editrightsbrowserlogging), TOPIC_RIGHTS(R_PERMISSIONS), TOPIC_TEXT("editrightslogtarget"), TOPIC_TEXT("editrightslogactor"), TOPIC_TEXT("editrightslogoperation"), TOPIC_TEXT("editrightslogpage"))
TOPIC_ACTION(/datum/admins, "editrightsbrowserhousekeep", PROC_REF(topic_editrightsbrowserhousekeep), TOPIC_RIGHTS(R_PERMISSIONS), TOPIC_TEXT("editrightschange"), TOPIC_TEXT("editrightsremove"), TOPIC_TEXT("editrightsremoverank"))
TOPIC_ACTION(/datum/admins, "editrights", PROC_REF(topic_editrights), TOPIC_RIGHTS(R_PERMISSIONS), TOPIC_TEXT("editrights"), TOPIC_TEXT("key"))
TOPIC_ACTION(/datum/admins, "call_shuttle", PROC_REF(topic_call_shuttle), TOPIC_RIGHTS(R_ADMIN|R_EVENT), TOPIC_TEXT("call_shuttle"))
TOPIC_ACTION(/datum/admins, "edit_shuttle_time", PROC_REF(topic_edit_shuttle_time), TOPIC_RIGHTS(R_SERVER))
TOPIC_ACTION(/datum/admins, "delay_round_end", PROC_REF(topic_delay_round_end), TOPIC_RIGHTS(R_SERVER))
TOPIC_ACTION(/datum/admins, "c_mode", PROC_REF(topic_c_mode), TOPIC_RIGHTS(R_ADMIN|R_EVENT))
TOPIC_ACTION(/datum/admins, "f_secret", PROC_REF(topic_f_secret), TOPIC_RIGHTS(R_ADMIN|R_EVENT))
TOPIC_ACTION(/datum/admins, "c_mode2", PROC_REF(topic_c_mode2), TOPIC_TEXT("c_mode2"))
TOPIC_ACTION(/datum/admins, "f_secret2", PROC_REF(topic_f_secret2), TOPIC_TEXT("f_secret2"))
TOPIC_ACTION(/datum/admins, "check_antagonist", PROC_REF(topic_check_antagonist))
TOPIC_ACTION(/datum/admins, "secretsadmin=check_antagonist", PROC_REF(topic_check_antagonist))
TOPIC_ACTION(/datum/admins, "viewruntime", PROC_REF(topic_viewruntime), TOPIC_REF("viewruntime", /datum/error_viewer), TOPIC_REF("viewruntime_backto", /datum/error_viewer), TOPIC_TEXT("viewruntime_linear"))
TOPIC_ACTION(/datum/admins, "adminchecklaws", PROC_REF(topic_adminchecklaws))
TOPIC_ACTION(/datum/admins, "spawn_panel", PROC_REF(topic_spawn_panel))
TOPIC_ACTION(/datum/admins, "populate_inactive_customitems", PROC_REF(topic_populate_inactive_customitems), TOPIC_RIGHTS(R_ADMIN|R_SERVER))
TOPIC_ACTION(/datum/admins, "vsc", PROC_REF(topic_vsc), TOPIC_RIGHTS(R_ADMIN|R_SERVER|R_EVENT))
TOPIC_ACTION(/datum/admins, "notes", PROC_REF(topic_notes), TOPIC_TEXT("notes"), TOPIC_TEXT("ckey"), TOPIC_REF("mob", /mob), TOPIC_NUM("index"))

/datum/admins/proc/topic_ticket(mob/user, list/args)
	var/datum/ticket/T = args["ticket"]
	T.Action(args["ticket_action"], user)

/datum/admins/proc/topic_tickets(mob/user, list/args)
	GLOB.tickets.BrowseTickets(args["tickets"], user)

/datum/admins/proc/topic_editrightsbrowser(mob/user, list/args)
	edit_admin_permissions(PERMISSIONS_PAGE_PERMISSIONS)

/datum/admins/proc/topic_editrightsbrowserranks(mob/user, list/args)
	if(args["editrightsaddrank"])
		add_rank(user = user)
	else if(args["editrightsremoverank"])
		remove_rank(args["editrightsremoverank"], user = user)
	else if(args["editrightseditrank"])
		change_rank(args["editrightseditrank"], user = user)
	edit_admin_permissions(PERMISSIONS_PAGE_RANKS)

/datum/admins/proc/topic_editrightsbrowserlogging(mob/user, list/args)
	edit_admin_permissions(PERMISSIONS_PAGE_LOGGING, args["editrightslogtarget"], args["editrightslogactor"], args["editrightslogoperation"], args["editrightslogpage"])

/datum/admins/proc/topic_editrightsbrowserhousekeep(mob/user, list/args)
	if(args["editrightschange"])
		permission_housekeeping_stage(user, args["editrightschange"], FALSE)
	else if(args["editrightsremove"])
		permission_housekeeping_stage(user, args["editrightsremove"], TRUE)
	else if(args["editrightsremoverank"])
		remove_rank(args["editrightsremoverank"], user = user)
	edit_admin_permissions(PERMISSIONS_PAGE_HOUSEKEEPING)

/datum/admins/proc/topic_editrights(mob/user, list/args)
	edit_rights_topic(args["editrights"], args["key"], user = user)

/datum/admins/proc/topic_call_shuttle(mob/user, list/args)
	if(SSticker.mode.name == "blob")
		tgui_alert_async(user, "You can't call the shuttle during blob!")
		return

	switch(args["call_shuttle"])
		if("1")
			if(!SSticker || !SSemergency_shuttle.location())
				return
			if(SSemergency_shuttle.can_call())
				SSemergency_shuttle.call_evac()
				log_admin("[key_name(user)] called the Emergency Shuttle")
				message_admins(span_blue("[key_name_admin(user)] called the Emergency Shuttle to the station."), 1)

		if("2")
			if(!SSticker || !SSemergency_shuttle.location())
				return
			if(SSemergency_shuttle.can_call())
				SSemergency_shuttle.call_evac()
				log_admin("[key_name(user)] called the Emergency Shuttle")
				message_admins(span_blue("[key_name_admin(user)] called the Emergency Shuttle to the station."), 1)

			else if(SSemergency_shuttle.can_recall())
				SSemergency_shuttle.recall()
				log_admin("[key_name(user)] sent the Emergency Shuttle back")
				message_admins(span_blue("[key_name_admin(user)] sent the Emergency Shuttle back."), 1)

/datum/admins/proc/topic_edit_shuttle_time(mob/user, list/args)
	if(SSemergency_shuttle.wait_for_launch)
		var/new_time_left = topic_ask(user, args, "a1", /datum/prompt/number, question = "Enter new shuttle launch countdown (seconds):", title = "Edit Shuttle Launch Time", default = SSemergency_shuttle.estimate_launch_time())
		if(isnull(new_time_left))
			return

		EXPIRY_SET(SSemergency_shuttle, launch_time, (new_time_left SECONDS), CLOCK_WORLD)

		log_admin("[key_name(user)] edited the Emergency Shuttle's launch time to [new_time_left]")
		message_admins(span_blue("[key_name_admin(user)] edited the Emergency Shuttle's launch time to [new_time_left SECONDS]"), 1)
	else if(SSemergency_shuttle.shuttle.has_arrive_time())
		var/new_time_left = topic_ask(user, args, "a2", /datum/prompt/number, question = "Enter new shuttle arrival time (seconds):", title = "Edit Shuttle Arrival Time", default = SSemergency_shuttle.estimate_arrival_time())
		if(isnull(new_time_left))
			return
		EXPIRY_SET(SSemergency_shuttle.shuttle, arrive_time, (new_time_left SECONDS), CLOCK_WORLD)

		log_admin("[key_name(user)] edited the Emergency Shuttle's arrival time to [new_time_left]")
		message_admins(span_blue("[key_name_admin(user)] edited the Emergency Shuttle's arrival time to [new_time_left SECONDS]"), 1)
	else
		tgui_alert_async(user, "The shuttle is neither counting down to launch nor is it in transit. Please try again when it is.")

/datum/admins/proc/topic_delay_round_end(mob/user, list/args)
	SSticker.delay_end = !SSticker.delay_end
	log_admin("[key_name(user)] [SSticker.delay_end ? "delayed the round end" : "has made the round end normally"].")
	message_admins(span_blue("[key_name(user)] [SSticker.delay_end ? "delayed the round end" : "has made the round end normally"]."), 1)

/datum/admins/proc/topic_c_mode(mob/user, list/args)
	if(SSticker && SSticker.mode)
		return tgui_alert_async(user, "The game has already started.")
	var/list/labels = list()
	var/list/label_to_mode = list()
	for(var/mode in config.modes)
		var/label = "[config.mode_names[mode]]"
		labels += label
		label_to_mode[label] = mode
	labels += "Secret"
	label_to_mode["Secret"] = "secret"
	labels += "Random"
	label_to_mode["Random"] = "random"
	var/datum/request/replayed = round_mode_topic_request(user, args, "a21")
	if(!replayed)
		var/list/original_href = args[TOPIC_HREF]
		var/list/saved_href = original_href.Copy()
		saved_href -= "round_mode_request"
		open_request(src, /datum/prompt/choice/admin_round_mode_topic, PROC_REF(round_mode_topic_answered), answerer = user, captured = list("href" = saved_href), step_name = "a21", question = "What mode do you wish to play? (current: [GLOB.master_mode])", title = "Game Mode", choices = labels)
		return
	var/pick = replayed.value
	if(!pick)
		return
	var/picked_mode = label_to_mode[pick]
	if(picked_mode)
		admin_set_master_mode(user, picked_mode)

/datum/admins/proc/topic_f_secret(mob/user, list/args)
	if(SSticker && SSticker.mode)
		return tgui_alert_async(user, "The game has already started.")
	if(GLOB.master_mode != "secret")
		return tgui_alert_async(user, "The game mode has to be secret!")
	var/list/labels = list()
	var/list/label_to_mode = list()
	for(var/mode in config.modes)
		var/label = "[config.mode_names[mode]]"
		labels += label
		label_to_mode[label] = mode
	labels += "Random (default)"
	label_to_mode["Random (default)"] = "secret"
	var/datum/request/replayed = round_mode_topic_request(user, args, "a22")
	if(!replayed)
		var/list/original_href = args[TOPIC_HREF]
		var/list/saved_href = original_href.Copy()
		saved_href -= "round_mode_request"
		open_request(src, /datum/prompt/choice/admin_round_mode_topic, PROC_REF(round_mode_topic_answered), answerer = user, captured = list("href" = saved_href), step_name = "a22", question = "What game mode do you want to force secret to be? (current: [GLOB.secret_force_mode])", title = "Force Secret", choices = labels)
		return
	var/pick = replayed.value
	if(!pick)
		return
	var/picked_mode = label_to_mode[pick]
	if(picked_mode)
		admin_set_secret_force_mode(user, picked_mode)

/datum/admins/proc/topic_c_mode2(mob/user, list/args)
	admin_set_master_mode(user, args["c_mode2"])

/datum/admins/proc/topic_f_secret2(mob/user, list/args)
	admin_set_secret_force_mode(user, args["f_secret2"])

/// Sets the round's game mode before it starts.
/datum/admins/proc/admin_set_master_mode(mob/user, mode)
	if(!check_rights_for(user?.client, R_ADMIN|R_SERVER|R_EVENT) || !mode)
		return
	if(SSticker && SSticker.mode)
		return tgui_alert_async(user, "The game has already started.")
	GLOB.master_mode = mode
	log_admin("[key_name(user)] set the mode as [config.mode_names[GLOB.master_mode]].")
	message_admins(span_blue("[key_name_admin(user)] set the mode as [config.mode_names[GLOB.master_mode]]."))
	to_chat(world, span_world(span_blue("The mode is now: [config.mode_names[GLOB.master_mode]]")))
	Game() // updates the main game menu
	world.save_mode(GLOB.master_mode)

/// Sets the mode a secret round will actually run.
/datum/admins/proc/admin_set_secret_force_mode(mob/user, mode)
	if(!check_rights_for(user?.client, R_ADMIN|R_SERVER|R_EVENT) || !mode)
		return
	if(SSticker && SSticker.mode)
		return tgui_alert_async(user, "The game has already started.")
	if(GLOB.master_mode != "secret")
		return tgui_alert_async(user, "The game mode has to be secret!")
	GLOB.secret_force_mode = mode
	log_admin("[key_name(user)] set the forced secret mode as [GLOB.secret_force_mode].")
	message_admins(span_blue("[key_name_admin(user)] set the forced secret mode as [GLOB.secret_force_mode]."))
	Game() // updates the main game menu

/datum/admins/proc/topic_check_antagonist(mob/user, list/args)
	check_antagonists(user.client)

/datum/admins/proc/topic_viewruntime(mob/user, list/args)
	var/datum/error_viewer/error_viewer = args["viewruntime"]
	error_viewer.show_to(owner(), args["viewruntime_backto"], args["viewruntime_linear"])

/datum/admins/proc/topic_adminchecklaws(mob/user, list/args)
	output_ai_laws(user)

/datum/admins/proc/topic_spawn_panel(mob/user, list/args)
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/spawn_panel)

/datum/admins/proc/topic_populate_inactive_customitems(mob/user, list/args)
	populate_inactive_customitems_list(owner())

// GLOB.vsc was a ZAS atmos-tuning settings holder; removed in LINDA
// migration since LINDA tuning is compile-time in auxmos. Stub admin response.
/datum/admins/proc/topic_vsc(mob/user, list/args)
	to_chat(user, span_warning("Atmos config (GLOB.vsc) is a ZAS feature; under LINDA, tuning lives at the auxmos crate level."))

/datum/admins/proc/topic_notes(mob/user, list/args)
	var/ckey = args["ckey"]
	if(!ckey)
		var/mob/M = args["mob"]
		if(M)
			ckey = M.ckey

	switch(args["notes"])
		if("show")
			var/datum/tgui_module/player_notes_info/A = new(src)
			A.key = ckey
			A.tgui_interact(user)
		if("list")
			PlayerNotesPage(user, args["index"])

/datum/prompt/choice/admin_round_mode_topic
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/admin_round_mode_topic/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return null

/datum/prompt/choice/admin_round_mode_topic/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_round_mode_topic/refusal(given)
	return null

/datum/admins/proc/round_mode_topic_request(mob/user, list/args, key)
	RETURN_TYPE(/datum/request)
	var/list/href = args[TOPIC_HREF]
	var/datum/request/replayed = href["round_mode_request"]
	if(!istype(replayed, /datum/prompt/choice/admin_round_mode_topic) || replayed.owner != src || replayed.answerer != user || replayed.outcome != REQ_ANSWERED || replayed.is_open() || QDELETED(replayed) || replayed.handler != PROC_REF(round_mode_topic_answered) || replayed.step_name != key)
		return null
	return replayed

/datum/admins/proc/round_mode_topic_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/list/original_href = A.answer.captured["href"]
	var/list/replayed_href = original_href.Copy()
	replayed_href["round_mode_request"] = A.answer
	var/mob/actor = A.request.answerer
	world.push_usr(actor, new /datum/callback(GLOBAL_PROC, GLOBAL_PROC_REF(topic_dispatch)), src, actor, replayed_href)
