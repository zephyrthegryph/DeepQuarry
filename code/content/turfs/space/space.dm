// reparent /turf/space → /turf/open so vacuum participates in
// LINDA's atmos graph (gas vents to space, breaches depressurize). Default
// initial_gas_mix changed from OPENTURF_DEFAULT_ATMOS to AIRLESS_ATMOS so
// space stays vacuum at spawn instead of inheriting a breathable mix.
/turf/space
	parent_type = /turf/open
	icon = 'icons/turf/space.dmi'
	name = "\proper space"
	icon_state = "default"
	dynamic_lighting = 0
	plane = SPACE_PLANE
	flags = TURF_ACID_IMMUNE
	initial_temperature = T20C
	thermal_conductivity = OPEN_HEAT_TRANSFER_COEFFICIENT
	can_build_into_floor = TRUE
	initial_gas_mix = AIRLESS_ATMOS
	immutable_atmos = TRUE
	var/keep_sprite = FALSE
	var/edge = FALSE //If we're an edge
	var/forced_dirs = 0 //Force this one to pretend it's an overedge turf

/// Starlight and the edge/dust sprite, picked from the turf's position.
/turf/space/proc/space_appearance()
	PRIVATE_PROC(TRUE)
	if(CONFIG_GET(number/starlight))
		update_starlight()

	//Sprite stuff only beyond here
	if(keep_sprite)
		return

	// ~310 k space turfs run this at boot: the map size and the skybox system are read once per turf, into locals.
	var/max_x = world.maxx
	var/max_y = world.maxy
	var/my_edge = edge
	var/my_forced = forced_dirs

	//We might be an edge
	if(y == max_y || my_forced & NORTH)
		my_edge |= NORTH
	else if(y == 1 || my_forced & SOUTH)
		my_edge |= SOUTH

	if(x == 1 || my_forced & WEST)
		my_edge |= WEST
	else if(x == max_x || my_forced & EAST)
		my_edge |= EAST

	var/datum/system/skybox/sky = SSskybox.ready()
	if(my_edge) //Magic edges
		edge = my_edge
		appearance = sky.mapedge_appearance("[my_edge]")
	else //Dust
		var/dust = ((x + y) ^ ~(x * y) + z) % 25
		var/list/dust_by_index = sky.dust_appearance_index()
		if(dust >= 0 && dust < length(dust_by_index))
			appearance = dust_by_index[dust + 1]
		else
			appearance = sky.dust_appearance("[dust]")

/turf/space/proc/toggle_transit(direction)
	if(edge) //Not a great way to do this yet. Maybe we'll come up with one. We could pre-make sprites... or tile the overlay over it?
		return

	var/datum/system/skybox/sky = SSskybox.ready()
	if(!direction) //Stopping our transit
		appearance = sky.dust_cache["[((x + y) ^ ~(x * y) + z) % 25]"]
	else if(direction & (NORTH|SOUTH)) //Starting transit vertically
		var/x_shift = sky.phase_shift_by_x[src.x % (sky.phase_shift_by_x.len - 1) + 1]
		var/transit_state = ((direction & SOUTH ? world.maxy - src.y : src.y) + x_shift)%15
		appearance = sky.speedspace_cache["NS_[transit_state]"]
	else if(direction & (EAST|WEST)) //Starting transit horizontally
		var/y_shift = sky.phase_shift_by_y[src.y % (sky.phase_shift_by_y.len - 1) + 1]
		var/transit_state = ((direction & WEST ? world.maxx - src.x : src.x) + y_shift)%15
		appearance = sky.speedspace_cache["EW_[transit_state]"]

	for(var/atom/movable/AM in turf_contents_of_type(src, /atom/movable))
		if (!atom_rules_of(AM).simulated)
			continue

		if(!AM.anchored)
			AM.throw_at(get_step(src,reverse_direction(direction)), 5, 1)
		else if (istype(AM, /obj/effect/decal))
			spent(AM) //No more space blood coming with the shuttle

