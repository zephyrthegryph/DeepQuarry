/mob/living/proc/toggle_active_cloaking() // Borrowed from Rogue Star, thanks guys!
	set category = VERB_CAT_ABILITIES_GENERAL
	set name = "Toggle Active Cloaking"

	if(invisibility == INVISIBILITY_OBSERVER)
		invisibility = initial(invisibility)
		to_chat(src, span_notice("You are now visible."))
		alpha = min(alpha + 100, 255)
	else
		invisibility = INVISIBILITY_OBSERVER
		to_chat(src, span_notice("You are now invisible."))
		alpha = max(alpha - 100, 0)

	fx_sparks(loc, 5, FALSE)
	act_message(src, null, others = span_warning("Electrical sparks manifest around %U% as they suddenly appear!"))
