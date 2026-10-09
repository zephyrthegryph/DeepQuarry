//50-stacks as their own type was too buggy, we're doing it a different way
/obj/fiftyspawner //this doesn't need to do anything but make the stack and die so it's light
	name = "50-stack spawner"
	desc = "This item spawns stack of 50 of a given material."
	icon = 'icons/misc/mark.dmi'
	icon_state = "x4"
	var/type_to_spawn = null

CAPABILITIES(/obj/fiftyspawner)
	map_resolver(GLOBAL_PROC_REF(resolve_fiftyspawner), vars = list("type_to_spawn"))

/// The map resolver of 50-stack spawners: a full stack, into the closet on the tile if any (or into
/// the crate a supply pack put the spawner in).
/proc/resolve_fiftyspawner(atom/loc, path, list/varedits)
	var/obj/fiftyspawner/P = path
	var/stack_type = MAP_VAR(P, varedits, type_to_spawn)
	var/obj/item/stack/M = new stack_type(map_spawn_container(loc), -1)
	if(varedits && ("pixel_y" in varedits))
		M.pixel_y = varedits["pixel_y"]
	return TRUE

/obj/fiftyspawner/rods
	name = "stack of rods" //this needs to be defined for cargo
	type_to_spawn = /obj/item/stack/rods
