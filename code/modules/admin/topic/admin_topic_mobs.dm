// Admin panel href actions on a player's mob: transforms, teleports, info and player-panel buttons.

TOPIC_ACTION(/datum/admins, "simplemake", PROC_REF(topic_simplemake), TOPIC_RIGHTS(R_SPAWN), TOPIC_TEXT("simplemake"), TOPIC_REF("mob", /mob), TOPIC_TEXT("species"))
TOPIC_ACTION(/datum/admins, VV_HK_TURN_MONKEY, PROC_REF(topic_turn_monkey), TOPIC_RIGHTS(R_SPAWN), TOPIC_REF(VV_HK_TURN_MONKEY, /mob/living/carbon/human))
TOPIC_ACTION(/datum/admins, "corgione", PROC_REF(topic_corgione), TOPIC_RIGHTS(R_SPAWN), TOPIC_REF("corgione", /mob/living/carbon/human))
TOPIC_ACTION(/datum/admins, "forcespeech", PROC_REF(topic_forcespeech), TOPIC_RIGHTS(R_FUN), TOPIC_REF("forcespeech", /mob))
TOPIC_ACTION(/datum/admins, "sendtoprison", PROC_REF(topic_sendtoprison), TOPIC_RIGHTS(R_ADMIN), TOPIC_REF("sendtoprison", /mob))
TOPIC_ACTION(/datum/admins, "sendbacktolobby", PROC_REF(topic_sendbacktolobby), TOPIC_RIGHTS(R_ADMIN), TOPIC_REF("sendbacktolobby", /mob))
TOPIC_ACTION(/datum/admins, "tdome1", PROC_REF(topic_tdome1), TOPIC_RIGHTS(R_FUN), TOPIC_REF("tdome1", /mob))
TOPIC_ACTION(/datum/admins, "tdome2", PROC_REF(topic_tdome2), TOPIC_RIGHTS(R_FUN), TOPIC_REF("tdome2", /mob))
TOPIC_ACTION(/datum/admins, "tdomeadmin", PROC_REF(topic_tdomeadmin), TOPIC_RIGHTS(R_FUN), TOPIC_REF("tdomeadmin", /mob))
TOPIC_ACTION(/datum/admins, "tdomeobserve", PROC_REF(topic_tdomeobserve), TOPIC_RIGHTS(R_FUN), TOPIC_REF("tdomeobserve", /mob))
TOPIC_ACTION(/datum/admins, "revive", PROC_REF(topic_revive), TOPIC_RIGHTS(R_REJUVINATE), TOPIC_REF("revive", /mob/living))
TOPIC_ACTION(/datum/admins, VK_HK_TURN_AI, PROC_REF(topic_turn_ai), TOPIC_RIGHTS(R_SPAWN), TOPIC_REF(VK_HK_TURN_AI, /mob/living/carbon/human))
TOPIC_ACTION(/datum/admins, VV_HK_TURN_ALIEN, PROC_REF(topic_turn_alien), TOPIC_RIGHTS(R_SPAWN), TOPIC_REF(VV_HK_TURN_ALIEN, /mob/living/carbon/human))
TOPIC_ACTION(/datum/admins, VK_HK_TURN_ROBOT, PROC_REF(topic_turn_robot), TOPIC_RIGHTS(R_SPAWN), TOPIC_REF(VK_HK_TURN_ROBOT, /mob/living/carbon/human))
TOPIC_ACTION(/datum/admins, "makeanimal", PROC_REF(topic_makeanimal), TOPIC_RIGHTS(R_SPAWN), TOPIC_REF("makeanimal", /mob))
TOPIC_ACTION(/datum/admins, "respawn", PROC_REF(topic_respawn), TOPIC_RIGHTS(R_SPAWN), TOPIC_REF("respawn", /client))
TOPIC_ACTION(/datum/admins, "togmutate", PROC_REF(topic_togmutate), TOPIC_RIGHTS(R_SPAWN), TOPIC_REF("togmutate", /mob/living/carbon/human), TOPIC_NUM("block"))
TOPIC_ACTION(/datum/admins, "adminplayeropts", PROC_REF(topic_adminplayeropts), TOPIC_REF("adminplayeropts", /mob))
TOPIC_ACTION(/datum/admins, "adminplayerobservejump", PROC_REF(topic_adminplayerobservejump), TOPIC_RIGHTS(R_MOD|R_ADMIN|R_SERVER), TOPIC_REF("adminplayerobservejump", /atom))
TOPIC_ACTION(/datum/admins, "adminplayerobservefollow", PROC_REF(topic_adminplayerobservefollow), TOPIC_RIGHTS(R_MOD|R_ADMIN|R_SERVER), TOPIC_REF("adminplayerobservefollow", /atom/movable))
TOPIC_ACTION(/datum/admins, "take_question", PROC_REF(topic_take_question), TOPIC_REF("take_question", /mob))
TOPIC_ACTION(/datum/admins, "adminplayerobservecoodjump", PROC_REF(topic_adminplayerobservecoodjump), TOPIC_RIGHTS(R_ADMIN|R_SERVER|R_MOD), TOPIC_NUM("X"), TOPIC_NUM("Y"), TOPIC_NUM("Z"))
TOPIC_ACTION(/datum/admins, "adminmoreinfo", PROC_REF(topic_adminmoreinfo), TOPIC_REF("adminmoreinfo", /mob))
TOPIC_ACTION(/datum/admins, "adminspawncookie", PROC_REF(topic_adminspawncookie), TOPIC_RIGHTS(R_ADMIN|R_FUN|R_EVENT), TOPIC_REF("adminspawncookie", /mob/living/carbon/human))
TOPIC_ACTION(/datum/admins, "adminsmite", PROC_REF(topic_adminsmite), TOPIC_RIGHTS(R_ADMIN|R_FUN|R_EVENT), TOPIC_REF("adminsmite", /mob/living/carbon/human))
TOPIC_ACTION(/datum/admins, "BlueSpaceArtillery", PROC_REF(topic_bluespaceartillery), TOPIC_RIGHTS(R_ADMIN|R_FUN|R_EVENT), TOPIC_REF("BlueSpaceArtillery", /mob/living))
TOPIC_ACTION(/datum/admins, "jumpto", PROC_REF(topic_jumpto), TOPIC_RIGHTS(R_ADMIN|R_MOD|R_DEBUG|R_EVENT), TOPIC_REF("jumpto", /mob))
TOPIC_ACTION(/datum/admins, "getmob", PROC_REF(topic_getmob), TOPIC_RIGHTS(R_ADMIN|R_MOD|R_DEBUG|R_EVENT), TOPIC_REF("getmob", /mob))
TOPIC_ACTION(/datum/admins, "sendmob", PROC_REF(topic_sendmob), TOPIC_RIGHTS(R_ADMIN|R_MOD|R_DEBUG|R_EVENT), TOPIC_REF("sendmob", /mob))
TOPIC_ACTION(/datum/admins, "narrateto", PROC_REF(topic_narrateto), TOPIC_RIGHTS(R_ADMIN|R_EVENT|R_FUN), TOPIC_REF("narrateto", /mob))
TOPIC_ACTION(/datum/admins, "subtlemessage", PROC_REF(topic_subtlemessage), TOPIC_RIGHTS(R_MOD|R_ADMIN|R_EVENT|R_FUN), TOPIC_REF("subtlemessage", /mob))
TOPIC_ACTION(/datum/admins, "traitor", PROC_REF(topic_traitor), TOPIC_RIGHTS(R_ADMIN|R_MOD|R_EVENT), TOPIC_REF("traitor", /mob))
TOPIC_ACTION(/datum/admins, "toglang", PROC_REF(topic_toglang), TOPIC_RIGHTS(R_SPAWN), TOPIC_REF("toglang", /mob), TOPIC_TEXT("lang"))
TOPIC_ACTION(/datum/admins, "cryoplayer", PROC_REF(topic_cryoplayer), TOPIC_RIGHTS(R_ADMIN|R_EVENT), TOPIC_REF("cryoplayer", /mob/living/carbon))

