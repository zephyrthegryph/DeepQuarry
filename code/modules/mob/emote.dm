// Shortcuts for above proc
/mob/proc/visible_emote(act_desc)
	custom_emote(VISIBLE_MESSAGE, act_desc)

/mob/proc/audible_emote(act_desc)
	custom_emote(AUDIBLE_MESSAGE, act_desc)

/proc/emote_dead(mob/source, message)

	if(source.client.prefs.muted & MUTE_DEADCHAT)
		to_chat(source, span_danger("You cannot send deadchat emotes (muted)."))
		return

	if(!source.client?.prefs?.read_preference(/datum/preference/toggle/show_dsay))
		to_chat(source, span_danger("You have deadchat muted."))
		return

	if(!check_rights(R_HOLDER, FALSE))
		if(!CONFIG_GET(flag/dsay_allowed))
			to_chat(source, span_danger("Deadchat is globally muted."))
			return


	var/input
	if(!message)
		input = sanitize_or_reflect(tgui_input_text(source, "Choose an emote to display.", encode = FALSE), source) // Reflect too long messages, within reason
	else
		input = message

	input = encode_html_emphasis(input)

	if(input)
		source.log_message("(GHOST EMOTE) [input]", LOG_EMOTE)
		if(!source.invisibility) //If the ghost is made visible by admins or cult. And to see if the ghost has toggled its own visibility, as well. -Mech
			source.visible_message(span_deadsay(span_bold("[source]") + " [input]"))
		else
			say_dead_direct(input, source)
