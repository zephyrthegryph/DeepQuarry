/// The map's fixed fabric: CentCom, the beach, the planet edge, the overmap. One open turf like any other, except that it is
/// indestructible (TURF_INDESTRUCTIBLE: nothing builds on it, rebuilds it, dissolves it or consecrates it) and it takes no part in
/// the gas field (blocks_air: gas neither enters nor leaves it, and a reading of it is vacuum), which is how the old unsimulated
/// turfs behaved. The air an isolated area wants is a subtype that sets blocks_air = FALSE.
/turf/open/fixed
	name = "command"
	oxygen = MOLES_O2STANDARD
	nitrogen = MOLES_N2STANDARD
	flags = TURF_ACID_IMMUNE | TURF_INDESTRUCTIBLE
	blocks_air = TRUE

/turf/open/fixed/fake_space
	name = "\proper space"
	icon = 'icons/turf/space.dmi'
	icon_state = "0"
	dynamic_lighting = FALSE

/// The star field by where the tile lies.
/turf/open/fixed/fake_space/draw(datum/look/look)
	..()
	look.state("[((x + y) ^ ~(x * y) + z) % 25]")