/// The mob types the rudimentary-transformation links (simplemake=<key>) can turn a mob into.
GLOBAL_LIST_INIT(admin_simplemake_types, list( \
		"observer" = /mob/observer/dead, \
		"larva" = /mob/living/carbon/alien/larva, \
		"nymph" = /mob/living/carbon/alien/diona, \
		"human" = /mob/living/carbon/human, \
		"slime" = /mob/living/simple_mob/slime/xenobio, \
		"monkey" = /mob/living/carbon/human/monkey, \
		"robot" = /mob/living/silicon/robot, \
		"cat" = /mob/living/simple_mob/animal/passive/cat, \
		"runtime" = /mob/living/simple_mob/animal/passive/cat/runtime, \
		"corgi" = /mob/living/simple_mob/animal/passive/dog/corgi, \
		"ian" = /mob/living/simple_mob/animal/passive/dog/corgi/Ian, \
		"crab" = /mob/living/simple_mob/animal/passive/crab, \
		"coffee" = /mob/living/simple_mob/animal/passive/crab/Coffee, \
		"parrot" = /mob/living/simple_mob/animal/passive/bird/parrot, \
		"polyparrot" = /mob/living/simple_mob/animal/passive/bird/parrot/poly, \
		"constructarmoured" = /mob/living/simple_mob/construct/juggernaut, \
		"constructbuilder" = /mob/living/simple_mob/construct/artificer, \
		"constructwraith" = /mob/living/simple_mob/construct/wraith, \
		"shade" = /mob/living/simple_mob/construct/shade, \
))

