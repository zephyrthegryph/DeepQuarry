//By Carnwennan
//fetches an external list and processes it into a list of ip addresses.
//It then stores the processed list into a savefile for later use
#define TORFILE "data/ToR_ban.bdb"
#define TOR_UPDATE_INTERVAL 216000	//~6 hours

/proc/ToRban_isbanned(ip_address)
	var/savefile/F = new(TORFILE)
	if(F)
		if( ip_address in F.dir )
			return 1
	return 0

/proc/ToRban_autoupdate()
	var/savefile/F = new(TORFILE)
	if(F)
		var/last_update
		F["last_update"] >> last_update
		if((last_update + TOR_UPDATE_INTERVAL) < world.realtime)	//we haven't updated for a while
			ToRban_update()
	return

/// after() target from world/New: the ToR list refresh, if enabled.
/proc/ToRban_autoupdate_if_enabled()
	if(CONFIG_GET(flag/ToRban))
		ToRban_autoupdate()

/// Downloads the ToR exit list on the I/O lane (io_job); returns at once. `requester` (optional)
/// is told when the update lands.
/proc/ToRban_update(client/requester)
	log_world("Downloading updated ToR data...")
	io_job(null, /datum/io_backend/http, RUSTG_HTTP_METHOD_GET, "https://check.torproject.org/exit-addresses", "", null, /proc/ToRban_update_done, requester?.ckey)

/// io_job() callback: stores the downloaded exit addresses.
/proc/ToRban_update_done(response_arg, error, requester_ckey)
	var/datum/http_response/response = response_arg
	if(error || !response?.body)
		log_world("ToR data update aborted: [error || "no data"].")
		return
	var/list/rawlist = splittext(response.body, "\n")
	if(rawlist.len)
		fdel(TORFILE)
		var/savefile/F = new(TORFILE)
		for( var/line in rawlist )
			if(!line)	continue
			if( copytext(line,1,12) == "ExitAddress" )
				var/cleaned = copytext(line,13,length(line)-19)
				if(!cleaned)	continue
				F[cleaned] << 1
		F["last_update"] << world.realtime
		log_world("ToR data updated!")
		var/client/requester = requester_ckey && GLOB.directory[requester_ckey]
		if(requester)
			to_chat(requester, span_filter_adminlog("ToRban updated."))
		return
	log_world("ToR data update aborted: no data.")

ADMIN_VERB(ToRban, R_ADMIN|R_SERVER, "ToRban", "Modifies the TorBan settings.", ADMIN_CATEGORY_SERVER_CONFIG)
	// Replay input is only a synchronous answered request from this verb.
	var/list/replay_answers = list()
	if(length(args) > 1)
		var/datum/request/resumed = args[2]
		if(istype(resumed, /datum/prompt/choice/admin_tor_menu_replay) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(ToRban_replay_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	if(!("a1" in replay_answers))
		open_request(src, /datum/prompt/choice/admin_tor_menu_replay, PROC_REF(ToRban_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a1", question = "What do you want to do?", title = "Select Option", choices = list("update","toggle","show","remove","remove all","find"))
		return
	var/task = replay_answers["a1"]
	if(isnull(task))
		return
	switch(task)
		if("update")
			ToRban_update(user)
		if("toggle")
			if(config)
				if(CONFIG_GET(flag/ToRban))
					CONFIG_SET(flag/ToRban, FALSE)
					message_admins(span_red("ToR banning disabled."))
				else
					CONFIG_SET(flag/ToRban, TRUE)
					message_admins(span_green("ToR banning enabled."))
		if("show")
			// Torban list now uses a structured TGUI panel.
			var/savefile/F = new(TORFILE)
			var/list/addresses = list()
			if(length(F.dir))
				for(var/i=1, i<=length(F.dir), i++)
					addresses += F.dir[i]
			var/datum/dq_torban_panel/panel = new(addresses)
			panel.tgui_interact(user.mob)

		if("remove")
			var/savefile/F = new(TORFILE)
			if(QDELETED(user.mob))
				return
			open_request(src, /datum/prompt/choice/admin_tor_remove, PROC_REF(address_selected), answerer = user.mob, choices = F.dir)
		if("remove all")
			to_chat(user, span_filter_adminlog(span_bold("[TORFILE] was [fdel(TORFILE)?"":"not "]removed.")))
		if("find")
			if(QDELETED(user.mob))
				return
			open_request(src, /datum/prompt/text/admin_tor_find, PROC_REF(address_entered), answerer = user.mob)
	return

/datum/admin_verb/ToRban/proc/address_selected(datum/act/request/context)
	if(!context.answer)
		return
	remove_address(context)

/datum/admin_verb/ToRban/proc/remove_address(datum/act/request/context)
	var/client/user = context.request.answerer.client
	var/choice = context.request.value
	var/savefile/F = new(TORFILE)
	if(choice)
		F.dir.Remove(choice)
		to_chat(user, span_filter_adminlog(span_bold("Address removed")))

/datum/admin_verb/ToRban/proc/address_entered(datum/act/request/context)
	if(!context.answer)
		return
	find_address(context)

/datum/admin_verb/ToRban/proc/find_address(datum/act/request/context)
	var/client/user = context.request.answerer.client
	var/input = context.request.value
	if(input)
		if(ToRban_isbanned(input))
			to_chat(user, span_filter_adminlog("[span_orange(span_bold("Address is a known ToR address"))]"))
		else
			to_chat(user, span_filter_adminlog(span_danger("Address is not a known ToR address")))

/datum/prompt/choice/admin_tor_remove
	rights = R_ADMIN|R_SERVER
	timeout = 0
	title = "Remove ToR ban"
	question = "Please select an IP address to remove from the ToR banlist:"
	recheck_on_open = TRUE

/datum/prompt/text/admin_tor_find
	rights = R_ADMIN|R_SERVER
	timeout = 0
	title = "Find ToR ban"
	question = "Please input an IP address to search for:"
	recheck_on_open = TRUE

#undef TORFILE
#undef TOR_UPDATE_INTERVAL

/datum/prompt/choice/admin_tor_menu_replay
	timeout = 0
	rights = R_ADMIN|R_SERVER
	recheck_on_open = TRUE

/datum/prompt/choice/admin_tor_menu_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_tor_menu_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_tor_menu_replay/refusal(given)
	return null

/datum/admin_verb/ToRban/proc/ToRban_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)
