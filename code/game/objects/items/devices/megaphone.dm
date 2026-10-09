/obj/item/megaphone
	name = "megaphone"
	desc = "A device used to project your voice. Loudly."
	icon = 'icons/obj/device.dmi'
	icon_state = "megaphone"
	w_class = ITEMSIZE_SMALL

	var/spamcheck = 0
	var/emagged = 0
	var/insults = 0
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

TYPE_TABLE_DECLARE(/obj/item/megaphone, megaphone_insults, list("FUCK EVERYONE!", "I'M A TERRORIST!", "ALL SECURITY TO SHOOT ME ON SIGHT!", "I HAVE A BOMB!", "CAPTAIN IS A COMDOM!", "GLORY TO ALMACH!"))

/obj/item/megaphone/proc/can_broadcast(mob/living/user)
	if(user.client)
		if(user.client.prefs.muted & MUTE_IC)
			to_chat(user, span_warning("You cannot speak in IC (muted)."))
			return FALSE
	if(!(ishuman(user) || HAS_SYNTHETIC_BIOLOGY(user)))
		to_chat(user, span_warning("You don't know how to use this!"))
		return FALSE
	if(user.has_status(STAT_MUTED))
		return FALSE
	if(!COOLDOWN_FINISHED(src, spamcheck))
		to_chat(user, span_warning("[src] needs to recharge!"))
		return FALSE
	if(loc != user)
		return FALSE
	if(user.stat != CONSCIOUS)
		return FALSE
	return TRUE

/obj/item/megaphone/proc/do_broadcast(mob/living/user, message)
	if(emagged)
		if(insults)
			var/insult = pick(TYPE_TABLE_GET(src, megaphone_insults))
			user.audible_message(span_infoplain(span_bold("[user.GetVoice()]") + "[user.GetAltName()] broadcasts, " + span_large("\"[insult]\"")), runemessage = insult)
			insults--
		else
			to_chat(user, span_warning("*BZZZZzzzzzt*"))
	else
		user.audible_message(span_infoplain(span_bold("[user.GetVoice()]") + "[user.GetAltName()] broadcasts, " + span_large("\"[message]\"")), runemessage = message)

/// The self-use op: asks what to shout (the prompt checks the broadcast again when it is answered).
/obj/item/megaphone/proc/shout(datum/act/op/A)
	open_request(src, /datum/prompt/text, PROC_REF(shout_entered), answerer = A.actor, title = "Megaphone", question = "Shout a message?", ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
	return OP_OK

/obj/item/megaphone/proc/shout_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	if(!A.answer.value)
		return
	var/message = capitalize(A.answer.value)

	if(!can_broadcast(user))
		return

	COOLDOWN_START(src, spamcheck, 2 SECONDS)
	do_broadcast(user, message)

CAPABILITIES(/obj/item/megaphone)
	op("shout", in_hand(), label("Shout"), then(PROC_REF(shout)))
	emag(then(PROC_REF(on_emag)), powered = FALSE)


/obj/item/megaphone/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_warning("You overload [src]'s voice synthesizer."))
	emagged = TRUE
	insults = rand(1, 3)//to prevent caps spam.
	return OP_OK

/obj/item/megaphone/super
	name = "gigaphone"
	desc = "A device used to project your voice. Loudly-er."
	icon_state = "gigaphone"

	var/broadcast_font = "verdana"
	var/broadcast_size = 3
	var/broadcast_color = "#000000" //Black by default.
	var/list/volume_options = list(2, 3, 4) // ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)
	var/list/font_options = list("times new roman", "times", "verdana", "sans-serif", "serif", "georgia") // ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)
	var/list/color_options= list("#000000", "#ff0000", "#00ff00", "#0000ff") // ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)

TYPE_TABLE(/obj/item/megaphone/super, megaphone_insults, list("HONK?!", "HONK!", "HOOOOOOOONK!", "...!", "HUNK.", "Honk?"))


