GLOBAL_VAR_INIT(floorIsLava, 0)


////////////////////////////////
/proc/message_admins(msg)
	msg = span_filter_adminlog(span_log_message(span_prefix("ADMIN LOG:") + span_message("[msg]")))
	//log_admin_private(msg) //log_and_message_admins is for this

	for(var/client/C in GLOB.admins)
		if(check_rights_for(C, (R_ADMIN|R_MOD|R_SERVER)))
			to_chat(C,
					type = MESSAGE_TYPE_ADMINLOG,
					html = msg,
					confidential = TRUE)

/proc/msg_admin_attack(text) //Toggleable Attack Messages
	var/rendered = span_filter_attacklog(span_log_message(span_prefix("ATTACK:") + span_message("[text]")))
	for(var/client/C in GLOB.admins)
		if(check_rights_for(C, (R_ADMIN|R_MOD)))
			if(C.prefs?.read_preference(/datum/preference/toggle/show_attack_logs))
				var/msg = rendered
				to_chat(C,
						type = MESSAGE_TYPE_ATTACKLOG,
						html = msg,
						confidential = TRUE)

/proc/admin_notice(message, rights)
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		var/C = M.client

		if(!C)
			continue

		if(!(istype(C, /client)))
			continue

		if(check_rights_for(C, rights))
			to_chat(C, message)

///////////////////////////////////////////////////////////////////////////////////////////////Panels

// Show Player Panel context-menu verb now opens a structured TGUI panel.
// The legacy 200-line HTML body has been deleted; ac_* / mute / dna / simplemake
// handlers in /datum/admins.Topic still own the per-action behavior.
ADMIN_VERB_ONLY_CONTEXT_MENU(show_player_panel, R_HOLDER, "Show Player Panel", mob/player in world)
	log_admin("[key_name(user)] checked the individual player panel for [key_name(player)][isobserver(user.mob)?"":" while in game"].")
	if(!player)
		to_chat(user, "You seem to be selecting a mob that doesn't exist anymore.")
		return
	user.holder?.dq_open_edit_player_panel(player)
	feedback_add_details("admin_verb","SPP")


/datum/player_info/var/author // admin who authored the information
/datum/player_info/var/rank //rank of admin who made the notes
/datum/player_info/var/content // text content of the information
/datum/player_info/var/timestamp // Because this is bloody annoying

ADMIN_VERB(PlayerNotes, R_ADMIN|R_MOD|R_EVENT|R_DEBUG, "Player Notes", "Access the player notes.", ADMIN_CATEGORY_INVESTIGATE)
	user.holder.PlayerNotesPage(user.mob, 1)

/datum/admins/proc/PlayerNotesPage(mob/user, page)
	var/savefile/S=new("data/player_notes.sav")
	var/list/note_keys
	S >> note_keys

	if(note_keys)
		note_keys = sortList(note_keys)

	var/datum/tgui_module/player_notes/A = new(src)
	A.ckeys = note_keys
	A.tgui_interact(user)


/datum/admins/proc/player_has_info(key as text)
	var/savefile/info = new("data/player_saves/[copytext(key, 1, 2)]/[key]/info.sav")
	var/list/infos
	info >> infos
	if(!infos || !infos.len) return 0
	else return 1

ADMIN_VERB(show_player_info, R_ADMIN|R_MOD|R_EVENT|R_DEBUG, "Show Player Info", "Access the player info.", ADMIN_CATEGORY_INVESTIGATE)
	var/datum/tgui_module/player_notes_info/A = new(src)
	A.tgui_interact(user.mob)