/datum/admins/proc/topic_simplemake(mob/user, list/args)
	var/mob/M = args["mob"]
	if(!M)
		to_chat(user, span_filter_adminlog("This can only be used on instances of type /mob"))
		return

	var/delmob = 0
	var/answer = topic_ask(user, args, "a3", /datum/om/prompt/choice/alert, message = "Delete old mob?", title = "Message", choices = list("Yes","No","Cancel"))
	switch(answer)
		if("Yes")
			delmob = 1
		if("No")
			delmob = 0
		else
			return

	var/kind = args["simplemake"]
	log_admin("[key_name(user)] has used rudimentary transformation on [key_name(M)]. Transforming to [kind]; deletemob=[delmob]")
	message_admins(span_blue("[key_name_admin(user)] has used rudimentary transformation on [key_name_admin(M)]. Transforming to [kind]; deletemob=[delmob]"), 1)

	var/new_type = GLOB.admin_simplemake_types[kind]
	if(!new_type)
		return
	if(kind == "human")
		M.change_mob_type(new_type, null, null, delmob, args["species"])
	else
		M.change_mob_type(new_type, null, null, delmob)

/datum/admins/proc/topic_turn_monkey(mob/user, list/args)
	var/mob/living/carbon/human/H = args[VV_HK_TURN_MONKEY]
	log_admin("[key_name(user)] attempting to monkeyize [key_name(H)]")
	message_admins(span_blue("[key_name_admin(user)] attempting to monkeyize [key_name_admin(H)]"))
	H.monkeyize()

/datum/admins/proc/topic_corgione(mob/user, list/args)
	var/mob/living/carbon/human/H = args["corgione"]
	log_admin("[key_name(user)] attempting to corgize [key_name(H)]")
	message_admins(span_blue("[key_name_admin(user)] attempting to corgize [key_name_admin(H)]"))
	H.corgize()

