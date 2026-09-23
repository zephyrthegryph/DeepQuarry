/mob/living/silicon/robot/Login()
	..()
	regenerate_icons()
	update_hud()

	show_laws(0)

	repick_laws()

	// Replaced upstream pick_module() with chargen-driven
	// apply. The popup is gone for good; see
	// code/modules/mob/living/silicon/robot/cyborg_spawn.dm.
	// Forces synths to select an icon relevant to their module
	apply_cyborg_chargen_prefs_or_default()

	plane_holder.set_vis(VIS_AUGMENTED, TRUE)

	if(syndicate)
		apply_syndicate_state()

/mob/living/silicon/robot/Logout()
	clear_traitor_hud()
	return ..()
