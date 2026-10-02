//Based on the ERT setup

GLOBAL_VAR_INIT(send_beruang, FALSE)
GLOBAL_VAR_INIT(can_call_traders, TRUE)

ADMIN_VERB(trader_ship, R_ADMIN|R_EVENT, "Dispatch Beruang Trader Ship", "Invite players to join the Beruang.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	if(SSticker.current_state <= GAME_STATE_PREGAME)
		to_chat(user, span_danger("The round hasn't started yet!"))
		return
	if(GLOB.send_beruang)
		to_chat(user, span_danger("The Beruang has already been sent this round!"))
		return
	var/_answer_a1 = verb_ask(user, "a1", args, /datum/om/prompt/choice/alert, message = "Do you want to dispatch the Beruang trade ship?", title = "Trade Ship", choices = list("Yes","No"))
	if(isnull(_answer_a1))
		return
	if(_answer_a1 != "Yes")
		return
	if(get_security_level() == "red") // Allow admins to reconsider if the alert level is Red
		var/_answer_a2 = verb_ask(user, "a2", args, /datum/om/prompt/choice/alert, message = "The station is in red alert. Do you still want to send traders?", title = "Trade Ship", choices = list("Yes","No"))
		if(isnull(_answer_a2))
			return
		if(_answer_a2 != "Yes")
			return
	if(GLOB.send_beruang)
		to_chat(user, span_danger("Looks like somebody beat you to it!"))
		return

	message_admins("[key_name_admin(user)] is dispatching the Beruang.")
	log_admin("[key_name(user)] used Dispatch Beruang Trader Ship.")
	trigger_trader_visit()

/client/verb/JoinTraders()
	set name = "Join Trader Visit"
	set category = VERB_CAT_IC_EVENT

	if(!MayRespawn(TRUE))
		to_chat(src, span_warning("You cannot join the traders."))
		return

	if(!isobserver(mob) && !isnewplayer(mob))
		to_chat(src, "You need to be an observer or new player to use this.")
		return

	if(!GLOB.send_beruang)
		to_chat(src, "The Beruang is not currently heading to the station.")
		return
	if(length(GLOB.traders.current_antagonists) >= GLOB.traders.hard_cap)
		to_chat(src, "The number of trader slots is already full!")
		return
	GLOB.traders.create_default(mob)

/proc/trigger_trader_visit()
	if(!GLOB.can_call_traders)
		return
	if(GLOB.send_beruang)
		return

	GLOB.command_announcement.Announce("Incoming cargo hauler: Beruang (Reg: VRS 22EB1F11C2).", "[station_name()] Traffic Control")

	GLOB.can_call_traders = FALSE // Only one call per round.
	GLOB.send_beruang = TRUE
	consider_trader_load()

	om_after(null, 300 SECONDS, GLOBAL_PROC_REF(close_trader_visit))

/proc/trader_load_finished(z)
	log_and_message_admins("Loaded the trade shuttle just now.")

/proc/close_trader_visit()
	GLOB.send_beruang = FALSE // Can no longer join the traders.

GLOBAL_VAR(trader_loaded)

/proc/consider_trader_load()
	if(!GLOB.trader_loaded)
		GLOB.trader_loaded = TRUE
		var/datum/map_template/MT = SSmapping.map_templates["Special Area - Salamander Trader"] //was: "Special Area - Trader"
		if(!istype(MT))
			log_mapping("Trader is not a valid map template!")
		else
			MT.load_new_z_async(TRUE, om_callable(null, GLOBAL_PROC_REF(trader_load_finished)))
