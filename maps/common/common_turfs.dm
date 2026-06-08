//Unsimulated

/turf/unsimulated/mineral/virgo3b
	blocks_air = TRUE

/turf/unsimulated/floor/steel
	icon = 'icons/turf/flooring/tiles_vr.dmi'
	icon_state = "steel"

// Some turfs to make floors look better in centcom tram station.

/turf/unsimulated/floor/techfloor_grid
	name = "floor"
	icon = 'icons/turf/flooring/techfloor.dmi'
	icon_state = "techfloor_grid"

///Used for train.dmm
/turf/unsimulated/floor/techfloor_grid/outdoors_tansit
	icon = 'icons/turf/transit_vr.dmi'
	outdoors = TRUE

/turf/unsimulated/floor/maglev
	name = "maglev track"
	desc = "Magnetic levitation tram tracks. Caution! Electrified!"
	icon = 'icons/turf/flooring/maglevs.dmi'
	icon_state = "maglevup"

/turf/unsimulated/floor/maglev/transit
	icon = 'icons/turf/transit_vr.dmi'
	outdoors = TRUE

/turf/unsimulated/wall/transit
	icon = 'icons/turf/transit_vr.dmi'

/turf/unsimulated/wall/transit/outdoors
	outdoors = TRUE

/turf/unsimulated/floor/transit
	icon = 'icons/turf/transit_vr.dmi'

//Unsim turf to constantly fill the atmos in the area. Made for v5_outpost_build
/turf/unsimulated/floor/steel/v5_snow
	carbon_dioxide = 75
	icon = 'icons/turf/outdoors.dmi'
	icon_state = "snow"
	nitrogen = 17
	outdoors = 1
	oxygen = 8
	temperature = 150

/obj/effect/floor_decal/transit/orange
	icon = 'icons/turf/transit_vr.dmi'
	icon_state = "transit_techfloororange_edges"

/obj/effect/transit/light
	icon = 'icons/turf/transit_128.dmi'
	icon_state = "tube1-2"

VIRGO3B_TURF_CREATE(/turf/simulated/floor/outdoors/dirt)
/turf/simulated/floor/outdoors/dirt/virgo3b
	icon = 'icons/turf/flooring/asteroid.dmi'
	icon_state = "asteroid"

VIRGO3B_TURF_CREATE(/turf/simulated/floor/outdoors/grass/sif)
/turf/simulated/floor/outdoors/grass/sif
	/* 
	turf_layers = list(
		/turf/simulated/floor/outdoors/rocks/virgo3b,
		/turf/simulated/floor/outdoors/dirt/virgo3b
		)
	*/

VIRGO3B_TURF_CREATE(/turf/simulated/floor/outdoors/rocks)
VIRGO3B_TURF_CREATE(/turf/simulated/floor/tiled/steel_dirty)
VIRGO3B_TURF_CREATE(/turf/simulated/floor/water/indoors)
VIRGO3B_TURF_CREATE(/turf/simulated/open)
VIRGO3B_TURF_CREATE(/turf/simulated/floor)
VIRGO3B_TURF_CREATE(/turf/simulated/mineral)
VIRGO3B_TURF_CREATE(/turf/simulated/mineral/floor)
VIRGO3B_TURF_CREATE(/turf/simulated/floor/plating/external)
VIRGO3B_TURF_CREATE(/turf/simulated/floor/reinforced)

// Bluespace jump turf!
/turf/space/bluespace
	name = "bluespace"
	icon = 'icons/turf/space_vr.dmi'
	icon_state = "bluespace"

// Desert jump turf!
/turf/space/sandyscroll
	name = "sand transit"
	icon = 'icons/turf/transit_vr.dmi'
	icon_state = "desert_ns"

//Sky stuff!
// A simple turf to fake the appearance of flying.
/turf/simulated/sky/virgo3b
	color = "#FFBBBB"

/turf/simulated/sky/virgo3b/Initialize(mapload)
	. = ..(mapload, color)

/turf/simulated/sky/virgo3b/north
	dir = NORTH
/turf/simulated/sky/virgo3b/south
	dir = SOUTH
/turf/simulated/sky/virgo3b/east
	dir = EAST
/turf/simulated/sky/virgo3b/west
	dir = WEST

/turf/simulated/sky/virgo3b/moving
	icon_state = "sky_fast"
/turf/simulated/sky/virgo3b/moving/north
	dir = NORTH
/turf/simulated/sky/virgo3b/moving/south
	dir = SOUTH
