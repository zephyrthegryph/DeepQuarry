// Ported from Haine and WrongEnd with much gratitude!
/* ._.-'~'-._.-'~'-._.-'~'-._.-'~'-._.-'~'-._.-'~'-._.-'~'-._. */
/*-=-=-=-=-=-=-=-=-=-=-=-=-=WHAT-EVER=-=-=-=-=-=-=-=-=-=-=-=-=-*/
/* '~'-._.-'~'-._.-'~'-._.-'~'-._.-'~'-._.-'~'-._.-'~'-._.-'~' */

/obj/effect/wingrille_spawn
	name = "window grille spawner"
	icon = 'icons/obj/structures.dmi'
	icon_state = "wingrille"
	layer = 1.9 // more visible for mappers
	density = TRUE
	anchored = TRUE
	pressure_resistance = 4*ONE_ATMOSPHERE
	can_atmos_pass = ATMOS_PASS_NO
	var/win_path = /obj/structure/window/basic

CAPABILITIES(/obj/effect/wingrille_spawn)
	map_resolver(GLOBAL_PROC_REF(resolve_wingrille), vars = list("id", "win_path"))

/// MAP_RESOLVER for window spawners: records the cell, then (once the load is in place, so every
/// neighbouring spawner is known) builds a grille and windows on the sides without a neighbour.
/proc/resolve_wingrille(atom/loc, path, list/varedits)
	var/obj/effect/wingrille_spawn/P = path
	var/turf/T = get_turf(loc)
	if(!T || !MAP_VAR(P, varedits, win_path) || !SSticker || round_game_state() >= GAME_STATE_FINISHED)
		return TRUE
	LAZYSET(GLOB.map_resolve_scratch["wingrille"], T, path)
	map_resolve_later(GLOBAL_PROC_REF(wingrille_build), T, path, varedits)
	return TRUE

/// Builds one window spawner cell on `T`.
/proc/wingrille_build(turf/T, path, list/varedits)
	var/obj/effect/wingrille_spawn/P = path
	var/win_path = MAP_VAR(P, varedits, win_path)
	var/list/cells = GLOB.map_resolve_scratch["wingrille"]
	if(!locate_within(T, /obj/structure/grille))
		new /obj/structure/grille(T)
	for(var/dir in GLOB.cardinal)
		var/turf/N = get_step(T, dir)
		if(N && cells && cells[N])
			continue
		var/found_connection
		if(N && locate_on(N, /obj/structure/grille))
			for(var/obj/structure/window/W in turf_contents_of_type(N, /obj/structure/window))
				if(W.type == win_path && W.dir == get_dir(N, T))
					found_connection = 1
					spent(W)
		if(!found_connection)
			var/obj/structure/window/new_win = new win_path(T)
			new_win.set_dir(dir)
			wingrille_window_spawned(new_win, path, varedits)

/// Per-type touches on each window a spawner makes.
/proc/wingrille_window_spawned(obj/structure/window/W, path, list/varedits)
	if(ispath(path, /obj/effect/wingrille_spawn/reinforced/crescent))
		W.max_integrity = 1000000
		W.update_integrity(1000000)
	else if(ispath(path, /obj/effect/wingrille_spawn/reinforced/polarized))
		var/obj/effect/wingrille_spawn/reinforced/polarized/P = path
		var/id = MAP_VAR(P, varedits, id)
		var/obj/structure/window/reinforced/polarized/polarized = W
		if(id && istype(polarized))
			polarized.id = id

/obj/effect/wingrille_spawn/reinforced
	name = "reinforced window grille spawner"
	icon_state = "r-wingrille"
	win_path = /obj/structure/window/reinforced

/obj/effect/wingrille_spawn/reinforced/crescent
	name = "Crescent window grille spawner"
	icon_state = "r-wingrille"
	win_path = /obj/structure/window/reinforced

/obj/effect/wingrille_spawn/phoron
	name = "phoron window grille spawner"
	icon_state = "p-wingrille"
	win_path = /obj/structure/window/phoronbasic

/obj/effect/wingrille_spawn/reinforced_phoron
	name = "reinforced phoron window grille spawner"
	icon_state = "pr-wingrille"
	win_path = /obj/structure/window/phoronreinforced

/obj/effect/wingrille_spawn/reinforced/polarized
	name = "polarized window grille spawner"
	color = "#444444"
	win_path = /obj/structure/window/reinforced/polarized
	var/id

