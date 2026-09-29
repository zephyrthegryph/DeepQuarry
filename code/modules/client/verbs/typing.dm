#define IC_VERBS list("say", "me", "whisper", "subtle")

/client/var/commandbar_thinking = FALSE
/client/var/commandbar_typing = FALSE

/client/proc/initialize_commandbar_spy()
	src << output('html/typing_indicator.html', "commandbar_spy")

/client/proc/handle_commandbar_typing(typed_verb, argument_length)
	if(!prefs?.read_preference(/datum/preference/toggle/show_typing_indicator))
		return

	if(length(typed_verb) < 1 || !(lowertext(typed_verb) in IC_VERBS) || !(argument_length >= 1))
		if(commandbar_typing)
			commandbar_typing = FALSE
			stop_typing()

		if(commandbar_thinking)
			commandbar_thinking = FALSE
			stop_thinking()
		return

	if(!commandbar_thinking)
		commandbar_thinking = TRUE
		start_thinking(typed_verb)

	if(!commandbar_typing)
		commandbar_typing = TRUE
		start_typing(typed_verb)


/** Sets the mob as "thinking" - with indicator and the TRAIT_THINKING_IN_CHARACTER trait */
/client/proc/start_thinking(channel)
	if(!prefs?.read_preference(/datum/preference/toggle/show_typing_indicator))
		return FALSE
	if(channel == "Whis" || channel == "Subtle" || channel == "whisper" || channel == "subtle")
		if(!prefs?.read_preference(/datum/preference/toggle/show_typing_indicator_subtle))
			return FALSE
	if(mob.status_flags & FAKEDEATH)
		return FALSE
	add_trait(mob, TRAIT_THINKING_IN_CHARACTER, CURRENTLY_TYPING_TRAIT)
	mob.create_thinking_indicator()

/** Removes typing/thinking indicators and flags the mob as not thinking */
/client/proc/stop_thinking(channel)
	mob?.remove_all_indicators()

/**
 * Handles the user typing. After a brief period of inactivity,
 * signals the client mob to revert to the "thinking" icon.
 */
/client/proc/start_typing(channel)
	var/mob/client_mob = mob
	client_mob.remove_thinking_indicator()
	if(!prefs?.read_preference(/datum/preference/toggle/show_typing_indicator) || !has_trait(client_mob, TRAIT_THINKING_IN_CHARACTER))
		return FALSE
	if(channel == "Whis" || channel == "Subtle" || channel == "whisper" || channel == "subtle")
		if(!prefs?.read_preference(/datum/preference/toggle/show_typing_indicator_subtle))
			return FALSE
	client_mob.create_typing_indicator()
	om_after_replace(src, 5 SECONDS, PROC_REF(stop_typing), channel)

/**
 * Callback to remove the typing indicator after a brief period of inactivity.
 * If the user was typing IC, the thinking indicator is shown.
 */
/client/proc/stop_typing(channel)
	if(isnull(mob))
		return FALSE
	var/mob/client_mob = mob
	client_mob.remove_typing_indicator()
	if(!prefs?.read_preference(/datum/preference/toggle/show_typing_indicator) || !has_trait(client_mob, TRAIT_THINKING_IN_CHARACTER))
		return FALSE
	if(channel == "Whis" || channel == "Subtle" || channel == "whisper" || channel == "subtle")
		if(!prefs?.read_preference(/datum/preference/toggle/show_typing_indicator_subtle))
			return FALSE
	client_mob.create_thinking_indicator()

#undef IC_VERBS
