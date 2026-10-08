// Admin panel href actions: tickets, permissions, round control, notes and misc panels.
// The owner + href-token gate is extend(TAG_TOPIC, needs(...)) in CAPABILITIES(/datum/admins) (topic_owner_only(), code/modules/admin/topic.dm).


/datum/admins/proc/topic_ticket(datum/act/op/A, href_ticket, href_ticket_action)
	var/mob/user = A.actor
	var/datum/ticket/T = href_ticket
	T.Action(href_ticket_action, user)

/datum/admins/proc/topic_tickets(datum/act/op/A, href_tickets)
	var/mob/user = A.actor
	GLOB.tickets.BrowseTickets(href_tickets, user)

/datum/admins/proc/topic_editrightsbrowser(datum/act/op/A)
	edit_admin_permissions(PERMISSIONS_PAGE_PERMISSIONS)

/datum/admins/proc/topic_editrightsbrowserranks(datum/act/op/A, href_editrightsaddrank, href_editrightsremoverank, href_editrightseditrank)
	var/mob/user = A.actor
	if(href_editrightsaddrank)
		add_rank(user = user)
	else if(href_editrightsremoverank)
		remove_rank(href_editrightsremoverank, user = user)
	else if(href_editrightseditrank)
		change_rank(href_editrightseditrank, user = user)
	edit_admin_permissions(PERMISSIONS_PAGE_RANKS)

/datum/admins/proc/topic_editrightsbrowserlogging(datum/act/op/A, href_editrightslogtarget, href_editrightslogactor, href_editrightslogoperation, href_editrightslogpage)
	edit_admin_permissions(PERMISSIONS_PAGE_LOGGING, href_editrightslogtarget, href_editrightslogactor, href_editrightslogoperation, href_editrightslogpage)

/datum/admins/proc/topic_editrightsbrowserhousekeep(datum/act/op/A, href_editrightschange, href_editrightsremove, href_editrightsremoverank)
	var/mob/user = A.actor
	if(href_editrightschange)
		permission_housekeeping_stage(user, href_editrightschange, FALSE)
	else if(href_editrightsremove)
		permission_housekeeping_stage(user, href_editrightsremove, TRUE)
	else if(href_editrightsremoverank)
		remove_rank(href_editrightsremoverank, user = user)
	edit_admin_permissions(PERMISSIONS_PAGE_HOUSEKEEPING)

/datum/admins/proc/topic_editrights(datum/act/op/A, href_editrights, href_key)
	var/mob/user = A.actor
	edit_rights_topic(href_editrights, href_key, user = user)

/datum/admins/proc/topic_call_shuttle(datum/act/op/A, href_call_shuttle)
	var/mob/user = A.actor
	if(SSticker.mode.name == "blob")
		tgui_alert_async(user, "You can't call the shuttle during blob!")
		return

	switch(href_call_shuttle)
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

/datum/admins/proc/topic_edit_shuttle_time(datum/act/op/A)
	var/mob/user = A.actor
	if(SSemergency_shuttle.wait_for_launch)
		var/new_time_left = topic_ask(user, A.topic_href(), "a1", /datum/prompt/number, question = "Enter new shuttle launch countdown (seconds):", title = "Edit Shuttle Launch Time", default = SSemergency_shuttle.estimate_launch_time())
		if(isnull(new_time_left))
			return

		EXPIRY_SET(SSemergency_shuttle, launch_time, (new_time_left SECONDS), CLOCK_WORLD)

		log_admin("[key_name(user)] edited the Emergency Shuttle's launch time to [new_time_left]")
		message_admins(span_blue("[key_name_admin(user)] edited the Emergency Shuttle's launch time to [new_time_left SECONDS]"), 1)
	else if(SSemergency_shuttle.shuttle.has_arrive_time())
		var/new_time_left = topic_ask(user, A.topic_href(), "a2", /datum/prompt/number, question = "Enter new shuttle arrival time (seconds):", title = "Edit Shuttle Arrival Time", default = SSemergency_shuttle.estimate_arrival_time())
		if(isnull(new_time_left))
			return
		EXPIRY_SET(SSemergency_shuttle.shuttle, arrive_time, (new_time_left SECONDS), CLOCK_WORLD)

		log_admin("[key_name(user)] edited the Emergency Shuttle's arrival time to [new_time_left]")
		message_admins(span_blue("[key_name_admin(user)] edited the Emergency Shuttle's arrival time to [new_time_left SECONDS]"), 1)
	else
		tgui_alert_async(user, "The shuttle is neither counting down to launch nor is it in transit. Please try again when it is.")

/datum/admins/proc/topic_delay_round_end(datum/act/op/A)
	var/mob/user = A.actor
	SSticker.delay_end = !SSticker.delay_end
	log_admin("[key_name(user)] [SSticker.delay_end ? "delayed the round end" : "has made the round end normally"].")
	message_admins(span_blue("[key_name(user)] [SSticker.delay_end ? "delayed the round end" : "has made the round end normally"]."), 1)