/obj/item/megaphone/super/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	..()
	if(emagged)
		if(!(11 in volume_options))
			volume_options = list(11)
			broadcast_size = 11
		if(!("comic sans ms" in font_options))
			font_options = list("comic sans ms")
			broadcast_font = "comic sans ms"
			to_chat(user, span_notice("\The [src] emits a <font face='comic sans ms' color='#ff69b4'>silly</font> sound."))
		if(!("#ff69b4" in color_options))
			color_options = list("#ff69b4")
			broadcast_color = "#ff69b4"
		if(insults <= 0)
			insults = rand(1,3)
			to_chat(user, span_warning("You re-scramble \the [src]'s voice synthesizer."))
		return 1

/obj/item/megaphone/super/proc/adjust_volume(datum/act/op/A)
	open_request(src, /datum/prompt/choice, PROC_REF(volume_chosen), answerer = A.actor, choices = volume_options, title = "Set Volume", question = "Set Volume", ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
	return OP_OK

/obj/item/megaphone/super/proc/volume_chosen(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value)
		broadcast_size = A.answer.value

/obj/item/megaphone/super/proc/adjust_font(datum/act/op/A)
	open_request(src, /datum/prompt/choice, PROC_REF(font_chosen), answerer = A.actor, choices = font_options, title = "Set Volume", question = "Set Volume", ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
	return OP_OK

/obj/item/megaphone/super/proc/font_chosen(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value)
		broadcast_font = A.answer.value

/obj/item/megaphone/super/proc/adjust_color(datum/act/op/A)
	open_request(src, /datum/prompt/choice, PROC_REF(color_chosen), answerer = A.actor, choices = color_options, title = "Set Volume", question = "Set Volume", ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
	return OP_OK

/obj/item/megaphone/super/proc/color_chosen(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value)
		broadcast_color = A.answer.value

/obj/item/megaphone/super/do_broadcast(mob/living/user, message)
	if(emagged)
		if(insults)
			var/insult = pick(TYPE_TABLE_GET(src, megaphone_insults))
			user.audible_message(span_bold("[user.GetVoice()]") + "[user.GetAltName()] broadcasts, <FONT size=[broadcast_size] face='[broadcast_font]' color='[broadcast_color]'>\"[insult]\"</FONT>", runemessage = insult)
			if(broadcast_size >= 11)
				var/turf/T = get_turf(user)
				play_sfx(src, SFX_ITEMS_AIRHORN)
				for(var/mob/living/carbon/M in oviewers(4, T))
					if(M.get_ear_protection() >= 2)
						continue
					M.status_set(STAT_SLEEPING, 0)
					M.status_adjust(STAT_STUTTERING, 20)
					M.status_adjust(STAT_DEAFENED, 30)
					M.deaf_loop.start() // Ear Ringing/Deafness
					M.status_at_least(STAT_WEAKENED, 3)
					if(prob(30))
						M.status_at_least(STAT_STUNNED, 10)
						M.status_at_least(STAT_PARALYZED, 4)
					else
						M.status_adjust(STAT_JITTERY, 50)
			insults--
		else
			user.audible_message(span_critical("*BZZZZzzzzzt*"))
			if(prob(40) && insults <= 0)
				fx_sparks(get_turf(user), 2)
				user.visible_message(span_warning("\The [src] sparks violently!"))
				after(src, 3 SECONDS, PROC_REF(overload_boom))
	else
		user.audible_message(span_bold("[user.GetVoice()]") + "[user.GetAltName()] broadcasts, <FONT size=[broadcast_size] face='[broadcast_font]' color='[broadcast_color]'>\"[message]\"</FONT>", runemessage = message)

/obj/item/megaphone/super/proc/overload_boom()
	explosion(get_turf(src), -1, -1, 1, 3, adminlog = 1)
	destroyed(src)
	return

/// Were INTERACT_VERB (object verbs): menu ops, no gesture reaches them: the Menu, the radial and the command bar name them. Only while carried.
CAPABILITIES(/obj/item/megaphone/super)
	op("change_volume", menu(), label("Change Volume"), needs(carried()), then(PROC_REF(adjust_volume)))
	op("change_font", menu(), label("Change... Pronunciation?"), needs(carried()), then(PROC_REF(adjust_font)))
	op("change_color", menu(), label("Change... Tune?"), needs(carried()), then(PROC_REF(adjust_color)))
