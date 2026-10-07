/obj/structure/catwalk
	name = "catwalk"
	debris_type = /obj/item/stack/rods
	desc = "Cats really don't like these things."
	icon = 'icons/turf/catwalks.dmi'
	icon_state = "catwalk"
	plane = DECAL_PLANE
	layer = DECAL_LAYER
	density = FALSE
	anchored = TRUE
	var/hatch_open = FALSE
	var/plating_color = null
	var/plated_tile
	var/static/plating_colors = list(
		/obj/item/stack/tile/floor = "#858a8f",
		/obj/item/stack/tile/floor/dark = "#4f4f4f",
		/obj/item/stack/tile/floor/white = "#e8e8e8",
		/obj/item/stack/tile/floor/techmaint = "#4d585b",
		/obj/item/stack/tile/floor/techgrey = "#363f43")
	max_integrity = 100
	var/delete_me = FALSE

/obj/structure/catwalk/Initialize(mapload)
	. = ..()
	if(delete_me)
		return INITIALIZE_HINT_QDEL
	for(var/obj/structure/catwalk/C in get_turf(src))
		if(C != src)
			if(!(C.flags & ATOM_INITIALIZED))
				C.delete_me = TRUE
			else
				consume(C)
	update_connections()

// neighbouring catwalks redraw and things on it may fall.
/obj/structure/catwalk/on_destroy(force)
	update_falling()
	..()

/obj/structure/catwalk/proc/update_falling()
	if(istype(loc, /turf/simulated/open)) after(loc, 0.1 SECONDS, TYPE_PROC_REF(/turf/simulated/open, update)) //We get called in Destroy() and things: the open turf, not us, owns the update.

TRACKED(/obj/structure/catwalk, hatch_open)
TRACKED(/obj/structure/catwalk, plating_color)

/obj/structure/catwalk/draw(datum/look/look)
	..()
	look.state("")
	if(!hatch_open)
		for(var/i = 1 to 4)
			var/connect = connections?[i] || 0
			look.overlay(look_overlay_image(icon, "catwalk[connect]", dir = 1<<(i-1)))
	if(plating_color)
		look.overlay(look_overlay_image(icon, "plated", color = plating_color))

/obj/structure/catwalk
	silicon_use = ROBOT_USE_HAND_ADJACENT

/// `leave_lattice`: sliced outside combat mode, so over open space the lattice stays.
/obj/structure/catwalk/atom_deconstruct(disassembled = TRUE, mob/user, leave_lattice = FALSE)
	play_sfx(src, SFX_ITEMS_WELDER)
	to_chat(user, span_notice("Slicing \the [src] joints ..."))
	//Lattice would delete itself, but let's save ourselves a new obj
	if(isopenspace(loc) && leave_lattice)
		new /obj/structure/lattice/(src.loc)
		new /obj/item/stack/rods(src.loc, 1)
	else
		new /obj/item/stack/rods(src.loc, 2)
	if(plated_tile)
		new plated_tile(src.loc)
	consume(src, user)

/// Old welder use: slice the catwalk apart with a lit welder. Outside combat mode (help) the lattice over open space stays.
/obj/structure/catwalk/proc/interaction_slice(datum/act/op/A)
	atom_deconstruct(TRUE, A.actor, FALSE)
	return OP_OK

/obj/structure/catwalk/proc/interaction_slice_keep(datum/act/op/A)
	atom_deconstruct(TRUE, A.actor, TRUE)
	return OP_OK

