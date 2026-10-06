//temporary visual effects
/obj/effect/temp_visual
	resistance_flags = BOMB_PROOF
	icon = 'icons/effects/effects.dmi'
	icon_state = "nothing"
	anchored = TRUE
	layer = ABOVE_MOB_LAYER
	mouse_opacity = 0
	var/duration = 10 //in deciseconds
	var/randomdir = TRUE

/obj/effect/temp_visual/Initialize(mapload)
	. = ..()
	if(randomdir)
		dir = pick(list(NORTH, SOUTH, EAST, WEST))
	expire(duration)

/obj/effect/temp_visual/singularity_act()
	return

/obj/effect/temp_visual/singularity_pull()
	return

/obj/effect/temp_visual/dir_setting
	randomdir = FALSE

// ALLOW(init/CTOR_ARGS): set_dir is a constructor argument from whoever builds it
/obj/effect/temp_visual/dir_setting/Initialize(mapload, set_dir)
	if(set_dir)
		dir = set_dir
	. = ..()