/datum/admins/proc/topic_forcespeech(mob/user, list/args)
	var/mob/M = args["forcespeech"]
	var/list/original_href = args[TOPIC_HREF]
	var/datum/request/resumed
	if(original_href)
		resumed = original_href["forcespeech_request"]
	var/speech
	if(istype(resumed, /datum/prompt/text/admin_force_speech) && resumed.owner == src && resumed.answerer == user && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(force_speech_answered))
		speech = resumed.value
	else
		var/list/scalar_href = original_href.Copy()
		scalar_href -= "forcespeech_request"
		open_request(src, /datum/prompt/text/admin_force_speech, PROC_REF(force_speech_answered), answerer = user, question = "What will [key_name(M)] say?.", title = "Force speech", captured = list("href" = scalar_href))
		return
	// Don't need to sanitize, since it does that in say(), we also trust our admins.
	if(!speech || QDELETED(M))
		return
	M.say(speech)
	speech = sanitize(speech) // Nah, we don't trust them
	log_admin("[key_name(user)] forced [key_name(M)] to say: [speech]")
	message_admins(span_blue("[key_name_admin(user)] forced [key_name_admin(M)] to say: [speech]"))

/// Topic prompts shared by the teleport-a-player actions: TRUE when `M` may be moved.
/datum/admins/proc/topic_movable_player(mob/user, mob/M)
	if(QDELETED(M))
		to_chat(user, span_filter_adminlog("This can only be used on instances of type /mob"))
		return FALSE
	if(isAI(M))
		to_chat(user, span_filter_adminlog("This cannot be used on instances of type /mob/living/silicon/ai"))
		return FALSE
	return TRUE

/datum/admins/proc/topic_sendtoprison(mob/user, list/args)
	var/answer = topic_ask(user, args, "a24", /datum/om/prompt/choice/alert, message = "Send to admin prison for the round?", title = "Message", choices = list("Yes", "No"))
	if(answer != "Yes")
		return

	var/mob/M = args["sendtoprison"]
	if(!topic_movable_player(user, M))
		return

	var/turf/prison_cell = pick(GLOB.prisonwarp)
	if(!prison_cell)
		return

	var/obj/structure/closet/secure_closet/brig/locker = new /obj/structure/closet/secure_closet/brig(prison_cell)
	locker.set_opened(FALSE)
	locker.force_lock(TRUE)

	//strip their stuff and stick it in the crate
	for(var/obj/item/I in contents_of(M))
		M.drop_from_inventory(I, locker)

	//so they black out before warping
	M.status_at_least(STAT_PARALYZED, 5)
	M.status_at_least(STAT_SLEEPING, 5)

	M.forceMove(prison_cell)
	if(ishuman(M))
		var/mob/living/carbon/human/prisoner = M
		prisoner.equip_to_slot_or_del(new /obj/item/clothing/under/color/prison(prisoner), SLOT_ID_UNIFORM)
		prisoner.equip_to_slot_or_del(new /obj/item/clothing/shoes/orange(prisoner), SLOT_ID_SHOES)

	to_chat(M, span_filter_system(span_warning("You have been sent to the prison station!")))
	log_admin("[key_name(user)] sent [key_name(M)] to the prison station.")
	message_admins(span_blue("[key_name_admin(user)] sent [key_name_admin(M)] to the prison station."))

/datum/admins/proc/topic_sendbacktolobby(mob/user, list/args)
	var/mob/M = args["sendbacktolobby"]
	if(!isobserver(M))
		to_chat(user, span_filter_adminlog(span_notice("You can only send ghost players back to the Lobby.")))
		return

	if(!M.client)
		to_chat(user, span_filter_adminlog(span_warning("[M] doesn't seem to have an active client.")))
		return

	var/answer = topic_ask(user, args, "a25", /datum/om/prompt/choice/alert, message = "Send [key_name(M)] back to Lobby?", title = "Message", choices = list("Yes", "No"))
	if(answer != "Yes" || QDELETED(M))
		return

	log_admin("[key_name(user)] has sent [key_name(M)] back to the Lobby.")
	message_admins("[key_name(user)] has sent [key_name(M)] back to the Lobby.")

	var/mob/new_player/NP = new()
	NP.ckey = M.ckey
	spent(M, user)

