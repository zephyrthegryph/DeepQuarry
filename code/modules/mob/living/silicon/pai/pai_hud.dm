/atom/movable/screen/pai
	icon = 'icons/mob/pai_hud.dmi'
	var/base_state

/atom/movable/screen/pai/click_with_actor(mob/user, location, control, params)
	. = ..()
	if(!ispAI(user))
		return
	var/mob/living/silicon/pai/p = user
	switch(name)
		if("fold/unfold")
			if(p.loc == p.card)
				p.fold_out()
			else
				p.fold_up()
		if("choose chassis")
			p.choose_chassis()

		if("software interface")
			p.paiInterface()

		if("radio configuration")
			p.radio.tgui_interact(p)

		if("pda")
			p.pda.cmd_pda_open_ui()

		if("communicator")
			p.communicator.activate()

		if("known languages")
			p.check_languages()

		if("software toggle")
			p.refresh_software_status()
			if(p.hud_used.inventory_shown)
				p.hud_used.inventory_shown = 0
				p.client.screen -= p.hud_used.other
			else
				p.hud_used.inventory_shown = 1
				p.client.screen += p.hud_used.other

		if("directives")
			p.directives()

		if("crew manifest")
			p.crew_manifest()

		if("universal translator")
			p.translator()

		if("medical records")
			p.med_records()

		if("security records")
			p.sec_records()

		if("remote signaler")
			p.remote_signal()

		if("atmosphere sensor")
			p.atmos_sensor()

		if("door jack")
			p.door_jack()

		if("ar hud")
			p.ar_hud()

		if("death alarm")
			p.death_alarm()

/atom/movable/screen/pai/pai_fold_display
	name = "fold/unfold"
	icon = 'icons/mob/pai_hud.dmi'

/datum/hud
	/// pAI / simple mob HUDs: every screen shown by the hud toggles (a roster; the screens are owned elsewhere).
	var/list/hud_elements
	/// pAI / simple mob HUDs: screens the hud builds that sit in no other hud list (owned).
	var/list/extra_screens

