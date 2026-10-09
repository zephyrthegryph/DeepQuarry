/obj/effect/decal/warning_stripes
	icon = 'icons/effects/warning_stripes.dmi'

CAPABILITIES(/obj/effect/decal/warning_stripes)
	map_resolver(GLOBAL_PROC_REF(resolve_warning_stripes))

/// MAP_RESOLVER for warning stripes: an overlay on the turf.
/proc/resolve_warning_stripes(atom/loc, path, list/varedits)
	var/obj/effect/decal/warning_stripes/P = path
	var/turf/T = get_turf(loc)
	if(!T)
		return TRUE
	var/image/I = image(MAP_VAR(P, varedits, icon), icon_state = MAP_VAR(P, varedits, icon_state), dir = MAP_VAR(P, varedits, dir))
	I.color = MAP_VAR(P, varedits, color)
	T.add_overlay(I)
	return TRUE