/// Sends `M` to one of the thunderdome landmark lists; `strip` drops their gear first.
/datum/admins/proc/topic_send_to_thunderdome(mob/user, list/args, key, answer_key, strip)
	var/answer = topic_ask(user, args, answer_key, /datum/om/prompt/choice/alert, message = "Confirm?", title = "Message", choices = list("Yes", "No"))
	if(answer != "Yes")
		return FALSE

	var/mob/M = args[key]
	if(!topic_movable_player(user, M))
		return FALSE

	if(strip)
		for(var/obj/item/I in contents_of(M))
			M.drop_from_inventory(I)

	return TRUE

/// The shared tail of the thunderdome actions: knock out, move, tell and log.
/datum/admins/proc/topic_finish_thunderdome(mob/user, mob/M, list/destinations, team_label)
	M.status_at_least(STAT_PARALYZED, 5)
	M.status_at_least(STAT_SLEEPING, 5)
	M.forceMove(pick(destinations))
	after(M, 5 SECONDS, GLOBAL_PROC_REF(to_chat), with = list(M, span_filter_system(span_notice("You have been sent to the Thunderdome."))))
	log_admin("[key_name(user)] has sent [key_name(M)] to the thunderdome. ([team_label])")
	message_admins("[key_name_admin(user)] has sent [key_name_admin(M)] to the thunderdome. ([team_label])")

/datum/admins/proc/topic_tdome1(mob/user, list/args)
	if(topic_send_to_thunderdome(user, args, "tdome1", "a26", TRUE))
		topic_finish_thunderdome(user, args["tdome1"], GLOB.tdome1, "Team 1")

/datum/admins/proc/topic_tdome2(mob/user, list/args)
	if(topic_send_to_thunderdome(user, args, "tdome2", "a27", TRUE))
		topic_finish_thunderdome(user, args["tdome2"], GLOB.tdome2, "Team 2")

/datum/admins/proc/topic_tdomeadmin(mob/user, list/args)
	if(topic_send_to_thunderdome(user, args, "tdomeadmin", "a28", FALSE))
		topic_finish_thunderdome(user, args["tdomeadmin"], GLOB.tdomeadmin, "Admin.")

/datum/admins/proc/topic_tdomeobserve(mob/user, list/args)
	if(!topic_send_to_thunderdome(user, args, "tdomeobserve", "a29", TRUE))
		return
	var/mob/M = args["tdomeobserve"]
	if(ishuman(M))
		var/mob/living/carbon/human/observer = M
		observer.equip_to_slot_or_del(new /obj/item/clothing/under/suit_jacket(observer), SLOT_ID_UNIFORM)
		observer.equip_to_slot_or_del(new /obj/item/clothing/shoes/black(observer), SLOT_ID_SHOES)
	topic_finish_thunderdome(user, M, GLOB.tdomeobserve, "Observer.")

/datum/admins/proc/topic_revive(mob/user, list/args)
	var/mob/living/L = args["revive"]
	if(CONFIG_GET(flag/allow_admin_rev))
		L.revive()
		message_admins(span_red("Admin [key_name_admin(user)] healed / revived [key_name_admin(L)]!"))
		log_admin("[key_name(user)] healed / Rrvived [key_name(L)]")
	else
		to_chat(user, span_filter_adminlog(span_filter_warning("Admin Rejuvinates have been disabled")))

/datum/admins/proc/topic_turn_ai(mob/user, list/args)
	var/mob/living/carbon/human/H = args[VK_HK_TURN_AI]
	message_admins(span_red("Admin [key_name_admin(user)] AIized [key_name_admin(H)]!"))
	log_admin("[key_name(user)] AIized [key_name(H)]")
	H.AIize()

/datum/admins/proc/topic_turn_alien(mob/user, list/args)
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_alienize, args[VV_HK_TURN_ALIEN])

/datum/admins/proc/topic_turn_robot(mob/user, list/args)
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_robotize, args[VK_HK_TURN_ROBOT])

/datum/admins/proc/topic_makeanimal(mob/user, list/args)
	var/mob/M = args["makeanimal"]
	if(isnewplayer(M))
		to_chat(user, span_filter_adminlog("This cannot be used on instances of type /mob/new_player"))
		return
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_animalize, M)

