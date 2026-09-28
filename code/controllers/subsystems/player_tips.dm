/// Player tips procs and lists are defined under /code/modules/player_tips
SUBSYSTEM_DEF(player_tips)
	name = "Periodic Player Tips"
	// We check if it's time to send a tip every 5 minutes: /datum/om/behaviour/world/feature/player_tips
	flags = SS_NO_INIT | SS_NO_FIRE

	var/static/datum/player_tips/player_tips = new
	var/list/current_run = list()

/datum/controller/subsystem/player_tips/lane_step(resumed)
	if(!resumed)
		if(!player_tips.check_next_tip())
			return TRUE
		player_tips.set_current_tip()
		current_run = REGISTRY_COPY(REGISTRY_PLAYERS)

	for(var/mob/target_mob in current_run)
		current_run -= target_mob
		player_tips.send_tip(target_mob)
		if(TICK_CHECK)
			return FALSE
	return TRUE
