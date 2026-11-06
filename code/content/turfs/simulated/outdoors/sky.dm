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
	// A backdrop, not a place: no heat flows into or out of it. A sky tile has no thermal mass (the 2.7 K space and the colder or warmer floors beside it
	// would drag it 10 K or more in a few steps), and nothing stands on it.
	thermal_conductivity = 0

CAPABILITIES(/turf/simulated/sky)
	setup(PROC_REF(apply_initial_sky_glow))
	param(nameof(sky_color), pos = 1)

/// The sky's glow (its constructor param).
/turf/simulated/sky/var/sky_color = "#FFFFFF"

/turf/simulated/sky/proc/apply_initial_sky_glow()
	// SSplanets.addTurf(src) Handled by parent
	set_glow(src, GLOW(2, 2, sky_color))

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
