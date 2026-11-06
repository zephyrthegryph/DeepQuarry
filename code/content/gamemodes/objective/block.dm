/datum/objective/block
	explanation_text = "Do not allow any organic lifeforms to escape on the shuttle alive."

/datum/objective/block/check_completion()
	if(!istype(owner.current, /mob/living/silicon))
		return 0
	if(!SSemergency_shuttle.returned())
		return 0
	if(!owner.current)
		return 0
	var/area/shuttle = locate(/area/shuttle/escape/centcom)
	var/protected_mobs[] = list(/mob/living/silicon/ai, /mob/living/silicon/pai, /mob/living/silicon/robot)
	for(var/mob/living/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(player.type in protected_mobs)	continue
		if (player.mind)
			if (player.stat != 2)
				if (get_turf(player) in shuttle)
					return 0
	return 1
