GLOBAL_LIST_EMPTY(turf_edge_cache)

/turf
	// If greater than 0, this turf will apply edge overlays on top of other turfs cardinally adjacent to it, if those adjacent turfs are of a different icon_state,
	// and if those adjacent turfs have a lower edge_blending_priority.
	var/edge_blending_priority = 0
	// Outdoors var determines if the game should consider the turf to be 'outdoors', which controls certain things such as weather effects.
	var/outdoors = OUTDOORS_AREA

/area
	// If a turf's `outdoors` variable is set to `OUTDOORS_AREA`,
	// it will decide if it's outdoors or not when being initialized based on this var.
	var/outdoors = OUTDOORS_NO

/turf/simulated/floor/outdoors
	name = "generic ground"
	desc = "Rather boring."
	icon = 'icons/turf/outdoors.dmi'
	icon_state = null
	edge_blending_priority = 1
	outdoors = OUTDOORS_YES			// This variable is used for weather effects.
	can_dirty = FALSE				// Looks hideous with dirt on it.
	can_build_into_floor = TRUE

	// When a turf gets demoted or promoted, this list gets adjusted.  The top-most layer is the layer on the bottom of the list, due to how pop() works.
	//var/list/turf_layers = list(/turf/simulated/floor/outdoors/rocks) CHOMPEdit kill. See outdoors_ch.dm for replacement.

/turf/simulated/floor/Destroy()
	if(is_outdoors())
		SSplanets.removeTurf(src)
	return ..()

/turf/simulated/floor/outdoors/get_dig_loot_type(mob/user, obj/item/W)
	return pick( \
		12;/obj/item/reagent_containers/food/snacks/worm, \
		1;/obj/item/material/knife/machete/hatchet/stone  \
	)

/turf/simulated/floor/outdoors/shovel_can_cultivate()
	return TRUE

// Turfs can decide if they should be indoors or outdoors.
// By default they choose based on their area's setting.
// This helps cut down on ten billion `/outdoors` subtypes being needed.
/turf/proc/is_outdoors()
	return FALSE

/turf/simulated/is_outdoors()
	switch(outdoors)
		if(OUTDOORS_YES)
			return TRUE
		if(OUTDOORS_NO)
			return FALSE
		if(OUTDOORS_AREA)
			var/area/A = loc
			if(A.outdoors == OUTDOORS_YES)
				return TRUE
	return FALSE

/// Makes the turf explicitly outdoors.
/turf/simulated/proc/make_outdoors()
	if(is_outdoors()) // Already outdoors.
		return
	outdoors = OUTDOORS_YES
	SSplanets.addTurf(src)

/// Makes the turf explicitly indoors.
/turf/simulated/proc/make_indoors()
	if(!is_outdoors()) // Already indoors.
		return
	outdoors = OUTDOORS_NO
	SSplanets.removeTurf(src)

/turf/simulated/post_change()
	..()
	// If it was outdoors and still is, it will not get added twice when the planet controller gets around to putting it in.
	if(is_outdoors())
		make_outdoors()
	else
		make_indoors()

/turf/simulated/floor/outdoors/mud
	name = "mud"
	icon_state = "mud_dark"
	edge_blending_priority = 4 // CHOMPedit
	initial_flooring = /datum/decl/flooring/mud
	flags = TURF_CAN_DIG_SHOVEL

/turf/simulated/floor/outdoors/rocks
	name = "rocks"
	desc = "Hard as a rock."
	icon_state = "rock"
	edge_blending_priority = 1
	initial_flooring = /datum/decl/flooring/rock
	dig_exhaustion_chance = TURF_DIG_LOOT_ENDLESS
	flags = TURF_CAN_DIG_SHOVEL

/turf/simulated/floor/outdoors/rocks/shovel_can_cultivate()
	return FALSE // Nope, no growing stuff on rocks

/turf/simulated/floor/outdoors/rocks/caves
	outdoors = OUTDOORS_NO