/datum/admins/proc/topic_respawn(mob/user, list/args)
	user.client.respawn_character_proper(args["respawn"])

/datum/admins/proc/topic_togmutate(mob/user, list/args)
	var/mob/living/carbon/human/H = args["togmutate"]
	user.client.cmd_admin_toggle_block(H, args["block"])
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_player_panel, H)

/datum/admins/proc/topic_adminplayeropts(mob/user, list/args)
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_player_panel, args["adminplayeropts"])

/datum/admins/proc/topic_adminplayerobservejump(mob/user, list/args)
	var/client/C = user.client
	if(!isobserver(user))
		SSadmin_verbs.dynamic_invoke_verb(C, /datum/admin_verb/admin_ghost)
	C.do_jumptomob(args["adminplayerobservejump"])

/datum/admins/proc/topic_adminplayerobservefollow(mob/user, list/args)
	var/client/C = user.client
	if(!isobserver(user))
		SSadmin_verbs.dynamic_invoke_verb(C, /datum/admin_verb/admin_ghost)
	var/mob/observer/dead/G = C.mob
	if(istype(G))
		G.ManualFollow(args["adminplayerobservefollow"])

/datum/admins/proc/topic_take_question(mob/user, list/args)
	var/mob/M = args["take_question"]
	var/take_msg = span_notice("<b>ADMINHELP</b>: <b>[key_name(user.client)]</b> is attending to <b>[key_name(M)]'s</b> adminhelp, please don't dogpile them.")
	for(var/client/X in GLOB.admins)
		if(check_rights_for(X, (R_ADMIN|R_MOD|R_SERVER)))
			to_chat(X, take_msg)
	to_chat(M, span_filter_pm(span_boldnotice("Your adminhelp is being attended to by [user.client]. Thanks for your patience!")))
	if(CONFIG_GET(string/chat_webhook_url))
		var/query_string = "type=admintake"
		query_string += "&key=[url_encode(CONFIG_GET(string/chat_webhook_key))]"
		query_string += "&admin=[url_encode(key_name(user.client))]"
		query_string += "&user=[url_encode(key_name(M))]"
		http_get_async("[CONFIG_GET(string/chat_webhook_url)]?[query_string]")

/datum/admins/proc/topic_adminplayerobservecoodjump(mob/user, list/args)
	if(!isobserver(user))
		SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/admin_ghost)
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/jumptocoord, args["X"], args["Y"], args["Z"])

