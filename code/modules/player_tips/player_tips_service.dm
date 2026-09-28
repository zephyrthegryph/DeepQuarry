/// Player tips procs and lists are defined under /code/modules/player_tips
// The player tips world service (was SSplayer_tips): every 5 minutes it checks whether a tip is
// due and sends it to every player.
GLOBAL_DATUM_INIT(player_tips_service, /datum/world_service/player_tips, new)

/datum/world_service/player_tips
	name = "Periodic Player Tips"
	lane = /datum/om/behaviour/world/player_tips

	var/static/datum/player_tips/player_tips = new
	var/list/current_run

/datum/world_service/player_tips/service_step(resumed)
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

/// player tips
/datum/om/behaviour/world/player_tips
	name = "world: player tips"
	every = 5 MINUTES
	runlevels = RUNLEVEL_GAME

/datum/om/behaviour/world/player_tips/service()
	return GLOB.player_tips_service