MSG_DEF_SELF(admin_topic/round_started, "The game has already started.")
MSG_DEF_SELF(admin_topic/not_secret, "The game mode has to be secret!")

/datum/admins/proc/round_not_started(datum/act/op/A)
	return !(SSticker && SSticker.mode)

/datum/admins/proc/round_is_secret(datum/act/op/A)
	return GLOB.master_mode == "secret"

/// The game modes an admin can pick before the round starts: label -> mode.
/datum/admins/proc/c_mode_choices()
	var/list/label_to_mode = list()
	for(var/mode in config.modes)
		label_to_mode["[config.mode_names[mode]]"] = mode
	label_to_mode["Secret"] = "secret"
	label_to_mode["Random"] = "random"
	return label_to_mode

/datum/admins/proc/c_mode_labels(datum/act/op/A)
	return assoc_to_keys(c_mode_choices())

/datum/admins/proc/c_mode_question(datum/act/op/A)
	return "What mode do you wish to play? (current: [GLOB.master_mode])"

/datum/admins/proc/topic_c_mode(datum/act/op/A)
	var/mob/user = A.actor
	var/pick = A.step_value("mode")
	if(!pick)
		return
	var/picked_mode = c_mode_choices()[pick]
	if(picked_mode)
		admin_set_master_mode(user, picked_mode)

/// The modes a secret round can be forced to: label -> mode.
/datum/admins/proc/f_secret_choices()
	var/list/label_to_mode = list()
	for(var/mode in config.modes)
		label_to_mode["[config.mode_names[mode]]"] = mode
	label_to_mode["Random (default)"] = "secret"
	return label_to_mode

/datum/admins/proc/f_secret_labels(datum/act/op/A)
	return assoc_to_keys(f_secret_choices())

/datum/admins/proc/f_secret_question(datum/act/op/A)
	return "What game mode do you want to force secret to be? (current: [GLOB.secret_force_mode])"

/datum/admins/proc/topic_f_secret(datum/act/op/A)
	var/mob/user = A.actor
	var/pick = A.step_value("mode")
	if(!pick)
		return
	var/picked_mode = f_secret_choices()[pick]
	if(picked_mode)
		admin_set_secret_force_mode(user, picked_mode)

/datum/admins/proc/topic_c_mode2(datum/act/op/A, href_c_mode2)
	var/mob/user = A.actor
	admin_set_master_mode(user, href_c_mode2)

/datum/admins/proc/topic_f_secret2(datum/act/op/A, href_f_secret2)
	var/mob/user = A.actor
	admin_set_secret_force_mode(user, href_f_secret2)

/// Sets the round's game mode before it starts.
/datum/admins/proc/admin_set_master_mode(mob/user, mode)
	if(!check_rights_for(user?.client, R_ADMIN|R_SERVER|R_EVENT) || !mode)
		return
	if(SSticker && SSticker.mode)
		tgui_alert_async(user, "The game has already started.")
		return
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
		tgui_alert_async(user, "The game has already started.")
		return
	if(GLOB.master_mode != "secret")
		tgui_alert_async(user, "The game mode has to be secret!")
		return
	GLOB.secret_force_mode = mode
	log_admin("[key_name(user)] set the forced secret mode as [GLOB.secret_force_mode].")
	message_admins(span_blue("[key_name_admin(user)] set the forced secret mode as [GLOB.secret_force_mode]."))
	Game() // updates the main game menu

/datum/admins/proc/topic_check_antagonist(datum/act/op/A)
	var/mob/user = A.actor
	check_antagonists(user.client)

/datum/admins/proc/topic_viewruntime(datum/act/op/A, href_viewruntime, href_viewruntime_backto, href_viewruntime_linear)
	var/datum/error_viewer/error_viewer = href_viewruntime
	error_viewer.show_to(owner(), href_viewruntime_backto, href_viewruntime_linear)

/datum/admins/proc/topic_adminchecklaws(datum/act/op/A)
	var/mob/user = A.actor
	output_ai_laws(user)

/datum/admins/proc/topic_spawn_panel(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/spawn_panel)

/datum/admins/proc/topic_populate_inactive_customitems(datum/act/op/A)
	populate_inactive_customitems_list(owner())

// GLOB.vsc was a ZAS atmos-tuning settings holder; removed in LINDA
// migration since LINDA tuning is compile-time in auxmos. Stub admin response.
/datum/admins/proc/topic_vsc(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_warning("Atmos config (GLOB.vsc) is a ZAS feature; under LINDA, tuning lives at the auxmos crate level."))

/datum/admins/proc/topic_notes(datum/act/op/op_act, href_notes, href_ckey, href_mob, href_index)
	var/mob/user = op_act.actor
	var/ckey = href_ckey
	if(!ckey)
		var/mob/M = href_mob
		if(M)
			ckey = M.ckey

	switch(href_notes)
		if("show")
			var/datum/tgui_module/player_notes_info/A = new(src)
			A.key = ckey
			A.tgui_interact(user)
		if("list")
			PlayerNotesPage(user, href_index)

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
