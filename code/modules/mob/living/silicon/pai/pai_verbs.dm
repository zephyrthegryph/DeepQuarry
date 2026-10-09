/// Change currently viewed camera
/mob/living/silicon/pai/proc/switchCamera(obj/machinery/camera/C)
	if (!C)
		src.reset_perspective()
		return 0
	if (stat == 2 || !C.status || !(src.network in C.network)) return 0

	// ok, we're alive, camera is good and in our network...
	rel_set(src, nameof(current), C)
	src.begin_remote_view(/datum/remote_view, C, null, /datum/remote_view_config/camera_standard)
	return 1

/mob/living/silicon/pai/cancel_camera()
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set name = "Cancel Camera View"
	reset_perspective()

/mob/living/silicon/pai/reset_perspective(atom/new_eye)
	. = ..()
	rel_clear(src, nameof(current))

/mob/living/silicon/pai/verb/reset_record_view()
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set name = "Reset Records Software"

	rel_clear(src, nameof(securityActive1))
	rel_clear(src, nameof(securityActive2))
	security_cannotfind = 0
	rel_clear(src, nameof(medicalActive1))
	rel_clear(src, nameof(medicalActive2))
	medical_cannotfind = 0
	SStgui.update_uis(src)
	to_chat(src, span_notice("You reset your record-viewing software."))

/mob/living/silicon/pai/proc/choose_verbs()
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set name = "Choose Speech Verbs"

	open_request(src, /datum/prompt/choice, PROC_REF(speech_verbs_chosen), answerer = src, title = "Theme Choice", question = "What theme would you like to use for your speech verbs?", choices = GLOB.possible_say_verbs, timeout = 0)

/mob/living/silicon/pai/proc/speech_verbs_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/list/sayverbs = GLOB.possible_say_verbs[A.answer.value]
	speak_statement = sayverbs[1]
	speak_exclamation = sayverbs[(sayverbs.len>1 ? 2 : sayverbs.len)]
	speak_query = sayverbs[(sayverbs.len>2 ? 3 : sayverbs.len)]

/mob/living/silicon/pai/verb/allowmodification()
	set name = "Change Access Modifcation Permission"
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set desc = "Allows people to modify your access or block people from modifying your access."

	if(idaccessible == 0)
		set_idaccessible(1)
		act_message(src, null, MSG_SELF(span_notice("You allow access modifications.")), MSG_OTHERS(span_notice("%U% clicks as their access modification slot opens.")), runemessage = "click")
	else
		set_idaccessible(0)
		act_message(src, null, MSG_SELF(span_notice("You block access modfications.")), MSG_OTHERS(span_notice("%U% clicks as their access modification slot closes.")), runemessage = "click")

/mob/living/silicon/pai/verb/toggle_gender_identity_vr()
	set name = "Set Gender Identity"
	set desc = "Sets the pronouns when examined and performing an emote."
	set category = VERB_CAT_IC_SETTINGS
	open_request(src, /datum/prompt/choice, PROC_REF(pai_gender_chosen), answerer = src, title = "Set Gender Identity", question = "Please select a gender Identity:", choices = list(FEMALE, MALE, NEUTER, PLURAL, HERM), timeout = 0)
	return 1

/mob/living/silicon/pai/proc/pai_gender_chosen(datum/act/request/A)
	if(!A.answer)
		return
	gender = A.answer.value

/mob/living/silicon/pai/verb/pai_hide()
	set name = "Hide"
	set desc = "Allows to hide beneath tables or certain items. Toggled on or off."
	set category = VERB_CAT_ABILITIES_PAI

	hide()
	set_hide_glow(!!(status_flags & HIDING))

/mob/living/silicon/pai/verb/screen_message(message as text|null)
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set name = "Screen Message"
	set desc = "Allows you to display a message on your screen. This will show up in the chat of anyone who is holding your card."

	if (src.client)
		if(client.prefs.muted & MUTE_IC)
			to_chat(src, span_warning("You cannot speak in IC (muted)."))
			return
	if(loc != card)
		to_chat(src, span_warning("Your message won't be visible while unfolded!"))
	if (!message)
		open_request(src, /datum/prompt/text, PROC_REF(screen_message_entered), answerer = src, title = "Screen Message", question = "Enter text you would like to show on your screen.", encode = FALSE, timeout = 0)
		return
	show_screen_message(message)

/mob/living/silicon/pai/proc/screen_message_entered(datum/act/request/A)
	if(!A.answer)
		return
	show_screen_message(A.answer.value)

