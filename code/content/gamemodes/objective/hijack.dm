/datum/objective/hijack
	explanation_text = "Hijack the emergency shuttle by escaping alone."

/datum/objective/hijack/check_completion()
	if(!owner.current || owner.current.stat)
		return 0
	if(!SSemergency_shuttle.returned())
		return 0
	if(issilicon(owner.current))
		return 0
	var/area/shuttle = locate(/area/shuttle/escape/centcom)
	var/static/list/protected_mobs = list(/mob/living/silicon/ai, /mob/living/silicon/pai)
	for(var/mob/living/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(player.type in protected_mobs)	continue
		if (player.mind && (player.mind != owner))
			if(player.stat != DEAD)			//they're not dead!
				if(get_turf(player) in shuttle)
					return 0
	return 1
