/mob/verb/pray()
	set category = VERB_CAT_IC_GAME
	set name = "Pray"

	open_request(src, /datum/prompt/text, PROC_REF(prayer_entered), answerer = src, title = "Pray", question = "Prayers are sent to staff but do not open tickets or go to Discord. If you have a technical difficulty or an event/spice idea/hook - please ahelp instead. Thank you!", max_len = MAX_MESSAGE_LEN, name_text = FALSE, timeout = 0)

/mob/proc/prayer_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/raw_msg = A.answer.value
	if(!raw_msg)	return

	if(src.client)
		if(raw_msg)
			client.handle_spam_prevention(MUTE_PRAY)
			if(src.client.prefs.muted & MUTE_PRAY)
				to_chat(src, span_red("You cannot pray (muted)."))
				return

	var/icon/cross = icon('icons/obj/storage.dmi',"bible")
	var/msg = span_filter_pray(span_blue("[icon2html(cross, GLOB.admins)] <b>" + span_purple("PRAY: ") + "[key_name(src, 1)] [ADMIN_QUE(src)] [ADMIN_PP(src)] [ADMIN_VV(src)] [ADMIN_SM(src)] ([admin_jump_link(src, src)]) [ADMIN_CA(src)] [ADMIN_SC(src)] [ADMIN_SMITE(src)]:</b> [raw_msg]"))

	for(var/client/C in GLOB.admins)
		if(!check_rights_for(C, R_ADMIN|R_EVENT))
			continue
		if(C.prefs?.read_preference(/datum/preference/toggle/show_chat_prayers))
			to_chat(C, msg, type = MESSAGE_TYPE_PRAYER, confidential = TRUE)
			C << 'sound/effects/ding.ogg'
	to_chat(src, "Your prayers have been received by the gods.", confidential = TRUE)

	feedback_add_details("admin_verb","PR") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	log_prayer("[src.key]/([src.name]): [raw_msg]")

/proc/CentCom_announce(msg, mob/Sender, iamessage)
	msg = span_blue(span_bold(span_orange("[uppertext(using_map.boss_short)]M[iamessage ? " IA" : ""]:") + "[key_name(Sender, 1)] [ADMIN_PP(Sender)] [ADMIN_VV(Sender)] [ADMIN_SM(Sender)] ([admin_jump_link(Sender)]) [ADMIN_CA(Sender)] [ADMIN_BSA(Sender)] [ADMIN_CENTCOM_REPLY(Sender)]:") + " [msg]")
	for(var/client/C in GLOB.admins) // GLOB admins
		if(!check_rights_for(C, R_ADMIN|R_EVENT))
			continue
		to_chat(C,msg)
		C << 'sound/machines/signal.ogg'

/proc/Syndicate_announce(msg, mob/Sender)
	msg = span_blue(span_bold(span_crimson("ILLEGAL:") + "[key_name(Sender, 1)] [ADMIN_PP(Sender)] [ADMIN_VV(Sender)] [ADMIN_SM(Sender)] ([admin_jump_link(Sender)]) [ADMIN_CA(Sender)] [ADMIN_BSA(Sender)] [ADMIN_SYNDICATE_REPLY(Sender)]:") + " [msg]")
	for(var/client/C in GLOB.admins) // GLOB admins
		if(!check_rights_for(C, R_ADMIN|R_EVENT))
			continue
		to_chat(C,msg)
		C << 'sound/machines/signal.ogg'