/mob/living/silicon/pai/create_mob_hud(datum/hud/HUD)
	..()

	var/ui_style = 'icons/mob/pai_hud.dmi'

	var/ui_color = "#ffffff"
	var/ui_alpha = 255


	var/atom/movable/screen/pai/using

	// The combat mode button (it replaced the intent selector).
	var/atom/movable/screen/combat_mode/combat_button = HUD.make_combat_mode_button(src, "intent_help-s", "intent_harm-s")
	combat_button.icon = ui_style
	combat_button.alpha = ui_alpha
	combat_button.layer = LAYER_HUD_ITEM
	rel_add(HUD, nameof(HUD.adding), combat_button)

	//Move intent (walk/run)
	using = new /atom/movable/screen()
	using.name = "mov_intent"
	using.icon = ui_style
	using.icon_state = (m_intent == I_RUN ? "running" : "walking")
	using.screen_loc = ui_movi
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.adding), using)
	rel_set(HUD, nameof(HUD.move_intent), using)

	//Resist button
	using = new /atom/movable/screen()
	using.name = "resist"
	using.icon = ui_style
	using.icon_state = "act_resist"
	using.screen_loc = ui_movi
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.hotkeybuttons), using)

	//Pull button
	rel_set(src, nameof(pullin), rel_add(HUD, nameof(HUD.extra_screens), new /atom/movable/screen()))
	pullin.icon = ui_style
	pullin.icon_state = "pull0"
	pullin.name = "pull"
	pullin.screen_loc = ui_movi
	rel_add(HUD, nameof(HUD.hud_elements), pullin)

	//Health status
	rel_set(src, nameof(healths), new /atom/movable/screen())
	healths.icon = ui_style
	healths.icon_state = "health0"
	healths.name = "health"
	healths.screen_loc = ui_health
	rel_add(HUD, nameof(HUD.hud_elements), healths)

	rel_set(src, nameof(pain), new /atom/movable/screen( null ))

	rel_set(src, nameof(zone_sel), new /atom/movable/screen/zone_sel( null ))
	zone_sel.icon = ui_style
	zone_sel.color = ui_color
	zone_sel.alpha = ui_alpha
	zone_sel.cut_overlays()
	rel_add(HUD, nameof(HUD.hud_elements), zone_sel)

	rel_set(src, nameof(pai_fold_display), new /atom/movable/screen/pai/pai_fold_display())
	pai_fold_display.screen_loc = ui_health
	pai_fold_display.icon_state = "folded"
	rel_add(HUD, nameof(HUD.hud_elements), pai_fold_display)

	//Choose chassis button
	using = new /atom/movable/screen/pai()
	using.name = "choose chassis"
	using.icon_state = "choose_chassis"
	using.screen_loc = ui_movi
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	//Software interface button
	using = new /atom/movable/screen/pai()
	using.name = "software interface"
	using.icon_state = "software_interface"
	using.screen_loc = ui_acti
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	//Radio configuration button
	using = new /atom/movable/screen/pai()
	using.name = "radio configuration"
	using.icon_state = "radio_configuration"
	using.screen_loc = ui_acti
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	//PDA button
	using = new /atom/movable/screen/pai()
	using.name = "pda"
	using.icon_state = "pda"
	using.screen_loc = ui_pai_comms
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	//Communicator button
	using = new /atom/movable/screen/pai()
	using.name = "communicator"
	using.icon_state = "communicator"
	using.screen_loc = ui_pai_comms
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	//Language button
	using = new /atom/movable/screen/pai()
	using.name = "known languages"
	using.icon_state = "language"
	using.screen_loc = ui_acti
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	using = new /atom/movable/screen/pai()
	using.name = "software toggle"
	using.icon_state = "software"
	using.screen_loc = ui_inventory
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	using = new /atom/movable/screen/pai()
	using.name = "directives"
	using.icon_state = "directives"
	using.screen_loc = "WEST:6,SOUTH:18"
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "crew manifest"
	using.icon_state = "manifest"
	using.screen_loc = "WEST:6,SOUTH+1:2"
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "medical records"
	using.base_state = "med_records"
	using.screen_loc = "WEST:6,SOUTH+1:18"
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "security records"
	using.base_state = "sec_records"
	using.screen_loc = "WEST:6,SOUTH+2:2"
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "atmosphere sensor"
	using.base_state = "atmos_sensor"
	using.screen_loc = "WEST:6,SOUTH+2:18"
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "remote signaler"
	using.base_state = "signaller"
	using.screen_loc = "WEST:6,SOUTH+3:2"
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "universal translator"
	using.base_state = "translator"
	using.screen_loc = "WEST:6,SOUTH+3:18"
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "door jack"
	using.base_state = "door_jack"
	using.screen_loc = "WEST:6,SOUTH+4:2"
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "ar hud"
	using.base_state = "ar_hud"
	using.screen_loc = "WEST:6,SOUTH+4:18"
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "death alarm"
	using.base_state = "death_alarm"
	using.screen_loc = "WEST:6,SOUTH+5:2"
	using.color = ui_color
	using.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.other), using)

	rel_set(src, nameof(autowhisper_display), rel_add(HUD, nameof(HUD.extra_screens), new /atom/movable/screen()))
	autowhisper_display.icon = 'icons/mob/screen/minimalist.dmi'
	autowhisper_display.icon_state = "autowhisper"
	autowhisper_display.name = "autowhisper"
	autowhisper_display.screen_loc = "EAST-1:28,CENTER-2:13"
	rel_add(HUD, nameof(HUD.hud_elements), autowhisper_display)

	var/atom/movable/screen/aw = new /atom/movable/screen()
	aw.icon = 'icons/mob/screen/minimalist.dmi'
	aw.icon_state = "aw-select"
	aw.name = "autowhisper mode"
	aw.screen_loc = "EAST-1:28,CENTER-2:13"
	rel_add(HUD, nameof(HUD.extra_screens), aw)
	rel_add(HUD, nameof(HUD.hud_elements), aw)

	aw = new /atom/movable/screen()
	aw.icon = 'icons/mob/screen/minimalist.dmi'
	aw.icon_state = "lang"
	aw.name = "check known languages"
	aw.screen_loc = ui_under_health
	rel_add(HUD, nameof(HUD.extra_screens), aw)
	rel_add(HUD, nameof(HUD.hud_elements), aw)

	aw = new /atom/movable/screen()
	aw.icon = 'icons/mob/screen/minimalist.dmi'
	aw.icon_state = "pose"
	aw.name = "set pose"
	aw.screen_loc = ui_under_health
	rel_add(HUD, nameof(HUD.extra_screens), aw)
	rel_add(HUD, nameof(HUD.hud_elements), aw)

	aw = new /atom/movable/screen()
	aw.icon = 'icons/mob/screen/minimalist.dmi'
	aw.icon_state = "up"
	aw.name = "move upwards"
	aw.screen_loc = ui_under_health
	rel_add(HUD, nameof(HUD.extra_screens), aw)
	rel_add(HUD, nameof(HUD.hud_elements), aw)

	aw = new /atom/movable/screen()
	aw.icon = 'icons/mob/screen/minimalist.dmi'
	aw.icon_state = "down"
	aw.name = "move downwards"
	aw.screen_loc = ui_under_health
	rel_add(HUD, nameof(HUD.extra_screens), aw)
	rel_add(HUD, nameof(HUD.hud_elements), aw)

	if(client)
		client.screen = list()
		client.screen += HUD.hud_elements
		client.screen += HUD.adding
		client.screen += HUD.hotkeybuttons
		client.screen += client.void

	HUD.inventory_shown = 0



