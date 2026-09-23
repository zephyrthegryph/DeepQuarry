//Unsimulated


// Some turfs to make floors look better in centcom tram station.


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


// === merged from maps/ during hard-fork flatten ===


/datum/decl/flooring/rock/cetus
	icon_base = "rock_brown"


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
