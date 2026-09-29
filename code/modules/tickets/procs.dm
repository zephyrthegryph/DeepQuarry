//
// CLIENT PROCS
//

/client/verb/mentorhelp(msg as text)
	set category = "Admin"
	set name = "Mentorhelp"

	//handle muting and automuting
	if(prefs.muted & MUTE_ADMINHELP)
		to_chat(src, span_danger("Error: Mentor-PM: You cannot send adminhelps (Muted)."))
		return
	if(handle_spam_prevention(MUTE_ADMINHELP))
		return

	if(!msg)
		return

	//remove out adminhelp verb temporarily to prevent spamming of admins.
	remove_verb(src,/client/verb/mentorhelp) // ALLOW(sys_add_verb_pair): ticket cooldown on a client verb (clients hold no grants)
	spawn(600) // ALLOW(scheduler): client verb cooldown (client procs)
		add_verb(src,/client/verb/mentorhelp) // 1 minute cool-down for mentorhelps // ALLOW(sys_add_verb_pair): ticket cooldown on a client verb (clients hold no grants)

	feedback_add_details("admin_verb","Mentorhelp") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	if(current_ticket())
		var/input = rerun_ask(src, "k26", VERB_REF(mentorhelp), args, /datum/om/prompt/choice/alert, message = "You already have a ticket open. Is this for the same issue?", title = "Duplicate?", choices = list("Yes","No"))
		if(isnull(input))
			return
		if(!input)
			return
		if(input == "Yes")
			if(current_ticket())
				log_admin("Mentorhelp: [key_name(src)]: [msg]")
				current_ticket().MessageNoRecipient(msg)
				to_chat(src, span_adminnotice(span_mentor("Mentor-PM to-" + span_bold("Mentors") + ": [msg]")))
				return
			else
				to_chat(src, span_warning("Ticket not found, creating new one..."))
		else
			current_ticket().AddInteraction("[usr.ckey] opened a new ticket.")
			current_ticket().Resolve(usr)

	new /datum/ticket(msg, src, FALSE, 0)

//admin proc
ADMIN_VERB(cmd_mentor_ticket_panel, (R_ADMIN|R_SERVER|R_MOD|R_MENTOR), "Mentor Ticket List", "Opens the list of mentor tickets", ADMIN_CATEGORY_MISC)
	var/browse_to

	var/_answer_k47 = verb_ask(user, "k47", args, /datum/om/prompt/choice, message = "Display which ticket list?", title = "List Choice", choices = list("Active Tickets", "Resolved Tickets"))
	if(isnull(_answer_k47))
		return
	switch(_answer_k47)
		if("Active Tickets")
			browse_to = AHELP_ACTIVE
		if("Resolved Tickets")
			browse_to = AHELP_RESOLVED
		else
			return

	GLOB.tickets.BrowseTickets(browse_to)

/proc/message_mentors(msg)
	msg = span_mentor_channel(span_prefix("Mentor: ") + span_message("[msg]"))

	for(var/client/C in GLOB.admins)
		to_chat(C, msg)

//
// CLIENT PROCS
//

/client/verb/requesthelp()
	set category = "Admin"
	set name = "Request help"
	set hidden = 1

	var/mhelp = rerun_ask(src, "k72", VERB_REF(requesthelp), args, /datum/om/prompt/choice/alert, message = "Select the help you need.", title = "Request for Help", choices = list("Adminhelp","Mentorhelp"))
	if(isnull(mhelp))
		return
	if(!mhelp)
		return

	var/msg = rerun_ask(src, "k76", VERB_REF(requesthelp), args, /datum/om/prompt/text, message = "Input your request for help.", title = "Request for Help ([mhelp])", multiline = TRUE, max_length = MAX_TGUI_INPUT)
	if(isnull(msg))
		return
	if(!msg)
		return

	if (mhelp == "Mentorhelp")
		mentorhelp(msg)
		return

	adminhelp(msg)

