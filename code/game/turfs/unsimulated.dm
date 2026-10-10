/turf/unsimulated
	name = "command"
	oxygen = MOLES_O2STANDARD
	nitrogen = MOLES_N2STANDARD
	var/skip_init = TRUE // Don't call down the chain, apparently for performance when loading maps at runtime.
	flags = TURF_ACID_IMMUNE
	init_from_table = TRUE

/turf/unsimulated/fake_space
	name = "\proper space"
	icon = 'icons/turf/space.dmi'
	icon_state = "0"
	dynamic_lighting = FALSE
	init_from_table = FALSE

/// The star field by where the tile lies.
/turf/unsimulated/fake_space/draw(datum/look/look)
	..()
	look.state("[((x + y) ^ ~(x * y) + z) % 25]")

// Better nip this just in case.
/turf/unsimulated/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	return FALSE

/turf/unsimulated/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	return FALSE

/turf/unsimulated/occult_act(mob/living/user)
	return FALSE
