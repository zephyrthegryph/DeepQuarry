/obj/structure/lattice
	name = "lattice"
	desc = "A lightweight support lattice."
	icon = 'icons/obj/structures.dmi'
	icon_state = "latticefull"
	density = FALSE
	anchored = TRUE
	w_class = ITEMSIZE_NORMAL
	plane = PLATING_PLANE

/obj/structure/lattice/Initialize(mapload)
	. = ..()

	if(!(isopenturf(src.loc) || ismineralturf(src.loc) || istype(src.loc, /turf/simulated/shuttle/plating/airless/carry)))
		return INITIALIZE_HINT_QDEL

	for(var/obj/structure/lattice/LAT in src.loc)
		if(LAT != src)
			// log_mapping("Found multiple lattices at '[log_info_line(loc)]'") // We do this on map lint level. This messes with random seed genned maps where such can happen in rare cases
			return INITIALIZE_HINT_QDEL
	icon = 'icons/obj/smoothlattice.dmi'
	icon_state = "latticeblank"
	if(mapload)
		// Every mapped lattice exists before any initializes, and each draws itself here: no
		// deferred redraw for it or its neighbours (that was up to five timers per lattice,
		// about 2,900 wheel entries queued at boot on Southern Cross).
		update_overlays_now()
		return
	updateOverlays()
	for (var/dir in GLOB.cardinal)
		var/obj/structure/lattice/L
		if(locate(/obj/structure/lattice, get_step(src, dir)))
			L = locate(/obj/structure/lattice, get_step(src, dir))
			L.updateOverlays()

// neighbour lattices redraw and what it held up falls.
/obj/structure/lattice/on_destroy(force)
	for (var/dir in GLOB.cardinal)
		var/obj/structure/lattice/L
		if(locate(/obj/structure/lattice, get_step(src, dir)))
			L = locate(/obj/structure/lattice, get_step(src, dir))
			L.updateOverlays(src.loc)
	if(istype(loc, /turf/simulated/open))
		var/turf/simulated/open/O = loc
		after(O, 0.1 SECONDS, TYPE_PROC_REF(/turf/simulated/open, update)) // This lattice may be supporting things on top of it.  If it's being deleted, they need to fall down.
	..()

/obj/structure/lattice/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/C = A.held
	if(istype(C, /obj/item/stack/tile/floor))
		var/turf/T = get_turf(src)
		T.attackby(C, user) //BubbleWrap - hand this off to the underlying turf instead
		return TRUE
	if(istype(C, /obj/item/stack/rods))
		upgrade(C, user)
		return TRUE
	return TRUE

CAPABILITIES(/obj/structure/lattice)
	op("use_welder", tool(TOOL_WELDER), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/obj/structure/lattice/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/C = A.held
	var/obj/item/weldingtool/WT = C.get_welder()
	if(WT.welding && WT.remove_fuel(0, user))
		to_chat(user, span_notice("Slicing lattice joints ..."))
		replace_with(src, /obj/item/stack/rods, 1)
	return OP_OK

/// Redraws next tick; requests before then share the one pending redraw.
/obj/structure/lattice/proc/updateOverlays()
	if(after_pending(src, "overlays"))
		return
	after(src, 0.1 SECONDS, PROC_REF(update_overlays_now), key = "overlays")

// Moves upgrading lattices to their own proc for other stuff to call. Also makes them instant.
/obj/structure/lattice/proc/upgrade(obj/item/stack/rods/R, mob/user)
	to_chat(user, span_notice("You start connecting \the [R.name] to \the [src.name] ..."))
	R.use(1)
	src.alpha = 0 // Note: I don't know why this is set, Eris did it, just trusting for now. ~Leshana
	replace_with(src, /obj/structure/catwalk)

/obj/structure/lattice/proc/update_overlays_now()
	cut_overlays()

	var/dir_sum = 0

	for (var/direction in GLOB.cardinal)
		if(locate(/obj/structure/lattice, get_step(src, direction)))
			dir_sum += direction
		else
			if(!(istype(get_step(src, direction), /turf/space)))
				dir_sum += direction

	icon_state = "lattice[dir_sum]"
	return
