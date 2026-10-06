// A client is not a datum and can't hold a relation view, so it names its tickets by id.
/client/var/tmp/current_ticket_id	//the id of the current ticket the (usually) not-admin client is dealing with; read with current_ticket()
/client/var/tmp/selected_ticket_id	//the id of the ticket being viewed in the Tickets Panel (usually) admin/mentor client; read with selected_ticket()

/proc/get_ahelp_channel()
	var/datum/tgs_api/v5/api = TGS_READ_GLOBAL(tgs)
	if(istype(api) && CONFIG_GET(string/ahelp_channel_tag))
		for(var/datum/tgs_chat_channel/channel in api.chat_channels)
			if(channel.custom_tag == CONFIG_GET(string/ahelp_channel_tag))
				return list(channel)
	return 0

/proc/ahelp_discord_message(message)
	if(!message)
		return
	if(CONFIG_GET(flag/discord_ahelps_disabled))
		return
	var/datum/tgs_chat_channel/ahelp_channel = get_ahelp_channel()
	if(ahelp_channel)
		world.TgsChatBroadcast(message,ahelp_channel)
	else
		world.TgsTargetedChatBroadcast(message,TRUE)

//
//TICKET MANAGER
//

GLOBAL_DATUM_INIT(tickets, /datum/tickets, new)

/datum/tickets
	var/list/active_tickets = list() // ALLOW(instance_list): d: ticket singleton; ListInsert() writes through an alias
	var/list/closed_tickets = list() // ALLOW(instance_list): d: ticket singleton; ListInsert() writes through an alias
	var/list/resolved_tickets = list() // ALLOW(instance_list): d: ticket singleton; ListInsert() writes through an alias

	// The stat-panel buttons, made on the first stat_entry(): a statclick takes its state as a param(), which the lifecycle forms cannot apply
	// while the globals (this singleton among them) are still being made.
	var/obj/effect/statclick/ticket_list/astatclick
	var/obj/effect/statclick/ticket_list/cstatclick
	var/obj/effect/statclick/ticket_list/rstatclick

//private
/// Adopts `new_ticket` (unowned, or owned by another of our lists) into the list for its
/// state, kept sorted by id.
/datum/tickets/proc/ListInsert(datum/ticket/new_ticket)
	var/list_var
	switch(new_ticket.state)
		if(AHELP_ACTIVE)
			list_var = "active_tickets"
		if(AHELP_CLOSED)
			list_var = "closed_tickets"
		if(AHELP_RESOLVED)
			list_var = "resolved_tickets"
		else
			CRASH("Invalid ticket state: [new_ticket.state]")
	if(!own_move(new_ticket, src, list_var))
		return
	new_ticket.metrics_state_event()
	// own_move() appended it; slide it back to its sorted position.
	var/list/ticket_list = vars[list_var]
	var/num_tickets = length(ticket_list)
	for(var/I in 1 to num_tickets - 1)
		var/datum/ticket/T = ticket_list[I]
		if(T.id > new_ticket.id)
			ticket_list.Insert(I, new_ticket)
			ticket_list.Cut(num_tickets + 1)
			return

/datum/tickets/proc/BrowseTickets(state, mob/user)
	tgui_interact(user)

//opens the ticket listings for one of the 3 states
/datum/tickets/proc/BrowseTicketsLegacy(state, mob/user)
	var/list/l2b
	var/title
	switch(state)
		if(AHELP_ACTIVE)
			l2b = active_tickets
			title = "Active Tickets"
		if(AHELP_CLOSED)
			l2b = closed_tickets
			title = "Closed Tickets"
		if(AHELP_RESOLVED)
			l2b = resolved_tickets
			title = "Resolved Tickets"
	if(!title)
		return
	var/list/dat = list("<html><head><title>[title]</title></head>")
	dat += "<A href='byond://?_src_=holder;[HrefToken()];ahelp_tickets=[state]'>Refresh</A><br><br>"
	for(var/datum/ticket/T as anything in l2b)
		dat += span_adminnotice(span_adminhelp("Ticket #[T.id]") + ": <A href='byond://?_src_=holder;ahelp=\ref[T];[HrefToken()];ahelp_action=ticket'>[T.initiator_key_name]: [T.name]</A>") + "<br>"
	dat += "</html>"
	// structured TGUI AdminReport (fallback path; primary tickets
	// UI is the dedicated TGUI module).
	dq_admin_report_html(user, title, dat.Join(), src)

