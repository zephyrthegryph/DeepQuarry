///////////
// Soulcatcher - Like a posibrain, sorta!
/datum/nifsoft/soulcatcher
	name = "Soulcatcher"
	desc = "A mind storage and processing system capable of capturing and supporting human-level minds in a small VR space."
	list_pos = NIF_SOULCATCHER
	cost = 100 //If I wanna trap people's minds and lood them, then by god I'll do so.
	wear = 0
	p_drain = 0.01

	var/setting_flags = (NIF_SC_ALLOW_EARS|NIF_SC_ALLOW_EYES|NIF_SC_BACKUPS|NIF_SC_PROJECTING)
	/// Occupants the soulcatcher creates and owns (lazy; deleted with it). Each names it back through `soulcatcher`.
	var/list/brainmobs
	var/inside_flavor = "A small completely white room with a couch, and a window to what seems to be the outside world. A small sign in the corner says 'Configure Me'."

CAPABILITIES(/datum/nifsoft/soulcatcher)
	owns_many(nameof(brainmobs))

/datum/nifsoft/soulcatcher/New()
	..()
	load_settings()


/datum/nifsoft/soulcatcher/activate()
	if((. = ..()))
		show_settings(nif().human)
		after(src, 0, PROC_REF(deactivate))

/datum/nifsoft/soulcatcher/deactivate(force = FALSE)
	if((. = ..()))
		return TRUE

/datum/nifsoft/soulcatcher/stat_text()
	return "Change Settings ([LAZYLEN(brainmobs)] minds)"

/datum/nifsoft/soulcatcher/install()
	if((. = ..()))
		//nif.set_flag(NIF_O_SCOTHERS,NIF_FLAGS_OTHER)	//Only required on install if the flag is in the default setting_flags list defined few lines above.
		if(nif()?.human)
			grant(nif().human, granted_verb(/mob/proc/nsay), src)
			grant(nif().human, granted_verb(/mob/proc/nme), src)

/datum/nifsoft/soulcatcher/uninstall()
	own_clear(src, nameof(brainmobs), OWN_DELETE)
	if((. = ..()) && nif()?.human) //Sometimes NIFs are deleted outside of a human
		revoke(nif().human, granted_verb(/mob/proc/nsay), src)
		revoke(nif().human, granted_verb(/mob/proc/nme), src)

/datum/nifsoft/soulcatcher/proc/save_settings()
	if(!nif())
		return
	nif().save_data["[list_pos]"] = inside_flavor
	return TRUE

/datum/nifsoft/soulcatcher/proc/load_settings()
	if(!nif())
		return
	var/load = nif().save_data["[list_pos]"]
	if(load)
		inside_flavor = load
	return TRUE

/datum/nifsoft/soulcatcher/proc/notify_into(message)
	var/sound = nif().good_sound

	message = " " + span_bold("Soulcatcher") + " displays, \"" + span_notice(span_nif("[message]")) + "\""

	to_chat(nif().human,
			type = MESSAGE_TYPE_NIF,
			html = span_nif(span_bold("\[[icon2html(nif().big_icon, nif().human)]NIF\]") + message))
	nif().human << sound

	for(var/mob/living/carbon/brain/caught_soul/CS as anything in brainmobs)
		to_chat(CS,
				type = MESSAGE_TYPE_NIF,
				html = span_nif(span_bold("\[[icon2html(nif().big_icon, CS.client)]NIF\]") + message))
		CS << sound

/datum/nifsoft/soulcatcher/proc/say_into(message, mob/living/sender, mob/eyeobj, whisper)
	var/sender_name = eyeobj ? eyeobj.name : sender.name

	//AR Projecting
	if(eyeobj)
		var/speak_verb = "says"
		message = span_game(span_say(span_bold("[sender_name]") + " [speak_verb], \"[message]\""))
		if(whisper)
			speak_verb = "whispers"
			eyeobj.visible_message(span_italics(message), range = 1)
		else
			eyeobj.visible_message(message)

	//Not AR Projecting
	else
		var/speak_verb = "speaks"
		message = " " + span_bold("[sender_name]") + " [speak_verb], \"[message]\""
		to_chat(nif().human,
				type = MESSAGE_TYPE_NIF,
				html = span_nif(span_bold("\[[icon2html(nif().big_icon, nif().human.client)]NIF\]") + message))
		if(whisper)
			speak_verb = "whispers"
			to_chat(sender,
					type = MESSAGE_TYPE_NIF,
					html = span_nif(span_bold("\[[icon2html(nif().big_icon, sender.client)]NIF\]") + span_italics(message)))
		else
			for(var/mob/living/carbon/brain/caught_soul/CS as anything in brainmobs)
				to_chat(CS,
						type = MESSAGE_TYPE_NIF,
						html = span_nif(span_bold("\[[icon2html(nif().big_icon, CS.client)]NIF\]") + message))

	sender.log_talk("NSAY (NIF:[nif().human.real_name]): [message]", LOG_SAY, color="#ff00c8")