/turf/space/is_space()
	return 1

// override for space turfs, since they should never hide anything
/turf/space/levelupdate()
	for(var/obj/O in turf_contents_of_type(src, /obj))
		O.hide(0)

/turf/space/is_solid_structure()
	return locate(/obj/structure/lattice, src) //counts as solid structure if it has a lattice

/turf/space/proc/update_starlight()
	if(locate_in_list(orange(src,1), /turf/simulated))
		set_glow(src, GLOW(CONFIG_GET(number/starlight), null, null))
	else
		set_glow(src, GLOW(0, null, null))

CAPABILITIES(/turf/space)
	setup(PROC_REF(space_appearance), early = TRUE) // assigning appearance replaces the whole appearance: before the chain applies the mapper colour
	// Rods build a lattice (or upgrade the one here to a catwalk), floor tiles plate a lattice, roofing patches the ceiling above.
	op("space_build_lattice", stack(/obj/item/stack/rods, 1), when(not(PROC_REF(has_lattice))), priority(OP_PRIORITY_DEFAULT - 2), label("Build lattice"),
		then(PROC_REF(build_lattice)))
	op("space_upgrade_lattice", item(/obj/item/stack/rods), when(PROC_REF(has_lattice)), priority(OP_PRIORITY_DEFAULT - 2), label("Build catwalk"),
		then(PROC_REF(upgrade_lattice))) // item(), not stack(): the lattice's upgrade() spends the rod itself
	op("space_plate", stack(/obj/item/stack/tile/floor, 1), priority(OP_PRIORITY_DEFAULT - 2), label("Lay plating"),
		needs(req(PROC_REF(lattice_support), because = MSG(space/needs_support))), then(PROC_REF(plate)))
	// The ceiling checks read the level map (GLOB.z_levels), which nothing publishes, so they cannot be requirements yet: patch_ceiling() checks them.
	op("space_patch_ceiling", stack(/obj/item/stack/tile/roofing, 1), priority(OP_PRIORITY_DEFAULT - 2), label("Patch ceiling"), then(PROC_REF(patch_ceiling)))

MSG_DEF_SELF(space/needs_support, span_warning("The plating is going to need some support."))

/// Condition: a lattice is on this turf.
/turf/space/proc/has_lattice(datum/act/op/A)
	return !isnull(locate(/obj/structure/lattice, src))

/// Requirement: plating needs a lattice to rest on.
/turf/space/proc/lattice_support(datum/act/op/A)
	return has_lattice(A) ? null : MSG(space/needs_support)

/turf/space/proc/build_lattice(datum/act/op/A)
	to_chat(A.actor, span_notice("Constructing support lattice ..."))
	play_sfx(src, SFX_WEAPONS_GENHIT)
	ReplaceWithLattice()
	return OP_OK

/turf/space/proc/upgrade_lattice(datum/act/op/A)
	var/obj/structure/lattice/L = locate(/obj/structure/lattice, src)
	L?.upgrade(A.held, A.actor)
	return OP_OK

/turf/space/proc/plate(datum/act/op/A)
	var/obj/structure/lattice/L = locate(/obj/structure/lattice, src)
	spent(L, A.actor)
	play_sfx(src, SFX_WEAPONS_GENHIT)
	ChangeTurf(/turf/simulated/floor/airless)
	return OP_OK

