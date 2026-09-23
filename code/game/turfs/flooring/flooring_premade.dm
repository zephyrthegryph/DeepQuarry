/turf/simulated/floor/carpet
	name = "carpet"
	icon = 'icons/turf/flooring/carpet.dmi'
	icon_state = "carpet"
	initial_flooring = /datum/decl/flooring/carpet

/turf/simulated/floor/carpet/bcarpet
	name = "black carpet"
	icon_state = "bcarpet"
	initial_flooring = /datum/decl/flooring/carpet/bcarpet

/turf/simulated/floor/carpet/blucarpet
	name = "blue carpet"
	icon_state = "blucarpet"
	initial_flooring = /datum/decl/flooring/carpet/blucarpet

/turf/simulated/floor/carpet/tealcarpet
	name = "teal carpet"
	icon_state = "tealcarpet"
	initial_flooring = /datum/decl/flooring/carpet/tealcarpet


// Legacy support for existing paths for blue carpet
/turf/simulated/floor/carpet/blue
	name = "blue carpet"
	icon_state = "blucarpet"
	initial_flooring = /datum/decl/flooring/carpet/blucarpet

/turf/simulated/floor/carpet/turcarpet
	name = "tur carpet"
	icon_state = "turcarpet"
	initial_flooring = /datum/decl/flooring/carpet/turcarpet

/turf/simulated/floor/carpet/sblucarpet
	name = "sblue carpet"
	icon_state = "sblucarpet"
	initial_flooring = /datum/decl/flooring/carpet/sblucarpet

/turf/simulated/floor/carpet/gaycarpet
	name = "clown carpet"
	icon_state = "gaycarpet"
	initial_flooring = /datum/decl/flooring/carpet/gaycarpet

/turf/simulated/floor/carpet/purcarpet
	name = "purple carpet"
	icon_state = "purcarpet"
	initial_flooring = /datum/decl/flooring/carpet/purcarpet

/turf/simulated/floor/carpet/oracarpet
	name = "orange carpet"
	icon_state = "oracarpet"
	initial_flooring = /datum/decl/flooring/carpet/oracarpet

/turf/simulated/floor/carpet/brown
	name = "brown carpet"
	icon_state = "brncarpet"
	initial_flooring = /datum/decl/flooring/carpet/browncarpet

/turf/simulated/floor/carpet/blue2
	name = "blue carpet"
	icon_state = "blue1"
	initial_flooring = /datum/decl/flooring/carpet/blucarpet2


/turf/simulated/floor/carpet/purple
	name = "purple carpet"
	icon_state = "purple"
	initial_flooring = /datum/decl/flooring/carpet/purplecarpet


/turf/simulated/floor/bluegrid
	name = "mainframe floor"
	icon = 'icons/turf/flooring/circuit.dmi'
	icon_state = "bcircuit"
	initial_flooring = /datum/decl/flooring/reinforced/circuit

/turf/simulated/floor/greengrid
	name = "mainframe floor"
	icon = 'icons/turf/flooring/circuit.dmi'
	icon_state = "gcircuit"
	initial_flooring = /datum/decl/flooring/reinforced/circuit/green

/turf/simulated/floor/wood
	name = "wooden floor"
	icon = 'icons/turf/flooring/wood_vr.dmi'
	icon_state = "wood"
	initial_flooring = /datum/decl/flooring/wood

/turf/simulated/floor/wood/broken
	icon_state = "wood-broken0" // This gets changed when spawned.

/turf/simulated/floor/wood/broken/LateInitialize()
	. = ..()
	break_tile()

/turf/simulated/floor/wood/sif
	name = "alien wooden floor"
	icon = 'icons/turf/flooring/wood_greyscale.dmi'
	icon_state = "wood"
	initial_flooring = /datum/decl/flooring/wood/sif
	color = "#293c50"

/turf/simulated/floor/wood/sif/broken
	icon_state = "sifwood-broken0" // This gets changed when spawned.

/turf/simulated/floor/wood/sif/broken/LateInitialize()
	. = ..()
	break_tile()


/turf/simulated/floor/wood/alt
	icon = 'icons/turf/flooring/wood_greyscale.dmi'
	initial_flooring = /datum/decl/flooring/wood/alt
	color = "#593c1c"

/turf/simulated/floor/wood/alt/broken
	icon_state = "wood-broken0" // This gets changed when spawned.

/turf/simulated/floor/wood/alt/broken/LateInitialize()
	. = ..()
	break_tile()

/turf/simulated/floor/wood/alt/tile
	icon_state = "wood_tile"
	initial_flooring = /datum/decl/flooring/wood/alt/tile

/turf/simulated/floor/wood/alt/tile/broken
	icon_state = "wood_tile-broken0" // This gets changed when spawned.

