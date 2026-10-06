//allows right clicking mobs to send an admin PM to their client, forwards the selected mob's client to cmd_admin_pm
ADMIN_VERB_ONLY_CONTEXT_MENU(cmd_admin_pm_context, R_ADMIN|R_MOD|R_SERVER|R_EVENT, "Admin PM Mob", mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
	if(!ismob(M) || !M.client)
		return
	user.cmd_admin_pm(M.client, null)
	feedback_add_details("admin_verb","Admin PM Mob") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

//shows a list of clients we could send PMs to, then forwards our choice to cmd_admin_pm
ADMIN_VERB(cmd_admin_pm_panel, R_ADMIN|R_MOD|R_SERVER|R_EVENT, "Admin PM", "Directly message a player.", ADMIN_CATEGORY_MAIN)
	var/list/client/targets = list()
	for(var/client/T)
		if(T.mob)
			if(isnewplayer(T.mob))
				targets["(New Player) - [T]"] = T
			else if(isobserver(T.mob))
				targets["[T.mob.name](Ghost) - [T]"] = T
			else
				targets["[T.mob.real_name](as [T.mob.name]) - [T]"] = T
		else
			targets["(No Mob) - [T]"] = T
	var/target
	var/datum/request/resumed = length(args) > 1 ? args[2] : null
	if(istype(resumed, /datum/prompt/choice/admin_pm_panel_selection) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(pm_panel_selection_answered))
		target = resumed.value
	else
		open_request(src, /datum/prompt/choice/admin_pm_panel_selection, PROC_REF(pm_panel_selection_answered), answerer = user.mob, question = "To whom shall we send a message?", title = "Admin PM", choices = sortList(targets))
		return
	if(isnull(target))
		return
	if(!target) //Admin canceled
		return
	user.cmd_admin_pm(targets[target], null)
	feedback_add_details("admin_verb","Admin PM") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/client/proc/cmd_ahelp_reply(whom)
	if(prefs.muted & MUTE_ADMINHELP)
		to_chat(src, span_admin_pm_warning("Error: Admin-PM: You are unable to use admin PM-s (muted)."))
		return
	var/client/C
	if(istext(whom))
		if(cmptext(copytext(whom,1,2),"@"))
			whom = findStealthKey(whom)
		C = GLOB.directory[whom]
	else if(isclient(whom))
		C = whom
	if(!C)
		if(holder)
			to_chat(src, span_admin_pm_warning("Error: Admin-PM: Client not found."))
		return

	var/datum/ticket/T = C.current_ticket()

	if(T)
		message_admins(span_pm("[key_name_admin(src)] has started replying to [key_name(C, 0, 0)]'s admin help."))
	om_ask(src, /datum/om/prompt/text/admin_pm/ahelp_reply, PROC_REF(ahelp_reply_entered), whom = C, ticket = T)

/// Writing an admin PM to `whom` (a client).
/datum/om/prompt/text/admin_pm
	message = "Message:"
	multiline = TRUE
	encode = FALSE
	var/client/whom
	var/datum/ticket/ticket

/datum/om/prompt/text/admin_pm/prepare()
	title = "Private message to [key_name(whom, 0, 0)]"
	return TRUE

/// Replying to an adminhelp: a cancel is announced to the other admins.
/datum/om/prompt/text/admin_pm/ahelp_reply

/datum/om/prompt/text/admin_pm/ahelp_reply/cancelled()
	answerer?.client?.ahelp_reply_cancelled(whom)

/// A popup admin PM's reply, on the recipient; the sender is looked up by ckey when it arrives.
/datum/prompt/text/admin_pm_popup
	multiline = TRUE
	timeout = 0
	var/sender_ckey

/client/proc/ahelp_reply_cancelled(client/whom)
	message_admins(span_pm("[key_name_admin(src)] has cancelled their reply to [key_name(whom, 0, 0)]'s admin help."))

/client/proc/ahelp_reply_entered(datum/om/prompt/text/admin_pm/ahelp_reply/ask)
	if (!ask.text)
		ahelp_reply_cancelled(ask.whom)
		return
	cmd_admin_pm(ask.whom, ask.text, ask.ticket)

//takes input from cmd_admin_pm_context, cmd_admin_pm_panel or /client/Topic and sends them a PM.
//Fetching a message if needed. src is the sender and C is the target client
/// A popup PM's reply (on the recipient): to the sender, or an adminhelp if they left.
/client/proc/admin_pm_popup_replied(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/text/admin_pm_popup/ask = A.answer
	var/reply = ask.value
	if(!reply)
		return
	var/client/sender = GLOB.directory[ask.sender_ckey]
	if(sender)
		cmd_admin_pm(sender, reply)										//sender is still about, let's reply to them
	else
		adminhelp(reply)													//sender has left, adminhelp instead

/client/proc/admin_pm_entered(datum/om/prompt/text/admin_pm/ask)
	if(ask.text)
		cmd_admin_pm(ask.whom, ask.text, ask.ticket)

/// Shows this client a popup admin PM they can reply to (the answer runs on this client).
/client/proc/ask_admin_pm_popup(msg, sender_key, sender_ckey)
	var/mob/answering_user = mob
	if(!answering_user)
		return
	open_request(src, /datum/prompt/text/admin_pm_popup, PROC_REF(admin_pm_popup_replied), answerer = answering_user, question = msg, title = "Admin PM from-[sender_key]", sender_ckey = sender_ckey)

/client/proc/cmd_admin_pm(whom, msg, datum/ticket/T, mob/token_actor)
	if(prefs.muted & MUTE_ADMINHELP)
		to_chat(src, span_admin_pm_warning("Error: Admin-PM: You are unable to use admin PM-s (muted)."))
		return

	if(!holder && !current_ticket())	//no ticket? https://www.youtube.com/watch?v=iHSPf6x1Fdo
		to_chat(src, span_admin_pm_warning("You can no longer reply to this ticket, please open another one by using the Adminhelp verb if need be."))
		if(!holder)
			msg = trim(sanitize(copytext(msg,1,MAX_MESSAGE_LEN)))
		to_chat(src, span_admin_pm_notice("Message: [msg]"))
		return

	var/client/recipient
	if(istext(whom))
		if(cmptext(copytext(whom,1,2),"@"))
			whom = findStealthKey(whom)
		recipient = GLOB.directory[whom]
	else if(isclient(whom))
		recipient = whom

	//get message text, limit it's length.and clean/escape html
	if(!msg)
		om_ask(src, /datum/om/prompt/text/admin_pm, PROC_REF(admin_pm_entered), whom = recipient, ticket = T)
		return

	//clean the message if it's not sent by a high-rank admin
	if(!admin_require(src, R_SERVER|R_DEBUG, "cmd_admin_pm", FALSE))//no sending html to the poor bots
		msg = trim(sanitize(copytext(msg,1,MAX_MESSAGE_LEN)))
	if(!msg)
		return

	if (src.handle_spam_prevention(MUTE_ADMINHELP))
		return

	if(prefs.muted & MUTE_ADMINHELP)
		to_chat(src, span_admin_pm_warning("Error: Admin-PM: You are unable to use admin PM-s (muted)."))
		return

	if(!recipient)
		if(!current_ticket())
			to_chat(src, span_admin_pm_warning("Error: Admin-PM: Client not found."))
			to_chat(src, msg)
			return
		log_admin("Adminhelp: [key_name(src)]: [msg]")
		current_ticket().MessageNoRecipient(msg)
		return

	var/rawmsg = msg

	var/keywordparsedmsg = keywords_lookup(msg, FALSE, token_actor)

	if(admin_can(recipient, 0))
		if(holder)	//both are admins
			to_chat(recipient, span_admin_pm_warning("Admin PM from-" + span_bold("[key_name(src, recipient, 1)]") + ": [keywordparsedmsg]"))
			to_chat(src, span_admin_pm_notice("Admin PM to-" + span_bold("[key_name(recipient, src, 1)]") + ": [keywordparsedmsg]"))

			//omg this is dumb, just fill in both their tickets
			var/interaction_message = span_admin_pm_notice("PM from-" + span_bold("[key_name(src, recipient, 1)]") + " to-" + span_bold("[key_name(recipient, src, 1)]") + ": [keywordparsedmsg]")
			admin_ticket_log(src, interaction_message)
			if(recipient != src)	//reeee
				admin_ticket_log(recipient, interaction_message)

		else		//recipient is an admin but sender is not
			var/replymsg = span_admin_pm_warning("Reply PM from-" + span_bold("[key_name(src, recipient, 1)]") + ": [keywordparsedmsg]")
			admin_ticket_log(src, replymsg)
			to_chat(recipient, replymsg)
			to_chat(src, span_admin_pm_notice("PM to-" + span_bold("Admins") + ": [msg]"))

		//play the recieving admin the adminhelp sound (if they have them enabled)
		if(recipient.prefs?.read_preference(/datum/preference/toggle/holder/play_adminhelp_ping))
			recipient << 'sound/effects/adminhelp.ogg'

	else
		if(holder)	//sender is an admin but recipient is not. Do BIG RED TEXT
			if(!recipient.current_ticket())
				new /datum/ticket(msg, recipient, TRUE, 1, mob, token_actor)

			to_chat(recipient, span_admin_pm_warning(span_huge(span_bold("-- Administrator private message --"))))
			to_chat(recipient, span_admin_pm_warning("Admin PM from-" + span_bold("[key_name(src, recipient, 0)]") + ": [msg]"))
			to_chat(recipient, span_admin_pm_warning(span_italics("Click on the administrator's name to reply.")))
			to_chat(src, span_admin_pm_notice("Admin PM to-" + span_bold("[key_name(recipient, src, 1)]") + ": [msg]"))

			admin_ticket_log(recipient, span_admin_pm_notice("PM From [key_name_admin(src)]: [keywordparsedmsg]"))

			//always play non-admin recipients the adminhelp sound
			recipient << 'sound/effects/adminhelp.ogg'

			//AdminPM popup for ApocStation and anybody else who wants to use it. Set it with POPUP_ADMIN_PM in config.txt ~Carn
			if(CONFIG_GET(flag/popup_admin_pm))
				// The recipient replies in their own time; the reply goes back to us if we're still here.
				recipient.ask_admin_pm_popup(msg, key, ckey)

		else		//neither are admins
			to_chat(src, span_admin_pm_warning("Error: Admin-PM: Non-admin to non-admin PM communication is forbidden."))
			return

	log_admin("PM: [key_name(src)]->[key_name(recipient)]: [rawmsg]")
	//we don't use message_admins here because the sender/receiver might get it too
	for(var/client/X in GLOB.admins)
		if(!check_rights_for(X, R_ADMIN|R_SERVER))
			continue
		if(X.key!=key && X.key!=recipient.key)	//check client/X is an admin and isn't the sender or recipient
			to_chat(X, span_admin_pm_notice(span_bold("PM: [key_name(src, X, 0)]-&gt;[key_name(recipient, X, 0)]:") + " [keywordparsedmsg]"))

/datum/prompt/choice/admin_pm_panel_selection
	timeout = 0
	rights = R_ADMIN|R_MOD|R_SERVER|R_EVENT
	recheck_on_open = TRUE

/datum/prompt/choice/admin_pm_panel_selection/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_pm_panel_selection/refusal(given)
	return null

/datum/prompt/choice/admin_pm_panel_selection/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/admin_verb/cmd_admin_pm_panel/proc/pm_panel_selection_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)