// This proc adds a 'layer' on top of the turf.
/* CHOMP Removal start
/turf/simulated/floor/outdoors/proc/promote(new_turf_type)
	var/list/new_turf_layer_list = turf_layers.Copy()
	var/list/coords = list(x, y, z)

	new_turf_layer_list.Add(src.type)

	ChangeTurf(new_turf_type)
	var/turf/simulated/floor/outdoors/T = locate(coords[1], coords[2], coords[3])
	if(istype(T))
		T.turf_layers = new_turf_layer_list.Copy()

// This proc removes the topmost layer.
/turf/simulated/floor/outdoors/proc/demote()
	if(!turf_layers.len)
		return // Cannot demote further.
	var/list/new_turf_layer_list = turf_layers.Copy()
	var/list/coords = list(x, y, z)

	ChangeTurf(pop(new_turf_layer_list))
	var/turf/simulated/floor/outdoors/T = locate(coords[1], coords[2], coords[3])
	if(istype(T))
		T.turf_layers = new_turf_layer_list.Copy()
CHOMP Removal End */
// Called by weather processes, and maybe technomancers in the future.
/turf/simulated/floor/proc/chill()
	return

/turf/simulated/floor/outdoors/chill()
	promote(/turf/simulated/floor/outdoors/snow)

/turf/simulated/floor/outdoors/snow/chill()
	return // Todo: Add heavy snow.

/turf/simulated/floor/outdoors/ex_act(severity)
	switch(severity)
		//VOREStation Edit - Outdoor turfs less explosion resistant
		if(1)
			if(prob(66))
				ChangeTurf(get_base_turf_by_area(src))
				return
			demote()
		if(2)
			if(prob(33))
				return
			else if(prob(33))
				demote()
		//VOREStation Edit End
		if(3)
			if(prob(66))
				return
	demote()

/turf/simulated/floor/outdoors/road
	name = "road"
	icon = 'icons/turf/concrete.dmi'
	icon_state = "concrete_dark"
	desc = "Some sort of material composite road."
	edge_blending_priority = -1

/turf/simulated/floor/tiled/asteroid_steel/outdoors
	name = "weathered tiles"
	desc = "Old tiles left out in the elements."
	outdoors = OUTDOORS_YES
	edge_blending_priority = 1

/turf/simulated/floor/outdoors/newdirt
	name = "dirt"
	desc = "Looks dirty."
	icon = 'icons/turf/outdoors_vr.dmi'
	icon_state = "dirt0"
	edge_blending_priority = 2
	initial_flooring = /datum/decl/flooring/outdoors/newdirt
	flags = TURF_CAN_DIG_SHOVEL

/datum/decl/flooring/outdoors/newdirt
	name = "dirt"
	desc = "Looks dirty."
	icon = 'icons/turf/outdoors_vr.dmi'
	icon_base = "dirt0"

/turf/simulated/floor/outdoors/newdirt/Initialize(mapload)
	var/possibledirts = list(
		"dirt0" = 150,
		"dirt1" = 25,
		"dirt2" = 25,
		"dirt3" = 25,
		"dirt4" = 25,
		"dirt5" = 10,
		"dirt6" = 10,
		"dirt7" = 3,
		"dirt8" = 3,
		"dirt9" = 1
	)
	flooring_override = pickweight(possibledirts)
	return ..()


/turf/simulated/floor/outdoors/newdirt_nograss
	name = "dirt"
	desc = "Looks dirty."
	icon = 'icons/turf/outdoors_vr.dmi'
	icon_state = "dirt0"
	edge_blending_priority = 2
	initial_flooring = /datum/decl/flooring/outdoors/newdirt

/turf/simulated/floor/outdoors/newdirt_nograss/Initialize(mapload)
	var/possibledirts = list(
		"dirt0" = 200,
		"dirt6" = 20,
		"dirt7" = 3,
		"dirt8" = 3,
		"dirt9" = 1
	)
	flooring_override = pickweight(possibledirts)
	return ..()