/turf/simulated/floor/wood/alt/tile/broken/LateInitialize()
	. = ..()
	break_tile()

/turf/simulated/floor/wood/alt/panel
	icon_state = "wood_panel"
	initial_flooring = /datum/decl/flooring/wood/alt/panel


/turf/simulated/floor/wood/alt/parquet
	icon_state = "wood_parquet"
	initial_flooring = /datum/decl/flooring/wood/alt/parquet

/turf/simulated/floor/wood/alt/parquet/broken
	icon_state = "wood_parquet-broken0" // This gets changed when spawned.

/turf/simulated/floor/wood/alt/parquet/broken/LateInitialize()
	. = ..()
	break_tile()


/turf/simulated/floor/grass
	name = "grass patch"
	icon = 'icons/turf/flooring/grass.dmi'
	icon_state = "grass0"
	can_dirty = FALSE
	initial_flooring = /datum/decl/flooring/grass
	footstep = FOOTSTEP_GRASS
	barefootstep = FOOTSTEP_GRASS
	clawfootstep = FOOTSTEP_GRASS

/turf/simulated/floor/tiled
	name = "floor"
	icon = 'icons/turf/flooring/tiles_vr.dmi'
	icon_state = "tiled"
	initial_flooring = /datum/decl/flooring/tiling

/turf/simulated/floor/tiled/techmaint
	name = "floor"
	icon = 'icons/turf/flooring/tiles_vr.dmi'
	icon_state = "techmaint"
	initial_flooring = /datum/decl/flooring/tiling/new_tile/techmaint

/turf/simulated/floor/tiled/techfloor
	name = "floor"
	icon = 'icons/turf/flooring/techfloor.dmi'
	icon_state = "techfloor_gray"
	initial_flooring = /datum/decl/flooring/tiling/tech

/turf/simulated/floor/tiled/monotile
	name = "floor"
	icon = 'icons/turf/flooring/tiles_vr.dmi'
	icon_state = "monotile"
	initial_flooring = /datum/decl/flooring/tiling/new_tile/monotile


/turf/simulated/floor/tiled/steel_grid
	name = "floor"
	icon = 'icons/turf/flooring/tiles_vr.dmi'
	icon_state = "steel_grid"
	initial_flooring = /datum/decl/flooring/tiling/new_tile/steel_grid

/turf/simulated/floor/tiled/steel_ridged
	name = "floor"
	icon = 'icons/turf/flooring/tiles_vr.dmi'
	icon_state = "steel_ridged"
	initial_flooring = /datum/decl/flooring/tiling/new_tile/steel_ridged

/turf/simulated/floor/tiled/old_tile
	name = "floor"
	icon_state = "tile_full"
	initial_flooring = /datum/decl/flooring/tiling/new_tile
/turf/simulated/floor/tiled/old_tile/white
	color = "#d9d9d9"
/turf/simulated/floor/tiled/old_tile/gray
	color = "#687172"
/turf/simulated/floor/tiled/old_tile/green
	color = "#46725c"


/turf/simulated/floor/tiled/kafel_full
	name = "floor"
	desc = "Ceramic tile flooring."
	icon_state = "kafel_full"
	initial_flooring = /datum/decl/flooring/tiling/new_tile/kafel
/turf/simulated/floor/tiled/kafel_full/purple
	color = "#906987"


/turf/simulated/floor/tiled/techfloor/grid
	name = "floor"
	icon_state = "techfloor_grid"
	initial_flooring = /datum/decl/flooring/tiling/tech/grid

/turf/simulated/floor/reinforced
	name = "reinforced floor"
	icon = 'icons/turf/flooring/tiles.dmi'
	icon_state = "reinforced"
	initial_flooring = /datum/decl/flooring/reinforced

/turf/simulated/floor/reinforced/airless
	oxygen = 0
	nitrogen = 0

/turf/simulated/floor/reinforced/airmix
	oxygen = MOLES_O2ATMOS
	nitrogen = MOLES_N2ATMOS

/turf/simulated/floor/reinforced/nitrogen
	oxygen = 0
	nitrogen = ATMOSTANK_NITROGEN

/turf/simulated/floor/reinforced/oxygen
	oxygen = ATMOSTANK_OXYGEN
	nitrogen = 0

/turf/simulated/floor/reinforced/phoron
	oxygen = 0
	nitrogen = 0
	phoron = ATMOSTANK_PHORON

/turf/simulated/floor/reinforced/carbon_dioxide
	oxygen = 0
	nitrogen = 0
	carbon_dioxide = ATMOSTANK_CO2

