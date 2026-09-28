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
	temperature = T20C
	thermal_conductivity = OPEN_HEAT_TRANSFER_COEFFICIENT
	can_build_into_floor = TRUE
	initial_gas_mix = AIRLESS_ATMOS
	immutable_atmos = TRUE
	var/keep_sprite = FALSE
	var/edge = FALSE //If we're an edge
	var/forced_dirs = 0 //Force this one to pretend it's an overedge turf

/turf/space/Initialize(mapload)
	if(CONFIG_GET(number/starlight))
		update_starlight()

	//Sprite stuff only beyond here
	if(keep_sprite)
		return ..()

	//We might be an edge
	if(y == world.maxy || forced_dirs & NORTH)
		edge |= NORTH
	else if(y == 1 || forced_dirs & SOUTH)
		edge |= SOUTH

	if(x == 1 || forced_dirs & WEST)
		edge |= WEST
	else if(x == world.maxx || forced_dirs & EAST)
		edge |= EAST

	if(edge) //Magic edges
		appearance = skybox_service().mapedge_cache["[edge]"]
	else //Dust
		appearance = skybox_service().dust_cache["[((x + y) ^ ~(x * y) + z) % 25]"]

	return ..()

/turf/space/proc/toggle_transit(direction)
	if(edge) //Not a great way to do this yet. Maybe we'll come up with one. We could pre-make sprites... or tile the overlay over it?
		return

	if(!direction) //Stopping our transit
		appearance = skybox_service().dust_cache["[((x + y) ^ ~(x * y) + z) % 25]"]
	else if(direction & (NORTH|SOUTH)) //Starting transit vertically
		var/x_shift = skybox_service().phase_shift_by_x[src.x % (skybox_service().phase_shift_by_x.len - 1) + 1]
		var/transit_state = ((direction & SOUTH ? world.maxy - src.y : src.y) + x_shift)%15
		appearance = skybox_service().speedspace_cache["NS_[transit_state]"]
	else if(direction & (EAST|WEST)) //Starting transit horizontally
		var/y_shift = skybox_service().phase_shift_by_y[src.y % (skybox_service().phase_shift_by_y.len - 1) + 1]
		var/transit_state = ((direction & WEST ? world.maxx - src.x : src.x) + y_shift)%15
		appearance = skybox_service().speedspace_cache["EW_[transit_state]"]

	for(var/atom/movable/AM in turf_contents_of_type(src, /atom/movable))
		if (!AM.simulated)
			continue

		if(!AM.anchored)
			AM.throw_at(get_step(src,reverse_direction(direction)), 5, 1)
		else if (istype(AM, /obj/effect/decal))
			qdel(AM) //No more space blood coming with the shuttle

/turf/space/is_space()
	return 1

// override for space turfs, since they should never hide anything
/turf/space/levelupdate()
	for(var/obj/O in turf_contents_of_type(src, /obj))
		O.hide(0)

/turf/space/is_solid_structure()
	return locate(/obj/structure/lattice, src) //counts as solid structure if it has a lattice

/turf/space/proc/update_starlight()
	if(locate(/turf/simulated) in orange(src,1))
		set_light(CONFIG_GET(number/starlight))
	else
		set_light(0)

EXTEND_INTERACTIONS(/turf/space, INTERACT_ITEM("Build", PROC_REF(space_build)))

/// Old attackby: rods build a lattice, tiles plate it, roofing patches the ceiling.
/turf/space/proc/space_build(mob/user, obj/item/C, datum/interaction/interaction)

	if(istype(C, /obj/item/stack/rods))
		var/obj/structure/lattice/L = locate(/obj/structure/lattice, src)
		if(L)
			L.upgrade(C, user)
			return INTERACTION_HANDLED_PASS
		var/obj/item/stack/rods/R = C
		if (R.use(1))
			to_chat(user, span_notice("Constructing support lattice ..."))
			playsound(src, 'sound/weapons/genhit.ogg', 50, 1)
			ReplaceWithLattice()
		return INTERACTION_HANDLED_PASS

	if(istype(C, /obj/item/stack/tile/floor))
		var/obj/structure/lattice/L = locate(/obj/structure/lattice, src)
		if(L)
			var/obj/item/stack/tile/floor/S = C
			if (S.get_amount() < 1)
				return INTERACTION_HANDLED_PASS
			qdel(L)
			playsound(src, 'sound/weapons/genhit.ogg', 50, 1)
			S.use(1)
			ChangeTurf(/turf/simulated/floor/airless)
			return INTERACTION_HANDLED_PASS
		else
			to_chat(user, span_warning("The plating is going to need some support."))

	if(istype(C, /obj/item/stack/tile/roofing))
		var/turf/T = GetAbove(src)
		var/obj/item/stack/tile/roofing/R = C

		// Patch holes in the ceiling
		if(T)
			if(isopenturf(T))
				// Must be build adjacent to an existing floor/wall, no floating floors
				var/turf/simulated/A = locate(/turf/simulated/floor) in T.CardinalTurfs()
				if(!A)
					A = locate(/turf/simulated/wall) in T.CardinalTurfs()
				if(!A)
					to_chat(user, span_warning("There's nothing to attach the ceiling to!"))
					return INTERACTION_HANDLED_PASS

				if(R.use(1)) // Cost of roofing tiles is 1:1 with cost to place lattice and plating
					T.ReplaceWithLattice()
					T.ChangeTurf(/turf/simulated/floor)
					playsound(src, 'sound/weapons/genhit.ogg', 50, 1)
					user.visible_message(span_notice("[user] expands the ceiling."), span_notice("You expand the ceiling."))
			else
				to_chat(user, span_warning("There aren't any holes in the ceiling to patch here."))
				return INTERACTION_HANDLED_PASS
		// Space shouldn't have weather of the sort planets with atmospheres do.
		// If that's changed, then you'll want to swipe the rest of the roofing code from code/game/turfs/simulated/floor_attackby.dm
	return INTERACTION_HANDLED_PASS

/turf/space/Entered(atom/movable/A)
	. = ..()

	if(edge && SSticker?.mode && !density) // !density so 'fake' space turfs don't fling ghosts everywhere
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
			qdel(A)
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
			qdel(A)
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
			qdel(A)
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
			qdel(A)
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