/datum/nifsoft/soulcatcher/proc/emote_into(message, mob/living/sender, mob/eyeobj, whisper)
	var/sender_name = eyeobj ? eyeobj.name : sender.name

	//AR Projecting
	if(eyeobj)
		var/range = world.view
		if(whisper)
			range = 1
		eyeobj.visible_message(span_emote("[sender_name] [message]"), range = range)

	//Not AR Projecting
	else
		message = " " + span_bold("[sender_name]") + " [message]"
		to_chat(nif().human,
				type = MESSAGE_TYPE_NIF,
				html = span_nif(span_bold("\[[icon2html(nif().big_icon,nif().human.client)]NIF\]") + message))
		if(whisper)
			to_chat(sender,
					type = MESSAGE_TYPE_NIF,
					html = span_nif(span_bold("\[[icon2html(nif().big_icon,sender.client)]NIF\]") + span_italics(message)))
		else
			for(var/mob/living/carbon/brain/caught_soul/CS as anything in brainmobs)
				to_chat(CS,
						type = MESSAGE_TYPE_NIF,
						html = span_nif(span_bold("\[[icon2html(nif().big_icon,CS.client)]NIF\]") + message))

	sender.log_message("NME (NIF:[nif().human.real_name]): [message]", LOG_EMOTE, color="#ff00c8")

/datum/nifsoft/soulcatcher/proc/show_settings(mob/living/carbon/human/H)
	return soul_settings_stage(H, list())

/datum/nifsoft/soulcatcher/proc/soul_settings_stage(mob/living/carbon/human/H, list/soul_answers, mob/living/carbon/brain/caught_soul/selected_soul)
	var/settings_list = list(
	"Catching You \[[setting_flags & NIF_SC_CATCHING_ME ? "Enabled" : "Disabled"]\]" = NIF_SC_CATCHING_ME,
	"Catching Prey \[[setting_flags & NIF_SC_CATCHING_OTHERS ? "Enabled" : "Disabled"]\]" = NIF_SC_CATCHING_OTHERS,
	"Ext. Hearing \[[setting_flags & NIF_SC_ALLOW_EARS ? "Enabled" : "Disabled"]\]" = NIF_SC_ALLOW_EARS,
	"Ext. Vision \[[setting_flags & NIF_SC_ALLOW_EYES ? "Enabled" : "Disabled"]\]" = NIF_SC_ALLOW_EYES,
	"Mind Backups \[[setting_flags & NIF_SC_BACKUPS ? "Enabled" : "Disabled"]\]" = NIF_SC_BACKUPS,
	"AR Projecting \[[setting_flags & NIF_SC_PROJECTING ? "Enabled" : "Disabled"]\]" = NIF_SC_PROJECTING,
	"Design Inside",
	"Erase Contents")
	if(!("k150" in soul_answers))
		open_request(src, /datum/prompt/choice/soulcatcher_settings, PROC_REF(soul_settings_answered), answerer = nif().human, settings_operator = H, selected_soul = selected_soul, soul_answers = soul_answers, soul_key = "k150", question = "Select a setting to modify:", title = "Soulcatcher NIFSoft", choices = settings_list)
		return
	var/choice = soul_answers["k150"]
	if(isnull(choice))
		return
	if(choice in settings_list)
		switch(choice)

			if("Design Inside")
				if(!("k155" in soul_answers))
					open_request(src, /datum/prompt/text/soulcatcher_settings, PROC_REF(soul_settings_answered), answerer = nif().human, settings_operator = H, selected_soul = selected_soul, soul_answers = soul_answers, soul_key = "k155", question = "Type what the prey sees after being 'caught'. This will be printed after an intro ending with: \"Around you, you see...\" to the prey. If you already have prey, this will be printed to them after \"Your surroundings change to...\". Limit 2048 char.", title = "VR Environment", default = html_decode(inside_flavor), max_len = MAX_MESSAGE_LEN*2, multiline = TRUE)
					return
				var/new_flavor = soul_answers["k155"]
				if(isnull(new_flavor))
					return
				inside_flavor = new_flavor
				nif().notify("Updating VR environment...")
				for(var/mob/living/carbon/brain/caught_soul/CS as anything in brainmobs)
					to_chat(CS,span_notice("Your surroundings change to...") + "\n[inside_flavor]")
				save_settings()
				return TRUE

			if("Erase Contents")
				if(!("k164" in soul_answers))
					open_request(src, /datum/prompt/choice/soulcatcher_settings, PROC_REF(soul_settings_answered), answerer = nif().human, settings_operator = H, selected_soul = selected_soul, soul_answers = soul_answers, soul_key = "k164", question = "Select a mind to delete:", title = "Erase Mind", choices = brainmobs)
					return
				var/mob/living/carbon/brain/caught_soul/brainpick = selected_soul
				if(isnull(brainpick))
					return

				if(!("k166" in soul_answers))
					open_request(src, /datum/prompt/choice/soulcatcher_settings, PROC_REF(soul_settings_answered), answerer = nif().human, settings_operator = H, selected_soul = selected_soul, soul_answers = soul_answers, soul_key = "k166", question = "Are you SURE you want to erase \"[brainpick]\"?", title = "Erase Mind", choices = list("CANCEL","DELETE"), buttons = TRUE)
					return
				var/warning = soul_answers["k166"]
				if(isnull(warning))
					return
				if(warning == "DELETE")
					own_remove(src, nameof(brainmobs), brainpick)
				return TRUE

			//Must just be a flag without special handling then.
			else
				var/flag = settings_list[choice]
				return toggle_setting(flag)

