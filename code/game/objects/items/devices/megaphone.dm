/obj/item/megaphone
	name = "megaphone"
	desc = "A device used to project your voice. Loudly."
	icon = 'icons/obj/device.dmi'
	icon_state = "megaphone"
	w_class = ITEMSIZE_SMALL

	var/spamcheck = 0
	var/emagged = 0
	var/insults = 0
	var/list/insultmsg = list("FUCK EVERYONE!", "I'M A TERRORIST!", "ALL SECURITY TO SHOOT ME ON SIGHT!", "I HAVE A BOMB!", "CAPTAIN IS A COMDOM!", "GLORY TO ALMACH!")
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/megaphone/proc/can_broadcast(mob/living/user)
	if(user.client)
		if(user.client.prefs.muted & MUTE_IC)
			to_chat(user, span_warning("You cannot speak in IC (muted)."))
			return FALSE
	if(!(ishuman(user) || user.isSynthetic()))
		to_chat(user, span_warning("You don't know how to use this!"))
		return FALSE
	if(user.has_status(EFFECT_MUTED))
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
			var/insult = pick(insultmsg)
			user.audible_message(span_infoplain(span_bold("[user.GetVoice()]") + "[user.GetAltName()] broadcasts, " + span_large("\"[insult]\"")), runemessage = insult)
			insults--
		else
			to_chat(user, span_warning("*BZZZZzzzzzt*"))
	else
		user.audible_message(span_infoplain(span_bold("[user.GetVoice()]") + "[user.GetAltName()] broadcasts, " + span_large("\"[message]\"")), runemessage = message)

/obj/item/megaphone/get_interactions()
	var/static/list/L = list(INTERACT_USE(null, PROC_REF(interaction_self)))
	return L

/obj/item/megaphone/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	om_ask(user, /datum/om/prompt/text, PROC_REF(shout_entered), title = "Megaphone", message = "Shout a message?", ask_flags = ASK_CARRIED | ASK_CAPABLE)

/obj/item/megaphone/proc/shout_entered(datum/om/prompt/text/ask)
	var/mob/user = ask.answerer
	if(!ask.text)
		return
	var/message = capitalize(ask.text)

	if(!can_broadcast(user))
		return

	COOLDOWN_START(src, spamcheck, 20)
	do_broadcast(user, message)

/obj/item/megaphone/emag_act(remaining_charges, mob/user)
	if(!emagged)
		to_chat(user, span_warning("You overload [src]'s voice synthesizer."))
		emagged = TRUE
		insults = rand(1, 3)//to prevent caps spam.
		return TRUE

/obj/item/megaphone/super
	name = "gigaphone"
	desc = "A device used to project your voice. Loudly-er."
	icon_state = "gigaphone"

	var/broadcast_font = "verdana"
	var/broadcast_size = 3
	var/broadcast_color = "#000000" //Black by default.
	var/list/volume_options = list(2, 3, 4)
	var/list/font_options = list("times new roman", "times", "verdana", "sans-serif", "serif", "georgia")
	var/list/color_options= list("#000000", "#ff0000", "#00ff00", "#0000ff")

	insultmsg = list("HONK?!", "HONK!", "HOOOOOOOONK!", "...!", "HUNK.", "Honk?")

/obj/item/megaphone/super/emag_act(remaining_charges, mob/user)
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

/obj/item/megaphone/super/verb/turn_volume_dial()
	set name = "Change Volume"
	set desc = "Allows you to change the megaphone's volume."
	set category = "Object"

	adjust_volume(usr)

/obj/item/megaphone/super/proc/adjust_volume(mob/living/user)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(volume_chosen), choices = volume_options, title = "Set Volume", message = "Set Volume", requires = PROMPT_ADJACENT)

/obj/item/megaphone/super/proc/volume_chosen(datum/om/prompt/choice/ask)
	if(ask.choice)
		broadcast_size = ask.choice

/obj/item/megaphone/super/verb/change_font()
	set name = "Change... Pronunciation?"
	set desc = "Allows you to change the megaphone's font."
	set category = "Object"

	adjust_font(usr)

/obj/item/megaphone/super/proc/adjust_font(mob/living/user)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(font_chosen), choices = font_options, title = "Set Volume", message = "Set Volume", requires = PROMPT_ADJACENT)

/obj/item/megaphone/super/proc/font_chosen(datum/om/prompt/choice/ask)
	if(ask.choice)
		broadcast_font = ask.choice

/obj/item/megaphone/super/verb/change_color()
	set name = "Change... Tune?"
	set desc = "Allows you to change the megaphone's color."
	set category = "Object"

	adjust_color(usr)

/obj/item/megaphone/super/proc/adjust_color(mob/living/user)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(color_chosen), choices = color_options, title = "Set Volume", message = "Set Volume", requires = PROMPT_ADJACENT)

/obj/item/megaphone/super/proc/color_chosen(datum/om/prompt/choice/ask)
	if(ask.choice)
		broadcast_color = ask.choice

/obj/item/megaphone/super/do_broadcast(mob/living/user, message)
	if(emagged)
		if(insults)
			var/insult = pick(insultmsg)
			user.audible_message(span_bold("[user.GetVoice()]") + "[user.GetAltName()] broadcasts, <FONT size=[broadcast_size] face='[broadcast_font]' color='[broadcast_color]'>\"[insult]\"</FONT>", runemessage = insult)
			if(broadcast_size >= 11)
				var/turf/T = get_turf(user)
				playsound(src, 'sound/items/AirHorn.ogg', 100, 1)
				for(var/mob/living/carbon/M in oviewers(4, T))
					if(M.get_ear_protection() >= 2)
						continue
					M.status_set(EFFECT_SLEEPING, 0)
					M.status_adjust(EFFECT_STUTTERING, 20)
					M.status_adjust(EFFECT_DEAFENED, 30)
					M.deaf_loop.start() // Ear Ringing/Deafness
					M.status_at_least(EFFECT_WEAKENED, 3)
					if(prob(30))
						M.status_at_least(EFFECT_STUNNED, 10)
						M.status_at_least(EFFECT_PARALYZED, 4)
					else
						M.status_adjust(EFFECT_JITTERY, 50)
			insults--
		else
			user.audible_message(span_critical("*BZZZZzzzzzt*"))
			if(prob(40) && insults <= 0)
				var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
				s.set_up(2, 1, get_turf(user))
				s.start()
				user.visible_message(span_warning("\The [src] sparks violently!"))
				om_after(src, 3 SECONDS, PROC_REF(overload_boom))
	else
		user.audible_message(span_bold("[user.GetVoice()]") + "[user.GetAltName()] broadcasts, <FONT size=[broadcast_size] face='[broadcast_font]' color='[broadcast_color]'>\"[message]\"</FONT>", runemessage = message)

/obj/item/megaphone/super/proc/overload_boom()
	explosion(get_turf(src), -1, -1, 1, 3, adminlog = 1)
	qdel(src)
	return