/datum/admins/proc/topic_adminmoreinfo(mob/user, list/args)
	var/mob/M = args["adminmoreinfo"]

	var/location_description = ""
	var/special_role_description = ""
	var/health_description = ""
	var/gender_description = ""
	var/turf/T = get_turf(M)

	//Location
	if(isturf(T))
		if(isarea(T.loc))
			location_description = "([M.loc == T ? "at coordinates " : "in [M.loc] at coordinates "] [T.x], [T.y], [T.z] in area <b>[T.loc]</b>)"
		else
			location_description = "([M.loc == T ? "at coordinates " : "in [M.loc] at coordinates "] [T.x], [T.y], [T.z])"

	//Job + antagonist
	if(M.mind)
		special_role_description = "Role: " + span_bold("[M.mind.assigned_role]") + "; Antagonist: [span_red(span_bold("[M.mind.special_role]"))]; Has been rev: [(M.mind.has_been_rev)?"Yes":"No"]"
	else
		special_role_description = "Role: " + span_italics("Mind datum missing") + " Antagonist: " + span_italics("Mind datum missing") + "; Has been rev: " + span_italics("Mind datum missing") + ";"

	//Health
	if(isliving(M))
		var/mob/living/L = M
		var/status
		switch(M.stat)
			if(0)
				status = "Alive"
			if(1)
				status = span_orange(span_bold("Unconscious"))
			if(2)
				status = span_red(span_bold("Dead"))
		health_description = "Status = [status]"
		health_description += "<BR>Vitality: [round(L.vitality() * 100)]%[L.is_critical() ? " (CRITICAL)" : ""] - Physical: [L.injury_load(INJURY_CATEGORY_PHYSICAL)] - Thermal: [L.injury_load(INJURY_CATEGORY_THERMAL)] - Toxic: [L.injury_load(INJURY_CATEGORY_TOXIC)] - Oxygen debt: [L.oxygen_debt()] - Genetic: [L.injury_load(INJURY_CATEGORY_GENETIC)] - Neural: [L.injury_load(INJURY_CATEGORY_NEURAL)] - Pain: [L.current_pain()]"
	else
		health_description = "This mob type has no health to speak of."

	//Gender
	switch(M.gender)
		if(MALE, FEMALE)
			gender_description = "[M.gender]"
		else
			gender_description = span_red(span_bold("[M.gender]"))

	to_chat(owner(), "<span class='filter_adminlog'><b>Info about [M.name]:</b><br>\
						Mob type = [M.type]; Gender = [gender_description] Damage = [health_description]<br>\
						Name = <b>[M.name]</b>; Real_name = [M.real_name]; Mind_name = [M.mind?"[M.mind.name]":""]; Key = <b>[M.key]</b>;<br>\
						Location = [location_description];<br>\
						[special_role_description]<br>\
						(<a href='byond://?src=\ref[user];[HrefToken()];priv_msg=\ref[M]'>PM</a>) (<A href='byond://?src=\ref[src];[HrefToken()];adminplayeropts=\ref[M]'>PP</A>) (<A href='byond://?_src_=vars;[HrefToken()];Vars=\ref[M]'>VV</A>) \
						(<A href='byond://?src=\ref[src];[HrefToken()];subtlemessage=\ref[M]'>SM</A>) ([admin_jump_link(M, src)]) (<A href='byond://?src=\ref[src];[HrefToken()];secretsadmin=check_antagonist'>CA</A>)</span>")

/datum/admins/proc/topic_adminspawncookie(mob/user, list/args)
	var/mob/living/carbon/human/H = args["adminspawncookie"]
	H.equip_to_slot_or_del(new /obj/item/reagent_containers/food/snacks/cookie(H), SLOT_ID_HAND_L)
	if(!(istype(H.get_equipped_item(SLOT_ID_HAND_L), /obj/item/reagent_containers/food/snacks/cookie)))
		H.equip_to_slot_or_del(new /obj/item/reagent_containers/food/snacks/cookie(H), SLOT_ID_HAND_R)
		if(!(istype(H.get_equipped_item(SLOT_ID_HAND_R), /obj/item/reagent_containers/food/snacks/cookie)))
			log_admin("[key_name(H)] has their hands full, so they did not receive their cookie, spawned by [key_name(owner())].")
			message_admins("[key_name(H)] has their hands full, so they did not receive their cookie, spawned by [key_name(owner())].")
			return
		else
			H.update_inv_r_hand()//To ensure the icon appears in the HUD
	else
		H.update_inv_l_hand()
	log_admin("[key_name(H)] got their cookie, spawned by [key_name(owner())]")
	message_admins("[key_name(H)] got their cookie, spawned by [key_name(owner())]")
	feedback_inc("admin_cookies_spawned",1)
	to_chat(H, span_notice("Your prayers have been answered!! You received the <b>best cookie</b>!"))

/datum/admins/proc/topic_adminsmite(mob/user, list/args)
	owner().smite(args["adminsmite"])

/datum/admins/proc/topic_bluespaceartillery(mob/user, list/args)
	var/mob/living/M = args["BlueSpaceArtillery"]
	var/answer = topic_ask(user, args, "a30", /datum/om/prompt/choice/alert, message = "Are you sure you wish to hit [key_name(M)] with Blue Space Artillery?", title = "Confirm Firing?", choices = list("Yes", "No"))
	if(answer != "Yes" || QDELETED(M))
		return
	bluespace_artillery(M, user)