/datum/nifsoft/soulcatcher/proc/toggle_setting(flag)
	setting_flags ^= flag

	var/notify_message
	//Special treatment
	switch(flag)
		if(NIF_SC_BACKUPS)
			if(setting_flags & NIF_SC_BACKUPS)
				notify_message = "Mind backup system enabled."
			else
				notify_message = "Mind backup system disabled."

		if(NIF_SC_CATCHING_ME)
			if(setting_flags & NIF_SC_CATCHING_ME)
				nif().set_flag(NIF_O_SCMYSELF,NIF_FLAGS_OTHER)
			else
				nif().clear_flag(NIF_O_SCMYSELF,NIF_FLAGS_OTHER)
		if(NIF_SC_CATCHING_OTHERS)
			if(setting_flags & NIF_SC_CATCHING_OTHERS)
				nif().set_flag(NIF_O_SCOTHERS,NIF_FLAGS_OTHER)
			else
				nif().clear_flag(NIF_O_SCOTHERS,NIF_FLAGS_OTHER)
		if(NIF_SC_ALLOW_EARS)
			if(setting_flags & NIF_SC_ALLOW_EARS)
				for(var/mob/living/carbon/brain/caught_soul/brainmob as anything in brainmobs)
					brainmob.ext_deaf = FALSE
				notify_message = "External audio input enabled."
			else
				for(var/mob/living/carbon/brain/caught_soul/brainmob as anything in brainmobs)
					brainmob.ext_deaf = TRUE
				notify_message = "External audio input disabled."
		if(NIF_SC_ALLOW_EYES)
			if(setting_flags & NIF_SC_ALLOW_EYES)
				for(var/mob/living/carbon/brain/caught_soul/brainmob as anything in brainmobs)
					brainmob.ext_blind = FALSE
				notify_message = "External video input enabled."
			else
				for(var/mob/living/carbon/brain/caught_soul/brainmob as anything in brainmobs)
					brainmob.ext_blind = TRUE
				notify_message = "External video input disabled."

	if(notify_message)
		notify_into(notify_message)

	return TRUE

