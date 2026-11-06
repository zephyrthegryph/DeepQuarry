/obj/fruitspawner //this doesn't need to do anything but make the stack and die so it's light
	name = "fruit spawner"
	desc = "This item spawns harvested seed items."
	icon = 'icons/obj/seeds.dmi'
	icon_state = "no name"
	var/seedtype = null
	var/variant

CAPABILITIES(/obj/fruitspawner)
	variants(nameof(variant), PROC_REF(variant_table))
	map_resolver(GLOBAL_PROC_REF(resolve_fruitspawner), vars = list("seedtype", "variant"))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/fruitspawner/proc/variant_table()
	return GLOB.dq_variants_fruitspawner

/// The map resolver of fruit spawners: one harvest of the seed, into the closet on the tile if any
/// (or into what holds the spawner).
/proc/resolve_fruitspawner(atom/loc, path, list/varedits)
	var/obj/fruitspawner/P = path
	var/seedtype = MAP_VAR(P, varedits, seedtype)
	if(!seedtype)
		// Made with a variant key (a compiled map, variant_new()): the resolver runs before the row is applied, so it reads the row itself.
		var/list/row = dq_variant_vars(path, MAP_VAR(P, varedits, variant))
		seedtype = row?["seedtype"]
	if(!seedtype || !SSplants.seeds[seedtype])
		return TRUE
	var/datum/seed/S = SSplants.seeds[seedtype]
	S.harvest(map_spawn_container(loc), 0, 0, 1)
	return TRUE
