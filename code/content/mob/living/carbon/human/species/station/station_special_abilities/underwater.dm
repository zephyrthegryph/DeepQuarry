/// Also re-checked: still stealthed underwater, and the target is still next to us.
/datum/prompt/choice/victim/underwater

/datum/prompt/choice/victim/underwater/recheck_extra()
	. = ..()
	if(.)
		return
	var/mob/living/L = answerer
	if(!L.has_body_effect(/datum/body_effect/underwater_stealth) || get_dist(L, value) > 1)
		return "lost the chance"
	return null
