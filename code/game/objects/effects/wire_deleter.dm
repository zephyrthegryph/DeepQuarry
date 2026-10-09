/obj/effect/wire_deleter
	name = "wire deleter"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x2"
	anchored = TRUE
	unacidable = TRUE
	simulated = FALSE
	invisibility = INVISIBILITY_MAXIMUM

CAPABILITIES(/obj/effect/wire_deleter)
	map_resolver(GLOBAL_PROC_REF(resolve_wire_deleter))

/// MAP_RESOLVER for wire deleters: once the load is in place, a third of the tile's cables go.
/proc/resolve_wire_deleter(atom/loc, path, list/varedits)
	map_resolve_later(GLOBAL_PROC_REF(wire_deleter_cut), get_turf(loc), path, varedits)
	return TRUE

/proc/wire_deleter_cut(turf/T, path, list/varedits)
	for(var/c in contents_of(T))
		if(istype(c, /obj/structure/cable))
			if(prob(33))
				spent(c)
