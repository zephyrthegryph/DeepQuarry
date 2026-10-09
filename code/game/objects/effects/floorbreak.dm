/obj/effect/floorbreak
	name = "Floor Breaker"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "floorbreaker"

CAPABILITIES(/obj/effect/floorbreak)
	map_resolver(GLOBAL_PROC_REF(resolve_floorbreak))

/// The map resolver of floor breakers: breaks the floor tile, once the load is in place.
/proc/resolve_floorbreak(atom/loc, path, list/varedits)
	if(!istype(loc, /turf/simulated/floor))
		log_world("Floor Breaker at X: [loc?.x], Y: [loc?.y] was somehow placed in a non-turf location, or placed on an unsimulated turf, non-floor turf, or other invalid location (e.g. wall, open space, inside a container).")
		return TRUE
	map_resolve_later(GLOBAL_PROC_REF(floorbreak_apply), loc, path, varedits)
	return TRUE

/proc/floorbreak_apply(turf/simulated/floor/our_turf, path, list/varedits)
	our_turf.break_tile()