/turf/simulated/sky/virgo3b/moving/east
	dir = EAST
/turf/simulated/sky/virgo3b/moving/west
	dir = WEST

/turf/simulated/floor/midpoint_glass
	name = "glass floor"
	desc = "Dont jump on it, or do, I'm not your mom."
	icon = 'icons/turf/flooring/glass.dmi'
	icon_state = "glass-0"
	base_icon_state = "glass"

/turf/simulated/floor/midpoint_glass/reinf
	name = "reinforced glass floor"
	desc = "Do jump on it, it can take it."
	icon = 'icons/turf/flooring/reinf_glass.dmi'
	icon_state = "reinf_glass-0"
	base_icon_state = "reinf_glass"

/turf/simulated/floor/midpoint_glass/Initialize(mapload)
	. = ..()
	return INITIALIZE_HINT_LATELOAD

/turf/simulated/floor/midpoint_glass/LateInitialize()
	do_icons()

/turf/simulated/floor/midpoint_glass/proc/do_icons()
	var/new_junction = NONE

	for(var/direction in GLOB.cardinal) //Cardinal case first.
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

	add_vis_overlay('icons/effects/effects.dmi', "white", plane = SPACE_PLANE, add_vis_flags = VIS_INHERIT_ID|VIS_UNDERLAY)

/turf/space/v3b_midpoint

// Tram transit floor
/turf/simulated/floor/tiled/techfloor/grid/transit
	icon = 'icons/turf/transit_vr.dmi'
	initial_flooring = null

/turf/unsimulated/floor/sky/virgo2_sky
	name = "virgo 2 atmosphere"
	desc = "Be careful where you step!"
	color = "#eacd7c"
	VIRGO2_SET_ATMOS

/turf/simulated/shuttle/wall/voidcraft/green/virgo2
	VIRGO2_SET_ATMOS
	color = "#eacd7c"

/turf/simulated/shuttle/wall/voidcraft/green/virgo2/nocol
	color = null

VIRGO2_TURF_CREATE(/turf/unsimulated/wall/planetary)

VIRGO2_TURF_CREATE(/turf/simulated/wall)
VIRGO2_TURF_CREATE(/turf/simulated/floor/plating)
VIRGO2_TURF_CREATE(/turf/simulated/floor/bluegrid)
VIRGO2_TURF_CREATE(/turf/simulated/floor/tiled/techfloor)

VIRGO2_TURF_CREATE(/turf/simulated/mineral)

VIRGO2_TURF_CREATE(/turf/simulated/mineral/ignore_mapgen)
VIRGO2_TURF_CREATE(/turf/simulated/mineral/floor)
VIRGO2_TURF_CREATE(/turf/simulated/mineral/floor/ignore_mapgen)

VIRGO2_TURF_CREATE(/turf/simulated/floor/hull)

/turf/simulated/mineral/vacuum/gb_mine

/turf/simulated/floor/virgo3b_indoors
	VIRGO3B_SET_ATMOS
/turf/simulated/floor/virgo3b_indoors/update_graphic(list/graphic_add = null, list/graphic_remove = null)
	return 0

/turf/simulated/floor/virgo3b_indoors/dirt
	desc = "Quite dirty!"
	icon = 'icons/turf/outdoors.dmi'
	icon_state = "dirt-dark"
	name = "dirt"


// === merged from maps/ during hard-fork flatten ===


/turf/simulated/mineral/thor

/turf/simulated/mineral/thor/ignore_oregen
	ignore_oregen = TRUE

/turf/simulated/mineral/thor/ignore_cavegen
	ignore_cavegen = TRUE

/turf/simulated/mineral/thor/ignore_mapgen
	ignore_mapgen = TRUE

/turf/simulated/mineral/thor/floor

/turf/simulated/mineral/thor/floor/ignore_oregen
	ignore_oregen = TRUE

/turf/simulated/mineral/thor/floor/ignore_cavegen
	ignore_cavegen = TRUE

/turf/simulated/mineral/thor/floor/ignore_mapgen
	ignore_mapgen = TRUE


/turf/simulated/mineral/thor/floor/cave
	name = "basalt"
	desc = "Loose, rocky basalt. It crumbles to sand under the slightest bit of force."
	icon_state = "basalt0"
	icon = 'icons/turf/thor.dmi'

/turf/simulated/mineral/thor/mines
	name = "dark rock"
	desc = "Dark black basalt. Rich in exotic minerals."
	icon_state = "deeprock"
	icon = 'icons/turf/thor.dmi'
	temperature = 393.15

