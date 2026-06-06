/turf/simulated/floor/proc/gets_drilled()
	return

/turf/simulated/floor/proc/break_tile_to_plating()
	if(!is_plating())
		make_plating()
	break_tile()

/turf/simulated/floor/proc/break_tile()
	if(!flooring || !(flooring.flags & TURF_CAN_BREAK) || !isnull(broken))
		return
	if(flooring.has_damage_range)
		broken = rand(0,flooring.has_damage_range)
	else
		broken = 0
	update_icon()

// DQEdit — promoted from /turf/simulated/floor to /turf/simulated so LINDA's
// turf-level fire spread (LINDA_turf_tile.dm + LINDA_fire.dm) can call it
// uniformly. Non-floor simulated turfs no-op by returning early.
/turf/simulated/proc/burn_tile(exposed_temperature)
	return // base no-op

/turf/simulated/floor/burn_tile(exposed_temperature)
	if(!flooring || !(flooring.flags & TURF_CAN_BURN) || !isnull(burnt))
		return
	if(flooring.has_burn_range)
		burnt = rand(0,flooring.has_burn_range)
	else
		burnt = 0
	update_icon()
