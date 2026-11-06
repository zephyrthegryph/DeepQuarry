//50-stacks as their own type was too buggy, we're doing it a different way
/obj/fiftyspawner //this doesn't need to do anything but make the stack and die so it's light
	name = "50-stack spawner"
	desc = "This item spawns stack of 50 of a given material."
	icon = 'icons/misc/mark.dmi'
	icon_state = "x4"
	var/type_to_spawn = null
	var/variant

CAPABILITIES(/obj/fiftyspawner)
	variants(nameof(variant), PROC_REF(variant_table))
	map_resolver(GLOBAL_PROC_REF(resolve_fiftyspawner), vars = list("type_to_spawn", "variant"))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/fiftyspawner/proc/variant_table()
	return GLOB.dq_variants_fiftyspawner

/// The map resolver of 50-stack spawners: a full stack, into the closet on the tile if any (or into
/// the crate a supply pack put the spawner in).
/proc/resolve_fiftyspawner(atom/loc, path, list/varedits)
	var/obj/fiftyspawner/P = path
	var/stack_type = MAP_VAR(P, varedits, type_to_spawn)
	if(!stack_type)
		// Made with a variant key (a compiled map, variant_new()): the resolver runs before the row is applied, so it reads the row itself.
		var/list/row = dq_variant_vars(path, MAP_VAR(P, varedits, variant))
		stack_type = row?["type_to_spawn"]
	if(!stack_type)
		return TRUE
	var/obj/item/stack/M = new stack_type(map_spawn_container(loc), -1)
	if(varedits && ("pixel_y" in varedits))
		M.set_pixel_y(varedits["pixel_y"])
	return TRUE