/turf/unsimulated/mineral/thor/mines
	name = "impassable dark rock"
	desc = "Dark black basalt. Packed impossibly tightly, no way to get past this."
	icon_state = "deeprock-solid"
	icon = 'icons/turf/thor.dmi'
	temperature = 393.15

/turf/simulated/mineral/thor/floor/ignore_mapgen/cave
	name = "basalt"

/turf/simulated/mineral/thor/ignore_mapgen/cave
	name = "dark rock"

// default shuttle roof type - blanket define our shuttle area ceiling type, we have multi-Zs and the default is none.
/turf/simulated/floor/reinforced/airless/shuttleroof
	// A special type just to make sure we don't delete airless reinforced when shuttles depart

/turf/unsimulated/wall/seperator //to block vision between transit zones
	name = ""
	icon = 'icons/effects/effects.dmi'
	icon_state = "1"

/turf/simulated/mineral/cetus
	desc = "Solid rock"
	floor_name = "rocks"
	outdoors = FALSE
	ignore_cavegen = TRUE
	sand_icon_path = 'icons/turf/outdoors.dmi'
	sand_icon_state = "rock_brown"
	oxygen		= MOLES_O2STANDARD
	nitrogen	= MOLES_N2STANDARD
	temperature = T20C

/turf/simulated/mineral/cetus/Initialize(mapload)
	if(!ignore_mapgen && prob(5))
		turf_resource_types |= TURF_HAS_ORE
	. = ..()


/turf/simulated/floor/outdoors/rocks/cetus
	name = "rocks"
	outdoors = FALSE
	icon_state = "rock_brown"
	oxygen		= MOLES_O2STANDARD
	nitrogen	= MOLES_N2STANDARD
	temperature = T20C
	initial_flooring = /datum/decl/flooring/rock/cetus
	flags = TURF_UNSHIELDABLE

/datum/decl/flooring/rock/cetus
	icon_base = "rock_brown"

/turf/simulated/mineral/cetus/edge
	name = "cold rock"
	desc = "Solid rock. It's cool to the touch. Digging through this will probably expose the area to hard vacuum!"
	outdoors = TRUE
	sand_icon_path = 'icons/turf/outdoors.dmi'
	sand_icon_state = "rock_brown"
	icon_state = "rock-dark"
	ignore_mapgen = TRUE
	oxygen = 0
	nitrogen = 0
	temperature = TCMB

/turf/simulated/floor/outdoors/rocks/cetus/edge
	outdoors = TRUE
	icon_state = "rock_brown"
	oxygen = 0
	nitrogen = 0
	temperature = TCMB
	flags = null

/turf/simulated/floor/outdoors/mud/cetus
	flags = TURF_UNSHIELDABLE
	outdoors = FALSE

/turf/simulated/floor/water/indoors/station
	name = "shallow water"
	oxygen		= MOLES_O2STANDARD
	nitrogen	= MOLES_N2STANDARD
	temperature = T20C

/turf/simulated/floor/water/deep/indoors/station
	oxygen		= MOLES_O2STANDARD
	nitrogen	= MOLES_N2STANDARD
	temperature = T20C

/turf/simulated/floor/water/hotspring/station
	oxygen		= MOLES_O2STANDARD
	nitrogen	= MOLES_N2STANDARD
	temperature = T20C

/turf/simulated/floor/water/pool/station
	oxygen		= MOLES_O2STANDARD
	nitrogen	= MOLES_N2STANDARD
	temperature = T20C

/turf/simulated/floor/water/deep/pool/station
	oxygen		= MOLES_O2STANDARD
	nitrogen	= MOLES_N2STANDARD
	temperature = T20C


/turf/simulated/floor/carpet/graycarpet
	name = "gray carpet"
	desc = "A dusty, gray carpeted floor."
	icon = 'icons/turf/flooring/carpet.dmi'
	icon_state = "gcarpet"
	initial_flooring = /datum/decl/flooring/carpet/gray

/datum/decl/flooring/carpet/gray
	name = "gray carpet"
	desc = "A dusty, gray carpeted floor."
	icon = 'icons/turf/flooring/carpet.dmi'
	icon_base = "gcarpet"
	build_type = /obj/item/stack/tile/carpet/gray
	flags = TURF_REMOVE_CROWBAR | TURF_CAN_BURN

/obj/item/stack/tile/carpet/gray
	name = "gray carpet"
	icon_state = "tile"
	desc = "A piece dusty, gray carpet. It is the same size as a normal floor tile!"
