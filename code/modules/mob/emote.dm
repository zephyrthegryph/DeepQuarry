// Shortcuts for above proc
/mob/proc/visible_emote(act_desc)
	custom_emote(VISIBLE_MESSAGE, act_desc)

/mob/proc/audible_emote(act_desc)
	custom_emote(AUDIBLE_MESSAGE, act_desc)

/mob/proc/emote_dead_entered(datum/om/prompt/text/ask)
	var/message = sanitize_or_reflect(ask.text, src) // Reflect too long messages, within reason
	if(message)
		emote_dead(message)

/mob/proc/emote_dead(message)

	if(client.prefs.muted & MUTE_DEADCHAT)
		to_chat(src, span_danger("You cannot send deadchat emotes (muted)."))
		return

	if(!client?.prefs?.read_preference(/datum/preference/toggle/show_dsay))
		to_chat(src, span_danger("You have deadchat muted."))
		return

	if(!check_rights(R_HOLDER, FALSE))
		if(!CONFIG_GET(flag/dsay_allowed))
			to_chat(src, span_danger("Deadchat is globally muted."))
			return


	if(!message)
		om_ask(src, /datum/om/prompt/text, PROC_REF(emote_dead_entered), message = "Choose an emote to display.", encode = FALSE)
		return
	var/input = message

	input = encode_html_emphasis(input)

	if(input)
		log_message("(GHOST EMOTE) [input]", LOG_EMOTE)
		if(!invisibility) //If the ghost is made visible by admins or cult. And to see if the ghost has toggled its own visibility, as well. -Mech
			act_message(src, null, others = span_deadsay(span_bold("%U%") + " [input]"))
		else
			say_dead_direct(input, src)