//Complex version for catching in-round characters
/datum/nifsoft/soulcatcher/proc/catch_mob(mob/M)
	if(!M.mind)	return
	if(!(M.soulcatcher_pref_flags & SOULCATCHER_ALLOW_CAPTURE) && !isobserver(M)) return // Bypass pref check for observer join

	//Create a new brain mob
	var/mob/living/carbon/brain/caught_soul/brainmob = new(nif())
	rel_set(brainmob, nameof(brainmob.nif), nif())
	rel_set(brainmob, nameof(brainmob.soulcatcher), src)
	rel_set(brainmob, nameof(brainmob.container), src)
	brainmob.status_set(EFFECT_MUTED, 0)
	brainmob.add_language(LANGUAGE_GALCOM)
	rel_add(src, nameof(brainmobs), brainmob)

	//Put the mind and player into the mob
	transfer_mind(M.mind, brainmob, "caught in [nif()]'s soulcatcher") // identity (DNA, OOC notes) comes by reference
	brainmob.name = brainmob.mind.name
	brainmob.real_name = brainmob.mind.name

	//If we caught our owner, special settings.
	if(M == nif().human)
		brainmob.ext_deaf = FALSE
		brainmob.ext_blind = FALSE
		brainmob.parent_mob = TRUE

	//If they have these values, apply them
	if(ishuman(M))
		SStranscore.m_backup(brainmob.mind,0) //It does ONE, so medical will hear about it.

	//Else maybe they're a joining ghost
	else if(isobserver(M))
		brainmob.transient = TRUE
		spent(M) //Bye ghost

	//Give them a flavortext message
	var/message = span_notice("Your vision fades in a haze of static, before returning.") + "\n\
					Around you, you see...\n\
					[inside_flavor]"

	to_chat(brainmob,message)

	//Reminder on how this works to host
	if(LAZYLEN(brainmobs) == 1) //Only spam this on the first one
		to_chat(nif().human,span_notice("Your occupant's messages/actions can only be seen by you, and you can \
		send messages that only they can hear/see by using the NSay and NMe verbs (or the *nsay and *nme emotes)."))

	//Announce to host and other minds
	notify_into("New mind loaded: [brainmob.name]")
	return TRUE

////////////////
//The caught mob
/mob/living/carbon/brain/caught_soul
	name = "recorded mind"
	desc = "A mind recorded and being played on digital hardware."
	use_me = 1
	var/ext_deaf = FALSE		//Forbidden from 'ear' access on host
	var/ext_blind = FALSE		//Forbidden from 'eye' access on host
	var/parent_mob = FALSE		//If we've captured our owner
	var/transient = FALSE		//Someone who ghosted into the NIF
	var/client_missing = 0		//How long the client has been missing
	universal_understand = TRUE

	var/tmp/obj/item/nif/nif
	var/tmp/datum/nifsoft/soulcatcher/soulcatcher
	var/identifying_gender

/mob/living/carbon/brain/caught_soul/Login()
	..()
	plane_holder.set_vis(VIS_AUGMENTED, TRUE)
	plane_holder.set_vis(VIS_SOULCATCHER, TRUE)
	identifying_gender = client.prefs.read_preference(/datum/preference/choiced/gender/identifying)

// the soulcatcher is told the mind unloaded.
/mob/living/carbon/brain/caught_soul/on_destroy(force)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(soulcatcher())
		soulcatcher().notify_into("Mind unloaded: [name]")
	if(eyeobj)
		reenter_soulcatcher()
	..()

/mob/living/carbon/brain/caught_soul/life_type_pre_due()
	return TRUE

/mob/living/carbon/brain/caught_soul/life_type_pre(datum/seq_frame/life/F)
	if(!src.mind || !src.key)
		spent(src)
		return F.abort()
	return ..()

/mob/living/carbon/brain/caught_soul/life_type_post_due()
	return TRUE

/mob/living/carbon/brain/caught_soul/life_type_post(datum/seq_frame/life/F)
	..()

	if(!src.parent_mob && !src.transient &&(src.life_tick % 150 == 0) && src.soulcatcher()?.setting_flags & NIF_SC_BACKUPS)
		SStranscore.m_backup(src.mind,0) //Passed 0 means "Don't touch the nif fields on the mind record"

	src.life_tick++

	if(!src.client)
		if(++src.client_missing == 300)
			spent(src)
		return
	else
		src.client_missing = 0

	if(src.parent_mob) return

	//If they're blinded
	if(src.soulcatcher()) // needs it's own handling to allow vore_fx
		if(src.ext_blind)
			src.status_set(EFFECT_BLINDED, 5)
			src.client.screen.Remove(GLOB.global_hud.whitense)
			src.overlay_fullscreen("blind", /atom/movable/screen/fullscreen/blind)
		else
			src.status_set(EFFECT_BLINDED, 0)
			src.clear_fullscreens()
			src.client.screen.Add(GLOB.global_hud.whitense)

	//If they're deaf
	if(src.ext_deaf)
		src.status_set(EFFECT_DEAFENED, 5)
		src.deaf_loop.start(skip_start_sound = TRUE) // CHOMPEnable: Ear Ringing/Deafness
	else
		src.status_set(EFFECT_DEAFENED, 0)
		src.deaf_loop.stop() // CHOMPEnable: Ear Ringing/Deafness

/mob/living/carbon/brain/caught_soul/hear_say()
	if(ext_deaf || !client)
		return FALSE
	.=..()

