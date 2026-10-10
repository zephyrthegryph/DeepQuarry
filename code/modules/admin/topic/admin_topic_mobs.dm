// Admin panel href actions on a player's mob: transforms, teleports, info and player-panel buttons.


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

/datum/admins/proc/topic_simplemake(datum/act/op/A, href_simplemake, href_mob, href_species)
	var/mob/user = A.actor
	var/mob/M = href_mob
	if(!M)
		to_chat(user, span_filter_adminlog("This can only be used on instances of type /mob"))
		return

	var/delmob = 0
	switch(A.step_value("delmob"))
		if("Yes")
			delmob = 1
		if("No")
			delmob = 0
		else
			return

	var/kind = href_simplemake
	log_admin("[key_name(user)] has used rudimentary transformation on [key_name(M)]. Transforming to [kind]; deletemob=[delmob]")
	message_admins(span_blue("[key_name_admin(user)] has used rudimentary transformation on [key_name_admin(M)]. Transforming to [kind]; deletemob=[delmob]"), 1)

	var/new_type = GLOB.admin_simplemake_types[kind]
	if(!new_type)
		return
	if(kind == "human")
		M.change_mob_type(new_type, null, null, delmob, href_species)
	else
		M.change_mob_type(new_type, null, null, delmob)

/datum/admins/proc/topic_turn_monkey(datum/act/op/A, href_vv_hk_turn_monkey)
	var/mob/user = A.actor
	var/mob/living/carbon/human/H = href_vv_hk_turn_monkey
	log_admin("[key_name(user)] attempting to monkeyize [key_name(H)]")
	message_admins(span_blue("[key_name_admin(user)] attempting to monkeyize [key_name_admin(H)]"))
	H.monkeyize()

/datum/admins/proc/topic_corgione(datum/act/op/A, href_corgione)
	var/mob/user = A.actor
	var/mob/living/carbon/human/H = href_corgione
	log_admin("[key_name(user)] attempting to corgize [key_name(H)]")
	message_admins(span_blue("[key_name_admin(user)] attempting to corgize [key_name_admin(H)]"))
	H.corgize()

/datum/admins/proc/force_speech_question(datum/act/op/A)
	return "What will [key_name(A.args["forcespeech"])] say?."

/datum/admins/proc/topic_forcespeech(datum/act/op/A, href_forcespeech)
	var/mob/user = A.actor
	var/mob/M = href_forcespeech
	var/speech = A.step_value("speech")
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

/datum/admins/proc/topic_sendtoprison(datum/act/op/A, href_sendtoprison)
	var/mob/user = A.actor
	if(A.step_value("confirm") != "Yes")
		return

	var/mob/M = href_sendtoprison
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

MSG_DEF_SELF(admin_topic/lobby_not_ghost, "You can only send ghost players back to the Lobby.")
MSG_DEF_SELF(admin_topic/lobby_no_client, "That player doesn't seem to have an active client.")
MSG_DEF_SELF(admin_topic/jump_disabled, "Admin jumping disabled")

/datum/admins/proc/lobby_target_observer(datum/act/op/A)
	return isobserver(A.args["sendbacktolobby"])

/datum/admins/proc/lobby_target_client(datum/act/op/A)
	var/mob/M = A.args["sendbacktolobby"]
	return !!M?.client

/datum/admins/proc/lobby_question(datum/act/op/A)
	return "Send [key_name(A.args["sendbacktolobby"])] back to Lobby?"

/datum/admins/proc/admin_jump_allowed(datum/act/op/A)
	return (admin_jumping_allowed()) ? null : MSG(admin_topic/jump_disabled)

/datum/admins/proc/topic_sendbacktolobby(datum/act/op/A, href_sendbacktolobby)
	var/mob/user = A.actor
	var/mob/M = href_sendbacktolobby
	if(A.step_value("confirm") != "Yes" || QDELETED(M))
		return

	log_admin("[key_name(user)] has sent [key_name(M)] back to the Lobby.")
	message_admins("[key_name(user)] has sent [key_name(M)] back to the Lobby.")

	var/mob/new_player/NP = new()
	NP.ckey = M.ckey
	spent(M, user)

/// Sends `M` to one of the thunderdome landmark lists; `strip` drops their gear first.
/datum/admins/proc/topic_send_to_thunderdome(datum/act/op/A, mob/M, strip)
	var/mob/user = A.actor
	if(A.step_value("confirm") != "Yes")
		return FALSE

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