//Tickets statpanel
/datum/tickets/proc/stat_entry(client/target)
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	if(!astatclick)
		astatclick = new(null, null, AHELP_ACTIVE) // ALLOW(ownership): the ticket singleton makes its stat buttons once and keeps them for the round
		cstatclick = new(null, null, AHELP_CLOSED) // ALLOW(ownership): the ticket singleton makes its stat buttons once and keeps them for the round
		rstatclick = new(null, null, AHELP_RESOLVED) // ALLOW(ownership): the ticket singleton makes its stat buttons once and keeps them for the round
	var/list/L = list()
	var/num_adm_tickets_disconnected = 0
	var/num_men_tickets_disconnected = 0

	var/list/admin_tickets = list()
	var/list/mentor_tickets = list()

	for(var/datum/ticket/T as anything in active_tickets)
		switch (T.level)
			if(1)
				admin_tickets += T
			if(0)
				mentor_tickets += T

	var/closed_admin_tickets = 0
	var/closed_mentor_tickets = 0

	for(var/datum/ticket/T as anything in closed_tickets)
		switch (T.level)
			if(1)
				closed_admin_tickets++
			if(0)
				closed_mentor_tickets++

	var/resolved_admin_tickets = 0
	var/resolved_mentor_tickets = 0

	for(var/datum/ticket/T as anything in resolved_tickets)
		switch (T.level)
			if(1)
				resolved_admin_tickets++
			if(0)
				resolved_mentor_tickets++

	if(check_rights_for(target, R_ADMIN|R_SERVER|R_MOD))
		L[++L.len] = list("== Admin Tickets ==", "", null, null)
		L[++L.len] = list("Active Tickets:", "[astatclick.update("[admin_tickets.len]")]", null, REF(astatclick))
		for(var/datum/ticket/T as anything in admin_tickets)
			if(T.initiator())
				L[++L.len] = list("ADM #[T.id]. [T.initiator_key_name]:", T.name, null, REF(T.statclick))
			else
				num_adm_tickets_disconnected++
		if(num_adm_tickets_disconnected)
			L[++L.len] = list("Disconnected:", "[astatclick.update("[num_adm_tickets_disconnected]")]", null, REF(astatclick))
		L[++L.len] = list("Closed Tickets:", "[cstatclick.update("[closed_admin_tickets]")]", null, REF(cstatclick))
		L[++L.len] = list("Resolved Tickets:", "[rstatclick.update("[resolved_admin_tickets]")]", null, REF(rstatclick))

	L[++L.len] = list("== Mentor Tickets ==", "", null, null)
	L[++L.len] = list("Active Tickets:", "[astatclick.update("[mentor_tickets.len]")]", null, REF(astatclick))
	for(var/datum/ticket/T as anything in mentor_tickets)
		if(T.initiator())
			L[++L.len] = list("MEN #[T.id]. [T.initiator_key_name]:", T.name, null, REF(T.statclick))
		else
			num_men_tickets_disconnected++
	if(num_men_tickets_disconnected)
		L[++L.len] = list("Disconnected:", "[astatclick.update("[num_men_tickets_disconnected]")]", null, REF(astatclick))
	L[++L.len] = list("Closed Tickets:", "[cstatclick.update("[closed_mentor_tickets]")]", null, REF(cstatclick))
	L[++L.len] = list("Resolved Tickets:", "[rstatclick.update("[resolved_mentor_tickets]")]", null, REF(rstatclick))

	return L

//Reassociate still open ticket if one exists
/datum/tickets/proc/ClientLogin(client/C, only_alert = FALSE)
	var/datum/ticket/active = CKey2ActiveTicket(C.ckey)
	C.current_ticket_id = active?.id
	if(C.current_ticket())
		if(!only_alert)
			C.current_ticket().AddInteraction("Client reconnected.")
		rel_set(C.current_ticket(), nameof(/datum/ticket::initiator), C)
		C.current_ticket().initiator().mob?.throw_alert("open ticket", /atom/movable/screen/alert/open_ticket)

//Dissasociate ticket
/datum/tickets/proc/ClientLogout(client/C)
	if(C.current_ticket())
		var/datum/ticket/T = C.current_ticket()
		T.AddInteraction("Client disconnected.")
		T.initiator()?.mob?.clear_alert("open ticket")
		rel_clear(T, nameof(T.initiator))
		T = null

//Get a ticket given a ckey
/datum/tickets/proc/CKey2ActiveTicket(ckey)
	for(var/datum/ticket/T as anything in active_tickets)
		if(T.initiator_ckey == ckey)
			return T

