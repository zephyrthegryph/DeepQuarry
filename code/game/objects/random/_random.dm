/// A map spawner: resolved at map time by its DECLARE_LOOT (code/datums/loot/loot.dm,
/// resolve_loot()); it never becomes a live atom.
/obj/random
	name = "random object"
	desc = "This item type is used to spawn random objects at round-start"
	icon = 'icons/misc/random_spawners.dmi'
	icon_state = "generic"
	/// Spawn on the turf (TRUE) or inside what holds the spawner (a crate, for supply packs).
	var/drop_get_turf = TRUE

// Junk: 20% clutter, 56% trash and remains, 24% small useful items.
DECLARE_LOOT(/loot/junk/useful, LOOT_TABLE(	LOOT_TYPES(1, subtypesof(/obj/item/pen/crayon)), 	/obj/item/pen, 	/obj/item/pen/blue, 	/obj/item/pen/red, 	/obj/item/pen/multi, 	/obj/item/storage/box/matches, 	/obj/item/stack/material/cardboard))

DECLARE_LOOT(/loot/junk/trash, LOOT_TABLE(	LOOT_TYPES(1, subtypesof(/obj/item/trash) - list(/obj/item/trash/plate, /obj/item/trash/snack_bowl, /obj/item/trash/syndi_cakes, /obj/item/trash/tray)), 	/obj/effect/decal/cleanable/bug_remains, 	/obj/effect/decal/remains/mouse, 	/obj/effect/decal/remains/robot, 	/obj/item/paper/crumpled, 	/obj/item/inflatable/torn, 	/obj/effect/decal/cleanable/molten_item, 	/obj/item/material/shard))

/////////////////////////////////////////////////////////////////////////

/// Multiple object spawn: its declaration's table entries are LOOT_SETs.
/obj/random/multiple

/*
//	Multi Point Spawn
//	Selects one spawn point out of a group of points with the same ID and asks it to generate its items
*/
/// Multi-point spawn groups: group id -> list(list(turf, item path) = weight). Rows are recorded
/// at map time (resolve_random_multi()); at round start one row per group spawns its item.
GLOBAL_LIST_EMPTY(multi_point_spawns)

/obj/random_multi
	name = "random object spawn point"
	desc = "This item type is used to spawn random objects at round-start. Only one spawn point for a given group id is selected."
	icon = 'icons/misc/random_spawners.dmi'
	icon_state = "generic_3"
	invisibility = INVISIBILITY_MAXIMUM
	var/id     // Group id
	var/weight // Probability weight for this spawn point

/obj/random_multi/single_item
	var/item_path  // Item type to spawn

CAPABILITIES(/obj/random_multi)
	map_resolver(GLOBAL_PROC_REF(resolve_random_multi), vars = list("id", "item_path", "weight"))

/// MAP_RESOLVER for multi-point spawn points: a weighted row in the point's group.
/proc/resolve_random_multi(atom/loc, path, list/varedits)
	var/turf/T = get_turf(loc)
	if(!T || !ispath(path, /obj/random_multi/single_item))
		return TRUE
	var/obj/random_multi/single_item/P = path
	var/id = MAP_VAR(P, varedits, id)
	var/list/spawnpoints = GLOB.multi_point_spawns[id]
	if(!spawnpoints)
		spawnpoints = list()
		GLOB.multi_point_spawns[id] = spawnpoints
	spawnpoints[list(T, MAP_VAR(P, varedits, item_path))] = max(1, round(MAP_VAR(P, varedits, weight)))
	return TRUE

/// Round start: one point per group spawns its item (a loot declaration rolls).
/proc/spawn_multi_point_items()
	for(var/id, value in GLOB.multi_point_spawns)
		var/list/row = pickweight(value)
		if(row)
			loot_spawn(row[2], row[1])
	GLOB.multi_point_spawns.Cut()
