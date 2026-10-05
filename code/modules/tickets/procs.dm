//
// CLIENT PROCS
//

/client/verb/mentorhelp(msg as text)
	set category = VERB_CAT_ADMIN
	set name = "Mentorhelp"

	//handle muting and automuting
	if(prefs.muted & MUTE_ADMINHELP)
		to_chat(src, span_danger("Error: Mentor-PM: You cannot send adminhelps (Muted)."))
		return
	if(handle_spam_prevention(MUTE_ADMINHELP))
		return

	// `msg as text` is raw player input and is shown to every staff member (MessageNoRecipient,
	// AddInteraction), so sanitize it once here. Never reassign `msg`: `args` is a live view of it, and
	// rerun_ask() below re-runs this verb with `args`, which would sanitize the encoded copy a second time.
	// /datum/ticket/New() takes the raw text: it sanitizes its own copy and forwards the raw text to Discord.
	var/raw_msg = copytext(msg, 1, MAX_MESSAGE_LEN)
	var/clean_msg = sanitize(raw_msg)
	if(!clean_msg)
		return

	//remove out adminhelp verb temporarily to prevent spamming of admins.
	om_grant_for(src, GRANT_VERB_HIDE, /client/verb/mentorhelp, om_grant_target(src), 1 MINUTES) // mentorhelp cooldown

	feedback_add_details("admin_verb","Mentorhelp") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	if(current_ticket())
		var/input = rerun_ask(src, "k26", VERB_REF(mentorhelp), args, /datum/om/prompt/choice/alert, message = "You already have a ticket open. Is this for the same issue?", title = "Duplicate?", choices = list("Yes","No"))
		if(isnull(input))
			return
		if(!input)
			return
		if(input == "Yes")
			if(current_ticket())
				log_admin("Mentorhelp: [key_name(src)]: [clean_msg]")
				current_ticket().MessageNoRecipient(clean_msg)
				to_chat(src, span_adminnotice(span_mentor("Mentor-PM to-" + span_bold("Mentors") + ": [clean_msg]")))
				return
			else
				to_chat(src, span_warning("Ticket not found, creating new one..."))
		else
			current_ticket().AddInteraction("[usr.ckey] opened a new ticket.")
			current_ticket().Resolve(usr)

	new /datum/ticket(raw_msg, src, FALSE, 0)

//admin proc
ADMIN_VERB(cmd_mentor_ticket_panel, (R_ADMIN|R_SERVER|R_MOD|R_MENTOR), "Mentor Ticket List", "Opens the list of mentor tickets", ADMIN_CATEGORY_MISC)
	if(!user.mob || QDELETED(user.mob))
		return
	open_request(src, /datum/prompt/choice/mentor_ticket_panel_list, PROC_REF(mentor_ticket_panel_answered), answerer = user.mob)

/datum/prompt/choice/mentor_ticket_panel_list
	title = "List Choice"
	question = "Display which ticket list?"
	choices = list("Active Tickets", "Resolved Tickets")
	timeout = 0
	rights = R_ADMIN|R_SERVER|R_MOD|R_MENTOR
	recheck_on_open = TRUE

/datum/prompt/choice/mentor_ticket_panel_list/recheck_extra()
	if(QDELETED(answerer))
		return "gone"
	return admin_can(answerer?.client, 0) ? null : "no admin rights"

