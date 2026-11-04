// This is a wall you surround the area of your "planet" with, that makes the atmosphere inside stay within bounds, even if canisters
// are opened or other strange things occur.
/turf/open/fixed/wall/planetary
	name = "railroading"
	desc = "Choo choo!"
	icon = 'icons/turf/walls.dmi'
	icon_state = "riveted"
	opacity = 1
	density = TRUE
	alpha = 0

	// Set these to get your desired planetary atmosphere.
	oxygen = 0
	nitrogen = 0
	carbon_dioxide = 0
	phoron = 0
	initial_temperature = T20C

/turf/open/fixed/wall/planetary/proc/register_planetary_turf()
	SSplanets.addTurf(src)

/// Phase 2: leaves its planet's turf set.
/turf/open/fixed/wall/planetary/lifecycle_dematerialize()
	. = ..()
	SSplanets.removeTurf(src)

/turf/open/fixed/wall/planetary/solid_temperature_set()
	// was: ZAS connections.erase_all() + SSair.mark_for_update.
	// LINDA equivalent: rebuild this turf's adjacency (so superconductivity
	// re-evaluates with the new temperature) and queue it for the next SSair
	// pass.
	air_update_turf(TRUE, FALSE)

// Normal station/earth air.
/turf/open/fixed/wall/planetary/normal
	oxygen = MOLES_O2STANDARD
	nitrogen = MOLES_N2STANDARD

// Wiki says it's 92.6 kPa, composition 18.1% O2 80.8% N2 1.1% trace.  We're gonna pretend trace is actually nitrogen.
/turf/open/fixed/wall/planetary/sif
	oxygen		= 114.50978 * 0.181
	nitrogen	= 114.50978 * 0.819
	initial_temperature	= 243.15 // Roughly -30C / -22F

//High Alt Sif
/turf/open/fixed/wall/planetary/sif/alt
	initial_temperature	= 225.15


CAPABILITIES(/turf/open/fixed/wall/planetary)
	setup(PROC_REF(register_planetary_turf))