/datum/admins/proc/topic_tdome1(datum/act/op/A, href_tdome1)
	var/mob/user = A.actor
	if(topic_send_to_thunderdome(A, href_tdome1, TRUE))
		topic_finish_thunderdome(user, href_tdome1, GLOB.tdome1, "Team 1")

/datum/admins/proc/topic_tdome2(datum/act/op/A, href_tdome2)
	var/mob/user = A.actor
	if(topic_send_to_thunderdome(A, href_tdome2, TRUE))
		topic_finish_thunderdome(user, href_tdome2, GLOB.tdome2, "Team 2")

/datum/admins/proc/topic_tdomeadmin(datum/act/op/A, href_tdomeadmin)
	var/mob/user = A.actor
	if(topic_send_to_thunderdome(A, href_tdomeadmin, FALSE))
		topic_finish_thunderdome(user, href_tdomeadmin, GLOB.tdomeadmin, "Admin.")

/datum/admins/proc/topic_tdomeobserve(datum/act/op/A, href_tdomeobserve)
	var/mob/user = A.actor
	if(!topic_send_to_thunderdome(A, href_tdomeobserve, TRUE))
		return
	var/mob/M = href_tdomeobserve
	if(ishuman(M))
		var/mob/living/carbon/human/observer = M
		observer.equip_to_slot_or_del(new /obj/item/clothing/under/suit_jacket(observer), SLOT_ID_UNIFORM)
		observer.equip_to_slot_or_del(new /obj/item/clothing/shoes/black(observer), SLOT_ID_SHOES)
	topic_finish_thunderdome(user, M, GLOB.tdomeobserve, "Observer.")

/datum/admins/proc/topic_revive(datum/act/op/A, href_revive)
	var/mob/user = A.actor
	var/mob/living/L = href_revive
	if(CONFIG_GET(flag/allow_admin_rev))
		L.revive()
		message_admins(span_red("Admin [key_name_admin(user)] healed / revived [key_name_admin(L)]!"))
		log_admin("[key_name(user)] healed / Rrvived [key_name(L)]")
	else
		to_chat(user, span_filter_adminlog(span_filter_warning("Admin Rejuvinates have been disabled")))

/datum/admins/proc/topic_turn_ai(datum/act/op/A, href_vk_hk_turn_ai)
	var/mob/user = A.actor
	var/mob/living/carbon/human/H = href_vk_hk_turn_ai
	message_admins(span_red("Admin [key_name_admin(user)] AIized [key_name_admin(H)]!"))
	log_admin("[key_name(user)] AIized [key_name(H)]")
	H.AIize()

/datum/admins/proc/topic_turn_alien(datum/act/op/A, href_vv_hk_turn_alien)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_alienize, href_vv_hk_turn_alien)

/datum/admins/proc/topic_turn_robot(datum/act/op/A, href_vk_hk_turn_robot)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_robotize, href_vk_hk_turn_robot)

/datum/admins/proc/topic_makeanimal(datum/act/op/A, href_makeanimal)
	var/mob/user = A.actor
	var/mob/M = href_makeanimal
	if(isnewplayer(M))
		to_chat(user, span_filter_adminlog("This cannot be used on instances of type /mob/new_player"))
		return
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_animalize, M)

/datum/admins/proc/topic_respawn(datum/act/op/A, href_respawn)
	var/mob/user = A.actor
	user.client.respawn_character_proper(href_respawn)

/datum/admins/proc/topic_togmutate(datum/act/op/A, href_togmutate, href_block)
	var/mob/user = A.actor
	var/mob/living/carbon/human/H = href_togmutate
	user.client.cmd_admin_toggle_block(H, href_block)
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_player_panel, H)

/datum/admins/proc/topic_adminplayeropts(datum/act/op/A, href_adminplayeropts)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_player_panel, href_adminplayeropts)

/datum/admins/proc/topic_adminplayerobservejump(datum/act/op/A, href_adminplayerobservejump)
	var/mob/user = A.actor
	var/client/C = user.client
	if(!isobserver(user))
		SSadmin_verbs.dynamic_invoke_verb(C, /datum/admin_verb/admin_ghost)
	C.do_jumptomob(href_adminplayerobservejump)

/datum/admins/proc/topic_adminplayerobservefollow(datum/act/op/A, href_adminplayerobservefollow)
	var/mob/user = A.actor
	var/client/C = user.client
	if(!isobserver(user))
		SSadmin_verbs.dynamic_invoke_verb(C, /datum/admin_verb/admin_ghost)
	var/mob/observer/dead/G = C.mob
	if(istype(G))
		G.ManualFollow(href_adminplayerobservefollow)

