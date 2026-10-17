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
	combat_button.set_icon(ui_style)
	combat_button.set_alpha(ui_alpha)
	combat_button.set_layer(LAYER_HUD_ITEM)
	rel_add(HUD, nameof(HUD.adding), combat_button)

	//Move intent (walk/run)
	using = new /atom/movable/screen()
	using.name = "mov_intent"
	using.set_icon(ui_style)
	using.set_icon_state((m_intent == I_RUN ? "running" : "walking"))
	using.screen_loc = ui_movi
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.adding), using)
	rel_set(HUD, nameof(HUD.move_intent), using)

	//Resist button
	using = new /atom/movable/screen()
	using.name = "resist"
	using.set_icon(ui_style)
	using.set_icon_state("act_resist")
	using.screen_loc = ui_movi
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.hotkeybuttons), using)

	//Pull button
	rel_set(hud_used, nameof(/datum/hud::pullin), rel_add(HUD, nameof(HUD.extra_screens), new /atom/movable/screen()))
	hud_used?.pullin?.icon = ui_style
	hud_used?.pullin?.icon_state = "pull0"
	hud_used?.pullin?.name = "pull"
	hud_used?.pullin?.screen_loc = ui_movi
	rel_add(HUD, nameof(HUD.hud_elements), hud_used?.pullin)

	//Health status
	rel_set(hud_used, nameof(/datum/hud::healths), new /atom/movable/screen())
	hud_used?.healths?.icon = ui_style
	hud_used?.healths?.icon_state = "health0"
	hud_used?.healths?.name = "health"
	hud_used?.healths?.screen_loc = ui_health
	rel_add(HUD, nameof(HUD.hud_elements), hud_used?.healths)

	rel_set(hud_used, nameof(/datum/hud::pain), new /atom/movable/screen( null ))

	rel_set(hud_used, nameof(/datum/hud::zone_sel), new /atom/movable/screen/zone_sel( null ))
	hud_used?.zone_sel?.icon = ui_style
	hud_used?.zone_sel?.color = ui_color
	hud_used?.zone_sel?.alpha = ui_alpha
	rel_add(HUD, nameof(HUD.hud_elements), hud_used?.zone_sel)

	rel_set(src, nameof(pai_fold_display), new /atom/movable/screen/pai/pai_fold_display())
	pai_fold_display.screen_loc = ui_health
	pai_fold_display.set_icon_state("folded")
	rel_add(HUD, nameof(HUD.hud_elements), pai_fold_display)

	//Choose chassis button
	using = new /atom/movable/screen/pai()
	using.name = "choose chassis"
	using.set_icon_state("choose_chassis")
	using.screen_loc = ui_movi
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	//Software interface button
	using = new /atom/movable/screen/pai()
	using.name = "software interface"
	using.set_icon_state("software_interface")
	using.screen_loc = ui_acti
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	//Radio configuration button
	using = new /atom/movable/screen/pai()
	using.name = "radio configuration"
	using.set_icon_state("radio_configuration")
	using.screen_loc = ui_acti
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	//PDA button
	using = new /atom/movable/screen/pai()
	using.name = "pda"
	using.set_icon_state("pda")
	using.screen_loc = ui_pai_comms
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	//Communicator button
	using = new /atom/movable/screen/pai()
	using.name = "communicator"
	using.set_icon_state("communicator")
	using.screen_loc = ui_pai_comms
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	//Language button
	using = new /atom/movable/screen/pai()
	using.name = "known languages"
	using.set_icon_state("language")
	using.screen_loc = ui_acti
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	using = new /atom/movable/screen/pai()
	using.name = "software toggle"
	using.set_icon_state("software")
	using.screen_loc = ui_inventory
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.extra_screens), using)
	rel_add(HUD, nameof(HUD.hud_elements), using)

	using = new /atom/movable/screen/pai()
	using.name = "directives"
	using.set_icon_state("directives")
	using.screen_loc = "WEST:6,SOUTH:18"
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "crew manifest"
	using.set_icon_state("manifest")
	using.screen_loc = "WEST:6,SOUTH+1:2"
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "medical records"
	using.base_state = "med_records"
	using.screen_loc = "WEST:6,SOUTH+1:18"
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "security records"
	using.base_state = "sec_records"
	using.screen_loc = "WEST:6,SOUTH+2:2"
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "atmosphere sensor"
	using.base_state = "atmos_sensor"
	using.screen_loc = "WEST:6,SOUTH+2:18"
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "remote signaler"
	using.base_state = "signaller"
	using.screen_loc = "WEST:6,SOUTH+3:2"
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "universal translator"
	using.base_state = "translator"
	using.screen_loc = "WEST:6,SOUTH+3:18"
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "door jack"
	using.base_state = "door_jack"
	using.screen_loc = "WEST:6,SOUTH+4:2"
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "ar hud"
	using.base_state = "ar_hud"
	using.screen_loc = "WEST:6,SOUTH+4:18"
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.other), using)

	using = new /atom/movable/screen/pai()
	using.name = "death alarm"
	using.base_state = "death_alarm"
	using.screen_loc = "WEST:6,SOUTH+5:2"
	using.set_color(ui_color)
	using.set_alpha(ui_alpha)
	rel_add(HUD, nameof(HUD.other), using)

	rel_set(hud_used, nameof(/datum/hud::autowhisper_display), rel_add(HUD, nameof(HUD.extra_screens), new /atom/movable/screen()))
	hud_used?.autowhisper_display?.icon = 'icons/mob/screen/minimalist.dmi'
	hud_used?.autowhisper_display?.icon_state = "autowhisper"
	hud_used?.autowhisper_display?.name = "autowhisper"
	hud_used?.autowhisper_display?.screen_loc = "EAST-1:28,CENTER-2:13"
	rel_add(HUD, nameof(HUD.hud_elements), hud_used?.autowhisper_display)

	var/atom/movable/screen/aw = new /atom/movable/screen()
	aw.set_icon('icons/mob/screen/minimalist.dmi')
	aw.set_icon_state("aw-select")
	aw.name = "autowhisper mode"
	aw.screen_loc = "EAST-1:28,CENTER-2:13"
	rel_add(HUD, nameof(HUD.extra_screens), aw)
	rel_add(HUD, nameof(HUD.hud_elements), aw)

	aw = new /atom/movable/screen()
	aw.set_icon('icons/mob/screen/minimalist.dmi')
	aw.set_icon_state("lang")
	aw.name = "check known languages"
	aw.screen_loc = ui_under_health
	rel_add(HUD, nameof(HUD.extra_screens), aw)
	rel_add(HUD, nameof(HUD.hud_elements), aw)

	aw = new /atom/movable/screen()
	aw.set_icon('icons/mob/screen/minimalist.dmi')
	aw.set_icon_state("pose")
	aw.name = "set pose"
	aw.screen_loc = ui_under_health
	rel_add(HUD, nameof(HUD.extra_screens), aw)
	rel_add(HUD, nameof(HUD.hud_elements), aw)

	aw = new /atom/movable/screen()
	aw.set_icon('icons/mob/screen/minimalist.dmi')
	aw.set_icon_state("up")
	aw.name = "move upwards"
	aw.screen_loc = ui_under_health
	rel_add(HUD, nameof(HUD.extra_screens), aw)
	rel_add(HUD, nameof(HUD.hud_elements), aw)

	aw = new /atom/movable/screen()
	aw.set_icon('icons/mob/screen/minimalist.dmi')
	aw.set_icon_state("down")
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
	if(!. || !hud_used?.healths)
		return

	hud_used?.healths?.icon_state = vitality_health_band(src)

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
		if(hud_used?.healths)
			client.screen |= hud_used?.healths
		if(hud_used?.internals)
			client.screen |= hud_used?.internals
		if(hud_used?.gun_setting_icon)
			client.screen |= hud_used?.gun_setting_icon
		if(hud_used.hud_elements)
			if(length(hud_used.hud_elements)) client.screen |= hud_used.hud_elements

		client.screen += hud_used?.zone_sel				//This one is a special snowflake

	hud_used.hidden_inventory_update()
	hud_used.persistant_inventory_update()
	update_action_buttons()
	hud_used.reorganize_alerts()
	return TRUE
