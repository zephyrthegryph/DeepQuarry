// A simple turf to fake the appearance of flying.
/turf/simulated/sky
	name = "sky"
	desc = "Hope you don't have a fear of heights."
	icon = 'icons/turf/floors.dmi'
	icon_state = "sky_slow"
	outdoors = OUTDOORS_YES

	// Assume there's a vacuum for the purposes of avoiding active edges at initialization, as well as ZAS fun if a window breaks.
	oxygen = 0
	carbon_dioxide = 0
	nitrogen = 0
	phoron = 0

CAPABILITIES(/turf/simulated/sky)
	param(nameof(sky_color), pos = 1)

/// The sky's glow (its constructor param).
/turf/simulated/sky/var/sky_color = "#FFFFFF"

// ALLOW(init/INSTANCE_STATE): the sky glows its colour
/turf/simulated/sky/Initialize(mapload)
	. = ..()
	// SSplanets.addTurf(src) Handled by parent
	set_light(2, 2, sky_color)

/turf/simulated/sky/north
	dir = NORTH

/turf/simulated/sky/south
	dir = SOUTH

/turf/simulated/sky/east
	dir = EAST

/turf/simulated/sky/west
	dir = WEST



/turf/simulated/sky/moving
	icon_state = "sky_fast"

/turf/simulated/sky/moving/north
	dir = NORTH

/turf/simulated/sky/moving/south
	dir = SOUTH

/turf/simulated/sky/moving/east
	dir = EAST

/turf/simulated/sky/moving/west
	dir = WEST
