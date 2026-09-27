/mob
	///the icon currently used for the typing indicator's bubble
	var/tmp/mutable_appearance/active_typing_indicator
	///the icon currently used for the thinking indicator's bubble
	var/tmp/mutable_appearance/active_thinking_indicator

/** Creates a thinking indicator over the mob. Note: Prefs are checked in /client/proc/start_thinking() */
/proc/create_thinking_indicator(mob/source)
	if(source.active_thinking_indicator || source.active_typing_indicator || source.stat != CONSCIOUS || !HAS_TRAIT(source, TRAIT_THINKING_IN_CHARACTER))
		return FALSE
	var/cur_bubble_appearance = source.custom_speech_bubble
	if(!cur_bubble_appearance || cur_bubble_appearance == "default")
		cur_bubble_appearance = source.speech_bubble_appearance()
	source.active_thinking_indicator = mutable_appearance('icons/mob/talk_vr.dmi', "[cur_bubble_appearance]_thinking", FLOAT_LAYER, appearance_flags=(KEEP_APART|RESET_COLOR|PIXEL_SCALE))
	source.active_thinking_indicator.pixel_x = source.get_oversized_icon_offsets()["x"]
	source.active_thinking_indicator.pixel_y = source.get_oversized_icon_offsets()["y"]
	source.add_overlay(source.active_thinking_indicator)

/** Removes the thinking indicator over the mob. */
/proc/remove_thinking_indicator(mob/source)
	if(!source.active_thinking_indicator)
		return FALSE
	source.cut_overlay(source.active_thinking_indicator)
	source.active_thinking_indicator = null

/** Creates a typing indicator over the mob. Note: Prefs are checked in /client/proc/start_typing() */
/proc/create_typing_indicator(mob/source)
	if(source.active_typing_indicator || source.active_thinking_indicator || source.stat != CONSCIOUS || !HAS_TRAIT(source, TRAIT_THINKING_IN_CHARACTER))
		return FALSE
	var/cur_bubble_appearance = source.custom_speech_bubble
	if(!cur_bubble_appearance || cur_bubble_appearance == "default")
		cur_bubble_appearance = source.speech_bubble_appearance()
	source.active_typing_indicator = mutable_appearance('icons/mob/talk_vr.dmi', "[cur_bubble_appearance]_typing", ABOVE_MOB_LAYER, appearance_flags=(KEEP_APART|RESET_COLOR|PIXEL_SCALE))
	source.active_typing_indicator.pixel_x = source.get_oversized_icon_offsets()["x"]
	source.active_typing_indicator.pixel_y = source.get_oversized_icon_offsets()["y"]
	source.add_overlay(source.active_typing_indicator)

/** Removes the typing indicator over the mob. */
/proc/remove_typing_indicator(mob/source)
	if(!source.active_typing_indicator)
		return FALSE
	source.cut_overlay(source.active_typing_indicator)
	source.active_typing_indicator = null

/** Removes any indicators and marks the mob as not speaking IC. */
/mob/proc/remove_all_indicators()
	REMOVE_TRAIT(src, TRAIT_THINKING_IN_CHARACTER, CURRENTLY_TYPING_TRAIT)
	remove_thinking_indicator(src)
	remove_typing_indicator(src)

/mob/set_stat(new_stat)
	. = ..()
	if(.)
		remove_all_indicators()

/mob/Logout()
	remove_all_indicators()
	return ..()

/** Sets the mob as "thinking" - with indicator and the TRAIT_THINKING_IN_CHARACTER trait */
/datum/tgui_say/proc/start_thinking(channel)
	if(!window_open)
		return FALSE
	return client.start_thinking(channel)

/** Removes typing/thinking indicators and flags the mob as not thinking */
/datum/tgui_say/proc/stop_thinking(channel)
	return client.stop_thinking(channel)

/**
 * Handles the user typing. After a brief period of inactivity,
 * signals the client mob to revert to the "thinking" icon.
 */
/datum/tgui_say/proc/start_typing(channel)
	if(!window_open)
		return FALSE
	return client.start_typing(channel)