/client/verb/adminhelp(msg as text)
	set category = "Admin"
	set name = "Adminhelp"

	//handle muting and automuting
	if(prefs.muted & MUTE_ADMINHELP)
		to_chat(src, span_danger("Error: Admin-PM: You cannot send adminhelps (Muted)."))
		return
	if(handle_spam_prevention(MUTE_ADMINHELP))
		return

	if(!msg)
		return

	//remove out adminhelp verb temporarily to prevent spamming of admins.
	remove_verb(src,/client/verb/adminhelp) // ALLOW(sys_add_verb_pair): ticket cooldown on a client verb (clients hold no grants)
	spawn(1200) // ALLOW(scheduler): client verb cooldown (client procs)
		add_verb(src,/client/verb/adminhelp	) // 2 minute cool-down for adminhelp // ALLOW(sys_add_verb_pair): ticket cooldown on a client verb (clients hold no grants)

	feedback_add_details("admin_verb","Adminhelp") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	if(current_ticket())
		var/input = rerun_ask(src, "k107", VERB_REF(adminhelp), args, /datum/om/prompt/choice/alert, message = "You already have a ticket open. Is this for the same issue?", title = "Duplicate?", choices = list("Yes","No"))
		if(isnull(input))
			return
		if(!input)
			return
		if(input == "Yes")
			if(current_ticket())
				current_ticket().MessageNoRecipient(msg)
				to_chat(src, span_adminnotice("PM to-" + span_bold("Admins") + ": [msg]"))
				return
			else
				to_chat(src, span_warning("Ticket not found, creating new one..."))
		else if(current_ticket())
			current_ticket().AddInteraction("[key_name_admin(usr)] opened a new ticket.")
			current_ticket().Close(usr)

	new /datum/ticket(msg, src, FALSE, 1)

//admin proc
/client/proc/cmd_admin_ticket_panel()
	set name = "Show Ticket List"
	set category = "Admin.Misc"

	if(!check_rights(R_ADMIN|R_MOD|R_DEBUG|R_EVENT, TRUE))
		return

	var/browse_to

	var/_answer_k133 = client_ask("k133", PROC_REF(cmd_admin_ticket_panel), args, 0, /datum/om/prompt/choice, message = "Display which ticket list?", title = "List Choice", choices = list("Active Tickets", "Closed Tickets", "Resolved Tickets"))
	if(isnull(_answer_k133))
		return
	switch(_answer_k133)
		if("Active Tickets")
			browse_to = AHELP_ACTIVE
		if("Closed Tickets")
			browse_to = AHELP_CLOSED
		if("Resolved Tickets")
			browse_to = AHELP_RESOLVED
		else
			return

	GLOB.tickets.BrowseTickets(browse_to)


/datum/ticket/proc/send2adminchatwebhook()
	if(!CONFIG_GET(string/chat_webhook_url))
		return

	var/list/adm = get_admin_counts()
	var/list/afkmins = adm["afk"]
	var/list/allmins = adm["total"]

	var/query_string = "type=adminhelp"
	query_string += "&key=[url_encode(CONFIG_GET(string/chat_webhook_key))]"
	query_string += "&from=[url_encode(key_name(initiator()))]"
	query_string += "&msg=[url_encode(html_decode(name))]"
	query_string += "&admin_number=[allmins.len]"
	query_string += "&admin_number_afk=[afkmins.len]"
	om_http_get("[CONFIG_GET(string/chat_webhook_url)]?[query_string]")

/client/verb/adminspice()
	set category = "Admin"
	set name = "Request Spice"
	set desc = "Request admins to spice round up for you"

	//handle muting and automuting
	if(prefs.muted & MUTE_ADMINHELP)
		to_chat(src, span_danger("Error: You cannot request spice (muted from adminhelps)."))
		return

	var/_answer_k176 = rerun_ask(src, "k176", VERB_REF(adminspice), args, /datum/om/prompt/choice/alert, message = "Are you sure you want to request the admins spice things up for you? You accept the consequences if you do.", title = "Spicy!", choices = list("Yes","No"))
	if(isnull(_answer_k176))
		return
	if(_answer_k176 == "Yes")
		message_admins("[ADMIN_FULLMONTY(src)] has requested the round be spiced up a little.")
		to_chat(src, span_notice("You have requested some more spice in your round."))
	else
		to_chat(src, span_notice("Spice request cancelled."))
		return

	//if they requested spice, then remove spice verb temporarily to prevent spamming
	remove_verb(src,/client/verb/adminspice) // ALLOW(sys_add_verb_pair): ticket cooldown on a client verb (clients hold no grants)
	spawn(10 MINUTES) // ALLOW(scheduler): client verb cooldown (client procs)
		if(src)		// In case we left in the 10 minute cooldown
			add_verb(src,/client/verb/adminspice) // 10 minute cool-down for spice request // ALLOW(sys_add_verb_pair): ticket cooldown on a client verb (clients hold no grants)

//
// MENTOR PROCS
//

