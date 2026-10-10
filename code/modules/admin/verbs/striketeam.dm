//STRIKE TEAMS
/client/proc/strike_team()
	set category = VERB_CAT_FUN_EVENT_KIT
	set name = "Spawn Strike Team"
	set desc = "Spawns a strike team if you want to run an admin event."

	if(!check_rights_for(src, R_HOLDER))
		to_chat(src, "Only administrators may use this command.")
		return

	if(!SSticker)
		to_chat(usr, span_red("The game hasn't started yet!"))
		return

	if(world.time < 6000)
		to_chat(usr, span_red("There are [(6000-world.time)/10] seconds remaining before it may be called."))
		return

	mob?.ask_admin_strike_team()

/proc/strike_team_datum(choice)
	switch(choice)
		if("Heavy Asset Protection")
			return GLOB.deathsquad
		if("Mercenaries")
			return GLOB.commandos

/// Strike-team questions retain the original admin mob, rights and team identity through every answer.
/datum/prompt/choice/admin_strike_team
	title = "Strike Team"
	rights = R_HOLDER
	timeout = 0
	var/team_type
	recheck_on_open = TRUE

/datum/prompt/text/admin_strike_team
	title = "Specify Mission"
	max_len = MAX_MESSAGE_LEN
	rights = R_HOLDER
	timeout = 0
	var/team_type

/mob/proc/ask_admin_strike_team()
	open_request(src, /datum/prompt/choice/admin_strike_team, PROC_REF(admin_strike_team_type_picked), answerer = src, question = "Select type of strike team:", choices = list("Heavy Asset Protection", "Mercenaries"))

/mob/proc/admin_strike_team_type_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/admin_strike_team/ask = A.answer
	var/team_type = ask.value
	var/datum/antagonist/deathsquad/team = strike_team_datum(team_type)
	if(team.deployed)
		to_chat(src, span_red("Someone is already sending a team."))
		return
	open_request(src, /datum/prompt/choice/admin_strike_team, PROC_REF(admin_strike_team_sure), answerer = src, team_type = team_type, buttons = TRUE, choices = list("Yes", "No"), question = "Do you want to send in a strike team? Once enabled, this is irreversible.")