/// Old attackby: plate the catwalk with a floor tile stack.
/obj/structure/catwalk/proc/interaction_plate(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/tile/floor/ST = A.held
	to_chat(user, span_notice("Placing tile..."))
	task_timed(user, 1 SECOND, target = src, receiver = src, on_done = PROC_REF(plate_done), done_args = list(user, ST))
	return OP_OK

/obj/structure/catwalk/proc/plate_done(mob/user, obj/item/stack/tile/floor/ST)
	if(plated_tile || !ST.use(1))
		return
	to_chat(user, span_notice("You plate \the [src]"))
	name = "plated catwalk"
	set_plated_tile(ST.type)
	add_fingerprint(user)
	for(var/tiletype in plating_colors)
		if(istype(ST, tiletype))
			set_plating_color(plating_colors[tiletype])

TRACKED(/obj/structure/catwalk, plated_tile)

CAPABILITIES(/obj/structure/catwalk)
	smoothing()
	op("slice_keep", tool(TOOL_WELDER), stance(I_HELP), label("Slice apart, keeping the lattice"), wait(0), needs(req_welder_lit()), costs(RES_FUEL, 0), then(PROC_REF(interaction_slice_keep)))
	op("slice", tool(TOOL_WELDER), stance(I_DISARM, I_GRAB, I_HURT), label("Slice apart"), wait(0), needs(req_welder_lit()), costs(RES_FUEL, 0), then(PROC_REF(interaction_slice)))
	op("plate", item(/obj/item/stack/tile/floor), label("Plate"), when(cond_not(nameof(plated_tile))), then(PROC_REF(interaction_plate)))
	op("use_crowbar", tool(TOOL_CROWBAR), wait(0), then(PROC_REF(crowbar_used)))

/obj/structure/catwalk/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	if(plated_tile)
		set_hatch_open(!hatch_open)
		if(hatch_open)
			play_sfx(src, SFX_ITEMS_CROWBAR, 2)
			to_chat(user, span_notice("You pry open \the [src]'s maintenance hatch."))
			update_falling()
		else
			play_sfx(src, SFX_ITEMS_DECONSTRUCT, 2)
			to_chat(user, span_notice("You shut \the [src]'s maintenance hatch."))
	return OP_OK

/obj/structure/catwalk/refresh_neighbors()
	return

/obj/structure/catwalk/atom_destruction(damage_flag)
	if(dq_destroy_effects_once(src))
		visible_message(span_warning("\The [src] breaks down!"))
		play_sfx(src, SFX_EFFECTS_GRILLEHIT)
	return ..()

/obj/structure/catwalk/Crossed(atom/movable/AM)
	. = ..()
	if(isliving(AM) && !AM.is_incorporeal())
		play_sfx(src, SFX_EFFECTS_FOOTSTEP_CATWALK)

/obj/effect/catwalk_plated
	name = "plated catwalk spawner"
	icon = 'icons/turf/catwalks.dmi'
	icon_state = "catwalk_plated"
	density = TRUE
	anchored = TRUE
	plane = DECAL_PLANE
	layer = DECAL_LAYER
	var/tile = /obj/item/stack/tile/floor
	var/platecolor = "#858a8f"

MAP_RESOLVER(/obj/effect/catwalk_plated, GLOBAL_PROC_REF(resolve_catwalk_plated))
MAP_RESOLVER_VARS(/obj/effect/catwalk_plated, "platecolor;tile")

/// MAP_RESOLVER for plated catwalk spawners: once the load is in place, a plated catwalk (unless
/// the tile already has one).
/proc/resolve_catwalk_plated(atom/loc, path, list/varedits)
	map_resolve_later(GLOBAL_PROC_REF(catwalk_plated_build), get_turf(loc), path, varedits)
	return TRUE

/proc/catwalk_plated_build(turf/T, path, list/varedits)
	var/obj/effect/catwalk_plated/P = path
	if(!T)
		return
	if(locate_within(T, /obj/structure/catwalk))
		WARNING("Frame Spawner: A catwalk already exists at [T.x]-[T.y]-[T.z]")
		return
	var/obj/structure/catwalk/C = new /obj/structure/catwalk(T)
	C.set_plated_tile(MAP_VAR(P, varedits, tile))
	C.set_plating_color(MAP_VAR(P, varedits, platecolor))
	C.name = "plated catwalk"

/obj/effect/catwalk_plated/dark
	icon_state = "catwalk_plateddark"
	tile = /obj/item/stack/tile/floor/dark
	platecolor = "#4f4f4f"

/obj/effect/catwalk_plated/white
	icon_state = "catwalk_platedwhite"
	tile = /obj/item/stack/tile/floor/white
	platecolor = "#e8e8e8"

/obj/effect/catwalk_plated/techmaint
	icon_state = "catwalk_techmaint"
	tile = /obj/item/stack/tile/floor/techmaint
	platecolor = "#4d585b"

/obj/effect/catwalk_plated/techfloor
	icon_state = "catwalk_techfloor"
	tile = /obj/item/stack/tile/floor/techgrey
	platecolor = "#363f43"

