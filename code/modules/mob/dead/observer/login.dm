//Nobody here anymore.
/mob/observer/dead/Login()
	..() //Creates the plane_holder lazily
	hud_used?.plane_holder?.set_vis(VIS_GHOSTS, ghostvision)
	hud_used?.plane_holder?.set_vis(VIS_FULLBRIGHT, !seedarkness)
	hud_used?.plane_holder?.set_vis(VIS_CLOAKED, TRUE)
	hud_used?.plane_holder?.set_vis(VIS_AI_EYE, TRUE)
	hud_used?.plane_holder?.set_vis(VIS_AUGMENTED, TRUE) // GHOST VISION IS AUGMENTED
	hud_used?.plane_holder?.set_vis(VIS_SOULCATCHER, TRUE) // Soulcatcher
	set_plane(PLANE_GHOSTS)
	expire(null)
