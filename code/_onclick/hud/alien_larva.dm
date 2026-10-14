/mob/living/carbon/alien/create_mob_hud(datum/hud/HUD, apply_to_client = TRUE)
	..()

	HUD.set_ui_style('icons/mob/screen1_alien.dmi')

	var/atom/movable/screen/using

	using = new /atom/movable/screen()
	using.name = "mov_intent"
	using.set_dir(SOUTHWEST)
	using.set_icon(HUD.ui_style)
	using.set_icon_state((m_intent == I_RUN ? "running" : "walking"))
	using.screen_loc = ui_acti
	using.layer = HUD_LAYER
	rel_add(HUD, nameof(HUD.adding), using)
	rel_set(HUD, nameof(HUD.move_intent), using) // owned by HUD.adding

	rel_set(hud_used, nameof(/datum/hud::healths), new /atom/movable/screen())
	hud_used?.healths?.icon = HUD.ui_style
	hud_used?.healths?.icon_state = "health0"
	hud_used?.healths?.name = "health"
	hud_used?.healths?.screen_loc = ui_alien_health

	if(client && apply_to_client)
		client.screen = list()
		client.screen += list(hud_used?.healths)
		if(length(HUD.adding))
			client.screen += HUD.adding
		if(length(HUD.other))
			client.screen += HUD.other
		client.screen += client.void