// access_news_network now opens a structured TGUI panel.
// The legacy switch-driven HTML builder is gone; ac_* Topic handlers
// in /datum/admins.Topic still own state transitions, and the panel
// refreshes after each click via SStgui.update_uis().
ADMIN_VERB(access_news_network, R_ADMIN|R_EVENT, "Access Newscaster Network", "Allows you to view, add and edit news feeds.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	user.holder?.dq_open_newscaster_panel()


/datum/admins/proc/Jobbans() // rights (R_BAN) are declared by the jobbans ADMIN_VERB
	var/dat = span_bold("Job Bans!") + "<HR><table>"
	for(var/t in GLOB.jobban_keylist)
		var/r = t
		if( findtext(r,"##") )
			r = copytext( r, 1, findtext(r,"##") )//removes the description
		dat += text("<tr><td>[t] (<a href='byond://?src=[REF(src)];[HrefToken()];removejobban=[r]'>unban</a>)</td></tr>")
	dat += "</table>"

	// structured TGUI AdminReport; byond:// links forwarded to host.
	dq_admin_report_html(owner(), "Job Bans", dat, src)

/datum/admins/proc/Game()
	if(!admin_require(owner(), 0, "Game", TRUE))	return
	open_game_panel(owner()?.mob)

/////////////////////////////////////////////////////////////////////////////////////////////////admins2.dm merge
//i.e. buttons/verbs

#define REGULAR_RESTART "Regular Restart"
#define REGULAR_RESTART_DELAYED "Regular Restart (with delay)"
#define HARD_RESTART "Hard Restart (No Delay/Feedback Reason)"
#define HARDEST_RESTART "Hardest Restart (No actions, just reboot)"
#define TGS_RESTART "Server Restart (Kill and restart DD)"
ADMIN_VERB(restart, R_SERVER, "Reboot World", "Restarts the world immediately.", ADMIN_CATEGORY_SERVER_GAME)
	// Only this verb's actual ended native request supplies replay answers.
	var/list/replay_answers = list()
	if(length(args) > 1)
		var/datum/request/resumed = args[2]
		if((istype(resumed, /datum/prompt/choice/admin_restart_replay) || istype(resumed, /datum/prompt/number/admin_restart_replay)) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(restart_replay_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	var/list/options = list(REGULAR_RESTART, REGULAR_RESTART_DELAYED, HARD_RESTART)

	// this option runs a codepath that can leak db connections because it skips subsystem (specifically SSdbcore) shutdown
	if(!SSdbcore.IsConnected())
		options += HARDEST_RESTART

	if(world.TgsAvailable())
		options += TGS_RESTART;

	if(SSticker.admin_delay_notice)
		if(!("delayed" in replay_answers))
			open_request(src, /datum/prompt/choice/admin_restart_replay, PROC_REF(restart_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "delayed", buttons = TRUE, question = "Are you sure? An admin has already delayed the round end for the following reason: [SSticker.admin_delay_notice]", title = "Confirmation", choices = list("Yes", "No"))
			return
		var/sure = replay_answers["delayed"]
		if(sure != "Yes")
			return FALSE

	if(!("method" in replay_answers))
		open_request(src, /datum/prompt/choice/admin_restart_replay, PROC_REF(restart_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "method", question = "Select reboot method", title = "World Reboot", choices = options, default = options[1])
		return
	var/result = replay_answers["method"]
	if(isnull(result))
		return
	var/delay = 0
	if(result == REGULAR_RESTART_DELAYED)
		if(!("delay" in replay_answers))
			open_request(src, /datum/prompt/number/admin_restart_replay, PROC_REF(restart_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "delay", question = "What delay should the restart have (in seconds)?", title = "Restart Delay", default = 5)
			return
		delay = replay_answers["delay"]
		if(!delay)
			return FALSE
	if((result == REGULAR_RESTART || result == REGULAR_RESTART_DELAYED) && !user.is_localhost())
		if(!("live" in replay_answers))
			open_request(src, /datum/prompt/choice/admin_restart_replay, PROC_REF(restart_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "live", buttons = TRUE, question = "Are you sure you want to restart the server?", title = "This server is live", choices = list("Restart", "Cancel"))
			return
		var/live = replay_answers["live"]
		if(live != "Restart")
			return FALSE

	feedback_add_details("admin_verb","R")
	if(GLOB.blackbox)
		GLOB.blackbox.save_all_data_to_sql()

	var/init_by = "Initiated by [user.holder.fakekey ? "Admin" : user.key]."
	switch(result)
		if(REGULAR_RESTART)
			SSticker.Reboot(init_by, "admin reboot - by [user.key] [user.holder.fakekey ? "(stealth)" : ""]", 10)
		if(REGULAR_RESTART_DELAYED)
			SSticker.Reboot(init_by, "admin reboot - by [user.key] [user.holder.fakekey ? "(stealth)" : ""]", delay * 10)
		if(HARD_RESTART)
			to_chat(world, "World reboot - [init_by]")
			world.Reboot()
		if(HARDEST_RESTART)
			to_chat(world, "Hard world reboot - [init_by]")
			world.Reboot(fast_track = TRUE)
		if(TGS_RESTART)
			to_chat(world, "Server restart - [init_by]")
			world.TgsEndProcess()

#undef REGULAR_RESTART
#undef REGULAR_RESTART_DELAYED
#undef HARD_RESTART
#undef HARDEST_RESTART
#undef TGS_RESTART

ADMIN_VERB(cancel_reboot, R_SERVER, "Cancel Reboot", "Cancels a pending world reboot.", ADMIN_CATEGORY_SERVER_GAME)
	if(!SSticker.cancel_reboot(user))
		return
	log_admin("[key_name(user)] cancelled the pending world reboot.")
	message_admins("[key_name_admin(user)] cancelled the pending world reboot.")

ADMIN_VERB(announce, R_SERVER|R_ADMIN|R_EVENT, "Announce", "Announce your desires to the world.", ADMIN_CATEGORY_CHAT)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/text/admin_announcement, PROC_REF(announcement_answered), answerer = answerer)

/datum/admin_verb/announce/proc/announcement_answered(datum/act/request/A)
	if(!A.answer)
		return
	send_announcement(A)

/datum/admin_verb/announce/proc/send_announcement(datum/act/request/A)
	var/client/user = A.request.answerer.client
	var/message = A.request.value
	if(!message)
		return

	if(!check_rights_for(user, R_SERVER))
		message = sanitize(message, 500, extra = 0)
	message = replacetext(message, "\n", "<br>") // required since we're putting it in a <p> tag
	send_ooc_announcement(message, "From [user.holder.fakekey ? "Administrator" : user.key]")
	log_admin("Announce: [key_name(user)] : [message]")
	feedback_add_details("admin_verb","A") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(intercom, R_ADMIN|R_EVENT, "Intercom Msg", "Send an intercom message, like an arrivals announcement.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	return advance_intercom(user)

/datum/admin_verb/intercom/proc/intercom_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/next_stage = 1
	var/channel
	var/sender
	var/message
	var/msgverb
	if(istype(A.request, /datum/prompt/text/admin_intercom))
		var/datum/prompt/text/admin_intercom/ask = A.request
		next_stage = ask.next_stage
		channel = ask.channel
		sender = next_stage == 2 ? ask.value : ask.sender
		message = next_stage == 3 ? ask.value : ask.message
		msgverb = next_stage == 4 ? ask.value : null
	else
		channel = A.request.value
	advance_intercom(A.request.answerer.client, next_stage, channel, sender, message, msgverb)

/datum/admin_verb/intercom/proc/advance_intercom(client/user, stage = 0, channel = null, sender = null, message = null, msgverb = null)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	if(stage == 0)
		open_request(src, /datum/prompt/choice/admin_intercom_channel, PROC_REF(intercom_answered), answerer = answerer, choices = GLOB.radiochannels)
		return
	if(!channel)
		return
	if(stage == 1)
		open_request(src, /datum/prompt/text/admin_intercom, PROC_REF(intercom_answered), answerer = answerer, question = "Name of sender (max 75):", title = "Announcement", default = "Announcement Computer", next_stage = 2, channel = channel)
		return
	if(!sender)
		feedback_add_details("admin_verb", "IN")
		return
	if(stage == 2)
		open_request(src, /datum/prompt/text/admin_intercom, PROC_REF(intercom_answered), answerer = answerer, question = "Message content (max 500):", title = "Contents", default = "This is a test of the announcement system.", multiline = TRUE, max_len = MAX_TGUI_INPUT, next_stage = 3, channel = channel, sender = sender)
		return
	if(stage == 3)
		open_request(src, /datum/prompt/text/admin_intercom, PROC_REF(intercom_answered), answerer = answerer, question = "Name of verb (Such as 'states', 'says', 'asks', etc):", title = "Verb", default = "says", next_stage = 4, channel = channel, sender = sender, message = message)
		return
	sender = sanitize(sender, 75, extra = 0)
	if(message) //They put a message
		message = sanitize(message, 500, extra = 0)
		if(msgverb)
			msgverb = sanitize(msgverb, 50, extra = 0)
		else
			msgverb = "states"
		GLOB.global_announcer.autosay("[message]", "[sender]", "[channel == "Common" ? null : channel]", states = msgverb) //Common is a weird case, as it's not a "channel", it's just talking into a radio without a channel set.
		log_admin("Intercom: [key_name(user)] : [sender]:[message]")

	feedback_add_details("admin_verb","IN") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(intercom_convo, R_ADMIN|R_EVENT, "Intercom Convo", "Send an intercom conversation, like several uses of the Intercom Msg verb.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_intercom_conversation_channel, PROC_REF(conversation_channel_selected), answerer = answerer, choices = GLOB.radiochannels)

/datum/admin_verb/intercom_convo/proc/conversation_channel_selected(datum/act/request/context)
	if(!context.answer)
		return
	ask_conversation_speech(context)

/datum/admin_verb/intercom_convo/proc/ask_conversation_speech(datum/act/request/context)
	var/channel = context.request.value
	if(!channel)
		return
	open_request(src, /datum/prompt/choice/admin_intercom_conversation_speech, PROC_REF(conversation_speech_selected), answerer = context.request.answerer, channel = channel)

/datum/admin_verb/intercom_convo/proc/conversation_speech_selected(datum/act/request/context)
	if(!context.answer)
		return
	ask_conversation_content(context)

/datum/admin_verb/intercom_convo/proc/ask_conversation_content(datum/act/request/context)
	var/datum/prompt/choice/admin_intercom_conversation_speech/request = context.request
	var/speech_verb = request.value
	if(!speech_verb)
		return
	var/client/user = request.answerer.client
	to_chat(user, span_notice(span_bold("Intercom Convo Directions") + "<br>Start the conversation with the sender, a pipe (|), and then the message on one line. Then hit enter to \
	add another line, and type a (whole) number of seconds to pause between that message, and the next message, then repeat the message syntax up to 20 times. For example:<br>\
	--- --- ---<br>\
	Some Guy|Hello guys, what's up?<br>\
	5<br>\
	Other Guy|Hey, good to see you.<br>\
	5<br>\
	Some Guy|Yeah, you too.<br>\
	--- --- ---<br>\
	The above will result in those messages playing, with a 5 second gap between each. Maximum of 20 messages allowed."))

	open_request(src, /datum/prompt/text/admin_intercom_conversation_content, PROC_REF(conversation_content_selected), answerer = request.answerer, channel = request.channel, speech_verb = speech_verb)

/datum/admin_verb/intercom_convo/proc/conversation_content_selected(datum/act/request/context)
	if(!context.answer)
		return
	send_conversation(context)

/datum/admin_verb/intercom_convo/proc/send_conversation(datum/act/request/context)
	var/datum/prompt/text/admin_intercom_conversation_content/request = context.request
	var/client/user = request.answerer.client
	var/channel = request.channel
	var/speech_verb = request.speech_verb
	var/message = request.value
	var/list/decomposed
	if(!message)
		return

	//Split on pipe or \n
	decomposed = splittext(message,regex("\\||$","m"))

	//Time to find how they screwed up.
	//Wasn't the right length
	if((decomposed.len) % 3)
		to_chat(user, span_warning("You passed [decomposed.len] segments (senders+messages+pauses). You must pass a multiple of 3, minus 1 (no pause after the last message). That means a sender and message on every other line (starting on the first), separated by a pipe character (|), and a number every other line that is a pause in seconds."))
		return
	decomposed.Remove("") //ancient black magic.
	decomposed += 0 //Add a final wait time for the final message.

	//Too long a conversation
	if((decomposed.len / 3) > 20)
		to_chat(user, span_warning("This conversation is too long! 20 messages maximum, please."))
		return

	//Missed some sleeps, or sanitized to nothing.
	for(var/i = 1; i < decomposed.len; i++)

		//Sanitize sender
		var/clean_sender = sanitize(decomposed[i])
		if(!istext(clean_sender))
			to_chat(user, span_warning("One part of your conversation was not able to be sanitized. It was the sender of the [(i+2)/3]\th message."))
			return
		decomposed[i] = clean_sender

		//Sanitize message
		var/clean_message = sanitize(decomposed[++i])
		if(!istext(clean_message))
			to_chat(user, span_warning("One part of your conversation was not able to be sanitized. It was the body of the [(i+2)/3]\th message."))
			return
		decomposed[i] = clean_message

		//Sanitize wait time
		var/clean_time = text2num(decomposed[++i])
		if(!isnum(clean_time))
			to_chat(user, span_warning("One part of your conversation was not able to be sanitized. It was the wait time after the [(i+2)/3]\th message."))
			return
		if(clean_time > 60)
			to_chat(user, span_warning("Max 60 second wait time between messages for sanity's sake please."))
			return
		decomposed[i] = clean_time

	log_admin("Intercom convo started by: [key_name(user)] : [sanitize(message)]")
	feedback_add_details("admin_verb","IN") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

	//Sanitized AND we still have a chance to send it? Wow!
	if(LAZYLEN(decomposed))
		var/delay = 0
		for(var/i = 1; i < decomposed.len; i++)
			var/this_sender = decomposed[i]
			var/this_message = decomposed[++i]
			var/this_wait = decomposed[++i]
			// Each line is a timer at its cumulative offset (no sleeping in the verb).
			after(null, delay, GLOBAL_PROC_REF(admin_intercom_line), with = list("[this_message]", "[this_sender]", "[channel == "Common" ? null : channel]", speech_verb)) //Common is a weird case, as it's not a "channel", it's just talking into a radio without a channel set.
			delay += this_wait SECONDS

/proc/admin_intercom_line(message, sender, channel, speech_verb)
	GLOB.global_announcer.autosay(message, sender, channel, states = speech_verb)

ADMIN_VERB(toggleooc, R_ADMIN, "Toggle Player OOC", "Globally Toggles OOC.", ADMIN_CATEGORY_SERVER_CHAT)
	CONFIG_SET(flag/ooc_allowed, !CONFIG_GET(flag/ooc_allowed))
	if (CONFIG_GET(flag/ooc_allowed))
		to_chat(world, span_world("The OOC channel has been globally enabled!"))
	else
		to_chat(world, span_world("The OOC channel has been globally disabled!"))
	log_and_message_admins("toggled OOC.", user.mob)
	feedback_add_details("admin_verb","TOOC") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(togglelooc, R_ADMIN, "Toggle Player LOOC", "Globally Toggles LOOC.", ADMIN_CATEGORY_SERVER_CHAT)
	CONFIG_SET(flag/looc_allowed, !CONFIG_GET(flag/looc_allowed))
	if (CONFIG_GET(flag/looc_allowed))
		to_chat(world, span_world("The LOOC channel has been globally enabled!"))
	else
		to_chat(world, span_world("The LOOC channel has been globally disabled!"))
	log_and_message_admins("toggled LOOC.", user.mob)
	feedback_add_details("admin_verb","TLOOC") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(toggledsay, R_ADMIN, "Toggle DSAY", "Globally Toggles DSAY.", ADMIN_CATEGORY_SERVER_CHAT)
	CONFIG_SET(flag/dsay_allowed, !CONFIG_GET(flag/dsay_allowed))
	if (CONFIG_GET(flag/dsay_allowed))
		to_chat(world, span_world("Deadchat has been globally enabled!"))
	else
		to_chat(world, span_world("Deadchat has been globally disabled!"))
	log_admin("[key_name(user)] toggled deadchat.")
	message_admins("[key_name_admin(user)] toggled deadchat.")
	feedback_add_details("admin_verb","TDSAY") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc

ADMIN_VERB(toggleoocdead, R_ADMIN, "Toggle Dead OOC", "Toggle Dead OOC.", ADMIN_CATEGORY_SERVER_CHAT)
	CONFIG_SET(flag/dooc_allowed, !CONFIG_GET(flag/dooc_allowed))
	log_admin("[key_name(user)] toggled Dead OOC.")
	message_admins("[key_name_admin(user)] toggled Dead OOC.")
	feedback_add_details("admin_verb","TDOOC") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(togglehubvisibility, R_HOST, "Toggle Hub Visibility", "Globally Toggles Hub Visibility.", ADMIN_CATEGORY_SERVER_CONFIG)
	world.visibility = !(world.visibility)
	log_admin("[key_name(user)] toggled hub visibility.")
	message_admins("[key_name_admin(user)] toggled hub visibility.  The server is now [world.visibility ? "visible" : "invisible"] ([world.visibility]).")
	feedback_add_details("admin_verb","THUB") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc

ADMIN_VERB(toggletraitorscaling, R_ADMIN, "Toggle traitor scaling", "Toggle traitor scaling.", ADMIN_CATEGORY_SERVER_GAME)
	CONFIG_SET(flag/traitor_scaling, !CONFIG_GET(flag/traitor_scaling))
	log_admin("[key_name(user)] toggled Traitor Scaling to [CONFIG_GET(flag/traitor_scaling)].")
	message_admins("[key_name_admin(user)] toggled Traitor Scaling [CONFIG_GET(flag/traitor_scaling) ? "on" : "off"].")
	feedback_add_details("admin_verb","TTS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(startnow, R_SERVER|R_EVENT, "Start Now", "Start the round ASAP.", ADMIN_CATEGORY_SERVER_GAME)
	if(SSticker.current_state > GAME_STATE_PREGAME)
		to_chat(user, span_warning("Error: Start Now: Game has already started."))
		return
	if(!SSticker.start_immediately)
		SSticker.start_immediately = TRUE
		var/msg = ""
		if(SSticker.current_state == GAME_STATE_STARTUP)
			msg = " (The server is still setting up, but the round will be started as soon as possible.)"

		log_admin("[key_name(user)] has started the game.[msg]")
		message_admins(span_notice("[key_name_admin(user)] has started the game.[msg]"))
		feedback_add_details("admin_verb","SN") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		return
	SSticker.start_immediately = FALSE
	to_chat(world, span_filter_system(span_blue("Immediate game start canceled. Normal startup resumed.")))
	log_and_message_admins("cancelled immediate game start.", user.mob)

ADMIN_VERB(toggleenter, R_SERVER|R_ADMIN, "Toggle Entering", "Toggle if people can join the round.", ADMIN_CATEGORY_SERVER_GAME)
	CONFIG_SET(flag/enter_allowed, !CONFIG_GET(flag/enter_allowed))
	if (!CONFIG_GET(flag/enter_allowed))
		to_chat(world, span_world("New players may no longer enter the game."))
	else
		to_chat(world, span_world("New players may now enter the game."))
	log_admin("[key_name(user)] toggled new player game entering.")
	message_admins(span_blue("[key_name_admin(user)] toggled new player game entering."))
	world.update_status()
	feedback_add_details("admin_verb","TE") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(toggleAI, R_SERVER|R_EVENT, "Toggle AI", "Toggle if people can play as AI.", ADMIN_CATEGORY_SERVER_GAME)
	CONFIG_SET(flag/allow_ai, !CONFIG_GET(flag/allow_ai))
	if (!CONFIG_GET(flag/allow_ai))
		to_chat(world, span_world("The AI job is no longer chooseable."))
	else
		to_chat(world, span_world("The AI job is chooseable now."))
	log_admin("[key_name(user)] toggled AI allowed.")
	world.update_status()
	feedback_add_details("admin_verb","TAI") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(toggleaban, R_SERVER|R_EVENT, "Toggle Respawn", "Respawn basically.", ADMIN_CATEGORY_SERVER_GAME)
	CONFIG_SET(flag/abandon_allowed, !CONFIG_GET(flag/abandon_allowed))
	if(CONFIG_GET(flag/abandon_allowed))
		to_chat(world, span_world("You may now respawn."))
	else
		to_chat(world, span_world("You may no longer respawn :("))
	message_admins(span_blue("[key_name_admin(user)] toggled respawn to [CONFIG_GET(flag/abandon_allowed) ? "On" : "Off"]."))
	log_admin("[key_name(user)] toggled respawn to [CONFIG_GET(flag/abandon_allowed) ? "On" : "Off"].")
	world.update_status()
	feedback_add_details("admin_verb","TR") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(togglepersistence, R_SERVER, "Toggle Persistent Data", "Whether persistent data will be saved from now on.", ADMIN_CATEGORY_SERVER_CONFIG)
	CONFIG_SET(flag/persistence_disabled, !CONFIG_GET(flag/persistence_disabled))
	message_admins(span_blue("[key_name_admin(user)] toggled persistence to [CONFIG_GET(flag/persistence_disabled) ? "Off" : "On"]."))
	log_admin("[key_name(user)] toggled persistence to [CONFIG_GET(flag/persistence_disabled) ? "Off" : "On"].")
	world.update_status()
	feedback_add_details("admin_verb","TPD") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/admins/proc/togglemaploadpersistence()
	set category = VERB_CAT_SERVER_CONFIG
	set desc="Whether mapload persistent data will be saved from now on."
	set name="Toggle Mapload Persistent Data"
	CONFIG_SET(flag/persistence_ignore_mapload, !CONFIG_GET(flag/persistence_ignore_mapload))
	if(!CONFIG_GET(flag/persistence_ignore_mapload))
		to_chat(world, span_world("Persistence is now enabled."))
	else
		to_chat(world, span_world("Persistence is no longer enabled."))
	message_admins(span_blue("[key_name_admin(usr)] toggled persistence to [CONFIG_GET(flag/persistence_ignore_mapload) ? "Off" : "On"]."))
	log_admin("[key_name(usr)] toggled persistence to [CONFIG_GET(flag/persistence_ignore_mapload) ? "Off" : "On"].")
	world.update_status()
	feedback_add_details("admin_verb","TMPD") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(toggle_aliens, R_FUN|R_SERVER, "Toggle Aliens", "Toggle alien mobs.", ADMIN_CATEGORY_SERVER_GAME)
	CONFIG_SET(flag/aliens_allowed, !CONFIG_GET(flag/aliens_allowed))
	log_admin("[key_name(user)] toggled Aliens to [CONFIG_GET(flag/aliens_allowed)].")
	message_admins("[key_name_admin(user)] toggled Aliens [CONFIG_GET(flag/aliens_allowed) ? "on" : "off"].")
	feedback_add_details("admin_verb","TA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(toggle_space_ninja, R_FUN|R_SERVER, "Toggle Space Ninjas", "Toggle space ninjas spawning.", ADMIN_CATEGORY_SERVER_GAME)
	CONFIG_SET(flag/ninjas_allowed, !CONFIG_GET(flag/ninjas_allowed))
	log_admin("[key_name(user)] toggled Space Ninjas to [CONFIG_GET(flag/ninjas_allowed)].")
	message_admins("[key_name_admin(user)] toggled Space Ninjas [CONFIG_GET(flag/ninjas_allowed) ? "on" : "off"].")
	feedback_add_details("admin_verb","TSN") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(delay, R_SERVER|R_EVENT|R_ADMIN|R_MOD, "Delay", "Delay the game start/end.", ADMIN_CATEGORY_SERVER_GAME)
	if (SSticker.current_state >= GAME_STATE_PLAYING)
		// Tell the ticker to delay/resume
		SSticker.toggle_delay()

		log_admin("[key_name(user)] [SSticker.delay_end ? "delayed the round end" : "has made the round end normally"].")
		message_admins(span_blue("[key_name(user)] [SSticker.delay_end ? "delayed the round end" : "has made the round end normally"]."))
		return
	GLOB.round_progressing = !GLOB.round_progressing
	if (!GLOB.round_progressing)
		to_chat(world, span_world("The game start has been delayed."))
		log_admin("[key_name(user)] delayed the game.")
	else
		to_chat(world, span_world("The game will start soon."))
		log_admin("[key_name(user)] removed the delay.")
	feedback_add_details("admin_verb","DELAY") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(adjump, R_SERVER, "Toggle Jump", "Toggle admin jumping.", ADMIN_CATEGORY_SERVER_GAME)
	CONFIG_SET(flag/allow_admin_jump, !CONFIG_GET(flag/allow_admin_jump))
	message_admins(span_blue("Toggled admin jumping to [CONFIG_GET(flag/allow_admin_jump)]."))
	feedback_add_details("admin_verb","TJ") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(adspawn, R_SERVER, "Toggle Spawn", "Toggle admin spawning.", ADMIN_CATEGORY_SERVER_GAME)
	CONFIG_SET(flag/allow_admin_spawning, !CONFIG_GET(flag/allow_admin_spawning))
	message_admins(span_blue("Toggled admin item spawning to [CONFIG_GET(flag/allow_admin_spawning)]."))
	feedback_add_details("admin_verb","TAS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(adrev, R_SERVER, "Toggle Revive", "Toggle admin revives.", ADMIN_CATEGORY_SERVER_GAME)
	CONFIG_SET(flag/allow_admin_rev, !CONFIG_GET(flag/allow_admin_rev))
	message_admins(span_blue("Toggled reviving to [CONFIG_GET(flag/allow_admin_rev)]."))
	feedback_add_details("admin_verb","TAR") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/admins/proc/unprison(mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
	set category = VERB_CAT_ADMIN_MODERATION
	set name = "Unprison"
	if (M.z == 2)
		if (CONFIG_GET(flag/allow_admin_jump))
			M.forceMove(get_turf(pick(REGISTRY_MEMBERS(REGISTRY_LATEJOIN))))
			message_admins("[key_name_admin(usr)] has unprisoned [key_name_admin(M)]", 1)
			log_admin("[key_name(usr)] has unprisoned [key_name(M)]")
		else
			tgui_alert_async(usr, "Admin jumping disabled")
	else
		tgui_alert_async(usr, "[M.name] is not prisoned.")
	feedback_add_details("admin_verb","UP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

////////////////////////////////////////////////////////////////////////////////////////////////ADMIN HELPER PROCS

/proc/is_special_character(character) // returns 1 for special characters and 2 for heroes of gamemode
	if(!SSticker|| !SSticker.mode)
		return 0
	var/datum/mind/M
	if (ismob(character))
		var/mob/C = character
		M = C.mind
	else if(istype(character, /datum/mind))
		M = character

	if(M)
		if(SSticker.mode.antag_templates && SSticker.mode.antag_templates.len)
			for(var/datum/antagonist/antag in SSticker.mode.antag_templates)
				if(antag.is_antagonist(M))
					return 2
		if(M.special_role)
			return 1

	if(isrobot(character))
		var/mob/living/silicon/robot/R = character
		if(R.emagged)
			return 1

	return 0

ADMIN_VERB(spawn_fruit, R_SPAWN, "Spawn Fruit", "Spawn the product of a seed.", ADMIN_CATEGORY_DEBUG_GAME)
	return seed_spawn_stage(user, list())

/datum/admin_verb/spawn_fruit/proc/seed_spawn_stage(client/user, list/seed_answers)
	if(!("a9" in seed_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/choice/admin_seed_spawn, PROC_REF(seed_spawn_answered), answerer = user.mob, seed_answers = seed_answers, seed_key = "a9", question = "Select Seed.", title = "Seed Type", choices = SSplants.seeds)
		return
	var/seedtype = seed_answers["a9"]
	if(isnull(seedtype))
		return
	if(!seedtype || !SSplants.seeds[seedtype])
		return
	if(!("a10" in seed_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/number/admin_seed_spawn, PROC_REF(seed_spawn_answered), answerer = user.mob, seed_answers = seed_answers, seed_key = "a10", question = "Amount of fruit to spawn", title = "Fruit Amount", default = 1)
		return
	var/amount = seed_answers["a10"]
	if(isnull(amount))
		return
	var/mob/user_mob = user.mob
	if(!isnull(amount))
		var/datum/seed/S = SSplants.seeds[seedtype]
		S.harvest(user_mob,0,0,amount)
	log_admin("[key_name(user)] spawned [seedtype] fruit at ([user_mob.x],[user_mob.y],[user_mob.z])")

ADMIN_VERB(spawn_custom_item, R_SPAWN, "Spawn Custom Item", "Spawn a custom item.", ADMIN_CATEGORY_DEBUG_GAME)
	return custom_item_spawn_stage(user, list())

/datum/admin_verb/spawn_custom_item/proc/custom_item_spawn_stage(client/user, list/custom_answers)
	if(!("a11" in custom_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/choice/admin_custom_item_spawn, PROC_REF(custom_item_spawn_answered), answerer = user.mob, custom_answers = custom_answers, custom_key = "a11", question = "Select a ckey.", title = "Spawn Custom Item", choices = GLOB.custom_items)
		return
	var/owner = custom_answers["a11"]
	if(isnull(owner))
		return
	if(!owner)
		return

	var/list/possible_items = GLOB.custom_items[owner]
	if(!possible_items)
		return
	if(!("a12" in custom_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/choice/admin_custom_item_spawn, PROC_REF(custom_item_spawn_answered), answerer = user.mob, custom_answers = custom_answers, custom_key = "a12", question = "Select an item to spawn.", title = "Spawn Custom Item", choices = possible_items)
		return
	var/datum/custom_item/chosen_item = custom_answers["a12"]
	if(isnull(chosen_item))
		return
	if(!chosen_item)
		return

	chosen_item.spawn_item(get_turf(user.mob))

ADMIN_VERB(check_custom_items, R_SPAWN, "Check Custom Items", "Check the custom item list.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	if(!GLOB.custom_items)
		to_chat(user, "Custom item list is null.")
		return

	if(!GLOB.custom_items.len)
		to_chat(user, "Custom item list not populated.")
		return

	for(var/assoc_key in GLOB.custom_items)
		to_chat(user, "[assoc_key] has:")
		var/list/current_items = GLOB.custom_items[assoc_key]
		for(var/datum/custom_item/item in current_items)
			to_chat(user, "- name: [item.name] icon: [item.item_icon] path: [item.item_path] desc: [item.item_desc]")

ADMIN_VERB(spawn_plant, R_SPAWN, "Spawn Plant", "Spawn a spreading plant effect.", ADMIN_CATEGORY_DEBUG_GAME)
	return seed_spawn_stage(user, list())

/datum/admin_verb/spawn_plant/proc/seed_spawn_stage(client/user, list/seed_answers)
	if(!("a13" in seed_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/choice/admin_seed_spawn, PROC_REF(seed_spawn_answered), answerer = user.mob, seed_answers = seed_answers, seed_key = "a13", question = "Select Seed.", title = "Seed Type", choices = SSplants.seeds)
		return
	var/seedtype = seed_answers["a13"]
	if(isnull(seedtype))
		return
	if(!seedtype || !SSplants.seeds[seedtype])
		return
	var/mob/user_mob = user.mob
	new /obj/effect/plant(get_turf(user_mob), SSplants.seeds[seedtype])
	log_admin("[key_name(user)] spawned [seedtype] vines at ([user_mob.x],[user_mob.y],[user_mob.z])")

ADMIN_VERB(spawn_atom, R_SPAWN, "Spawn", "(atom path) Spawn an atom", ADMIN_CATEGORY_DEBUG_GAME, object as text|null)
	var/static/list/atom_types
	if(isnull(atom_types))
		atom_types = subtypesof(/atom)

	var/chosen_path = null
	var/list/preparsed = null
	if(object)
		preparsed = splittext(object, ":")
		var/list/matches = filter_fancy_list(atom_types, preparsed[1])
		if(length(matches) == 1)
			chosen_path = matches[1]

	if(!chosen_path)
		var/datum/spawn_menu/menu = user.holder.spawn_menu
		if(!menu)
			menu = rel_set(user.admin_datum(), nameof(/datum/admins::spawn_menu), new /datum/spawn_menu())
		menu.init_value = object
		menu.tgui_interact(user.mob)
		feedback_add_details("admin_verb","SA")
		return

	var/amount = 1
	if(length(preparsed) > 1)
		amount = clamp(text2num(preparsed[2]), 1, ADMIN_SPAWN_CAP)

	var/turf/target_turf = get_turf(user.mob)
	if(ispath(chosen_path, /turf))
		target_turf.ChangeTurf(chosen_path)
	else
		for(var/i in 1 to amount)
			var/atom/spawned = new chosen_path(target_turf)
			spawned.flags |= ADMIN_SPAWNED

	log_and_message_admins("spawned [amount] x [chosen_path] at [AREACOORD(user.mob)]", user)
	feedback_add_details("admin_verb","SA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_AND_CONTEXT_MENU(show_traitor_panel, R_ADMIN|R_FUN|R_EVENT, "Show Traitor Panel", "Edit mobs's memory and role", ADMIN_CATEGORY_EVENTS, mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
	if(!istype(M))
		to_chat(user, "This can only be used on instances of type /mob")
		return
	if(!M.mind)
		to_chat(user, "This mob has no mind!")
		return

	M.mind.edit_memory(user.mob)
	feedback_add_details("admin_verb","STP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(show_game_mode, R_ADMIN|R_EVENT, "Show Game Mode", "Show the current round configuration.", ADMIN_CATEGORY_GAME)
	// structured TGUI GameModePanel (see
	// code/modules/admin/game_mode_panel.dm).
	open_game_mode_panel(user)
	feedback_add_details("admin_verb","SGM")

ADMIN_VERB(toggletintedweldhelmets, R_ADMIN, "Toggle tinted welding helmets", "Reduces view range when wearing welding helmets.", ADMIN_CATEGORY_SERVER_CONFIG)
	CONFIG_SET(flag/welder_vision, !CONFIG_GET(flag/welder_vision))
	if (CONFIG_GET(flag/welder_vision))
		to_chat(world, span_world("Reduced welder vision has been enabled!"))
	else
		to_chat(world, span_world("Reduced welder vision has been disabled!"))
	log_admin("[key_name(user)] toggled welder vision.")
	message_admins("[key_name_admin(user)] toggled welder vision.", 1)
	feedback_add_details("admin_verb","TTWH") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(toggleguests, R_HOST, "Toggle guests", "Guests can't enter.", ADMIN_CATEGORY_SERVER_CONFIG)
	CONFIG_SET(flag/guests_allowed, !CONFIG_GET(flag/guests_allowed))
	if (!CONFIG_GET(flag/guests_allowed))
		to_chat(world, span_world("Guests may no longer enter the game."))
	else
		to_chat(world, span_world("Guests may now enter the game."))
	log_admin("[key_name(user)] toggled guests game entering [CONFIG_GET(flag/guests_allowed)?"":"dis"]allowed.")
	message_admins(span_blue("[key_name_admin(user)] toggled guests game entering [CONFIG_GET(flag/guests_allowed)?"":"dis"]allowed."))
	feedback_add_details("admin_verb","TGU") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/client/proc/update_mob_sprite(mob/living/carbon/human/H as mob)
	set category = VERB_CAT_ADMIN_GAME
	set name = "Update Mob Sprite"
	set desc = "Should fix any mob sprite update errors."

	if (!check_rights_for(src, R_HOLDER))
		to_chat(src, "Only administrators may use this command.")
		return

	if(istype(H))
		H.regenerate_icons()

/proc/get_options_bar(whom, detail = 2, name = 0, link = 1, highlight_special = 1)
	if(!whom)
		return span_bold("(*null*)")
	var/mob/M
	var/client/C
	if(istype(whom, /client))
		C = whom
		M = C.mob
	else if(istype(whom, /mob))
		M = whom
		C = M.client
	else
		return span_bold("(*not a mob*)")
	switch(detail)
		if(0)
			return span_bold("[key_name(C, link, name, highlight_special)]")

		if(1)	//Private Messages
			return span_bold("[key_name(C, link, name, highlight_special)](<a href='byond://?_src_=holder;[HrefToken()];adminmoreinfo=[REF(M)]'>?</a>)")

		if(2)	//Admins
			var/ref_mob = "[REF(M)]"
			return span_bold("[key_name(C, link, name, highlight_special)](<a href='byond://?_src_=holder;[HrefToken()];adminmoreinfo=[ref_mob]'>?</a>) (<a href='byond://?_src_=holder;[HrefToken()];adminplayeropts=[ref_mob]'>PP</a>) (<a href='byond://?_src_=vars;[HrefToken()];Vars=[ref_mob]'>VV</a>) (<a href='byond://?_src_=holder;[HrefToken()];subtlemessage=[ref_mob]'>SM</a>) ([admin_jump_link(M)]) (<a href='byond://?_src_=holder;[HrefToken()];check_antagonist=1'>CA</a>) (<a href='byond://?_src_=holder;[HrefToken()];take_question=[REF(M)]'>TAKE</a>)")

		if(3)	//Devs
			var/ref_mob = "[REF(M)]"
			return span_bold("[key_name(C, link, name, highlight_special)](<a href='byond://?_src_=vars;[HrefToken()];Vars=[ref_mob]'>VV</a>)([admin_jump_link(M)]) (<a href='byond://?_src_=holder;[HrefToken()];take_question=[REF(M)]'>TAKE</a>)")

		if(4)	//Event Managers
			var/ref_mob = "[REF(M)]"
			return span_bold("[key_name(C, link, name, highlight_special)] (<a href='byond://?_src_=holder;[HrefToken()];adminmoreinfo=[REF(M)]'>?</a>) (<a href='byond://?_src_=holder;[HrefToken()];adminplayeropts=[ref_mob]'>PP</a>) (<a href='byond://?_src_=vars;[HrefToken()];Vars=[ref_mob]'>VV</a>) (<a href='byond://?_src_=holder;[HrefToken()];subtlemessage=[ref_mob]'>SM</a>) ([admin_jump_link(M)]) (<a href='byond://?_src_=holder;[HrefToken()];take_question=[REF(M)]'>TAKE</a>)")


/proc/ishost(whom)
	if(!whom)
		return 0
	var/client/C
	var/mob/M
	if(istype(whom, /client))
		C = whom
	if(istype(whom, /mob))
		M = whom
		C = M.client
	if(check_rights_for(C, R_HOST))
		return 1
	else
		return 0
//
//
//ALL DONE
//*********************************************************************************************************
//

//Returns 1 to let the dragdrop code know we are trapping this event
//Returns 0 if we don't plan to trap the event
/datum/admins/proc/cmd_ghost_drag(mob/observer/dead/frommob, mob/living/tomob, mob/user)
	if(!istype(frommob))
		return //Extra sanity check to make sure only observers are shoved into things

	//Same as assume-direct-control perm requirements.
	if (!admin_require(user.client, R_VAREDIT, "cmd_ghost_drag", 0) || !admin_require(user.client, R_ADMIN|R_DEBUG|R_EVENT, "cmd_ghost_drag", 0))
		return 0
	if (!frommob.ckey)
		return 0
	var/question = ""
	if (tomob.ckey)
		question = "This mob already has a user ([tomob.key]) in control of it! "
	question += "Are you sure you want to place [frommob.name]([frommob.key]) in control of [tomob.name]?"
	open_request(src, /datum/prompt/choice/ghost_drag, PROC_REF(ghost_drag_confirmed), answerer = user, question = question, asker = frommob, subject = tomob)
	return 1

/// Re-checked: both original mobs exist and the ghost still has a player.
/datum/prompt/choice/ghost_drag
	title = "Place ghost in control of mob?"
	choices = list("Yes", "No")
	buttons = TRUE
	timeout = 0
	rights = R_VAREDIT
	recheck_on_open = TRUE

/datum/prompt/choice/ghost_drag/recheck_extra()
	var/mob/admin = answerer
	var/mob/observer/dead/frommob = asker
	var/mob/living/tomob = subject
	if(!istype(admin) || QDELETED(admin) || !istype(frommob) || QDELETED(frommob) || !istype(tomob) || QDELETED(tomob))
		return "gone"
	return frommob.ckey ? null : "no player"

/datum/admins/proc/ghost_drag_confirmed(datum/act/request/context)
	if(!context.answer || context.answer.value != "Yes")
		return
	var/mob/admin = context.request.answerer
	var/mob/observer/dead/frommob = context.request.asker
	var/mob/living/tomob = context.request.subject
	if(tomob.client) //No need to ghostize if there is no client
		tomob.ghostize(0)
	if(frommob.mind && frommob.mind.current) //Preserve teleop for original body when adminghosting.
		var/mob/body = frommob.mind.current
		if(body)
			if(body.teleop)
				body.teleop = tomob
	message_admins(span_adminnotice("[key_name_admin(admin)] has put [frommob.ckey] in control of [tomob.name]."))
	log_admin("[key_name(admin)] stuffed [frommob.ckey] into [tomob.name].")
	feedback_add_details("admin_verb","CGD")
	tomob.ckey = frommob.ckey
	spent(frommob)
	return 1

ADMIN_VERB(force_antag_latespawn, R_ADMIN|R_EVENT|R_FUN, "Force Template Spawn", "Force an antagonist template to spawn.", ADMIN_CATEGORY_EVENTS)
	// Only this verb's actual ended native request supplies replay answers.
	var/list/replay_answers = list()
	if(length(args) >= 2)
		var/datum/request/resumed = args[2]
		if((istype(resumed, /datum/prompt/choice/admin_force_antag_replay)) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(force_antag_latespawn_replay_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	if(!SSticker|| !SSticker.mode)
		to_chat(user, span_warning("Mode has not started."))
		return

	if(!("a14" in replay_answers))
		open_request(src, /datum/prompt/choice/admin_force_antag_replay, PROC_REF(force_antag_latespawn_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a14", question = "Choose a template.", title = "Force Latespawn", choices = SSantag.all_antag_types)
		return
	var/antag_type = replay_answers["a14"]
	if(isnull(antag_type))
		return
	if(!antag_type || !SSantag.all_antag_types[antag_type])
		to_chat(user, span_warning("Aborting."))
		return

	var/datum/antagonist/antag = SSantag.all_antag_types[antag_type]
	message_admins("[key_name(user)] attempting to force latespawn with template [antag.id].")
	antag.attempt_late_spawn()

ADMIN_VERB(force_mode_latespawn, R_ADMIN|R_EVENT|R_FUN, "Force Mode Spawn", "Force autotraitor to proc.", ADMIN_CATEGORY_EVENTS)
	if(!SSticker|| !SSticker.mode)
		to_chat(user, span_warning("Mode has not started."))
		return

	log_and_message_admins("attempting to force mode autospawn.", user.mob)
	SSticker.mode.try_latespawn()

ADMIN_VERB_AND_CONTEXT_MENU(paralyze_mob, R_ADMIN|R_MOD|R_EVENT, "Toggle Paralyze", "Paralyzes a player. Or unparalyses them.", ADMIN_CATEGORY_EVENTS, mob/living/living_target in REGISTRY_MEMBERS(REGISTRY_MOBS))
	return toggle_paralyze(user, living_target)

/datum/admin_verb/paralyze_mob/proc/paralyze_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/admin_paralyze_confirm/ask = A.request
	toggle_paralyze(ask.answerer.client, ask.target, ask.value, TRUE)

/datum/admin_verb/paralyze_mob/proc/toggle_paralyze(client/user, mob/living/living_target, _answer_a15 = null, answered = FALSE)
	var/msg
	if (!living_target.has_status(EFFECT_PARALYZED))
		living_target.status_set(EFFECT_PARALYZED, 800 SECONDS)
		msg = "has paralyzed [key_name(living_target)]."
		log_and_message_admins(msg, user.mob)
		return
	if(!answered)
		var/mob/answerer = user.mob
		if(QDELETED(answerer))
			return
		open_request(src, /datum/prompt/choice/admin_paralyze_confirm, PROC_REF(paralyze_answered), answerer = answerer, question = "[key_name(living_target)] is paralyzed, would you like to unparalyze them?", target = living_target)
		return
	if(isnull(_answer_a15))
		return
	if(_answer_a15 == "Yes")
		living_target.status_set(EFFECT_PARALYZED, 0)
		msg = "has unparalyzed [key_name(living_target)]."
		log_and_message_admins(msg, user)

ADMIN_VERB(set_tcrystals, R_ADMIN|R_EVENT, "Set Telecrystals", "Allows admins to change telecrystals of a user.", ADMIN_CATEGORY_DEBUG_GAME, mob/living/carbon/human/human_mob in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/number/admin_telecrystals, PROC_REF(set_crystals), answerer = answerer, question = "Amount of telecrystals for [human_mob.ckey], currently [human_mob.mind.tcrystals].", human_target = human_mob)

/datum/admin_verb/set_tcrystals/proc/set_crystals(datum/act/request/A)
	crystals_answered(A)

/datum/admin_verb/set_tcrystals/proc/crystals_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/number/admin_telecrystals/ask = A.request
	var/mob/living/carbon/human/human_mob = ask.human_target
	var/client/user = ask.answerer.client
	var/crystals = ask.value
	if (!isnull(crystals))
		human_mob.mind.tcrystals = crystals
		var/msg = "[key_name(user)] has modified [human_mob.ckey]'s telecrystals to [crystals]."
		message_admins(msg)

ADMIN_VERB(add_tcrystals, R_ADMIN|R_EVENT, "Add Telecrystals", "Allows admins to change telecrystals of a user by addition.", ADMIN_CATEGORY_DEBUG_GAME, mob/living/carbon/human/human_mob in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/number/admin_telecrystals, PROC_REF(add_crystals), answerer = answerer, question = "Amount of telecrystals to give to [human_mob.ckey], currently [human_mob.mind.tcrystals].", human_target = human_mob)

/datum/admin_verb/add_tcrystals/proc/add_crystals(datum/act/request/A)
	crystals_answered(A)

/datum/admin_verb/add_tcrystals/proc/crystals_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/number/admin_telecrystals/ask = A.request
	var/mob/living/carbon/human/human_mob = ask.human_target
	var/client/user = ask.answerer.client
	var/crystals = ask.value
	if (!isnull(crystals))
		human_mob.mind.tcrystals += crystals
		var/msg = "[key_name(user)] has added [crystals] to [human_mob.ckey]'s telecrystals."
		message_admins(msg)


ADMIN_VERB(sendFax, R_ADMIN|R_MOD|R_EVENT, "Send Fax", "Sends a fax to this machine.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	fax_request_stage(user, list())

/datum/admin_verb/sendFax/proc/fax_request_stage(client/user, list/fax_answers)
	var/department = fax_answers["department"]
	if(!("department" in fax_answers))
		if(!user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/choice/admin_fax_department, PROC_REF(fax_request_answered), answerer = user.mob, question = "Choose a fax", title = "Fax", choices = GLOB.alldepartments, fax_answers = fax_answers)
		return
	if(isnull(department))
		return
	var/replyorigin = fax_answers["origin"]
	if(!("origin" in fax_answers))
		if(!user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/text/admin_fax_origin, PROC_REF(fax_request_answered), answerer = user.mob, question = "Please specify who the fax is coming from", title = "Origin", fax_answers = fax_answers)
		return
	if(isnull(replyorigin))
		return
	for(var/obj/machinery/photocopier/faxmachine/sendto in REGISTRY_MEMBERS(REGISTRY_FAXES))
		if(sendto.department == department)
			var/obj/item/paper/admin/P = new /obj/item/paper/admin(null) //hopefully the null loc won't cause trouble for us
			rel_set(user.admin_datum(), nameof(/datum/admins::faxreply), P) // a replaced reply is deleted

			rel_set(P, nameof(/obj/item/paper/admin::admindatum), user.admin_datum())
			P.origin = replyorigin
			rel_set(P, nameof(/datum/ai_brain::destination), sendto)

			P.adminbrowse(user.mob)


/datum/admins/var/obj/item/paper/admin/faxreply // var to hold fax replies in (owned)

/datum/admins/proc/faxCallback(obj/item/paper/admin/P, obj/machinery/photocopier/faxmachine/destination)
	var/client/recipient = owner()
	if((!isnull(P) && QDELETED(P)) || (!isnull(destination) && QDELETED(destination)))
		return
	var/mob/answerer = recipient?.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/text/fax_title, PROC_REF(fax_titled), answerer = answerer, paper = P, destination = destination)

/// An admin fax reply: its title, then (admin-initiated) whether to stamp it. A cancel skips either.
/datum/prompt/text/fax_title
	name_text = TRUE
	title = "Title"
	question = "Pick a title for the report"
	timeout = 0
	var/obj/item/paper/admin/paper
	var/obj/machinery/photocopier/faxmachine/destination
	var/paper_required = FALSE
	var/destination_required = FALSE

CAPABILITIES(/datum/prompt/text/fax_title)
	ref_one(nameof(paper), /obj/item/paper/admin)
	ref_one(nameof(destination), /obj/machinery/photocopier/faxmachine)

/datum/prompt/text/fax_title/prepare(datum/act/A)
	..()
	var/obj/item/paper/admin/captured_paper = paper
	var/obj/machinery/photocopier/faxmachine/captured_destination = destination
	paper_required = !isnull(captured_paper)
	destination_required = !isnull(captured_destination)
	rel_clear(src, nameof(paper))
	rel_clear(src, nameof(destination))
	rel_set(src, nameof(paper), captured_paper)
	rel_set(src, nameof(destination), captured_destination)

/datum/prompt/text/fax_title/recheck_extra()
	return (paper_required && QDELETED(paper)) || (destination_required && QDELETED(destination)) ? "gone" : null

/datum/prompt/choice/fax_stamp
	title = "Stamped?"
	question = "Would you like the fax stamped?"
	choices = list("Yes", "No")
	buttons = TRUE
	timeout = 0
	var/obj/item/paper/admin/paper
	var/obj/machinery/photocopier/faxmachine/destination
	var/paper_required = FALSE
	var/destination_required = FALSE
	var/custom_title

CAPABILITIES(/datum/prompt/choice/fax_stamp)
	ref_one(nameof(paper), /obj/item/paper/admin)
	ref_one(nameof(destination), /obj/machinery/photocopier/faxmachine)

/datum/prompt/choice/fax_stamp/prepare(datum/act/A)
	..()
	var/obj/item/paper/admin/captured_paper = paper
	var/obj/machinery/photocopier/faxmachine/captured_destination = destination
	paper_required = !isnull(captured_paper)
	destination_required = !isnull(captured_destination)
	rel_clear(src, nameof(paper))
	rel_clear(src, nameof(destination))
	rel_set(src, nameof(paper), captured_paper)
	rel_set(src, nameof(destination), captured_destination)

/datum/prompt/choice/fax_stamp/recheck_extra()
	return (paper_required && QDELETED(paper)) || (destination_required && QDELETED(destination)) ? "gone" : null

/datum/admins/proc/fax_titled(datum/act/request/A)
	var/datum/prompt/text/fax_title/ask = A.request
	if(QDELETED(ask.answerer) || (ask.paper_required && QDELETED(ask.paper)) || (ask.destination_required && QDELETED(ask.destination)))
		return
	if(!A.answer && (ask.outcome != REQ_CANCELLED || !isnull(ask.value)))
		return
	var/custom_title = isnull(ask.value) ? "" : ask.value
	if(ask.paper.sender())
		fax_answered(ask.paper, ask.destination, custom_title, FALSE)
		return
	open_request(src, /datum/prompt/choice/fax_stamp, PROC_REF(fax_stamp_answered), answerer = ask.answerer, paper = ask.paper, destination = ask.destination, custom_title = custom_title)

/datum/admins/proc/fax_stamp_answered(datum/act/request/A)
	var/datum/prompt/choice/fax_stamp/ask = A.request
	if(QDELETED(ask.answerer) || (ask.paper_required && QDELETED(ask.paper)) || (ask.destination_required && QDELETED(ask.destination)))
		return
	if(!A.answer && (ask.outcome != REQ_CANCELLED || !isnull(ask.value)))
		return
	fax_answered(ask.paper, ask.destination, ask.custom_title, ask.value == "Yes")

/datum/admins/proc/fax_answered(obj/item/paper/admin/P, obj/machinery/photocopier/faxmachine/destination, customname, stamp)
	P.name = "[P.origin] - [customname]"
	P.desc = "This is a paper titled '" + P.name + "'."

	var/shouldStamp = P.sender() || stamp // admin initiated faxes are stamped when asked

	if(shouldStamp)
		P.stamps += "<hr>" + span_italics("This paper has been stamped by the [P.origin] Quantum Relay.")

		var/image/stampoverlay = image('icons/obj/bureaucracy.dmi')
		var/x = rand(-2, 0)
		var/y = rand(-1, 2)
		P.offset_x += x
		P.offset_y += y
		stampoverlay.pixel_x = x
		stampoverlay.pixel_y = y

		if(!P.ico)
			P.ico = new
		LAZYADD(P.ico, "paper_stamp-cent")
		stampoverlay.icon_state = "paper_stamp-cent"

		if(!P.stamped)
			P.stamped = new
		P.stamped += /obj/item/stamp/centcomm
		P.add_overlay(stampoverlay)

	var/obj/item/rcvdcopy
	rcvdcopy = destination.copy(P)
	rcvdcopy.moveToNullspace() //hopefully this shouldn't cause trouble
	GLOB.adminfaxes += rcvdcopy



	if(destination.receivefax(P))
		to_chat(src.owner(), span_notice("Message reply to transmitted successfully."))
		if(P.sender()) // sent as a reply
			log_admin("[key_name(src.owner())] replied to a fax message from [key_name(P.sender())]")
			for(var/client/C in GLOB.admins)
				if(check_rights_for(C, (R_ADMIN | R_MOD | R_EVENT)))
					to_chat(C, span_log_message("[span_prefix("FAX LOG:")][key_name_admin(src.owner())] replied to a fax message from [key_name_admin(P.sender())] (<a href='byond://?_src_=holder;[HrefToken()];AdminFaxView=[REF(rcvdcopy)]'>VIEW</a>)"))
		else
			log_admin("[key_name(src.owner())] has sent a fax message to [destination.department]")
			for(var/client/C in GLOB.admins)
				if(check_rights_for(C, (R_ADMIN | R_MOD | R_EVENT)))
					to_chat(C, span_log_message("[span_prefix("FAX LOG:")][key_name_admin(src.owner())] has sent a fax message to [destination.department] (<a href='byond://?_src_=holder;[HrefToken()];AdminFaxView=[REF(rcvdcopy)]'>VIEW</a>)"))

		var/plaintext_title = P.sender() ? "replied to [key_name(P.sender())]'s fax" : "sent a fax message to [destination.department]"
		var/fax_text = paper_html_to_plaintext(P.info)
		log_game(plaintext_title)
		log_game(fax_text)

	else
		to_chat(src.owner(), span_warning("Message reply failed."))

	// A sent reply goes away 10 seconds later; deleting it also empties the admin's owned faxreply var.
	P.expire(10 SECONDS)
	return

ADMIN_VERB(set_uplink, R_ADMIN|R_DEBUG, "Set Uplink", "Allows admins to set up an uplink on a character. This will be required for a character to use telecrystals.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_uplink_target, PROC_REF(uplink_target_chosen), answerer = answerer, choices = REGISTRY_MEMBERS(REGISTRY_HUMANS))

/datum/admin_verb/set_uplink/proc/uplink_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	give_selected_uplink(A)

/datum/admin_verb/set_uplink/proc/give_selected_uplink(datum/act/request/A)
	var/mob/living/carbon/human/traitor_human = A.request.value
	var/client/user = A.request.answerer.client
	GLOB.traitors.spawn_uplink(traitor_human)
	traitor_human.mind.tcrystals = DEFAULT_TELECRYSTAL_AMOUNT
	traitor_human.mind.accept_tcrystals = 1
	message_admins("[key_name(user)] has given [traitor_human.ckey] an uplink.")

/datum/prompt/number/admin_telecrystals
	rights = R_ADMIN|R_EVENT
	timeout = 0
	min_value = 0
	max_value = INFINITY
	step = 1
	var/mob/living/carbon/human/human_target
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/number/admin_telecrystals)
	ref_one(nameof(human_target), /mob/living/carbon/human)

/datum/prompt/number/admin_telecrystals/prepare(datum/act/A)
	. = ..()
	var/mob/living/carbon/human/captured = human_target
	rel_clear(src, nameof(human_target))
	rel_set(src, nameof(human_target), captured)

/datum/prompt/number/admin_telecrystals/recheck_extra()
	. = ..()
	if(.)
		return
	return QDELETED(human_target) ? "target is gone" : null

/datum/prompt/number/admin_telecrystals/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, !isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/choice/admin_paralyze_confirm
	rights = R_ADMIN|R_MOD|R_EVENT
	timeout = 0
	title = "Paralyze Mob"
	buttons = TRUE
	choices = list("Yes", "No")
	var/mob/living/target
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/choice/admin_paralyze_confirm)
	ref_one(nameof(target), /mob/living)

/datum/prompt/choice/admin_paralyze_confirm/prepare(datum/act/A)
	. = ..()
	var/mob/living/captured = target
	rel_clear(src, nameof(target))
	rel_set(src, nameof(target), captured)

/datum/prompt/choice/admin_paralyze_confirm/recheck_extra()
	. = ..()
	if(.)
		return
	return QDELETED(target) ? "target is gone" : null

/datum/prompt/text/admin_announcement
	rights = R_SERVER|R_ADMIN|R_EVENT
	timeout = 0
	question = "Global message to send:"
	title = "Admin Announce"
	multiline = TRUE
	max_len = MAX_TGUI_INPUT
	recheck_on_open = TRUE

/datum/prompt/choice/admin_uplink_target
	rights = R_ADMIN|R_DEBUG
	timeout = 0
	question = "Select whom to give an uplink."
	title = "Set uplink"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_uplink_target/recheck_extra()
	. = ..()
	if(.)
		return
	if(!isnull(value))
		var/mob/living/carbon/human/picked = value
		return QDELETED(picked) ? "target is gone" : null

/datum/prompt/choice/admin_intercom_channel
	rights = R_ADMIN|R_EVENT
	timeout = 0
	question = "Channel for message:"
	title = "Channel"
	recheck_on_open = TRUE

/datum/prompt/text/admin_intercom
	rights = R_ADMIN|R_EVENT
	timeout = 0
	var/next_stage
	var/channel
	var/sender
	var/message
	recheck_on_open = TRUE

/datum/prompt/choice/admin_intercom_conversation_channel
	rights = R_ADMIN|R_EVENT
	timeout = 0
	question = "Channel for message:"
	title = "Channel"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_intercom_conversation_speech
	rights = R_ADMIN|R_EVENT
	timeout = 0
	question = "What speech verb to use for the conversation?"
	title = "Type"
	var/channel
	choices = list("states", "says")
	buttons = TRUE
	recheck_on_open = TRUE

/datum/prompt/text/admin_intercom_conversation_content
	rights = R_ADMIN|R_EVENT
	timeout = 0
	question = "See your chat box for instructions. Keep a copy elsewhere in case it is rejected when you click OK."
	title = "Input Conversation"
	var/channel
	var/speech_verb
	multiline = TRUE
	max_len = MAX_TGUI_INPUT
	recheck_on_open = TRUE


/datum/prompt/choice/admin_seed_spawn
	recheck_on_open = TRUE
	timeout = 0
	rights = R_SPAWN
	var/list/seed_answers
	var/seed_key

/datum/prompt/choice/admin_seed_spawn/recheck_extra()
	if(!admin_can(answerer?.client, 0))
		return "no admin rights"

/datum/prompt/number/admin_seed_spawn
	recheck_on_open = TRUE
	timeout = 0
	rights = R_SPAWN
	var/list/seed_answers
	var/seed_key

/datum/prompt/number/admin_seed_spawn/recheck_extra()
	if(!admin_can(answerer?.client, 0))
		return "no admin rights"

/proc/admin_seed_spawn_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/admin_verb/spawn_fruit/proc/seed_spawn_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(admin_seed_spawn_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	var/list/seed_answers
	var/seed_key
	if(istype(context.answer, /datum/prompt/choice/admin_seed_spawn))
		var/datum/prompt/choice/admin_seed_spawn/ask = context.answer
		seed_answers = ask.seed_answers.Copy()
		seed_key = ask.seed_key
	else
		var/datum/prompt/number/admin_seed_spawn/ask = context.answer
		seed_answers = ask.seed_answers.Copy()
		seed_key = ask.seed_key
	seed_answers[seed_key] = context.answer.value
	return seed_spawn_stage(user, seed_answers)

/datum/admin_verb/spawn_plant/proc/seed_spawn_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(admin_seed_spawn_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	var/list/seed_answers
	var/seed_key
	if(istype(context.answer, /datum/prompt/choice/admin_seed_spawn))
		var/datum/prompt/choice/admin_seed_spawn/ask = context.answer
		seed_answers = ask.seed_answers.Copy()
		seed_key = ask.seed_key
	else
		var/datum/prompt/number/admin_seed_spawn/ask = context.answer
		seed_answers = ask.seed_answers.Copy()
		seed_key = ask.seed_key
	seed_answers[seed_key] = context.answer.value
	return seed_spawn_stage(user, seed_answers)

/datum/prompt/choice/admin_custom_item_spawn
	recheck_on_open = TRUE
	timeout = 0
	rights = R_SPAWN
	var/list/custom_answers
	var/custom_key

/datum/prompt/choice/admin_custom_item_spawn/recheck_extra()
	if(!admin_can(answerer?.client, 0))
		return "no admin rights"
	if(custom_key == "a12" && !isnull(value))
		var/datum/custom_item/selected = value
		if(!istype(selected) || QDELETED(selected))
			return "gone"

/proc/custom_item_spawn_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/admin_verb/spawn_custom_item/proc/custom_item_spawn_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(custom_item_spawn_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	var/datum/prompt/choice/admin_custom_item_spawn/ask = context.answer
	var/list/custom_answers = ask.custom_answers.Copy()
	custom_answers[ask.custom_key] = ask.value
	return custom_item_spawn_stage(user, custom_answers)

/datum/prompt/choice/admin_fax_department
	timeout = 0
	recheck_on_open = TRUE
	rights = R_ADMIN|R_MOD|R_EVENT
	var/list/fax_answers

/datum/prompt/choice/admin_fax_department/recheck_extra()
	return admin_can(answerer?.client, 0) ? null : "no admin rights"

/datum/prompt/text/admin_fax_origin
	timeout = 0
	recheck_on_open = TRUE
	rights = R_ADMIN|R_MOD|R_EVENT
	var/list/fax_answers

/datum/prompt/text/admin_fax_origin/recheck_extra()
	return admin_can(answerer?.client, 0) ? null : "no admin rights"

/datum/prompt/text/admin_fax_origin/normalize(given)
	return istext(given) ? given : null

/proc/admin_fax_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/admin_verb/sendFax/proc/fax_request_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(admin_fax_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	var/list/fax_answers
	var/key
	if(istype(context.answer, /datum/prompt/choice/admin_fax_department))
		var/datum/prompt/choice/admin_fax_department/ask = context.answer
		fax_answers = ask.fax_answers.Copy()
		key = "department"
	else
		var/datum/prompt/text/admin_fax_origin/ask = context.answer
		fax_answers = ask.fax_answers.Copy()
		key = "origin"
	fax_answers[key] = context.answer.value
	fax_request_stage(user, fax_answers)

/datum/prompt/choice/admin_restart_replay
	timeout = 0
	rights = R_SERVER
	recheck_on_open = TRUE

/datum/prompt/choice/admin_restart_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_restart_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_restart_replay/refusal(given)
	return null

/datum/prompt/number/admin_restart_replay
	timeout = 0
	rights = R_SERVER
	recheck_on_open = TRUE

/datum/prompt/number/admin_restart_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/number/admin_restart_replay/normalize(given)
	return isnum(given) ? given : null

/datum/admin_verb/restart/proc/restart_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)

/datum/prompt/choice/admin_force_antag_replay
	timeout = 0
	rights = R_ADMIN|R_EVENT|R_FUN
	recheck_on_open = TRUE

/datum/prompt/choice/admin_force_antag_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_force_antag_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_force_antag_replay/refusal(given)
	return null

/datum/admin_verb/force_antag_latespawn/proc/force_antag_latespawn_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)