/turf/simulated/floor/reinforced/n20
	oxygen = 0
	nitrogen = 0
	nitrous_oxide = ATMOSTANK_NITROUSOXIDE


/turf/simulated/floor/cult
	name = "engraved floor"
	icon = 'icons/turf/flooring/cult.dmi'
	icon_state = "cult"
	initial_flooring = /datum/decl/flooring/reinforced/cult

/turf/simulated/floor/cult/cultify()
	return

/turf/simulated/floor/tiled/dark
	name = "dark floor"
	icon_state = "dark"
	initial_flooring = /datum/decl/flooring/tiling/dark

/turf/simulated/floor/tiled/hydro
	name = "hydro floor"
	icon_state = "hydrofloor"
	initial_flooring = /datum/decl/flooring/tiling/hydro

/turf/simulated/floor/tiled/neutral
	name = "light floor"
	icon_state = "neutral"
	initial_flooring = /datum/decl/flooring/tiling/neutral

/turf/simulated/floor/tiled/red
	name = "red floor"
	color = COLOR_RED_GRAY
	icon_state = "white"
	initial_flooring = /datum/decl/flooring/tiling/red

/turf/simulated/floor/tiled/steel
	name = "steel floor"
	icon_state = "steel"
	initial_flooring = /datum/decl/flooring/tiling/steel

/turf/simulated/floor/tiled/steel_dirty
	name = "steel floor"
	icon_state = "steel_dirty"
	initial_flooring = /datum/decl/flooring/tiling/steel_dirty


/turf/simulated/floor/tiled/asteroid_steel
	icon_state = "asteroidfloor"
	initial_flooring = /datum/decl/flooring/tiling/asteroidfloor


/turf/simulated/floor/tiled/white
	name = "white floor"
	icon_state = "white"
	initial_flooring = /datum/decl/flooring/tiling/white

/turf/simulated/floor/tiled/yellow
	name = "yellow floor"
	color = COLOR_BROWN
	icon_state = "white"
	initial_flooring = /datum/decl/flooring/tiling/yellow


/turf/simulated/floor/tiled/freezer
	name = "tiles"
	icon_state = "freezer"
	initial_flooring = /datum/decl/flooring/tiling/freezer

/turf/simulated/floor/lino
	name = "lino"
	icon = 'icons/turf/flooring/linoleum.dmi'
	icon_state = "lino"
	initial_flooring = /datum/decl/flooring/linoleum


//ATMOS PREMADES
/turf/simulated/floor/reinforced/airless
	name = "vacuum floor"
	initial_gas_mix = AIRLESS_ATMOS
	oxygen = 0
	nitrogen = 0
	temperature = T20C

/turf/simulated/floor/airless
	name = "plating"
	initial_gas_mix = AIRLESS_ATMOS
	oxygen = 0
	nitrogen = 0
	temperature = T20C

/turf/simulated/floor/tiled/airless
	name = "floor"
	initial_gas_mix = AIRLESS_ATMOS
	oxygen = 0
	nitrogen = 0
	temperature = T20C


/turf/simulated/floor/greengrid/nitrogen
	oxygen = 0


// Placeholders

/*
/turf/simulated/floor/beach
/turf/simulated/floor/beach/sand
/turf/simulated/floor/beach/sand/desert
/turf/simulated/floor/beach/coastline
/turf/simulated/floor/beach/water
/turf/simulated/floor/beach/water/ocean
*/
/turf/simulated/floor/plating
/turf/simulated/floor/plating/external // To be overrided by the map files.

//**** Here lives snow ****
/turf/simulated/floor/snow
	name = "snow"
	icon = 'icons/turf/outdoors.dmi'
	icon_state = "snow"
	initial_flooring = /datum/decl/flooring/snow
	var/list/crossed_dirs


// TODO: Move foortprints to a datum-component signal so they can actually be applied to other turf types, like sand, or mud
/turf/simulated/floor/snow/Entered(atom/A)
	if(isliving(A))
		var/mob/living/L = A
		if(dq_get_hovering(L) || L.flying) // Flying things shouldn't make footprints.
			if(L.flying)
				L.adjust_nutrition(-0.5)
			return ..()
		var/mdir = "[A.dir]"
		LAZYSET(crossed_dirs, mdir, 1)
		update_icon()
	. = ..()

/turf/simulated/floor/snow/update_icon()
	..()
	for(var/d in crossed_dirs)
		add_overlay(image(icon = 'icons/turf/outdoors.dmi', icon_state = "snow_footprints", dir = text2num(d)))

//**** Here ends snow ****

/turf/simulated/floor/concrete
	name = "concrete"
	icon = 'icons/turf/concrete.dmi'
	icon_state = "concrete"
	initial_flooring = /datum/decl/flooring/concrete

