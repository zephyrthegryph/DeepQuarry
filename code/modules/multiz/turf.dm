/// Multiz support override for CanZPass
/turf/proc/CanZPass(atom/A, direction, recursive = FALSE)
	if(recursive)
		return FALSE
	if(z == A.z) //moving FROM this turf
		return direction == UP //can't go below
	else
		if(direction == UP) //on a turf below, trying to enter
			return FALSE
		if(direction == DOWN) //on a turf above, trying to enter
			var/turf/above = GetAbove(src)
			return !density && above?.CanZPass(A, direction, TRUE) // do not call the function again, only accept overrides that return TRUE for a direction

/// Multiz support override for CanZPass
/turf/simulated/open/CanZPass(atom, direction)
	return TRUE

/// Multiz support override for CanZPass
/turf/space/CanZPass(atom, direction)
	return TRUE

/// The turf `T` in direction `dir` from this one is being deleted.
/turf/proc/multiz_turf_del(turf/T, dir)
	if(z_transparency && dir == DOWN)
		z_transparency_update()

/// A new turf `T` appeared in direction `dir` from this one.
/turf/proc/multiz_turf_new(turf/T, dir)
	if(z_transparency && dir == DOWN)
		z_transparency_update()

//
// Open Space - "empty" turf that lets stuff fall thru it to the layer below
//

GLOBAL_DATUM_INIT(openspace_backdrop_one_for_all, /atom/movable/openspace_backdrop, new)

/atom/movable/openspace_backdrop
	name = "openspace_backdrop"

	anchored = TRUE

	icon = 'icons/turf/floors.dmi'
	icon_state = "grey"
	plane = OPENSPACE_BACKDROP_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	vis_flags = VIS_INHERIT_ID

/turf/simulated/open
	name = "open space"
	icon = 'icons/turf/floors.dmi'
	icon_state = "invisible"
	desc = "Watch your step!"
	density = FALSE
	plane = OPENSPACE_PLANE
	pathweight = 100000 //Seriously, don't try and path over this one numbnuts
	dynamic_lighting = 0 // Someday lets do proper lighting z-transfer.  Until then we are leaving this off so it looks nicer.
	can_build_into_floor = TRUE
	can_dirty = FALSE // It's open space
	can_start_dirty = FALSE


/turf/simulated/open/Initialize(mapload)
	. = ..()
	ASSERT(HasBelow(z))

/turf/simulated/open/runtime_after_init()
	return TRUE

/// Shows the level below, once it exists.
/turf/simulated/open/sim_after_init(datum/act/timer/A)
	..()
	make_z_transparent(FALSE)

/turf/simulated/open/Entered(atom/movable/mover, atom/oldloc)
	..()
	mover.fall()

/turf/simulated/open/proc/update()
	for(var/atom/movable/A in turf_contents_of_type(src, /atom/movable))
		A.fall()

// Called when thrown object lands on this turf.
/turf/simulated/open/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	. = ..()
	source.fall()

/turf/simulated/open/examine(mob/user, distance, infix, suffix)
	. = ..()
	if(Adjacent(user))
		var/depth = 1
		for(var/T = GetBelow(src); isopenspace(T); T = GetBelow(T))
			depth += 1
		. += "It is about [depth] levels deep."

/// The edges of the stronger turfs around it (edge_spill, kept by the adjacency index) and the backdrop.
/turf/simulated/open/draw(datum/look/look)
	..()
	for(var/image/spill_image as anything in edge_spill)
		look.overlay(spill_image)
	look.overlay(GLOB.openspace_backdrop_one_for_all) //Special grey square for projecting backdrop darkness filter on it.

/turf/simulated/open/edges_changed(mask)
	..()
	var/list/spill = edge_spill_overlays()
	if(!same_images(edge_spill, spill))
		set_edge_spill(spill)

// Straight copy from space.
CAPABILITIES(/turf/simulated/open)
	op("open_space_build", item(/obj/item), label("Build"), then(PROC_REF(open_space_build)))