/// Roofing costs 1:1 with a lattice and its plating. Space has no weather of the sort planets with atmospheres do; if that changes, take the rest of the
/// roofing code from code/content/turfs/simulated/floor_attackby.dm.
/turf/space/proc/patch_ceiling(datum/act/op/A)
	var/turf/T = GetAbove(src)
	if(!T)
		return OP_DECLINE
	if(!isopenturf(T))
		to_chat(A.actor, span_warning("There aren't any holes in the ceiling to patch here."))
		return OP_DECLINE
	// Must be built adjacent to an existing floor/wall, no floating floors
	if(!locate_in_list(T.CardinalTurfs(), /turf/simulated/floor) && !locate_in_list(T.CardinalTurfs(), /turf/simulated/wall))
		to_chat(A.actor, span_warning("There's nothing to attach the ceiling to!"))
		return OP_DECLINE
	T.ReplaceWithLattice()
	T.ChangeTurf(/turf/simulated/floor)
	play_sfx(src, SFX_WEAPONS_GENHIT)
	act_message(A.actor, null, MSG_SELF(span_notice("You expand the ceiling.")), MSG_OTHERS(span_notice("%U% expands the ceiling.")))
	return OP_OK

/turf/space/Entered(atom/movable/A)
	. = ..()

	if(edge && ticker_mode() && !density) // !density so 'fake' space turfs don't fling ghosts everywhere
		if(isliving(A))
			var/mob/living/L = A
			if(L?.pulling_target())
				var/atom/movable/pulled = L?.pulling_target()
				L.stop_pulling()
				A?.touch_map_edge()
				pulled.forceMove(L.loc)
				L.continue_pulling(pulled)
			else
				A?.touch_map_edge()
		else
			A?.touch_map_edge()

/turf/space/proc/Sandbox_Spacemove(atom/movable/A as mob|obj)
	var/cur_x
	var/cur_y
	var/next_x
	var/next_y
	var/target_z
	var/list/y_arr

	if(src.x <= 1)
		if(istype(A, /obj/effect/meteor)||istype(A, /obj/effect/space_dust))
			spent(A)
			return

		var/list/cur_pos = src.get_global_map_pos()
		if(!cur_pos) return
		cur_x = cur_pos["x"]
		cur_y = cur_pos["y"]
		next_x = (--cur_x||GLOB.global_map.len)
		y_arr = GLOB.global_map[next_x]
		target_z = y_arr[cur_y]
		if(target_z)
			A.z = target_z
			A.x = world.maxx - 2
			if ((A && A.loc))
				A.loc.Entered(A)
	else if (src.x >= world.maxx)
		if(istype(A, /obj/effect/meteor))
			spent(A)
			return

		var/list/cur_pos = src.get_global_map_pos()
		if(!cur_pos) return
		cur_x = cur_pos["x"]
		cur_y = cur_pos["y"]
		next_x = (++cur_x > GLOB.global_map.len ? 1 : cur_x)
		y_arr = GLOB.global_map[next_x]
		target_z = y_arr[cur_y]
		if(target_z)
			A.z = target_z
			A.x = 3
			if ((A && A.loc))
				A.loc.Entered(A)
	else if (src.y <= 1)
		if(istype(A, /obj/effect/meteor))
			spent(A)
			return
		var/list/cur_pos = src.get_global_map_pos()
		if(!cur_pos) return
		cur_x = cur_pos["x"]
		cur_y = cur_pos["y"]
		y_arr = GLOB.global_map[cur_x]
		next_y = (--cur_y||y_arr.len)
		target_z = y_arr[next_y]
		if(target_z)
			A.z = target_z
			A.y = world.maxy - 2
			if ((A && A.loc))
				A.loc.Entered(A)

	else if (src.y >= world.maxy)
		if(istype(A, /obj/effect/meteor)||istype(A, /obj/effect/space_dust))
			spent(A)
			return
		var/list/cur_pos = src.get_global_map_pos()
		if(!cur_pos) return
		cur_x = cur_pos["x"]
		cur_y = cur_pos["y"]
		y_arr = GLOB.global_map[cur_x]
		next_y = (++cur_y > y_arr.len ? 1 : cur_y)
		target_z = y_arr[next_y]
		if(target_z)
			A.z = target_z
			A.y = 3
			if ((A && A.loc))
				A.loc.Entered(A)
	return

/turf/space/ChangeTurf(turf/N, tell_universe, force_lighting_update, preserve_outdoors)
	return ..(N, tell_universe, 1, preserve_outdoors)
