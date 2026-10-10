//Based on the ERT setup

GLOBAL_VAR_INIT(send_beruang, FALSE)
GLOBAL_VAR_INIT(can_call_traders, TRUE)

ADMIN_VERB(trader_ship, R_ADMIN|R_EVENT, "Dispatch Beruang Trader Ship", "Invite players to join the Beruang.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	if(QDELETED(user.mob))
		return
	var/datum/admin_trader_dispatch_review/review = new
	review.client_ckey = user.ckey
	rel_set(review, nameof(review.actor), user.mob)
	review.run_step()

/datum/admin_trader_dispatch_review
	var/tmp/mob/actor
	var/client_ckey
	var/stage = 0
	var/dispatch_answer
	var/alert_answer

CAPABILITIES(/datum/admin_trader_dispatch_review)
	ref_one(nameof(actor), /mob)

/datum/admin_trader_dispatch_review/proc/refusal()
	if(QDELETED(actor) || !GLOB.directory[client_ckey])
		return "The requesting administrator is no longer available."

/datum/admin_trader_dispatch_review/proc/run_step()
	var/datum/result/result = safe_call(PROC_REF(replay))
	if(!result.ok)
		stack_trace("om flow trader_ship continuation: [result.error]")
	if(!result.ok || result.value != TRUE)
		retire()

/datum/admin_trader_dispatch_review/proc/answered(datum/act/request/context)
	if(!context.answer)
		retire()
		return
	if(stage == 0)
		dispatch_answer = context.request.value
	else
		alert_answer = context.request.value
	stage++
	run_step()

/datum/admin_trader_dispatch_review/proc/replay()
	var/client/user = GLOB.directory[client_ckey]
	if(!user || QDELETED(user.mob))
		return
	rel_set(src, nameof(actor), user.mob)
	if(round_game_state() <= GAME_STATE_PREGAME)
		to_chat(user, span_danger("The round hasn't started yet!"))
		return
	if(GLOB.send_beruang)
		to_chat(user, span_danger("The Beruang has already been sent this round!"))
		return
	if(stage == 0)
		open_request(src, /datum/prompt/choice/admin_trader_dispatch, PROC_REF(answered), answerer = actor)
		return TRUE
	var/_answer_a1 = dispatch_answer
	if(isnull(_answer_a1))
		return
	if(_answer_a1 != "Yes")
		return
	if(get_security_level() == "red") // Allow admins to reconsider if the alert level is Red
		if(stage == 1)
			open_request(src, /datum/prompt/choice/admin_trader_red_alert, PROC_REF(answered), answerer = actor)
			return TRUE
		var/_answer_a2 = alert_answer
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

/datum/admin_trader_dispatch_review/proc/retire()
	spent(src)

/datum/prompt/choice/admin_trader_dispatch
	rights = R_ADMIN|R_EVENT
	timeout = 0
	title = "Trade Ship"
	question = "Do you want to dispatch the Beruang trade ship?"
	choices = list("Yes", "No")
	buttons = TRUE
	recheck_on_open = TRUE

/datum/prompt/choice/admin_trader_dispatch/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_trader_dispatch_review/review = owner
	return review.refusal()

/datum/prompt/choice/admin_trader_red_alert
	parent_type = /datum/prompt/choice/admin_trader_dispatch
	question = "The station is in red alert. Do you still want to send traders?"

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

	after(null, 300 SECONDS, GLOBAL_PROC_REF(close_trader_visit))

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
			MT.load_new_z_async(TRUE, GLOBAL_PROC_REF(trader_load_finished))
