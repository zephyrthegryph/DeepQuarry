/datum/decl/emote/visible/vomit
	key = "vomit"

/datum/decl/emote/visible/vomit/do_emote(atom/user, extra_params)
	if(isliving(user))
		var/mob/living/M = user
		if(!HAS_SYNTHETIC_BIOLOGY(M))
			M.vomit()
			return
	to_chat(src, span_warning("You are unable to vomit."))