/turf/simulated/floor/outdoors/newdirt_nograss/caves
	outdoors = OUTDOORS_NO

/turf/simulated/floor/outdoors/sidewalk
	name = "sidewalk"
	desc = "Concrete shaped into a path!"
	icon = 'icons/turf/outdoors_vr.dmi'
	icon_state = "sidewalk"
	edge_blending_priority = -1
	movement_cost = -0.5
	initial_flooring = /datum/decl/flooring/outdoors/sidewalk
	can_dirty = TRUE

/datum/decl/flooring/outdoors/sidewalk
	name = "sidewalk"
	desc = "Concrete shaped into a path!"
	icon = 'icons/turf/outdoors_vr.dmi'
	icon_base = "sidewalk"
	has_damage_range = 2
	damage_temperature = T0C+1400
	flags = TURF_REMOVE_CROWBAR | TURF_CAN_BREAK | TURF_CAN_BURN
	build_type = /obj/item/stack/tile/floor/sidewalk
	can_paint = 1
	can_engrave = FALSE

/obj/item/stack/tile/floor/sidewalk
	name = "sidewalk tile"
	singular_name = "floor tile"
	desc = "A stone tile fit for covering a section of floor."
	icon_state = "tile"
	force = 6.0
	matter = list(DEFAULT_WALL_MATERIAL = SHEET_MATERIAL_AMOUNT / 4)
	throwforce = 15.0
	throw_speed = 5
	throw_range = 20
	no_variants = FALSE

/turf/simulated/floor/outdoors/sidewalk/Initialize(mapload)
	var/possibledirts = list(
		"[initial(icon_state)]" = 150,
		"[initial(icon_state)]1" = 3,
		"[initial(icon_state)]2" = 3,
		"[initial(icon_state)]3" = 3,
		"[initial(icon_state)]4" = 3,
		"[initial(icon_state)]5" = 3,
		"[initial(icon_state)]6" = 2,
		"[initial(icon_state)]7" = 2,
		"[initial(icon_state)]8" = 2,
		"[initial(icon_state)]9" = 2,
		"[initial(icon_state)]10" = 2
	)
	flooring_override = pickweight(possibledirts)
	return ..()

/turf/simulated/floor/outdoors/sidewalk/side
	icon_state = "side-walk"
	initial_flooring = /datum/decl/flooring/outdoors/sidewalk/side


/datum/decl/flooring/outdoors/sidewalk/side
	icon_base = "sidewalk"
	build_type = /obj/item/stack/tile/floor/sidewalk/side

/obj/item/stack/tile/floor/sidewalk/side

/turf/simulated/floor/outdoors/sidewalk/slab
	icon_state = "slab"
	initial_flooring = /datum/decl/flooring/outdoors/sidewalk/slab

/datum/decl/flooring/outdoors/sidewalk/slab
	icon_base = "slab"
	build_type = /obj/item/stack/tile/floor/sidewalk/slab

/obj/item/stack/tile/floor/sidewalk/slab/

/turf/simulated/floor/outdoors/sidewalk/slab/city
	icon_state = "cityslab"
	initial_flooring = /datum/decl/flooring/outdoors/sidewalk/slab/city

/datum/decl/flooring/outdoors/sidewalk/slab/city
	icon_base = "cityslab"
	build_type = /obj/item/stack/tile/floor/sidewalk/slab/city

/obj/item/stack/tile/floor/sidewalk/slab/city

/obj/item/stack/tile/floor/concrete //Proper concrete tile.
	name = "concrete tile"
	singular_name = "floor tile"
	desc = "A concrete tile fit for covering a section of floor."
	icon_state = "tile"
	force = 6.0
	matter = list(DEFAULT_WALL_MATERIAL = SHEET_MATERIAL_AMOUNT / 4)
	throwforce = 15.0
	throw_speed = 5
	throw_range = 20
	no_variants = TRUE

/datum/decl/flooring/concrete
	build_type = /obj/item/stack/tile/floor/concrete


