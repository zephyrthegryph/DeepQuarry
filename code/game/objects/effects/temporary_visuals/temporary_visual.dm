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

CAPABILITIES(/obj/effect/temp_visual)
	rolls(nameof(dir), pick_one(list(NORTH, SOUTH, EAST, WEST)), when = nameof(randomdir))
	lives_for(nameof(duration))

/obj/effect/temp_visual/singularity_act()
	return

/obj/effect/temp_visual/singularity_pull()
	return

/obj/effect/temp_visual/dir_setting
	randomdir = FALSE

CAPABILITIES(/obj/effect/temp_visual/dir_setting)
	param(nameof(dir), pos = 1)

