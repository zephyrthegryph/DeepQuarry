/obj/item/megaphone
	name = "megaphone"
	desc = "A device used to project your voice. Loudly."
	icon = 'icons/obj/device.dmi'
	icon_state = "megaphone"
	w_class = ITEMSIZE_SMALL

	var/spamcheck = 0
	var/emagged = 0
	var/insults = 0
	var/list/insultmsg = list("FUCK EVERYONE!", "I'M A TERRORIST!", "ALL SECURITY TO SHOOT ME ON SIGHT!", "I HAVE A BOMB!", "CAPTAIN IS A COMDOM!", "GLORY TO ALMACH!") // ALLOW(instance_list): c: read-only per-subtype constant table (1 subtype overrides); a getter would share it, not worth it on a rare type
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

/obj/item/megaphone/proc/can_broadcast(mob/living/user)
	if(user.client)
		if(user.client.prefs.muted & MUTE_IC)
			to_chat(user, span_warning("You cannot speak in IC (muted)."))
			return FALSE
	if(!(ishuman(user) || HAS_SYNTHETIC_BIOLOGY(user)))
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

DECLARE_INTERACTIONS(/obj/item/megaphone, INTERACT_USE(null, PROC_REF(interaction_self)))

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
	var/list/volume_options = list(2, 3, 4) // ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)
	var/list/font_options = list("times new roman", "times", "verdana", "sans-serif", "serif", "georgia") // ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)
	var/list/color_options= list("#000000", "#ff0000", "#00ff00", "#0000ff") // ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)

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

/obj/item/megaphone/super/proc/turn_volume_dial_effect(mob/user, obj/item/held, datum/interaction/interaction)

	adjust_volume(user)

/obj/item/megaphone/super/proc/adjust_volume(mob/living/user)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(volume_chosen), choices = volume_options, title = "Set Volume", message = "Set Volume", requires = PROMPT_ADJACENT)

/obj/item/megaphone/super/proc/volume_chosen(datum/om/prompt/choice/ask)
	if(ask.choice)
		broadcast_size = ask.choice

/obj/item/megaphone/super/proc/change_font_effect(mob/user, obj/item/held, datum/interaction/interaction)

	adjust_font(user)

/obj/item/megaphone/super/proc/adjust_font(mob/living/user)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(font_chosen), choices = font_options, title = "Set Volume", message = "Set Volume", requires = PROMPT_ADJACENT)

/obj/item/megaphone/super/proc/font_chosen(datum/om/prompt/choice/ask)
	if(ask.choice)
		broadcast_font = ask.choice

/obj/item/megaphone/super/proc/change_color_effect(mob/user, obj/item/held, datum/interaction/interaction)

	adjust_color(user)

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
				play_sfx(src, SFX_ITEMS_AIRHORN)
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
				fx_sparks(get_turf(user), 2)
				user.visible_message(span_warning("\The [src] sparks violently!"))
				om_after(src, 3 SECONDS, PROC_REF(overload_boom))
	else
		user.audible_message(span_bold("[user.GetVoice()]") + "[user.GetAltName()] broadcasts, <FONT size=[broadcast_size] face='[broadcast_font]' color='[broadcast_color]'>\"[message]\"</FONT>", runemessage = message)

/obj/item/megaphone/super/proc/overload_boom()
	explosion(get_turf(src), -1, -1, 1, 3, adminlog = 1)
	qdel(src)
	return

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/megaphone/super, \
	INTERACT_VERB("Change Volume", PROC_REF(turn_volume_dial_effect), REQ_IN_INVENTORY), \
	INTERACT_VERB("Change... Pronunciation?", PROC_REF(change_font_effect), REQ_IN_INVENTORY), \
	INTERACT_VERB("Change... Tune?", PROC_REF(change_color_effect), REQ_IN_INVENTORY), \
)