/datum/admins/proc/topic_take_question(datum/act/op/A, href_take_question)
	var/mob/user = A.actor
	var/mob/M = href_take_question
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

/datum/admins/proc/topic_adminplayerobservecoodjump(datum/act/op/A, href_x, href_y, href_z)
	var/mob/user = A.actor
	if(!isobserver(user))
		SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/admin_ghost)
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/jumptocoord, href_x, href_y, href_z)

/datum/admins/proc/topic_adminmoreinfo(datum/act/op/op_act, href_adminmoreinfo)
	var/mob/user = op_act.actor
	var/mob/M = href_adminmoreinfo

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

/datum/admins/proc/topic_adminspawncookie(datum/act/op/A, href_adminspawncookie)
	var/mob/living/carbon/human/H = href_adminspawncookie
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

/datum/admins/proc/topic_adminsmite(datum/act/op/A, href_adminsmite)
	owner().smite(href_adminsmite)

/datum/admins/proc/artillery_question(datum/act/op/A)
	return "Are you sure you wish to hit [key_name(A.args["BlueSpaceArtillery"])] with Blue Space Artillery?"

/datum/admins/proc/topic_bluespaceartillery(datum/act/op/A, href_bluespaceartillery)
	var/mob/user = A.actor
	var/mob/living/M = href_bluespaceartillery
	if(A.step_value("confirm") != "Yes" || QDELETED(M))
		return
	bluespace_artillery(M, user)

/datum/admins/proc/topic_jumpto(datum/act/op/A, href_jumpto)
	var/mob/user = A.actor
	if(!CONFIG_GET(flag/allow_admin_jump))
		tgui_alert_async(user, "Admin jumping disabled")
		return

	var/mob/M = href_jumpto
	var/turf/T = get_turf(M)
	if(isturf(T))
		user.on_mob_jump()
		user.forceMove(T)
		feedback_add_details("admin_verb","JM") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		log_and_message_admins("jumped to [key_name_admin(M)]", user)
	else
		to_chat(user, span_filter_adminlog("This mob is not located in the game world."))

/datum/admins/proc/topic_getmob(datum/act/op/A, href_getmob)
	var/mob/user = A.actor
	if(A.step_value("confirm") != "Yes")
		return

	var/mob/M = href_getmob
	if(QDELETED(M))
		return
	M.on_mob_jump()
	M.forceMove(get_turf(user))
	var/msg = "[key_name_admin(user)] jumped [key_name_admin(M)] to them"
	log_and_message_admins(msg)
	admin_ticket_log(M, msg)
	feedback_add_details("admin_verb","GM") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/admins/proc/area_choices(datum/act/op/A)
	return return_sorted_areas()

/datum/admins/proc/topic_sendmob(datum/act/op/op_act, href_sendmob)
	var/mob/user = op_act.actor
	var/mob/M = href_sendmob
	var/list/areachoices = return_sorted_areas()
	var/choice = op_act.step_value("area")
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

/datum/admins/proc/topic_narrateto(datum/act/op/A, href_narrateto)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_direct_narrate, href_narrateto)

/datum/admins/proc/topic_subtlemessage(datum/act/op/A, href_subtlemessage)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_subtle_message, href_subtlemessage)

/datum/admins/proc/topic_traitor(datum/act/op/A, href_traitor)
	var/mob/user = A.actor
	if(!SSticker || !ticker_mode())
		tgui_alert_async(user, "The game hasn't started yet!")
		return
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_traitor_panel, href_traitor)

/datum/admins/proc/topic_toglang(datum/act/op/A, href_toglang, href_lang)
	var/mob/user = A.actor
	var/mob/M = href_toglang
	var/lang2toggle = href_lang
	var/datum/language/L = GLOB.all_languages[lang2toggle]

	if(L in M.languages)
		if(!M.remove_language(lang2toggle))
			to_chat(user, span_filter_adminlog("Failed to remove language '[lang2toggle]' from \the [M]!"))
	else
		if(!M.add_language(lang2toggle))
			to_chat(user, span_filter_adminlog("Failed to add language '[lang2toggle]' to \the [M]!"))

	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_player_panel, M)

/datum/admins/proc/topic_cryoplayer(datum/act/op/A, href_cryoplayer)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/despawn_player, href_cryoplayer)

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
