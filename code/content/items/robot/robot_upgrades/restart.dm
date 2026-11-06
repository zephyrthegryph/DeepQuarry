/obj/item/borg/upgrade/utility/restart
	name = "robot emergency restart module"
	desc = "Used to force a restart of a disabled-but-repaired robot, bringing it back online."
	icon_state = "cyborg_upgrade1"
	item_state = "cyborg_upgrade"

/obj/item/borg/upgrade/utility/restart/action(mob/user, mob/living/silicon/robot/R)
	if(R.stat == CONSCIOUS)
		return FALSE

	if(R.vitality() < 0.5) // below half integrity (the old health < 0)
		to_chat(user, span_warning("You have to repair the robot before using this module!"))
		return FALSE

	if(!R.key)
		for(var/mob/observer/dead/ghost in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
			if(ghost.mind && ghost.mind.current == R)
				bind_player(R, ghost.key)

	if(R.stat == DEAD)
		var/revived = R.return_from_death("restart module", src)
		if(revived != TRUE)
			to_chat(user, span_warning("The restart fails: [revived]."))
			return FALSE
	else
		R.set_stat(CONSCIOUS)
	R.notify_ai(ROBOT_NOTIFICATION_NEW_UNIT)
	return TRUE