/mob/living/carbon/brain/caught_soul/show_message(msg, type, alt, alt_type)
	if(ext_blind || !client)
		return FALSE
	..()

/mob/living/carbon/brain/caught_soul/face_atom(atom/A)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(eyeobj)
		return eyeobj.face_atom(A)
	else
		return ..(A)

/mob/living/carbon/brain/caught_soul/set_dir(direction)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(eyeobj)
		return eyeobj.set_dir(direction)
	else
		return ..(direction)

/mob/living/carbon/brain/caught_soul/me_verb_subtle(message as message)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(has_status(EFFECT_MUTED)) return FALSE
	soulcatcher().emote_into(message,src,eyeobj,TRUE)

/mob/living/carbon/brain/caught_soul/whisper(message as text)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(has_status(EFFECT_MUTED)) return FALSE
	soulcatcher().say_into(message,src,eyeobj,TRUE)

/mob/living/carbon/brain/caught_soul/say(message, datum/language/speaking = null, whispering = 0)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(has_status(EFFECT_MUTED)) return FALSE
	soulcatcher().say_into(message,src,eyeobj)

/mob/living/carbon/brain/caught_soul/emote(act,m_type=1,message = null)
	if(has_status(EFFECT_MUTED)) return FALSE
	if (act == "me")
		if(has_status(EFFECT_MUTED))
			return
		if (src.client)
			if (client.prefs.muted & MUTE_IC)
				to_chat(src, span_warning("You cannot send IC messages (muted)."))
				return
		if (stat)
			return
		if(!(message))
			return
		return custom_emote(m_type, message)
	else
		return FALSE

/mob/living/carbon/brain/caught_soul/custom_emote(m_type, message)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(has_status(EFFECT_MUTED)) return FALSE
	soulcatcher().emote_into(message,src,eyeobj)

/mob/living/carbon/brain/caught_soul/resist()
	set name = "Resist"
	set category = VERB_CAT_IC_GAME

	to_chat(src,span_warning("There's no way out! You're stuck in VR."))

///////////////////
//A projected AR soul thing
/mob/observer/eye/ar_soul
	invisibility = INVISIBILITY_NONE
	plane = PLANE_AUGMENTED
	icon = 'icons/obj/machines/ar_elements.dmi'
	icon_state = "beacon"
	var/tmp/mob/living/parent_human

CAPABILITIES(/mob/observer/eye/ar_soul)
	param(nameof(parent_human), pos = 1)

// ALLOW(init/INSTANCE_STATE): an AR soul looks through its brain mob, follows its owner's body and dresses as its owner's character
/mob/observer/eye/ar_soul/Initialize(mapload)
	. = ..()
	var/mob/brainmob = loc
	if(!istype(brainmob) || !brainmob.client)
		return INITIALIZE_HINT_QDEL

	brainmob.take_eye(src)			//Look through us
	sight |= SEE_SELF				//Always see yourself

	name = "[brainmob.name] (AR)"	//Set the name
	real_name = brainmob.real_name	//And the OTHER name

	forceMove(get_turf(parent_human()))
	dq_add_recursive_move(parent_human())
	global.observe(parent_human(), /datum/notice/movable_attempted_move, src, then(PROC_REF(human_moved)))

	//Time to play dressup
	if(brainmob.client.prefs)
		var/mob/living/carbon/human/dummy/mannequin = get_mannequin(brainmob.client.ckey)
		mannequin.delete_inventory(TRUE)
		brainmob.client.prefs.dress_preview_mob(mannequin)
		mannequin.regenerate_icons()

		var/icon/new_icon = getHologramIcon(getCompoundIcon(mannequin))
		icon = new_icon

/mob/observer/eye/ar_soul/EyeMove(n, direct)
	var/initial = initial(sprint)
	var/max_sprint = 50

	if(cooldown && cooldown < world.timeofday)
		sprint = initial

	for(var/i = 0; i < max(sprint, initial); i += 20)
		var/turf/stepn = get_turf(get_step(src, direct))
		if(stepn)
			set_dir(direct)
			if(can_see(parent_human(), stepn))
				forceMove(stepn)

	cooldown = world.timeofday + 5
	if(acceleration)
		sprint = min(sprint + 0.5, max_sprint)
	else
		sprint = initial
	return 1

/mob/observer/eye/ar_soul/proc/human_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	if(!can_see(parent_human(),src))
		forceMove(get_turf(parent_human()))