/// Its own HUD stays awake (rerun every Life cycle while it has a client).
/mob/living/silicon/pai/life_hud_idle()
	return FALSE

/mob/living/silicon/pai/life_hud()
	. = ..()
	if(!.)
		return

	if(src.pai_fold_display)
		if(src.loc == src.card)
			src.pai_fold_display.icon_state = "folded"
		else
			src.pai_fold_display.icon_state = "unfolded"

/mob/living/silicon/pai/life_hud_health_icons()
	. = ..()
	if(!. || !src.healths)
		return

	src.healths.icon_state = vitality_health_band(src)

/mob/living/silicon/pai/toggle_hud_vis(full)
	if(!client)
		return FALSE

	if(hud_used.hud_shown)
		hud_used.hud_shown = 0
		if(hud_used.adding)
			client.screen -= hud_used.adding
		if(hud_used.other)
			client.screen -= hud_used.other
		if(hud_used.hotkeybuttons)
			client.screen -= hud_used.hotkeybuttons
		if(hud_used.other_important)
			client.screen -= hud_used.other_important
		if(hud_used.hud_elements)
			client.screen -= hud_used.hud_elements

	else
		hud_used.hud_shown = 1
		if(hud_used.adding)
			client.screen += hud_used.adding
		if(hud_used.other && hud_used.inventory_shown)
			client.screen += hud_used.other
		if(hud_used.other_important)
			client.screen += hud_used.other_important
		if(hud_used.hotkeybuttons && !hud_used.hotkey_ui_hidden)
			client.screen += hud_used.hotkeybuttons
		if(healths)
			client.screen |= healths
		if(internals)
			client.screen |= internals
		if(gun_setting_icon)
			client.screen |= gun_setting_icon
		if(hud_used.hud_elements)
			if(length(hud_used.hud_elements)) client.screen |= hud_used.hud_elements

		client.screen += zone_sel				//This one is a special snowflake

	hud_used.hidden_inventory_update()
	hud_used.persistant_inventory_update()
	update_action_buttons()
	hud_used.reorganize_alerts()
	return TRUE