/mob/proc/admin_strike_team_sure(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/admin_strike_team/ask = A.answer
	if(ask.value != "Yes")
		return
	open_request(src, /datum/prompt/text/admin_strike_team, PROC_REF(admin_strike_team_mission_entered), answerer = src, team_type = ask.team_type, question = "This 'mode' will go on until everyone is dead or the station is destroyed. You may also admin-call the evac shuttle when appropriate. Spawned commandos have internals cameras which are viewable through a monitor inside the Spec. Ops. Office. Assigning the team's detailed task is recommended from there. While you will be able to manually pick the candidates from active ghosts, their assignment in the squad will be random.\n\nPlease specify which mission the strike team shall undertake.")

/mob/proc/admin_strike_team_mission_entered(datum/act/request/A)
	if(!A.answer || isnull(A.answer.value))
		return
	var/datum/prompt/text/admin_strike_team/ask = A.answer
	var/datum/antagonist/deathsquad/team = strike_team_datum(ask.team_type)
	consider_ert_load()

	if(team.deployed)
		to_chat(src, "Looks like someone beat you to it.")
		return

	team.attempt_random_spawn()

//STRIKE TEAMS
//Thanks to Kilakk for the admin-button portion of this code.

GLOBAL_VAR_INIT(send_emergency_team, 0) // Used for automagic response teams; 'admin_emergency_team' for admin-spawned response teams

GLOBAL_VAR_INIT(ert_base_chance, 10) // Default base chance. Will be incremented by increment ERT chance.
GLOBAL_VAR(can_call_ert)
GLOBAL_VAR_INIT(silent_ert, FALSE)

ADMIN_VERB(response_team, R_ADMIN|R_MOD|R_EVENT, "Dispatch Emergency Response Team", "Send an emergency response team to the station.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	// Only this verb's actual ended native request supplies replay answers.
	var/list/replay_answers = list()
	if(length(args) > 1)
		var/datum/request/resumed = args[2]
		if((istype(resumed, /datum/prompt/choice/admin_response_team_replay)) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(response_team_replay_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	if(round_game_state() <= GAME_STATE_PREGAME)
		to_chat(user, span_danger("The round hasn't started yet!"))
		return
	if(GLOB.send_emergency_team)
		to_chat(user, span_danger("[using_map.boss_name] has already dispatched an emergency response team!"))
		return
	if(!("a1" in replay_answers))
		open_request(src, /datum/prompt/choice/admin_response_team_replay, PROC_REF(response_team_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a1", buttons = TRUE, question = "Do you want to dispatch an Emergency Response Team?", title = "ERT", choices = list("Yes","No"))
		return
	var/_answer_a1 = replay_answers["a1"]
	if(isnull(_answer_a1))
		return
	if(_answer_a1 != "Yes")
		return
	if(!("a2" in replay_answers))
		open_request(src, /datum/prompt/choice/admin_response_team_replay, PROC_REF(response_team_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a2", buttons = TRUE, question = "Do you want this Response Team to be announced?", title = "ERT", choices = list("Yes","No"))
		return
	var/_answer_a2 = replay_answers["a2"]
	if(isnull(_answer_a2))
		return
	if(_answer_a2 != "Yes")
		GLOB.silent_ert = TRUE
	if(get_security_level() != "red") // Allow admins to reconsider if the alert level isn't Red
		if(!("a3" in replay_answers))
			open_request(src, /datum/prompt/choice/admin_response_team_replay, PROC_REF(response_team_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a3", buttons = TRUE, question = "The station is not in red alert. Do you still want to dispatch a response team?", title = "ERT", choices = list("Yes","No"))
			return
		var/_answer_a3 = replay_answers["a3"]
		if(isnull(_answer_a3))
			return
		if(_answer_a3 != "Yes")
			return
	if(GLOB.send_emergency_team)
		to_chat(user, span_danger("Looks like somebody beat you to it!"))
		return

	message_admins("[key_name_admin(user)] is dispatching an Emergency Response Team.")
	admin_chat_message(message = "[key_name(user)] is dispatching an Emergency Response Team", color = "#CC2222")
	log_admin("[key_name(user)] used Dispatch Response Team.")
	trigger_armed_response_team(TRUE)

/client/verb/JoinResponseTeam()

	set name = "Join Response Team"
	set category = VERB_CAT_IC_EVENT

	if(!MayRespawn(1))
		to_chat(usr, span_warning("You cannot join the response team at this time."))
		return

	if(isobserver(usr) || isnewplayer(usr))
		if(!GLOB.send_emergency_team)
			to_chat(usr, "No emergency response team is currently being sent.")
			return
		if(jobban_isbanned(usr, JOB_SYNDICATE) || jobban_isbanned(usr, JOB_EMERGENCY_RESPONSE_TEAM) || jobban_isbanned(usr, JOB_SECURITY_OFFICER))
			to_chat(usr, span_danger("You are jobbanned from the emergency reponse team!"))
			return
		if(length(GLOB.ert.current_antagonists) >= GLOB.ert.hard_cap)
			to_chat(usr, "The emergency response team is already full!")
			return
		GLOB.ert.create_default(usr)
	else
		to_chat(usr, "You need to be an observer or new player to use this.")

// returns a number of dead players in %
/proc/percentage_dead()
	var/total = 0
	var/deadcount = 0
	for(var/mob/living/carbon/human/H in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(H.client) // Monkeys and mice don't have a client, amirite?
			if(H.stat == 2) deadcount++
			total++

	if(total == 0) return 0
	else return round(100 * deadcount / total)

// counts the number of antagonists in %
/proc/percentage_antagonists()
	var/total = 0
	var/antagonists = 0
	for(var/mob/living/carbon/human/H in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(is_special_character(H) >= 1)
			antagonists++
		total++

	if(total == 0) return 0
	else return round(100 * antagonists / total)

// Increments the ERT chance automatically, so that the later it is in the round,
// the more likely an ERT is to be able to be called.
/proc/increment_ert_chance()
	if(GLOB.send_emergency_team) // An ERT is out; the chance stops growing.
		return
	if(get_security_level() == "green")
		GLOB.ert_base_chance += 1
	if(get_security_level() == "yellow")
		GLOB.ert_base_chance += 1
	if(get_security_level() == "violet")
		GLOB.ert_base_chance += 2
	if(get_security_level() == "orange")
		GLOB.ert_base_chance += 2
	if(get_security_level() == "blue")
		GLOB.ert_base_chance += 2
	if(get_security_level() == "red")
		GLOB.ert_base_chance += 3
	if(get_security_level() == "delta")
		GLOB.ert_base_chance += 10           // Need those big guns
	after(null, 3 MINUTES, GLOBAL_PROC_REF(increment_ert_chance))


/proc/trigger_armed_response_team(force = 0)
	if(!GLOB.can_call_ert && !force)
		return
	if(GLOB.send_emergency_team)
		return

	var/send_team_chance = GLOB.ert_base_chance // Is incremented by increment_ert_chance.
	send_team_chance += 2*percentage_dead() // the more people are dead, the higher the chance
	send_team_chance += percentage_antagonists() // the more antagonists, the higher the chance
	send_team_chance = min(send_team_chance, 100)

	if(force) send_team_chance = 100

	// there's only a certain chance a team will be sent
	if(!prob(send_team_chance))
		GLOB.command_announcement.Announce("It would appear that an emergency response team was requested for [station_name()]. Unfortunately, we were unable to send one at this time.", "[using_map.boss_name]", ANNOUNCER_MSG_STRIKETEAM_FAIL)
		GLOB.can_call_ert = 0 // Only one call per round, ladies.
		return
	if(GLOB.silent_ert == 0)
		GLOB.command_announcement.Announce("It would appear that an emergency response team was requested for [station_name()]. We will prepare and send one as soon as possible.", "[using_map.boss_name]", ANNOUNCER_MSG_STRIKETEAM_SUCCESS)

	GLOB.can_call_ert = 0 // Only one call per round, gentleman.
	GLOB.send_emergency_team = 1
	consider_ert_load()

	after(null, 5 MINUTES, GLOBAL_PROC_REF(close_armed_response_team))

/proc/ert_load_finished(z)
	log_and_message_admins("Loaded the ERT shuttle just now.")

/proc/close_armed_response_team()
	GLOB.send_emergency_team = 0 // Can no longer join the ERT.

GLOBAL_VAR(ert_loaded)

/proc/consider_ert_load()
	if(!GLOB.ert_loaded)
		GLOB.ert_loaded = TRUE
		var/datum/map_template/MT = SSmapping.map_templates["Special Area - ERT"]
		if(!istype(MT))
			log_mapping("ERT Area is not a valid map template!")
		else
			MT.load_new_z_async(TRUE, GLOBAL_PROC_REF(ert_load_finished))

/datum/prompt/choice/admin_response_team_replay
	timeout = 0
	rights = R_ADMIN|R_MOD|R_EVENT
	recheck_on_open = TRUE

/datum/prompt/choice/admin_response_team_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_response_team_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_response_team_replay/refusal(given)
	return null

/datum/admin_verb/response_team/proc/response_team_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)