/// Old attackby, a straight copy from space: rods build a lattice, tiles plate it, cable is laid.
/turf/simulated/open/proc/open_space_build(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/C = A.held
	if (istype(C, /obj/item/stack/rods))
		var/obj/structure/lattice/L = locate(/obj/structure/lattice, src)
		if(L)
			return OP_PASS
		var/obj/item/stack/rods/R = C
		if (R.use(1))
			to_chat(user, span_notice("Constructing support lattice ..."))
			play_sfx(src, SFX_WEAPONS_GENHIT)
			ReplaceWithLattice()
		return OP_PASS

	if (istype(C, /obj/item/stack/tile/floor))
		var/obj/structure/lattice/L = locate(/obj/structure/lattice, src)
		if(L)
			var/obj/item/stack/tile/floor/S = C
			if (S.get_amount() < 1)
				return OP_PASS
			spent(L)
			play_sfx(src, SFX_WEAPONS_GENHIT)
			S.use(1)
			ChangeTurf(/turf/simulated/floor/airless)
			return OP_PASS
		else
			to_chat(user, span_warning("The plating is going to need some support."))

	//To lay cable.
	if(istype(C, /obj/item/stack/cable_coil))
		var/obj/item/stack/cable_coil/coil = C
		coil.turf_place(src, user)
		return OP_PASS
	return OP_PASS

//Most things use is_plating to test if there is a cover tile on top (like regular floors)
/turf/simulated/open/is_plating()
	return TRUE

/turf/simulated/open/is_space()
	var/turf/below = GetBelow(src)
	return !below || below.is_space()

/turf/simulated/open/is_solid_structure()
	return locate(/obj/structure/lattice, src) //counts as solid structure if it has a lattice (same as space)

/turf/simulated/open/is_safe_to_enter(mob/living/L)
	if(L.can_fall())
		for(var/obj/O in contents)
			if(!O.CanFallThru(L, GetBelow(src)))
				return TRUE // Can't fall through this, like lattice or catwalk.
	return ..()

/turf/simulated/floor/glass
	name = "glass floor"
	desc = "Dont jump on it, or do, I'm not your mom."
	icon = 'icons/turf/flooring/glass.dmi'
	icon_state = "glass-0"
	base_icon_state = "glass"

// /turf/simulated/floor/glass/setup_broken_states()
//	return list("glass-damaged1", "glass-damaged2", "glass-damaged3")

/// No base sprite: the smooth overlays are the floor (the normal icon would show behind them).
/turf/simulated/floor/glass/draw(datum/look/look)
	..()
	look.state("")

/turf/simulated/floor/glass/runtime_after_init()
	return TRUE

/// Shows the level below and blends with the glass around it, once that exists.
/turf/simulated/floor/glass/sim_after_init(datum/act/timer/A)
	..()
	make_z_transparent(TRUE)
	blend_icons()

// TG's icon blending method because I don't want to redo all the icon states AAA

//Redefinitions of the diagonal directions so they can be stored in one var without conflicts
/turf/simulated/floor/glass/proc/blend_icons()
	var/new_junction = NONE

	for(var/direction in GLOB.cardinal) //GLOB.cardinal case first.
		var/turf/T = get_step(src, direction)
		if(istype(T, type))
			new_junction |= direction

	if(!(new_junction & (NORTH|SOUTH)) || !(new_junction & (EAST|WEST)))
		icon_state = "[base_icon_state]-[new_junction]"
		return

	if(new_junction & NORTH)
		if(new_junction & WEST)
			var/turf/T = get_step(src, NORTHWEST)
			if(istype(T, type))
				new_junction |= (1<<7)

		if(new_junction & EAST)
			var/turf/T = get_step(src, NORTHEAST)
			if(istype(T, type))
				new_junction |= (1<<4)

	if(new_junction & SOUTH)
		if(new_junction & WEST)
			var/turf/T = get_step(src, SOUTHWEST)
			if(istype(T, type))
				new_junction |= (1<<6)

		if(new_junction & EAST)
			var/turf/T = get_step(src, SOUTHEAST)
			if(istype(T, type))
				new_junction |= (1<<5)

	icon_state = "[base_icon_state]-[new_junction]"

/turf/simulated/floor/glass/reinforced
	name = "reinforced glass floor"
	desc = "Do jump on it, it can take it."
	icon = 'icons/turf/flooring/reinf_glass.dmi'
	icon_state = "reinf_glass-0"
	base_icon_state = "reinf_glass"

// /turf/simulated/floor/glass/reinforced/setup_broken_states()
//	return list("reinf_glass-damaged1", "reinf_glass-damaged2", "reinf_glass-damaged3")

/turf/simulated/open
	dynamic_lighting = 1 //I don't care if there's no true multiz lighting, this looks so much nicer it's not even funny -KK