///////////////////
//The catching hook
/mob/living/proc/soulcatcher_on_mob_death()
	if(!mind)
		return

	if(isbelly(loc)) //Died in someone
		var/obj/belly/B = loc
		var/mob/living/owner = B.owner
		var/obj/soulgem/gem = owner.soulgem
		if(gem && gem.flag_check(SOULGEM_ACTIVE | NIF_SC_CATCHING_OTHERS, TRUE))
			var/to_use_custom_name = null
			if(isanimal(src))
				to_use_custom_name = name
			gem.catch_mob(src, to_use_custom_name)
			return
		var/mob/living/carbon/human/HP = B.owner
		var/mob/living/carbon/human/H = src
		if(!istype(H))
			return
		if(istype(HP) && HP.nif && HP.nif.flag_check(NIF_O_SCOTHERS,NIF_FLAGS_OTHER))
			var/datum/nifsoft/soulcatcher/SC = HP.nif.imp_check(NIF_SOULCATCHER)
			if(istype(SC))
				SC.catch_mob(H)
	else
		var/obj/soulgem/gem = soulgem
		if(gem && gem.flag_check(SOULGEM_ACTIVE | NIF_SC_CATCHING_ME, TRUE))
			var/to_use_custom_name = null
			if(isanimal(src))
				to_use_custom_name = name
			gem.catch_mob(src, to_use_custom_name)
			return
		var/mob/living/carbon/human/H = src
		if(!istype(H))
			return
		if(H.nif && H.nif.flag_check(NIF_O_SCMYSELF,NIF_FLAGS_OTHER)) //They are caught in their own NIF
			var/datum/nifsoft/soulcatcher/SC = H.nif.imp_check(NIF_SOULCATCHER)
			if(istype(SC))
				SC.catch_mob(H)

///////////////////
//Verbs for humans
/mob/proc/nsay(message as text)
	set name = "NSay"
	set desc = "Speak into your NIF's Soulcatcher."
	set category = VERB_CAT_IC_NIF

	src.nsay_act(message)

/mob/proc/nsay_act(message as text)
	to_chat(src, span_warning("You must be a humanoid with a NIF implanted to use that."))

/mob/living/carbon/human/nsay_act(message as text)
	return nif_say_stage(message)

/mob/living/carbon/human/proc/nif_say_stage(message, prompted = FALSE)
	if(stat != CONSCIOUS)
		to_chat(src,span_warning("You can't use NSay while unconscious."))
		return
	if(!nif)
		to_chat(src,span_warning("You can't use NSay without a NIF."))
		return
	var/datum/nifsoft/soulcatcher/SC = nif.imp_check(NIF_SOULCATCHER)
	if(!SC)
		to_chat(src,span_warning("You need the Soulcatcher software to use NSay."))
		return
	if(!LAZYLEN(SC.brainmobs))
		to_chat(src,span_warning("You need a loaded mind to use NSay."))
		return
	if(!message)
		if(!prompted)
			open_request(src, /datum/prompt/text/soulcatcher_speech, PROC_REF(nif_say_answered), answerer = src, question = "Type a message to say.", title = "Speak into Soulcatcher", encode = FALSE)
			return ITEM_INTERACT_BLOCKING
	if(message)
		var/sane_message = sanitize(message)
		SC.say_into(sane_message,src)

/mob/proc/nme(message as message)
	set name = "NMe"
	set desc = "Emote into your NIF's Soulcatcher."
	set category = VERB_CAT_IC_NIF

	src.nme_act(message)

/mob/proc/nme_act(message as message)
	to_chat(src, span_warning("You must be a humanoid with a NIF implanted to use that."))

/mob/living/carbon/human/nme_act(message as message)
	return nif_emote_stage(message)

/mob/living/carbon/human/proc/nif_emote_stage(message, prompted = FALSE)
	if(stat != CONSCIOUS)
		to_chat(src,span_warning("You can't use NMe while unconscious."))
		return
	if(!nif)
		to_chat(src,span_warning("You can't use NMe without a NIF."))
		return
	var/datum/nifsoft/soulcatcher/SC = nif.imp_check(NIF_SOULCATCHER)
	if(!SC)
		to_chat(src,span_warning("You need the Soulcatcher software to use NMe."))
		return
	if(!LAZYLEN(SC.brainmobs))
		to_chat(src,span_warning("You need a loaded mind to use NMe."))
		return

	if(!message)
		if(!prompted)
			open_request(src, /datum/prompt/text/soulcatcher_speech, PROC_REF(nif_emote_answered), answerer = src, question = "Type an action to perform.", title = "Emote into Soulcatcher", encode = FALSE)
			return ITEM_INTERACT_BLOCKING
	if(message)
		var/sane_message = sanitize(message)
		SC.emote_into(sane_message,src)