/client/proc/cmd_mhelp_reply(whom)
	if(prefs.muted & MUTE_ADMINHELP)
		to_chat(src, span_admin_pm_warning("Error: Mentor-PM: You are unable to use admin PM-s (muted)."))
		return
	var/client/C
	if(istext(whom))
		C = GLOB.directory[whom]
	else if(isclient(whom))
		C = whom
	if(!C)
		if(src.holder)
			to_chat(src, span_admin_pm_warning("Error: Mentor-PM: Client not found."))
		return

	var/datum/ticket/T = C.current_ticket()

	if(T)
		message_mentors(span_mentor_channel("[src] has started replying to [C]'s mentor help."))
	var/msg = client_ask("k208", PROC_REF(cmd_mhelp_reply), args, 0, /datum/om/prompt/text, message = "Message:", title = "Private message to [C]", multiline = TRUE, encode = FALSE, max_length = MAX_TGUI_INPUT)
	if(isnull(msg))
		return
	if (!msg)
		message_mentors(span_mentor_channel("[src] has cancelled their reply to [C]'s mentor help."))
		return
	cmd_mentor_pm(whom, msg, T)

/client/proc/cmd_mentor_pm(whom, msg, datum/ticket/T)
	set category = "Admin"
	set name = "Mentor-PM"
	set hidden = 1

	if(prefs.muted & MUTE_ADMINHELP)
		to_chat(src, span_mentor_warning("Error: Mentor-PM: You are unable to use mentor PM-s (muted)."))
		return

	//Not a mentor and no open ticket
	if(!holder && !current_ticket())
		to_chat(src, span_mentor_warning("You can no longer reply to this ticket, please open another one by using the Mentorhelp verb if need be."))
		if(!holder)
			msg = trim(sanitize(copytext(msg,1,MAX_MESSAGE_LEN)))
		to_chat(src, span_mentor_notice("Message: [msg]"))
		return

	var/client/recipient

	if(istext(whom))
		recipient = GLOB.directory[whom]

	else if(istype(whom,/client))
		recipient = whom

	//get message text, limit it's length.and clean/escape html
	if(!msg)
		var/_answer_k241 = client_ask("k241", PROC_REF(cmd_mentor_pm), args, 0, /datum/om/prompt/text, message = "Message:", title = "Mentor-PM to [whom]", multiline = TRUE, encode = FALSE, max_length = MAX_TGUI_INPUT)
		if(isnull(_answer_k241))
			return
		msg = _answer_k241

		if(!msg)
			return

		if(prefs.muted & MUTE_ADMINHELP)
			to_chat(src, span_mentor_warning("Error: Mentor-PM: You are unable to use mentor PM-s (muted)."))
			return

	if(!recipient)
		if(!current_ticket())
			to_chat(src, span_mentor_warning("Error: Mentor-PM: Client not found."))
			to_chat(src, msg)
			return
		log_admin("Mentorhelp: [key_name(src)]: [msg]")
		current_ticket().MessageNoRecipient(msg)
		return

	//Has mentor powers but the recipient no longer has an open ticket
	if(src.holder && !recipient.current_ticket())
		to_chat(src, span_mentor_warning("You can no longer reply to this ticket."))
		to_chat(src, span_mentor_notice("Message: [msg]"))
		return

	if (src.handle_spam_prevention(MUTE_ADMINHELP))
		return

	msg = trim(sanitize(copytext(msg,1,MAX_MESSAGE_LEN)))
	if(!msg)
		return

	var/interaction_message = span_mentor_notice("Mentor-PM from-" + span_bold("[src]") + " to-" + span_bold("[recipient]") + ": [msg]")

	if (recipient.current_ticket() && !recipient.holder && recipient.current_ticket().level == 0)
		recipient.current_ticket().AddInteraction(interaction_message)
	if (src.current_ticket() && !src.holder && src.current_ticket().level == 0)
		src.current_ticket().AddInteraction(interaction_message)

	// It's a little fucky if they're both mentors, but while admins may need to adminhelp I don't really see any reason a mentor would have to mentorhelp since you can literally just ask any other mentors online
	if (recipient.holder && src.holder)
		if (recipient.current_ticket() && recipient != src && recipient.current_ticket().level == 0)
			recipient.current_ticket().AddInteraction(interaction_message)
		if (src.current_ticket() && src.current_ticket().level == 0)
			src.current_ticket().AddInteraction(interaction_message)

	to_chat(recipient, span_mentor(span_italics("Mentor-PM from-" + span_bold("<a href='byond://?mentorhelp_msg=\ref[src]'>[src]</a>") + ": [msg]")))
	to_chat(src, span_mentor(span_italics("Mentor-PM to-" + span_bold("[recipient]") + ": [msg]")))

	log_admin("[key_name(src)]->[key_name(recipient)]: [msg]")

	if(recipient.prefs?.read_preference(/datum/preference/toggle/play_mentorhelp_ping))
		recipient << 'sound/effects/mentorhelp.mp3'

	for(var/client/C in GLOB.admins)
		if (C != recipient && C != src)
			to_chat(C, interaction_message)
