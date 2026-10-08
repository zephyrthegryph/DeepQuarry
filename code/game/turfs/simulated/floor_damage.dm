/turf/simulated/floor/proc/gets_drilled()
	return

/turf/simulated/floor/proc/break_tile_to_plating()
	if(!is_plating())
		make_plating()
	break_tile()

/turf/simulated/floor/proc/break_tile()
	if(!flooring || !(flooring.flags & TURF_CAN_BREAK) || !isnull(broken))
		return
	set_broken(flooring.has_damage_range ? rand(0,flooring.has_damage_range) : 0)
	set_plating_damage_state(rand(1, 4))

// promoted from /turf/simulated/floor to /turf/simulated so LINDA's
// turf-level fire spread (LINDA_turf_tile.dm + LINDA_fire.dm) can call it
// uniformly. Non-floor simulated turfs no-op by returning early.
/turf/simulated/proc/burn_tile(exposed_temperature)
	return // base no-op

/turf/simulated/floor/burn_tile(exposed_temperature)
	if(!flooring || !(flooring.flags & TURF_CAN_BURN) || !isnull(burnt))
		return
	set_burnt(flooring.has_burn_range ? rand(0,flooring.has_burn_range) : 0)
	set_plating_damage_state(rand(1, 4))
