/mob/living/carbon/alien/create_mob_hud(datum/hud/HUD, apply_to_client = TRUE)
	..()

	HUD.ui_style = 'icons/mob/screen1_alien.dmi'

	var/atom/movable/screen/using

	using = new /atom/movable/screen()
	using.name = "mov_intent"
	using.set_dir(SOUTHWEST)
	using.icon = HUD.ui_style
	using.icon_state = (m_intent == I_RUN ? "running" : "walking")
	using.screen_loc = ui_acti
	using.layer = HUD_LAYER
	own_add(HUD, "adding", using)
	rel_set(HUD, "move_intent", using) // owned by HUD.adding

	own_set(src, "healths", new /atom/movable/screen())
	healths.icon = HUD.ui_style
	healths.icon_state = "health0"
	healths.name = "health"
	healths.screen_loc = ui_alien_health

	if(client && apply_to_client)
		client.screen = list()
		client.screen += list(healths)
		if(length(HUD.adding))
			client.screen += HUD.adding
		if(length(HUD.other))
			client.screen += HUD.other
		client.screen += client.void