/proc/mentor_ticket_panel_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/admin_verb/cmd_mentor_ticket_panel/proc/mentor_ticket_panel_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(mentor_ticket_panel_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(!admin_can(user, permissions))
		admin_log_denial(user, "verb:[src.type]", permissions)
		to_chat(user, span_adminnotice("You lack the permissions to do this."))
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	var/browse_to
	switch(context.request.answer_value)
		if("Active Tickets")
			browse_to = AHELP_ACTIVE
		if("Resolved Tickets")
			browse_to = AHELP_RESOLVED
		else
			return
	GLOB.tickets.BrowseTickets(browse_to, user.mob)

/proc/message_mentors(msg)
	msg = span_mentor_channel(span_prefix("Mentor: ") + span_message("[msg]"))

	for(var/client/C in GLOB.admins)
		to_chat(C, msg)

//
// CLIENT PROCS
//

/client/verb/requesthelp()
	set category = VERB_CAT_ADMIN
	set name = "Request help"
	set hidden = 1

	var/mhelp = rerun_ask(src, "k72", VERB_REF(requesthelp), args, /datum/om/prompt/choice/alert, message = "Select the help you need.", title = "Request for Help", choices = list("Adminhelp","Mentorhelp"))
	if(isnull(mhelp))
		return
	if(!mhelp)
		return

	// encode = FALSE: mentorhelp()/adminhelp() sanitize their own argument, so encoding here would double-encode it.
	var/msg = rerun_ask(src, "k76", VERB_REF(requesthelp), args, /datum/om/prompt/text, message = "Input your request for help.", title = "Request for Help ([mhelp])", multiline = TRUE, encode = FALSE, max_length = MAX_TGUI_INPUT)
	if(isnull(msg))
		return
	if(!msg)
		return

	if (mhelp == "Mentorhelp")
		mentorhelp(msg)
		return

	adminhelp(msg)

/client/verb/adminhelp(msg as text)
	set category = VERB_CAT_ADMIN
	set name = "Adminhelp"

	//handle muting and automuting
	if(prefs.muted & MUTE_ADMINHELP)
		to_chat(src, span_danger("Error: Admin-PM: You cannot send adminhelps (Muted)."))
		return
	if(handle_spam_prevention(MUTE_ADMINHELP))
		return

	// Same contract as mentorhelp: clean_msg is the staff-facing text, raw_msg goes to the ticket. Never reassign `msg` (see mentorhelp).
	var/raw_msg = copytext(msg, 1, MAX_MESSAGE_LEN)
	var/clean_msg = sanitize(raw_msg)
	if(!clean_msg)
		return

	//remove out adminhelp verb temporarily to prevent spamming of admins.
	om_grant_for(src, GRANT_VERB_HIDE, /client/verb/adminhelp, om_grant_target(src), 2 MINUTES) // adminhelp cooldown

	feedback_add_details("admin_verb","Adminhelp") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	if(current_ticket())
		var/input = rerun_ask(src, "k107", VERB_REF(adminhelp), args, /datum/om/prompt/choice/alert, message = "You already have a ticket open. Is this for the same issue?", title = "Duplicate?", choices = list("Yes","No"))
		if(isnull(input))
			return
		if(!input)
			return
		if(input == "Yes")
			if(current_ticket())
				current_ticket().MessageNoRecipient(clean_msg)
				to_chat(src, span_adminnotice("PM to-" + span_bold("Admins") + ": [clean_msg]"))
				return
			else
				to_chat(src, span_warning("Ticket not found, creating new one..."))
		else if(current_ticket())
			current_ticket().AddInteraction("[key_name_admin(usr)] opened a new ticket.")
			current_ticket().Close(usr)

	new /datum/ticket(raw_msg, src, FALSE, 1)

//admin proc
/client/proc/cmd_admin_ticket_panel()
	set name = "Show Ticket List"
	set category = VERB_CAT_ADMIN_MISC

	if(!admin_require(src, R_ADMIN|R_MOD|R_DEBUG|R_EVENT, "ticket.panel"))
		return

	if(QDELETED(mob))
		return
	var/datum/admin_ticket_panel_review/review = new
	review.client_ckey = ckey
	rel_set(review, nameof(review.actor), mob)
	open_request(review, /datum/prompt/choice/admin_ticket_panel_list, TYPE_PROC_REF(/datum/admin_ticket_panel_review, answered), answerer = mob)

/datum/admin_ticket_panel_review
	var/tmp/mob/actor
	var/client_ckey

CAPABILITIES(/datum/admin_ticket_panel_review)
	ref_one(nameof(actor), /mob)

/datum/admin_ticket_panel_review/proc/answered(datum/act/request/context)
	if(context.answer)
		apply_choice(context.request.answer_value)
	retire()

/datum/admin_ticket_panel_review/proc/apply_choice(choice)
	var/client/requester = GLOB.directory[client_ckey]
	if(!requester || QDELETED(actor))
		return
	if(!admin_require(requester, R_ADMIN|R_MOD|R_DEBUG|R_EVENT, "ticket.panel"))
		return
	var/browse_to
	switch(choice)
		if("Active Tickets")
			browse_to = AHELP_ACTIVE
		if("Closed Tickets")
			browse_to = AHELP_CLOSED
		if("Resolved Tickets")
			browse_to = AHELP_RESOLVED
		else
			return

	GLOB.tickets.BrowseTickets(browse_to, requester.mob)


/datum/admin_ticket_panel_review/proc/retire()
	qdel(src) // ALLOW(lifecycle): Finished nonspatial request state has no inventory release contract.

/datum/prompt/choice/admin_ticket_panel_list
	title = "List Choice"
	question = "Display which ticket list?"
	choices = list("Active Tickets", "Closed Tickets", "Resolved Tickets")
	timeout = 0

/datum/prompt/choice/admin_ticket_panel_list/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_ticket_panel_review/review = owner
	if(QDELETED(review.actor) || !GLOB.directory[review.client_ckey])
		return "The original administrator is no longer available."

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
	set category = VERB_CAT_ADMIN
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
	om_grant_for(src, GRANT_VERB_HIDE, /client/verb/adminspice, om_grant_target(src), 10 MINUTES) // spice request cooldown

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
	// encode = FALSE: cmd_mentor_pm() sanitizes the raw answer before it reaches any other client or the ticket log.
	var/msg = client_ask("k208", PROC_REF(cmd_mhelp_reply), args, 0, /datum/om/prompt/text, message = "Message:", title = "Private message to [C]", multiline = TRUE, encode = FALSE, max_length = MAX_TGUI_INPUT)
	if(isnull(msg))
		return
	if (!msg)
		message_mentors(span_mentor_channel("[src] has cancelled their reply to [C]'s mentor help."))
		return
	cmd_mentor_pm(whom, msg, T)

/client/proc/cmd_mentor_pm(whom, msg, datum/ticket/T)
	set category = VERB_CAT_ADMIN
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
		// encode = FALSE: the raw answer is sanitized below, before any branch shows it to another client.
		var/_answer_k241 = client_ask("k241", PROC_REF(cmd_mentor_pm), args, 0, /datum/om/prompt/text, message = "Message:", title = "Mentor-PM to [whom]", multiline = TRUE, encode = FALSE, max_length = MAX_TGUI_INPUT)
		if(isnull(_answer_k241))
			return
		msg = _answer_k241

		if(!msg)
			return

		if(prefs.muted & MUTE_ADMINHELP)
			to_chat(src, span_mentor_warning("Error: Mentor-PM: You are unable to use mentor PM-s (muted)."))
			return

	// Sanitize before any branch below shows the text to a staff client or writes it to a ticket log
	// (MessageNoRecipient, AddInteraction). The prompts above are encode = FALSE and several callers pass raw text.
	msg = trim(sanitize(copytext(msg,1,MAX_MESSAGE_LEN)))
	if(!msg)
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