/mob/living/silicon/pai/proc/show_screen_message(message)
	message = sanitize_or_reflect(message,src)
	if (!message)
		return
	message = capitalize(message)
	if (stat == DEAD)
		return
	card.screen_msg = message
	var/logmsg = "(CARD SCREEN)[message]"
	log_talk(logmsg, LOG_SAY)
	to_chat(src, span_filter_say(span_cult("You print a message to your screen, \"[message]\"")))
	if(isliving(card.loc))
		var/mob/living/L = card.loc
		if(L.client)
			to_chat(L, span_filter_say(span_cult("[src.name]'s screen prints, \"[message]\"")))
		else return
	else if(isbelly(card.loc))
		var/obj/belly/b = card.loc
		if(b.owner.client)
			to_chat(b.owner, span_filter_say(span_cult("[src.name]'s screen prints, \"[message]\"")))
		else return
	else if(istype(card.loc, /obj/item/pda))
		var/obj/item/pda/p = card.loc
		if(isliving(p.loc))
			var/mob/living/L = p.loc
			if(L.client)
				to_chat(L, span_filter_say(span_cult("[src.name]'s screen prints, \"[message]\"")))
			else return
		else if(isbelly(p.loc))
			var/obj/belly/b = card.loc
			if(b.owner.client)
				to_chat(b.owner, span_filter_say(span_cult("[src.name]'s screen prints, \"[message]\"")))
			else return
		else return
	else return
	to_chat(src, span_notice("Your message was relayed."))
	for (var/mob/G in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if (isnewplayer(G))
			continue
		else if(isobserver(G) && G.client?.prefs?.read_preference(/datum/preference/toggle/ghost_ears))
			if((client?.prefs?.read_preference(/datum/preference/toggle/whisubtle_vis) || check_rights_for(G.client, R_HOLDER)) && \
			G.client?.prefs?.read_preference(/datum/preference/toggle/ghost_see_whisubtle))
				to_chat(G, span_filter_say(span_cult("[src.name]'s screen prints, \"[message]\"")))

/mob/living/silicon/pai/proc/pai_nom(mob/living/T in oview(1))
	set name = "pAI Nom"
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set desc = "Allows you to eat someone while unfolded. Can't be used while in card form."

	if (stat != CONSCIOUS)
		return
	return feed_grabbed_to_self(src,T)

/mob/living/silicon/pai/verb/toggle_eyeglow()
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set name = "Toggle Eye Glow"

	if(!SSpai.chassis_data(chassis_name).has_eye_sprites)
		to_chat(src, span_filter_notice("Your selected chassis cannot modify its eye glow!"))
		return

	if(eye_glow && !hide_glow)
		set_eye_glow(FALSE)
	else
		set_eye_glow(TRUE)
		set_hide_glow(FALSE)

/mob/living/silicon/pai/verb/pick_eye_color()
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set name = "Pick Eye Color"

	if(!SSpai.chassis_data(chassis_name).has_eye_sprites)
		to_chat(src, span_warning("Your selected chassis eye color can not be modified. The color you pick will only apply to supporting chassis and your card screen."))
		return

	open_request(src, /datum/prompt/color, PROC_REF(pai_eye_color_chosen), answerer = src, title = "Eye Color", question = "Choose your character's eye color:", timeout = 0)

/mob/living/silicon/pai/proc/pai_eye_color_chosen(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value)
		set_eye_color(A.answer.value)
		card.setEmotion(card.current_emotion)

/mob/living/silicon/pai/proc/hug(mob/living/silicon/pai/H, mob/living/target)

	var/t_him = "them"
	if(ishuman(target))
		var/mob/living/carbon/human/T = target
		switch(T.identifying_gender)
			if(MALE)
				t_him = "him"
			if(FEMALE)
				t_him = "her"
			if(NEUTER)
				t_him = "it"
			if(HERM)
				t_him = "hir"
			else
				t_him = "them"
	else
		switch(target.gender)
			if(MALE)
				t_him = "him"
			if(FEMALE)
				t_him = "her"
			if(NEUTER)
				t_him = "it"
			if(HERM)
				t_him = "hir"
			else
				t_him = "them"

	if(H.zone_sel.selecting == BP_HEAD)
		act_message(H, target, MSG_SELF(span_notice("You pat %T% on the head.")), MSG_OTHERS(span_notice("%U% pats %T% on the head.")))
	else if(H.zone_sel.selecting == BP_R_HAND || H.zone_sel.selecting == BP_L_HAND)
		act_message(H, target, MSG_SELF(span_notice("You shake %T%'s hand.")), MSG_OTHERS(span_notice("%U% shakes %T%'s hand.")))
	else if(H.zone_sel.selecting == "mouth")
		act_message(H, target, MSG_SELF(span_notice("You boop %T% on the nose.")), MSG_OTHERS(span_notice("%U% boops %T%'s nose.")))
	else
		act_message(H, target, MSG_SELF(span_notice("You hug %T% to make [t_him] feel better!")), \
			MSG_OTHERS(span_notice("%U% hugs %T% to make [t_him] feel better!")))
	play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