// === merged from outdoors_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/turf/simulated/floor/outdoors
	var/demote_to = /turf/simulated/floor/outdoors/rocks

/turf/simulated/floor/outdoors/proc/promote(new_turf_type)
	var/mytype = src.type
	var/list/coords = list(x, y, z)

	ChangeTurf(new_turf_type)
	var/turf/simulated/floor/outdoors/T = locate(coords[1], coords[2], coords[3])
	if(istype(T))
		T.demote_to = mytype

// This proc removes the topmost layer.
/turf/proc/demote()
	return

/turf/simulated/floor/outdoors/demote()
	if(!demote_to)
		return // Cannot demote further.

	ChangeTurf(demote_to, preserve_outdoors = TRUE)

/turf/simulated/floor/outdoors/grass
	demote_to = /turf/simulated/floor/outdoors/dirt

/turf/simulated/floor/outdoors/snow
	demote_to = /turf/simulated/floor/outdoors/dirt

/turf/simulated/floor/outdoors/fur
	demote_to = null

// General sif turf defines for unit test, overridden in map for specific values
/turf/simulated/floor/plating/sif/planetuse

/turf/simulated/mineral/floor/sif

/turf/simulated/open/sif

/turf/simulated/mineral/floor/ignore_mapgen/sif

/turf/simulated/floor/plating/sif/planetuse

/turf/simulated/floor/outdoors/snow/sif/planetuse
	name = "snow"
	icon_state = "snow"
	edge_blending_priority = 6
	movement_cost = 2
	initial_flooring = /datum/decl/flooring/snow

/turf/simulated/floor/outdoors/snow/sif/planetuse/Entered(atom/A)
	if(isliving(A))
		var/mob/living/L = A
		if(dq_get_hovering(L)) // Flying things shouldn't make footprints.
			return ..()
		var/mdir = "[A.dir]"
		crossed_dirs[mdir] = 1
		update_icon()
	. = ..()

/turf/simulated/floor/outdoors/snow/sif/planetuse/update_icon()
	..()
	for(var/d in crossed_dirs)
		add_overlay(image(icon = 'icons/turf/outdoors.dmi', icon_state = "snow_footprints", dir = text2num(d)))

/turf/simulated/floor/outdoors/snow/sif/planetuse/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/shovel))
		to_chat(user, span_notice("You begin to remove \the [src] with your [W]."))
		if(do_after(user, 4 SECONDS * W.toolspeed, src))
			to_chat(user, span_notice("\The [src] has been dug up, and now lies in a pile nearby."))
			new /obj/item/stack/material/snow(src)
			demote()
		else
			to_chat(user, span_notice("You decide to not finish removing \the [src]."))
	else
		..()

/turf/simulated/floor/outdoors/snow/sif/planetuse/attack_hand(mob/user as mob)
	visible_message("[user] starts scooping up some snow.", "You start scooping up some snow.")
	if(do_after(user, 1 SECOND, src))
		var/obj/S = new /obj/item/stack/material/snow(user.loc)
		user.put_in_hands(S)
		visible_message("[user] scoops up a pile of snow.", "You scoop up a pile of snow.")
	return

/turf/simulated/sky/moving/north/sif/planet_fall/find_planet()
	return GLOB.planet_sif

/turf/simulated/floor/outdoors/dirt/sif

/turf/simulated/floor/outdoors/dirt/sif/planetuse

/turf/simulated/floor/outdoors/grass/sif/forest/planetuse

/turf/simulated/floor/outdoors/rocks/sif/planetuse

/turf/simulated/floor/outdoors/mud/sif/planetuse

/turf/simulated/mineral/sif

/turf/simulated/mineral/ignore_mapgen/sif

/turf/simulated/floor/outdoors/grass/sif/planetuse

/turf/simulated/floor/tiled/steel/sif/planetuse

/turf/simulated/floor/tiled/sif/planetuse

/obj/effect/step_trigger/teleporter/planetary_fall/sif/find_planet()
	planet = GLOB.planet_sif
