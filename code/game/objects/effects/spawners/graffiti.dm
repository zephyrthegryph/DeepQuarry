/obj/effect/graffitispawner
	name = "old scrawling"
	icon = 'icons/effects/map_effects.dmi'
	icon_state = "graffiti"

	var/graffiti_type	// The text string for the desired icon state of your graffiti.

	// If the effect's color is not set, it will be chosen at random.
	var/color_secondary	// The hexcode for the desired secondary color of your graffiti. If blank, it will inherit this effect's color.

CAPABILITIES(/obj/effect/graffitispawner)
	map_resolver(GLOBAL_PROC_REF(resolve_graffitispawner), vars = list("color_secondary", "graffiti_type"))

/// MAP_RESOLVER for old scrawlings: a crayon drawing, random colour and shape unless set.
/proc/resolve_graffitispawner(atom/loc, path, list/varedits)
	var/obj/effect/graffitispawner/P = path
	var/color = MAP_VAR(P, varedits, color)
	if(!color)
		color = rgb(rand(1,255),rand(1,255),rand(1,255))
	var/color_secondary = MAP_VAR(P, varedits, color_secondary) || color
	var/graffiti_type = MAP_VAR(P, varedits, graffiti_type) || pick("rune", "graffiti", "left", "right", "up", "down")
	var/obj/effect/decal/cleanable/crayon/C = new(get_turf(loc), color, color_secondary, graffiti_type)
	C.name = MAP_VAR(P, varedits, name)
	return TRUE