//Get a ticket by ticket id
/datum/tickets/proc/ID2Ticket(id, mob/user)
	if(!admin_require(user?.client, R_ADMIN|R_SERVER|R_MOD|R_MENTOR, "ticket.lookup"))
		message_admins("[user] has attempted to look up a ticket with ID [id] without sufficent privileges.")
		return

	for(var/datum/ticket/T as anything in active_tickets)
		if(T.id == id)
			return T

	for(var/datum/ticket/T as anything in resolved_tickets)
		if(T.id == id)
			return T

	for(var/datum/ticket/T as anything in closed_tickets)
		if(T.id == id)
			return T

//
//TICKET LIST STATCLICK
//

/obj/effect/statclick/ticket_list
	var/current_state

INITIALIZE_IMMEDIATE(/obj/effect/statclick/ticket_list)

CAPABILITIES(/obj/effect/statclick/ticket_list)
	param(nameof(current_state), pos = 2)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/obj/effect/statclick/ticket_list/proc/click_input(datum/act/input/A)
	GLOB.tickets.BrowseTickets(current_state, A.actor)
	return TRUE

//
//TICKET DATUM
//

/datum/ticket
	var/id
	var/name
	var/level = 0 // 0 = Mentor, 1 = Admin
	var/list/tags
	var/state = AHELP_ACTIVE

	EXPIRY_DECLARE(opened_at)
	EXPIRY_DECLARE(closed_at)

	var/tmp/client/initiator	//semi-misnomer, it's the person who ahelped/was bwoinked
	/// The handling admin's ckey (a client is not a datum, so it is held by key); read with handler_client().
	var/handler_ckey
	var/handler = "/Unassigned\\" // The admin handling the ticket
	var/initiator_ckey
	var/initiator_key_name

	var/list/_interactions	//use AddInteraction() or, preferably, admin_ticket_log()

	var/obj/effect/statclick/ticket/statclick

	var/static/ticket_counter = 0

CAPABILITIES(/datum/ticket)
	owns_one(nameof(statclick), /obj/effect/statclick/ticket)
	interface("Ticket", state = nameof(GLOB.tgui_mentor_state))
	op("retitle", ui_act("retitle"), then(PROC_REF(ui_act_retitle)))
	op("reopen", ui_act("reopen"), then(PROC_REF(ui_act_reopen)))
	op("legacy", ui_act("legacy"), then(PROC_REF(ui_act_legacy)))
	op("send_msg", ui_act("send_msg", arg("msg", schema_text(4096)), arg("ticket_ref", schema_ref(/datum/ticket))), then(PROC_REF(ui_act_send_msg)))

/**
 * public
 *
 * Create a new Ticket.
 * Call this on its own to create a ticket, don't manually assign current_ticket
 *
 * required msg string The title of the ticket: usually the ahelp text
 * required C client The object or datum which owns the UI.
 * required is_bwoink boolean TRUE if this ticket was started by an admin PM
 * required level integer The level of the ticket. 0 = Admin, 1 = Mentor
 */