/datum/admins/proc/topic_jumpto(mob/user, list/args)
	if(!CONFIG_GET(flag/allow_admin_jump))
		tgui_alert_async(user, "Admin jumping disabled")
		return

	var/mob/M = args["jumpto"]
	var/turf/T = get_turf(M)
	if(isturf(T))
		user.on_mob_jump()
		user.forceMove(T)
		feedback_add_details("admin_verb","JM") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		log_and_message_admins("jumped to [key_name_admin(M)]", user)
	else
		to_chat(user, span_filter_adminlog("This mob is not located in the game world."))

/datum/admins/proc/topic_getmob(mob/user, list/args)
	if(!CONFIG_GET(flag/allow_admin_jump))
		tgui_alert_async(user, "Admin jumping disabled")
		return
	var/answer = topic_ask(user, args, "a33", /datum/om/prompt/choice/alert, message = "Confirm?", title = "Message", choices = list("Yes", "No"))
	if(answer != "Yes")
		return

	var/mob/M = args["getmob"]
	if(QDELETED(M))
		return
	M.on_mob_jump()
	M.forceMove(get_turf(user))
	var/msg = "[key_name_admin(user)] jumped [key_name_admin(M)] to them"
	log_and_message_admins(msg)
	admin_ticket_log(M, msg)
	feedback_add_details("admin_verb","GM") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/admins/proc/topic_sendmob(mob/user, list/args)
	if(!CONFIG_GET(flag/allow_admin_jump))
		tgui_alert_async(user, "Admin jumping disabled")
		return

	var/mob/M = args["sendmob"]
	var/list/areachoices = return_sorted_areas()
	var/choice = topic_ask(user, args, "a34", /datum/om/prompt/choice, message = "Pick an area:", title = "Send Mob", choices = areachoices)
	if(!choice || QDELETED(M))
		return

	var/area/A = areachoices[choice]
	if(!A)
		return

	M.on_mob_jump()
	M.forceMove(pick(get_area_turfs(A)))
	var/msg = "[key_name_admin(user)] teleported [ADMIN_LOOKUPFLW(M)]"
	log_and_message_admins(msg)
	admin_ticket_log(M, msg)
	feedback_add_details("admin_verb","SMOB") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/admins/proc/topic_narrateto(mob/user, list/args)
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_direct_narrate, args["narrateto"])

/datum/admins/proc/topic_subtlemessage(mob/user, list/args)
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_subtle_message, args["subtlemessage"])

/datum/admins/proc/topic_traitor(mob/user, list/args)
	if(!SSticker || !SSticker.mode)
		tgui_alert_async(user, "The game hasn't started yet!")
		return
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_traitor_panel, args["traitor"])

/datum/admins/proc/topic_toglang(mob/user, list/args)
	var/mob/M = args["toglang"]
	var/lang2toggle = args["lang"]
	var/datum/language/L = GLOB.all_languages[lang2toggle]

	if(L in M.languages)
		if(!M.remove_language(lang2toggle))
			to_chat(user, span_filter_adminlog("Failed to remove language '[lang2toggle]' from \the [M]!"))
	else
		if(!M.add_language(lang2toggle))
			to_chat(user, span_filter_adminlog("Failed to add language '[lang2toggle]' to \the [M]!"))

	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_player_panel, M)

/datum/admins/proc/topic_cryoplayer(mob/user, list/args)
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/despawn_player, args["cryoplayer"])

/// Only this caller's actual ended question supplies the speech text on public topic replay.
/datum/prompt/text/admin_force_speech
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/admin_force_speech/normalize(given)
	return given

/datum/prompt/text/admin_force_speech/refusal(given)
	return null

/datum/prompt/text/admin_force_speech/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return null

/datum/admins/proc/force_speech_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/list/captured_href = A.answer.captured["href"]
	var/list/replayed_href = captured_href.Copy()
	replayed_href["forcespeech_request"] = A.answer
	world.push_usr(A.request.answerer, new /datum/callback(GLOBAL_PROC, GLOBAL_PROC_REF(topic_dispatch)), src, A.request.answerer, replayed_href)
