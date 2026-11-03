/// Player tips procs and lists are defined under /code/modules/player_tips
// The player tips system (was SSplayer_tips): every 5 minutes it checks whether a tip is due and sends it to every
// player.
SYSTEM_DEF(player_tips)
	name = "Periodic Player Tips"
	periodic_runlevels = RUNLEVEL_GAME
	VAR_PRIVATE/static/datum/player_tips/player_tips = new
	VAR_PRIVATE/list/current_run
	/// TRUE while a pass that ran out of budget waits to resume.
	VAR_PRIVATE/resuming = FALSE

/datum/system/player_tips/reactions()
	. = ..()
	. += every(5 MINUTES, PROC_REF(send_tips), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/player_tips/proc/send_tips(dt)
	if(!resuming)
		if(!player_tips.check_next_tip())
			return STEP_DONE
		player_tips.set_current_tip()
		current_run = REGISTRY_COPY(REGISTRY_PLAYERS)
	resuming = FALSE

	for(var/mob/target_mob in current_run)
		current_run -= target_mob
		player_tips.send_tip(target_mob)
		if(KERNEL_OVER_BUDGET)
			resuming = TRUE
			return STEP_YIELD
	return STEP_DONE
