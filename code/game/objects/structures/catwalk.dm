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
	update_icon()

// neighbouring catwalks redraw and things on it may fall.
/obj/structure/catwalk/on_destroy(force)
	update_falling()
	..()

/obj/structure/catwalk/proc/update_falling()
	if(istype(loc, /turf/simulated/open)) after(loc, 0.1 SECONDS, TYPE_PROC_REF(/turf/simulated/open, update)) //We get called in Destroy() and things: the open turf, not us, owns the update.

DECLARE_APPEARANCE_PROC(/obj/structure/catwalk, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/catwalk/appearance_overlays()
	. = list()
	update_connections()
	icon_state = ""
	var/image/I
	if(!hatch_open)
		for(var/i = 1 to 4)
			var/connect = connections?[i] || 0
			I = image(icon, "catwalk[connect]", dir = 1<<(i-1))
			. += I
	if(plating_color)
		I = image(icon, "plated")
		I.color = plating_color
		. += I

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

/obj/structure/catwalk/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/catwalk_plate,
		/datum/interaction/catwalk_slice/help,
		/datum/interaction/catwalk_slice/disarm,
		/datum/interaction/catwalk_slice/grab,
		/datum/interaction/catwalk_slice/harm,
	)
	..()

/// Abstract: slice the catwalk apart with a lit welder. Outside combat mode the lattice over open space stays.
/datum/interaction/catwalk_slice
	name = "Slice apart"
	category = INTERACTION_CAT_MAINTAIN
	priority = 10
	default_action = INPUT_ACTION_USE
	tool = TOOL_WELDER
	tool_volume = 0
	requires = list(REQ_REACH_ADJACENT)
	effect = /obj/structure/catwalk/proc/interaction_slice

/datum/interaction/catwalk_slice/help
	id = "catwalk_slice_help"
	name = "Slice apart, keeping the lattice"
	stance = I_HELP

/datum/interaction/catwalk_slice/disarm
	id = "catwalk_slice_disarm"
	stance = I_DISARM

/datum/interaction/catwalk_slice/grab
	id = "catwalk_slice_grab"
	stance = I_GRAB

/datum/interaction/catwalk_slice/harm
	id = "catwalk_slice_harm"
	stance = I_HURT

/obj/structure/catwalk/proc/interaction_slice(mob/user, obj/item/C, datum/interaction/interaction)
	var/obj/item/weldingtool/WT = C.get_welder()
	if(WT.isOn() && WT.remove_fuel(0, user))
		atom_deconstruct(TRUE, user, interaction.stance == I_HELP)
	return TRUE

/// Old attackby: plate the catwalk with a floor tile stack.
/datum/interaction/entry_item/catwalk_plate
	id = "catwalk_plate"
	name = "Plate"
	held_type = /obj/item/stack/tile/floor
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/structure/catwalk/proc/catwalk_not_plated, null))
	effect = /obj/structure/catwalk/proc/interaction_plate

/obj/structure/catwalk/proc/catwalk_not_plated(mob/actor, atom/target, obj/item/held)
	return !plated_tile

/obj/structure/catwalk/proc/interaction_plate(mob/user, obj/item/stack/tile/floor/ST, datum/interaction/interaction)
	to_chat(user, span_notice("Placing tile..."))
	om_task_timed(user, 1 SECOND, target = src, receiver = src, on_done = PROC_REF(plate_done), done_args = list(user, ST))
	return TRUE

/obj/structure/catwalk/proc/plate_done(mob/user, obj/item/stack/tile/floor/ST)
	if(plated_tile || !ST.use(1))
		return
	to_chat(user, span_notice("You plate \the [src]"))
	name = "plated catwalk"
	plated_tile = ST.type
	add_fingerprint(user)
	for(var/tiletype in plating_colors)
		if(istype(ST, tiletype))
			plating_color = plating_colors[tiletype]
	update_icon()

CAPABILITIES(/obj/structure/catwalk)
	smoothing()
	op("use_crowbar", tool(TOOL_CROWBAR), wait(0), then(PROC_REF(crowbar_used)))

/obj/structure/catwalk/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	if(plated_tile)
		hatch_open = !hatch_open
		if(hatch_open)
			play_sfx(src, SFX_ITEMS_CROWBAR, 2)
			to_chat(user, span_notice("You pry open \the [src]'s maintenance hatch."))
			update_falling()
		else
			play_sfx(src, SFX_ITEMS_DECONSTRUCT, 2)
			to_chat(user, span_notice("You shut \the [src]'s maintenance hatch."))
		update_icon()
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
	C.plated_tile = MAP_VAR(P, varedits, tile)
	C.plating_color = MAP_VAR(P, varedits, platecolor)
	C.name = "plated catwalk"
	C.update_icon()

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