///////////////////
//Verbs for soulbrains
/mob/living/carbon/brain/caught_soul/verb/ar_project()
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set name = "AR/SR Project"
	set desc = "Project your form into Augmented Reality for those around your predator with the appearance of your loaded character."
	set category = VERB_CAT_SOULCATCHER

	if(eyeobj)
		to_chat(src,span_warning("You're already projecting in AR!"))
		return

	if(!(soulcatcher().setting_flags & NIF_SC_PROJECTING))
		to_chat(src,span_warning("Projecting from this NIF has been disabled!"))
		return

	if(!client || !client.prefs)
		return //Um...

	new /mob/observer/eye/ar_soul(src, nif().human) // takes itself as our eye
	soulcatcher().notify_into("[src] now AR projecting.")

/mob/living/carbon/brain/caught_soul/verb/jump_to_owner()
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set name = "Jump to Owner"
	set desc = "Jump your projection back to the owner of the soulcatcher you're inside."
	set category = VERB_CAT_SOULCATCHER

	if(!eyeobj)
		to_chat(src,span_warning("You're not projecting into AR!"))
		return

	eyeobj.forceMove(get_turf(nif()))

/mob/living/carbon/brain/caught_soul/verb/reenter_soulcatcher()
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set name = "Re-enter Soulcatcher"
	set desc = "Leave AR projection and drop back into the soulcatcher."
	set category = VERB_CAT_SOULCATCHER

	if(!eyeobj)
		to_chat(src,span_warning("You're not projecting into AR!"))
		return

	QDEL_NULL(eyeobj)
	soulcatcher().notify_into("[src] ended AR projection.")

/mob/living/carbon/brain/caught_soul/verb/nsay_brain(message as text)
	set name = "NSay"
	set desc = "Speak into the NIF's Soulcatcher (circumventing AR speaking)."
	set category = VERB_CAT_SOULCATCHER

	return nif_brain_say_stage(message)

/mob/living/carbon/brain/caught_soul/proc/nif_brain_say_stage(message, prompted = FALSE)
	if(!message)
		if(!prompted)
			open_request(src, /datum/prompt/text/soulcatcher_speech, PROC_REF(nif_brain_say_answered), answerer = src, question = "Type a message to say.", title = "Speak into Soulcatcher", encode = FALSE)
			return
	if(message)
		var/sane_message = sanitize(message)
		soulcatcher().say_into(sane_message,src,null)

/mob/living/carbon/brain/caught_soul/verb/nme_brain(message as message)
	set name = "NMe"
	set desc = "Emote into the NIF's Soulcatcher (circumventing AR speaking)."
	set category = VERB_CAT_SOULCATCHER

	return nif_brain_emote_stage(message)

/mob/living/carbon/brain/caught_soul/proc/nif_brain_emote_stage(message, prompted = FALSE)
	if(!message)
		if(!prompted)
			open_request(src, /datum/prompt/text/soulcatcher_speech, PROC_REF(nif_brain_emote_answered), answerer = src, question = "Type an action to perform.", title = "Emote into Soulcatcher", encode = FALSE)
			return
	if(message)
		var/sane_message = sanitize(message)
		soulcatcher().emote_into(sane_message,src,null)

/// LC-refs: the soulcatcher this refers to -- a relation view: null once it is deleted.
/mob/living/carbon/brain/caught_soul/proc/soulcatcher() as /datum/nifsoft/soulcatcher
	return soulcatcher

/// LC-refs: the parent_human this refers to -- a relation view: null once it is deleted.
/mob/observer/eye/ar_soul/proc/parent_human() as /mob/living
	return parent_human

/// LC-refs: the nif this refers to -- a relation view: null once it is deleted.
/mob/living/carbon/brain/caught_soul/proc/nif() as /obj/item/nif
	return nif

/mob/living/carbon/human/proc/nif_say_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = nif_say_apply(A)
	SStgui.update_uis(src)

/mob/living/carbon/human/proc/nif_say_apply(datum/act/request/A)
	var/datum/prompt/text/soulcatcher_speech/ask = A.answer
	return nif_say_stage(ask.value, TRUE)

/mob/living/carbon/human/proc/nif_emote_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = nif_emote_apply(A)
	SStgui.update_uis(src)

/mob/living/carbon/human/proc/nif_emote_apply(datum/act/request/A)
	var/datum/prompt/text/soulcatcher_speech/ask = A.answer
	return nif_emote_stage(ask.value, TRUE)