/datum/ticket/New(raw_msg, client/C, is_bwoink, ticket_level, mob/user, mob/token_actor)
	//clean the input msg
	var/msg = sanitize(copytext(raw_msg,1,MAX_MESSAGE_LEN))
	if(!msg || !C || !C.mob)
		spent(src, user)
		return

	id = ++ticket_counter
	EXPIRY_STAMP(src, opened_at, CLOCK_WORLD)

	name = msg

	level = ticket_level

	rel_set(src, nameof(initiator), C)
	initiator_ckey = initiator().ckey
	initiator_key_name = key_name(initiator(), FALSE, TRUE)
	if(initiator().current_ticket())	//This is a bug
		log_admin("Ticket erroneously left open by code, closing...")
		initiator().current_ticket().AddInteraction("Ticket erroneously left open by code")
		initiator().current_ticket().Close(user || C.mob)
	initiator().current_ticket_id = id

	var/parsed_message = keywords_lookup(msg, FALSE, token_actor)

	rel_set(src, nameof(statclick), make(/obj/effect/statclick/ticket, at = null, ticket_datum = src))
	_interactions = list()

	if(is_bwoink)
		AddInteraction(span_blue("[key_name_admin(user)] PM'd [LinkedReplyName()]"))
		message_admins(span_blue("Ticket [TicketHref("#[id]")] created"))
	else
		MessageNoRecipient(parsed_message)
		//show it to the person adminhelping too
		switch(level)
			if(0)
				to_chat(C, span_mentor_notice("PM to-" + span_bold("Mentors") + ": [name]"))

			if(1)
				to_chat(C, span_adminnotice("PM to-" + span_bold("Admins") + ": [name]"))

		var/admin_number_present = count_admins()
		log_admin("Ticket #[id]: [key_name(initiator())]: [name] - heard by [admin_number_present] non-AFK admins who have +BAN.")
		if(admin_number_present <= 0)
			to_chat(C, span_notice("No active admins are online, your adminhelp was sent to the admin discord."))

	send2adminchatwebhook()

	var/list/adm = get_admin_counts()
	var/list/activemins = adm["present"]
	var/activeMins = activemins.len
	if(is_bwoink)
		ahelp_discord_message("[level == 0 ? "MENTORHELP" : "ADMINHELP"]: FROM: [key_name_admin(user)] TO [initiator_ckey]/[initiator_key_name] - MSG: \n ```[raw_msg]``` \n Heard by [activeMins] NON-AFK staff members.")
	else
		ahelp_discord_message("[level == 0 ? "MENTORHELP" : "ADMINHELP"]: FROM: [initiator_ckey]/[initiator_key_name] - MSG: \n ```[raw_msg]``` \n Heard by [activeMins] NON-AFK staff members.")

	GLOB.tickets.ListInsert(src) // state is AHELP_ACTIVE

	C.mob.throw_alert("open ticket", /atom/movable/screen/alert/open_ticket)

// Leaving GLOB.tickets' owned active/closed/resolved lists is automatic (phase 2).
/datum/ticket/lifecycle_dematerialize()
	..()
	RemoveActive()

/datum/ticket/proc/AddInteraction(formatted_message)
	var/curinteraction = "[gameTimestamp()]: [formatted_message]"
	if(CONFIG_GET(flag/discord_ahelps_all))
		ahelp_discord_message("ADMINHELP: TICKETID: [id] [strip_html_properly(curinteraction)]")
	_interactions += curinteraction

/datum/ticket/proc/TicketPanel(mob/user)
	tgui_interact(user)

//private
/datum/ticket/proc/FullMonty(ref_src, admin_commands = FALSE)
	if(!ref_src)
		ref_src = "\ref[src]"
	if(initiator() && initiator().mob)
		if(admin_commands)
			. = ADMIN_FULLMONTY_NONAME(initiator().mob)
	else
		. = "Initiator disconnected."
	if(state == AHELP_ACTIVE)
		. += ClosureLinks(ref_src)

//private
/datum/ticket/proc/ClosureLinks(ref_src)
	if(!ref_src)
		ref_src = "\ref[src]"

	if(level == 1)
		. = " (<A href='byond://?_src_=holder;ticket=[ref_src];[HrefToken(TRUE)];ticket_action=reject'>REJT</A>)"
		. += " (<A href='byond://?_src_=holder;ticket=[ref_src];[HrefToken(TRUE)];ticket_action=icissue'>IC</A>)"
		. += " (<A href='byond://?_src_=holder;ticket=[ref_src];[HrefToken(TRUE)];ticket_action=close'>CLOSE</A>)"
		. += " (<A href='byond://?_src_=holder;ticket=[ref_src];[HrefToken(TRUE)];ticket_action=resolve'>RSLVE</A>)"
		. += " (<A href='byond://?_src_=holder;ticket=[ref_src];[HrefToken(TRUE)];ticket_action=handleissue'>HANDLE</A>)"
	else
		. = " (<A href='byond://?_src_=holder;ticket=[ref_src];[HrefToken(TRUE)];ticket_action=resolve'>RSLVE</A>)"
		. += " (<A href='byond://?_src_=holder;ticket=[ref_src];[HrefToken(TRUE)];ticket_action=escalate'>ESCALATE</A>)"

//private
/datum/ticket/proc/LinkedReplyName(ref_src)
	if(!ref_src)
		ref_src = "\ref[src]"
	return "<A href='byond://?_src_=holder;ticket=[ref_src];[HrefToken(TRUE)];ticket_action=reply'>[initiator_key_name]</A>"

//private
/datum/ticket/proc/TicketHref(msg, ref_src, action = "ticket")
	if(!ref_src)
		ref_src = "\ref[src]"
	return "<A href='byond://?_src_=holder;ticket=[ref_src];[HrefToken(TRUE)];ticket_action=[action]'>[msg]</A>"

/*
	var/chat_msg = span_notice("(<A href='byond://?_src_=holder;ahelp=[ref_src];[HrefToken()];ahelp_action=escalate'>ESCALATE</A>) Ticket [TicketHref("#[id]", ref_src)]" + span_bold(": [LinkedReplyName(ref_src)]:") + " [msg]")
	 */

//message from the initiator without a target, all admins will see this
//won't bug irc
/datum/ticket/proc/MessageNoRecipient(msg)
	var/ref_src = "\ref[src]"

	AddInteraction(span_red("[LinkedReplyName(ref_src)]: [msg]"))
	//send this msg to all admins

	switch(level)
		if(0)
			for (var/client/C in GLOB.admins)
				var/chat_msg = span_mentor_channel(span_admin_pm_notice(span_adminhelp("Ticket [TicketHref("#[id]", ref_src)]") + span_bold(" (Mentor): [LinkedReplyName(ref_src)] [FullMonty(ref_src, check_rights_for(C, (R_ADMIN|R_SERVER|R_MOD)))]: ") + msg))
				if (C.prefs?.read_preference(/datum/preference/toggle/play_mentorhelp_ping))
					C << 'sound/effects/mentorhelp.mp3'
				to_chat(C, chat_msg)
		if(1)
			for(var/client/X in GLOB.admins)
				var/chat_msg = span_admin_pm_notice(span_adminhelp("Ticket [TicketHref("#[id]", ref_src)] (Admin)") + span_bold(": [LinkedReplyName(ref_src)] [FullMonty(ref_src, check_rights_for(X, (R_ADMIN|R_SERVER|R_MOD)))]:") + msg)
				if(!check_rights_for(X, R_HOLDER))
					continue
				if(X.prefs?.read_preference(/datum/preference/toggle/holder/play_adminhelp_ping))
					X << 'sound/effects/adminhelp.ogg'
				window_flash(X)
				to_chat(X, chat_msg)

//Reopen a closed ticket
/datum/ticket/proc/Reopen(user)
	if(state == AHELP_ACTIVE)
		to_chat(user, span_warning("This ticket is already open."))
		return

	if(GLOB.tickets.CKey2ActiveTicket(initiator_ckey))
		to_chat(user, span_warning("This user already has an active ticket, cannot reopen this one."))
		return

	rel_set(src, nameof(statclick), make(/obj/effect/statclick/ticket, at = null, ticket_datum = src))
	switch(state)
		if(AHELP_CLOSED)
			feedback_dec("ticket_close")
		if(AHELP_RESOLVED)
			feedback_dec("ticket_resolve")
	state = AHELP_ACTIVE
	GLOB.tickets.ListInsert(src) // moves it out of the closed/resolved list
	closed_at = null
	if(initiator())
		initiator().current_ticket_id = id

	var/admin_reopener_name = ismob(user) ? key_name_admin(user) : user
	AddInteraction(span_purple("Reopened by [admin_reopener_name]"))
	if(initiator())
		to_chat(initiator(), span_filter_adminlog("[span_purple("Ticket [TicketHref("#[id]")] was reopened by [ismob(user) ? key_name(user,FALSE,FALSE) : user].")]"))
	var/msg = span_adminhelp("Ticket [TicketHref("#[id]")] reopened by [admin_reopener_name].")
	message_admins(msg)
	log_admin(msg)
	feedback_inc("ticket_reopen")
	initiator().mob.throw_alert("open ticket", /atom/movable/screen/alert/open_ticket)
	//TicketPanel()	//can only be done from here, so refresh it

//private
/datum/ticket/proc/RemoveActive()
	if(state != AHELP_ACTIVE)
		return
	EXPIRY_STAMP(src, closed_at, CLOCK_WORLD)
	rel_clear(src, nameof(statclick))
	own_take_member(GLOB.tickets, nameof(/datum/tickets::active_tickets), src) // Close()/Resolve() re-adopt it via ListInsert()
	if(initiator() && initiator().current_ticket() == src)
		initiator().current_ticket_id = null

//Mark open ticket as closed/meme
/datum/ticket/proc/Close(user, silent = FALSE)
	if(state != AHELP_ACTIVE)
		return
	RemoveActive()
	state = AHELP_CLOSED
	GLOB.tickets.ListInsert(src)
	var/admin_closer_name = ismob(user) ? key_name_admin(user) : user
	AddInteraction(span_filter_adminlog(span_red("Closed by [admin_closer_name].")))
	if(initiator())
		to_chat(initiator(), span_filter_adminlog("[span_red("Ticket [TicketHref("#[id]")] was closed by [ismob(user) ? key_name(user,FALSE,FALSE) : user].")]"))
	if(!silent)
		feedback_inc("ahelp_close")
		var/msg = "Ticket [TicketHref("#[id]")] closed by [admin_closer_name]."
		message_admins(msg)
		log_admin(msg)
	initiator()?.mob?.clear_alert("open ticket")

//Mark open ticket as resolved/legitimate, returns ahelp verb
/datum/ticket/proc/Resolve(user, silent = FALSE)
	if(state != AHELP_ACTIVE)
		return
	RemoveActive()
	state = AHELP_RESOLVED
	GLOB.tickets.ListInsert(src)

	var/admin_resolver_name = ismob(user) ? key_name_admin(user) : user
	AddInteraction(span_filter_adminlog(span_green("Resolved by [admin_resolver_name].")))
	if(initiator())
		to_chat(initiator(), span_filter_adminlog("[span_green("Ticket [TicketHref("#[id]")] was marked resolved by [ismob(user) ? key_name(user,FALSE,FALSE) : user].")]"))
	if(!silent)
		feedback_inc("ticket_resolve")
		var/msg = "Ticket [TicketHref("#[id]")] resolved by [admin_resolver_name]"
		if(level == 1)
			message_mentors(msg)
		else if (level == 0)
			message_admins(msg)

		log_admin(msg)
	initiator()?.mob?.clear_alert("open ticket")

//Close and return ahelp verb, use if ticket is incoherent
/datum/ticket/proc/Reject(mob/user)
	if(state != AHELP_ACTIVE)
		return

	if(initiator())
		if(initiator().prefs?.read_preference(/datum/preference/toggle/holder/play_adminhelp_ping))
			initiator() << 'sound/effects/adminhelp.ogg'

		to_chat(initiator(), span_filter_pm("[span_red(span_huge(span_bold("- AdminHelp Rejected! -")))]<br>\
							[span_red(span_bold("Your admin help was rejected."))]<br>\
							Please try to be calm, clear, and descriptive in admin helps, do not assume the admin has seen any related events, and clearly state the names of anybody you are reporting."))

	var/admin_rejecter_name = ismob(user) ? key_name_admin(user) : user
	feedback_inc("ahelp_reject")
	var/msg = "Ticket [TicketHref("#[id]")] rejected by [admin_rejecter_name]"
	message_admins(msg)
	log_admin(msg)
	AddInteraction("Rejected by [admin_rejecter_name].")
	Close(user, silent = TRUE)

//Resolve ticket with IC Issue message
/datum/ticket/proc/ICIssue(user)
	if(state != AHELP_ACTIVE)
		return

	var/msg = "[span_red(span_huge(span_bold("- AdminHelp marked as IC issue! -")))]<br>"
	msg += "[span_red(span_bold("This is something that can be solved ICly, and does not currently require staff intervention."))]<br>"
	msg += "[span_red("Your AdminHelp may also be unanswerable due to ongoing events.")]"

	if(initiator())
		to_chat(initiator(), span_filter_pm(msg))

	var/admin_resolve_name = ismob(user) ? key_name_admin(user) : user
	feedback_inc("ahelp_icissue")
	msg = "Ticket [TicketHref("#[id]")] marked as IC by [admin_resolve_name]"
	message_admins(msg)
	log_admin(msg)
	AddInteraction("Marked as IC issue by [admin_resolve_name]")
	Resolve(user, silent = TRUE)

//Handle ticket
/datum/ticket/proc/HandleIssue(user)
	if(state != AHELP_ACTIVE)
		return

	var/handler_name = ismob(user) ? key_name(user, FALSE, TRUE) : user
	if(handler == handler_name)
		to_chat(user, span_red("You are already handling this ticket."))
		return

	var/handler_shown_name = ismob(user) ? key_name_admin(user) : user
	var/msg
	switch(level)
		if(0)
			msg = span_green("Your MentorHelp is being handled by [handler_shown_name] please be patient.")
		if(1)
			msg = span_red("Your AdminHelp is being handled by [handler_shown_name] please be patient.")

	if(initiator())
		to_chat(initiator(), msg)

	feedback_inc("ahelp_handling")
	msg = "Ticket [TicketHref("#[id]")] being handled by [handler_shown_name]"
	message_admins(msg)
	log_admin(msg)
	AddInteraction("[handler_shown_name] is now handling this ticket.")
	handler = handler_name
	if(ismob(user))
		var/mob/our_handler_mob = user
		handler_ckey = our_handler_mob.client?.ckey
	metrics_state_event("handled")

/datum/ticket/proc/Retitle(mob/user)
	return retitle_stage(user, null, FALSE)

/datum/ticket/proc/retitle_stage(mob/user, response, response_ready)
	if(!admin_require(user?.client, level == 0 ? (R_ADMIN|R_SERVER|R_MOD|R_MENTOR) : (R_ADMIN|R_SERVER|R_MOD), "ticket.retitle"))
		return
	if(!response_ready)
		open_request(src, /datum/prompt/text/ticket_title, PROC_REF(title_entered), answerer = user, title = "Rename Ticket", question = "Enter a title for the ticket", default = name)
		return
	var/new_title = response
	if(isnull(new_title))
		return
	if(new_title)
		name = new_title
		//not saying the original name cause it could be a long ass message
		var/msg = "Ticket [TicketHref("#[id]")] titled [name] by [key_name_admin(user)]"
		message_admins(msg)
		log_admin(msg)
	//TicketPanel(user)	//we have to be here to do this

//Kick ticket to next level
/datum/ticket/proc/Escalate(mob/user)
	return escalate_stage(user, null, FALSE)

/datum/ticket/proc/escalate_stage(mob/user, response, response_ready)
	if(level != 0)
		return
	if(!admin_require(user?.client, R_ADMIN|R_SERVER|R_MOD|R_MENTOR, "ticket.escalate"))
		return
	if(!response_ready)
		open_request(src, /datum/prompt/choice/ticket_escalate, PROC_REF(escalation_chosen), answerer = user, title = "Escalate", question = "Really escalate this ticket to admins? No mentors will ever be able to interact with it again if you do.", choices = list("Yes","No"))
		return
	var/_answer_k569 = response
	if(isnull(_answer_k569))
		return
	if(_answer_k569 != "Yes")
		return
	if (src.initiator() == null) // You can't escalate a mentorhelp of someone who's logged out because it won't create the adminhelp properly
		to_chat(user, span_mentor_warning("Error: client not found, unable to escalate."))
		return

	SStgui.close_uis(src)
	level = level + 1

	AddInteraction("[key_name_admin(user)] escalated Ticket.")
	message_mentors("[user.ckey] escalated Ticket [TicketHref("#[id]")]")
	log_admin("[key_name(user)] escalated ticket [src.name]")
	to_chat(src.initiator(), span_mentor("[user.ckey] escalated your ticket to admins."))

//Forwarded action from admin/Topic
/datum/ticket/proc/Action(action, mob/user)

	// Actions everyone can do
	switch(level)
		if(0)
			if(!admin_require(user?.client, R_ADMIN|R_SERVER|R_MOD|R_MENTOR, "ticket.action"))
				return
		if(1)
			if(!admin_require(user?.client, R_ADMIN|R_SERVER|R_MOD, "ticket.action"))
				return
		else
			log_admin("[key_name(user)] attempted to act on ticket #[id] with invalid level [level].")
			return

	perform_action(action, user)

/datum/ticket/proc/perform_action(action, mob/user)
	PRIVATE_PROC(TRUE)
	switch(action)
		if("ticket")
			TicketPanel(user)
		if("retitle")
			Retitle(user)
		if("reject")
			Reject(user)
		if("reply")
			switch(level)
				if(0)
					user.client.cmd_mhelp_reply(initiator())
				if(1)
					user.client.cmd_ahelp_reply(initiator())
		if("icissue")
			ICIssue(user)
		if("close")
			Close(user)
		if("resolve")
			Resolve(user)
		if("handleissue")
			HandleIssue(user)
		if("reopen")
			Reopen(user)
		if("escalate")
			Escalate(user)

//
// TICKET STATCLICK
//

/obj/effect/statclick/ticket
	var/tmp/datum/ticket/ticket_datum

INITIALIZE_IMMEDIATE(/obj/effect/statclick/ticket)

CAPABILITIES(/obj/effect/statclick/ticket)
	param(nameof(ticket_datum), pos = 1)
	click_on(PROC_REF(click_input))

/obj/effect/statclick/ticket/update()
	return ..(ticket_datum().name)

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/obj/effect/statclick/ticket/proc/click_input(datum/act/input/A)
	ticket_datum().TicketPanel(A.actor)
	return TRUE

//
// LOGGING
//

//Use this proc when an admin takes action that may be related to an open ticket on what
//what can be a client, ckey, or mob
/proc/admin_ticket_log(what, message)
	var/client/C
	var/mob/Mob = what
	if(istype(Mob))
		C = Mob.client
	else
		C = what
	if(istype(C) && C.current_ticket())
		C.current_ticket().AddInteraction(message)
		return C.current_ticket()
	if(istext(what))	//ckey
		var/datum/ticket/T = GLOB.tickets.CKey2ActiveTicket(what)
		if(T)
			T.AddInteraction(message)
			return T

//
// HELPER PROCS
//

/proc/count_admins(requiredflags = R_BAN)
	var/list/adm = get_admin_counts(requiredflags)
	var/list/activemins = adm["present"]
	. = activemins.len

/proc/get_admin_counts(requiredflags = R_BAN)
	. = list("total" = list(), "noflags" = list(), "afk" = list(), "stealth" = list(), "present" = list())
	for(var/client/X in GLOB.admins)
		.["total"] += X
		if(requiredflags != 0 && !check_rights_for(X, requiredflags))
			.["noflags"] += X
		else if(X.is_afk())
			.["afk"] += X
		else if(X.holder.fakekey)
			.["stealth"] += X
		else
			.["present"] += X

/proc/keywords_lookup(msg,irc, mob/token_actor)

	//This is a list of words which are ignored by the parser when comparing message contents for names. MUST BE IN LOWER CASE!
	var/static/list/adminhelp_ignored_words = list("unknown","the","a","an","of","monkey","alien","as", "i")

	//explode the input msg into a list
	var/list/msglist = splittext(msg, " ")

	//generate keywords lookup
	var/list/surnames = list()
	var/list/forenames = list()
	var/list/ckeys = list()
	var/founds = ""
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		var/list/indexing = list(M.real_name, M.name)
		if(M.mind)
			indexing += M.mind.name

		for(var/string in indexing)
			var/list/L = splittext(string, " ")
			var/surname_found = 0
			//surnames
			for(var/i=L.len, i>=1, i--)
				var/word = ckey(L[i])
				if(word)
					surnames[word] = M
					surname_found = i
					break
			//forenames
			for(var/i=1, i<surname_found, i++)
				var/word = ckey(L[i])
				if(word)
					forenames[word] = M
			//ckeys
			ckeys[M.ckey] = M

	var/ai_found = 0
	msg = ""
	var/list/mobs_found = list()
	for(var/original_word in msglist)
		var/word = ckey(original_word)
		if(word)
			if(!(word in adminhelp_ignored_words))
				if(word == "ai")
					ai_found = 1
				else
					var/mob/found = ckeys[word]
					if(!found)
						found = surnames[word]
						if(!found)
							found = forenames[word]
					if(found)
						if(!(found in mobs_found))
							mobs_found += found
							if(!ai_found && isAI(found))
								ai_found = 1
							var/is_antag = 0
							if(found.mind && found.mind.special_role)
								is_antag = 1
							founds += "Name: [found.name]([found.real_name]) Ckey: [found.ckey] [is_antag ? "(Antag)" : null] "
							var/textentry = "(<A href='byond://?_src_=holder;[token_actor ? HrefTokenFor(token_actor) : HrefToken()];adminmoreinfo=\ref[found]'>?</A>|<A href='byond://?_src_=holder;[token_actor ? HrefTokenFor(token_actor) : HrefToken()];adminplayerobservefollow=\ref[found]'>F</A> "
							msg += "[original_word]" + span_small((is_antag ? span_red(textentry) : span_black(textentry)))
							continue
		msg += "[original_word] "
	if(irc)
		if(founds == "")
			return "Search Failed"
		else
			return founds

	return msg

/// The ticket_datum this refers to (a relation view: null once that is deleted).
/obj/effect/statclick/ticket/proc/ticket_datum() as /datum/ticket
	return ticket_datum

/// The current ticket being viewed in the Tickets Panel (usually) admin/mentor client (a relation view: null once that is deleted).
/client/proc/selected_ticket() as /datum/ticket
	return GLOB.tickets?.ticket_by_id(selected_ticket_id)

/// The current ticket the (usually) not-admin client is dealing with (a relation view: null once that is deleted).
/client/proc/current_ticket() as /datum/ticket
	return GLOB.tickets?.ticket_by_id(current_ticket_id)

/// Semi-misnomer, it's the person who ahelped/was bwoinked (a relation view: null once that is deleted).
/datum/ticket/proc/initiator() as /client
	return initiator

/// The ticket with this id (active or resolved), or null. No rights check: callers name their own tickets.
/datum/tickets/proc/ticket_by_id(id)
	if(isnull(id))
		return null
	for(var/datum/ticket/T as anything in active_tickets)
		if(T.id == id)
			return T
	for(var/datum/ticket/T as anything in resolved_tickets)
		if(T.id == id)
			return T
	return null

/// The handling admin's client, or null while they are disconnected.
/datum/ticket/proc/handler_client()
	return handler_ckey ? GLOB.directory[handler_ckey] : null

/datum/prompt/text/ticket_title
	timeout = 0

/datum/ticket/proc/title_entered(datum/act/request/A)
	if(!A.answer)
		return
	. = title_entered_apply(A)
	SStgui.update_uis(src)

/datum/ticket/proc/title_entered_apply(datum/act/request/A)
	return retitle_stage(A.request.answerer, A.request.value, TRUE)

/datum/prompt/choice/ticket_escalate
	timeout = 0
	buttons = TRUE

/datum/ticket/proc/escalation_chosen(datum/act/request/A)
	if(!A.answer)
		return
	. = escalation_chosen_apply(A)
	SStgui.update_uis(src)

/datum/ticket/proc/escalation_chosen_apply(datum/act/request/A)
	return escalate_stage(A.request.answerer, A.request.value, TRUE)
