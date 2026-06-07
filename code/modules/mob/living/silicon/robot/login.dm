/mob/living/silicon/robot/Login()
	..()
	regenerate_icons()
	update_hud()

	show_laws(0)

	// Override the DreamSeeker macro with the borg version!
	client.set_hotkeys_macro("borgmacro", "borghotkeymode")
	// DQEdit — force hotkey mode; non-hotkey disabled in this fork.
	winset(client, null, "mainwindow.macro=borghotkeymode;hotkey_toggle.is-checked=true;mapwindow.map.focus=true")

	repick_laws()

	// DQEdit Start — Replaced upstream pick_module() with chargen-driven
	// apply. The popup is gone for good; see
	// code/modules/mob/living/silicon/robot/cyborg_spawn.dm.
	// Forces synths to select an icon relevant to their module
	apply_cyborg_chargen_prefs_or_default()
	// DQEdit End

	plane_holder.set_vis(VIS_AUGMENTED, TRUE)