/mob/living/carbon/brain/caught_soul/proc/nif_brain_say_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = nif_brain_say_apply(A)
	SStgui.update_uis(src)

/mob/living/carbon/brain/caught_soul/proc/nif_brain_say_apply(datum/act/request/A)
	var/datum/prompt/text/soulcatcher_speech/ask = A.answer
	return nif_brain_say_stage(ask.value, TRUE)

/mob/living/carbon/brain/caught_soul/proc/nif_brain_emote_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = nif_brain_emote_apply(A)
	SStgui.update_uis(src)

/mob/living/carbon/brain/caught_soul/proc/nif_brain_emote_apply(datum/act/request/A)
	var/datum/prompt/text/soulcatcher_speech/ask = A.answer
	return nif_brain_emote_stage(ask.value, TRUE)

/datum/prompt/text/soulcatcher_speech
	timeout = 0

/datum/nifsoft/soulcatcher/proc/soul_settings_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = soul_settings_apply(A)
	SStgui.update_uis(src)

/datum/nifsoft/soulcatcher/proc/soul_settings_apply(datum/act/request/A)
	if(istype(A.answer, /datum/prompt/choice/soulcatcher_settings))
		var/datum/prompt/choice/soulcatcher_settings/ask = A.answer
		if(ask.soul_key == "k164")
			var/mob/living/carbon/brain/caught_soul/chosen = ask.value
			rel_set(ask, nameof(ask.selected_soul), chosen)
			ask.soul_answers[ask.soul_key] = TRUE
		else
			ask.soul_answers[ask.soul_key] = ask.value
		return soul_settings_stage(ask.settings_operator, ask.soul_answers, ask.selected_soul)
	if(istype(A.answer, /datum/prompt/text/soulcatcher_settings))
		var/datum/prompt/text/soulcatcher_settings/ask = A.answer
		ask.soul_answers[ask.soul_key] = ask.value
		return soul_settings_stage(ask.settings_operator, ask.soul_answers, ask.selected_soul)

/datum/prompt/text/soulcatcher_settings
	timeout = 0
	var/mob/living/carbon/human/settings_operator
	var/settings_operator_expected = FALSE
	var/mob/living/carbon/brain/caught_soul/selected_soul
	var/list/soul_answers
	var/soul_key

CAPABILITIES(/datum/prompt/text/soulcatcher_settings)
	ref_one(nameof(settings_operator), /mob/living/carbon/human)
	ref_one(nameof(selected_soul), /mob/living/carbon/brain/caught_soul)

/datum/prompt/text/soulcatcher_settings/prepare(datum/act/A)
	. = ..()
	var/mob/living/carbon/human/captured_operator = settings_operator
	settings_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(settings_operator))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(settings_operator), captured_operator)
	var/mob/living/carbon/brain/caught_soul/captured_soul = selected_soul
	rel_clear(src, nameof(selected_soul))
	if(captured_soul && !QDELETED(captured_soul))
		rel_set(src, nameof(selected_soul), captured_soul)

/datum/prompt/text/soulcatcher_settings/recheck_extra()
	if(settings_operator_expected && QDELETED(settings_operator))
		return "gone"

/datum/prompt/choice/soulcatcher_settings
	timeout = 0
	var/mob/living/carbon/human/settings_operator
	var/settings_operator_expected = FALSE
	var/mob/living/carbon/brain/caught_soul/selected_soul
	var/list/soul_answers
	var/soul_key

CAPABILITIES(/datum/prompt/choice/soulcatcher_settings)
	ref_one(nameof(settings_operator), /mob/living/carbon/human)
	ref_one(nameof(selected_soul), /mob/living/carbon/brain/caught_soul)

/datum/prompt/choice/soulcatcher_settings/prepare(datum/act/A)
	. = ..()
	var/mob/living/carbon/human/captured_operator = settings_operator
	settings_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(settings_operator))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(settings_operator), captured_operator)
	var/mob/living/carbon/brain/caught_soul/captured_soul = selected_soul
	rel_clear(src, nameof(selected_soul))
	if(captured_soul && !QDELETED(captured_soul))
		rel_set(src, nameof(selected_soul), captured_soul)

/datum/prompt/choice/soulcatcher_settings/recheck_extra()
	if(settings_operator_expected && QDELETED(settings_operator))
		return "gone"
	if(!isnull(value) && soul_key == "k164")
		var/mob/living/carbon/brain/caught_soul/chosen = value
		if(!istype(chosen) || QDELETED(chosen))
			return "gone"
