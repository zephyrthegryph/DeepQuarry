/mob/living/carbon/human/create_mob_hud(datum/hud/HUD)
	..()

	var/datum/hud_data/hud_data
	if(species?.hud)
		hud_data = species.hud
	else
		hud_data = new ()

	if(hud_data.icon) // Species wants a specific dmi for the HUD
		HUD.ui_style = hud_data.icon

	var/slot_info = list()

	// HUD.adding / HUD.other / HUD.hotkeybuttons (the last can be disabled for hotkey users) own
	// their screen elements; the named vars pointing at listed elements are relations back.
	HUD.slot_info = slot_info

	var/list/hud_elements = list()
	var/atom/movable/screen/using
	var/atom/movable/screen/inventory/inv_box

	// Draw the various inventory equipment slots.
	var/has_hidden_gear
	for(var/gear_slot in hud_data.gear)

		inv_box = new /atom/movable/screen/inventory()
		inv_box.icon = HUD.ui_style
		inv_box.color = HUD.ui_color
		inv_box.alpha = HUD.ui_alpha
		rel_set(inv_box, nameof(inv_box.hud), HUD)

		var/list/slot_data =  hud_data.gear[gear_slot]
		inv_box.name =        gear_slot
		inv_box.screen_loc =  slot_data["loc"]
		inv_box.slot_id =     slot_data["slot"]
		inv_box.icon_state =  slot_data["state"]
		slot_info["[inv_box.slot_id]"] = inv_box.screen_loc

		if(slot_data["dir"])
			inv_box.set_dir(slot_data["dir"])

		if(slot_data["toggle"])
			rel_add(HUD, nameof(HUD.other), inv_box)
			has_hidden_gear = 1
		else
			rel_add(HUD, nameof(HUD.adding), inv_box)

	if(has_hidden_gear)
		using = new /atom/movable/screen()
		using.name = "toggle"
		using.icon = HUD.ui_style
		using.icon_state = "other"
		using.screen_loc = ui_inventory
		using.hud_layerise()
		using.color = HUD.ui_color
		using.alpha = HUD.ui_alpha
		rel_add(HUD, nameof(HUD.adding), using)

	// The combat mode button (it replaced the intent selector).
	if(hud_data.has_a_intent)
		using = HUD.make_combat_mode_button(src)
		using.icon = HUD.ui_style
		using.color = HUD.ui_color
		using.alpha = HUD.ui_alpha
		hud_elements |= using // owned by HUD.combat_mode_button

	if(hud_data.has_m_intent)
		using = new /atom/movable/screen()
		using.name = "mov_intent"
		using.icon = HUD.ui_style
		using.icon_state = (m_intent == I_RUN ? "running" : "walking")
		using.screen_loc = ui_movi
		using.color = HUD.ui_color
		using.alpha = HUD.ui_alpha
		rel_add(HUD, nameof(HUD.adding), using)
		rel_set(HUD, nameof(HUD.move_intent), using)

	if(hud_data.has_drop)
		using = new /atom/movable/screen()
		using.name = "drop"
		using.icon = HUD.ui_style
		using.icon_state = "act_drop"
		using.screen_loc = ui_drop_throw
		using.color = HUD.ui_color
		using.alpha = HUD.ui_alpha
		rel_add(HUD, nameof(HUD.hotkeybuttons), using)

	if(hud_data.has_hands)

		using = new /atom/movable/screen()
		using.name = "equip"
		using.icon = HUD.ui_style
		using.icon_state = "act_equip"
		using.screen_loc = ui_equip
		using.color = HUD.ui_color
		using.alpha = HUD.ui_alpha
		rel_add(HUD, nameof(HUD.adding), using)

		using = new /atom/movable/screen/useself()
		using.icon = HUD.ui_style
		using.screen_loc = ui_swaphand2
		using.color = HUD.ui_color
		using.alpha = HUD.ui_alpha
		rel_add(HUD, nameof(HUD.adding), using)

		inv_box = new /atom/movable/screen/inventory/hand()
		rel_set(inv_box, nameof(inv_box.hud), HUD)
		inv_box.name = "r_hand"
		inv_box.icon = HUD.ui_style
		inv_box.icon_state = "r_hand_inactive"
		if(!hand)	//This being 0 or null means the right hand is in use
			inv_box.icon_state = "r_hand_active"
		inv_box.screen_loc = ui_rhand
		inv_box.slot_id = SLOT_ID_HAND_R
		inv_box.color = HUD.ui_color
		inv_box.alpha = HUD.ui_alpha
		rel_set(HUD, nameof(HUD.r_hand_hud_object), inv_box)
		rel_add(HUD, nameof(HUD.adding), inv_box)
		slot_info["[SLOT_ID_HAND_R]"] = inv_box.screen_loc

		inv_box = new /atom/movable/screen/inventory/hand()
		rel_set(inv_box, nameof(inv_box.hud), HUD)
		inv_box.name = "l_hand"
		inv_box.icon = HUD.ui_style
		inv_box.icon_state = "l_hand_inactive"
		if(hand)	//This being 1 means the left hand is in use
			inv_box.icon_state = "l_hand_active"
		inv_box.screen_loc = ui_lhand
		inv_box.slot_id = SLOT_ID_HAND_L
		inv_box.color = HUD.ui_color
		inv_box.alpha = HUD.ui_alpha
		rel_set(HUD, nameof(HUD.l_hand_hud_object), inv_box)
		rel_add(HUD, nameof(HUD.adding), inv_box)
		slot_info["[SLOT_ID_HAND_L]"] = inv_box.screen_loc

		using = new /atom/movable/screen/inventory()
		using.name = "hand"
		using.icon = HUD.ui_style
		using.icon_state = "hand1"
		using.screen_loc = ui_swaphand1
		using.color = HUD.ui_color
		using.alpha = HUD.ui_alpha
		rel_set(using, nameof(using.hud), HUD)
		rel_add(HUD, nameof(HUD.adding), using)

		using = new /atom/movable/screen/inventory()
		using.name = "hand"
		using.icon = HUD.ui_style
		using.icon_state = "hand2"
		using.screen_loc = ui_swaphand2
		using.color = HUD.ui_color
		using.alpha = HUD.ui_alpha
		rel_set(using, nameof(using.hud), HUD)
		rel_add(HUD, nameof(HUD.adding), using)

	if(hud_data.has_resist)
		using = new /atom/movable/screen()
		using.name = "resist"
		using.icon = HUD.ui_style
		using.icon_state = "act_resist"
		using.screen_loc = ui_pull_resist
		using.color = HUD.ui_color
		using.alpha = HUD.ui_alpha
		rel_add(HUD, nameof(HUD.hotkeybuttons), using)

	if(hud_data.has_throw)
		rel_set(hud_used, nameof(/datum/hud::throw_icon), rel_add(HUD, nameof(HUD.hotkeybuttons), new /atom/movable/screen()))
		hud_used?.throw_icon?.icon = HUD.ui_style
		hud_used?.throw_icon?.icon_state = "act_throw_off"
		hud_used?.throw_icon?.name = "throw"
		hud_used?.throw_icon?.screen_loc = ui_drop_throw
		hud_used?.throw_icon?.color = HUD.ui_color
		hud_used?.throw_icon?.alpha = HUD.ui_alpha
		hud_elements |= hud_used?.throw_icon

		rel_set(hud_used, nameof(/datum/hud::pullin), rel_add(HUD, nameof(HUD.hotkeybuttons), new /atom/movable/screen()))
		hud_used?.pullin?.icon = HUD.ui_style
		hud_used?.pullin?.icon_state = "pull0"
		hud_used?.pullin?.name = "pull"
		hud_used?.pullin?.screen_loc = ui_pull_resist
		hud_elements |= hud_used?.pullin

	if(hud_data.has_internals)
		rel_set(hud_used, nameof(/datum/hud::internals), new /atom/movable/screen())
		hud_used?.internals?.icon = HUD.ui_style
		hud_used?.internals?.icon_state = "internal0"
		if(istype(internal, /obj/item/tank)) //Internals on already? Iight, prove it
			hud_used?.internals?.icon_state = "internal1"
		hud_used?.internals?.name = "internal"
		hud_used?.internals?.screen_loc = ui_internal
		hud_elements |= hud_used?.internals

	if(hud_data.has_warnings)
		rel_set(hud_used, nameof(/datum/hud::healths), new /atom/movable/screen())
		hud_used?.healths?.icon = HUD.ui_style
		hud_used?.healths?.icon_state = "health0"
		hud_used?.healths?.name = "health"
		hud_used?.healths?.screen_loc = ui_health
		hud_elements |= hud_used?.healths

	rel_set(hud_used, nameof(/datum/hud::autowhisper_display), rel_add(HUD, nameof(HUD.adding), new /atom/movable/screen()))
	hud_used?.autowhisper_display?.icon = 'icons/mob/screen/minimalist.dmi'
	hud_used?.autowhisper_display?.icon_state = "autowhisper"
	hud_used?.autowhisper_display?.name = "autowhisper"
	hud_used?.autowhisper_display?.screen_loc = ui_under_health
	hud_elements |= hud_used?.autowhisper_display

	var/atom/movable/screen/aw = new /atom/movable/screen()
	aw.icon = 'icons/mob/screen/minimalist.dmi'
	aw.icon_state = "aw-select"
	aw.name = "autowhisper mode"
	aw.screen_loc = ui_under_health
	hud_elements |= aw
	rel_add(HUD, nameof(HUD.adding), aw)

	aw = new /atom/movable/screen()
	aw.icon = 'icons/mob/screen/minimalist.dmi'
	aw.icon_state = "lang"
	aw.name = "check known languages"
	aw.screen_loc = ui_under_health
	hud_elements |= aw
	rel_add(HUD, nameof(HUD.adding), aw)

	aw = new /atom/movable/screen()
	aw.icon = 'icons/mob/screen/minimalist.dmi'
	aw.icon_state = "pose"
	aw.name = "set pose"
	aw.screen_loc = ui_under_health
	hud_elements |= aw
	rel_add(HUD, nameof(HUD.adding), aw)

	aw = new /atom/movable/screen()
	aw.icon = 'icons/mob/screen/minimalist.dmi'
	aw.icon_state = "up"
	aw.name = "move upwards"
	aw.screen_loc = ui_under_health
	hud_elements |= aw
	rel_add(HUD, nameof(HUD.adding), aw)

	aw = new /atom/movable/screen()
	aw.icon = 'icons/mob/screen/minimalist.dmi'
	aw.icon_state = "down"
	aw.name = "move downwards"
	aw.screen_loc = ui_under_health
	hud_elements |= aw
	rel_add(HUD, nameof(HUD.adding), aw)

	aw = new /atom/movable/screen()
	aw.icon = HUD.ui_style
	aw.icon_state = "use"
	aw.name = "use held item on self"
	aw.screen_loc = ui_swaphand2
	aw.color = HUD.ui_color
	aw.alpha = HUD.ui_alpha
	rel_add(HUD, nameof(HUD.adding), aw)

	//Component hud elements. Made in /mob/living/create_mob_hud
	hud_elements |= hud_used?.shadekin_display
	hud_elements |= hud_used?.xenochimera_danger_display
	hud_elements |= hud_used?.lleill_display

	rel_set(hud_used, nameof(/datum/hud::ling_chem_display), new /atom/movable/screen/ling/chems())
	hud_used?.ling_chem_display?.screen_loc = ui_ling_chemical_display
	hud_used?.ling_chem_display?.icon_state = "ling_chems"
	hud_elements |= hud_used?.ling_chem_display

	rel_set(hud_used, nameof(/datum/hud::wiz_instability_display), new /atom/movable/screen/wizard/instability())
	hud_used?.wiz_instability_display?.screen_loc = ui_wiz_instability_display
	hud_used?.wiz_instability_display?.icon_state = "wiz_instability_none"
	hud_elements |= hud_used?.wiz_instability_display

	rel_set(hud_used, nameof(/datum/hud::wiz_energy_display), new/atom/movable/screen/wizard/energy())
	hud_used?.wiz_energy_display?.screen_loc = ui_wiz_energy_display
	hud_used?.wiz_energy_display?.icon_state = "wiz_energy"
	hud_elements |= hud_used?.wiz_energy_display


	rel_set(hud_used, nameof(/datum/hud::pain), new /atom/movable/screen( null ))

	rel_set(hud_used, nameof(/datum/hud::zone_sel), new /atom/movable/screen/zone_sel( null ))
	hud_used?.zone_sel?.icon = HUD.ui_style
	hud_used?.zone_sel?.color = HUD.ui_color
	hud_used?.zone_sel?.alpha = HUD.ui_alpha
	hud_elements |= hud_used?.zone_sel

	//Handle the gun settings buttons
	rel_set(hud_used, nameof(/datum/hud::gun_setting_icon), new /atom/movable/screen/gun/mode(null))
	hud_used?.gun_setting_icon?.icon = HUD.ui_style
	hud_used?.gun_setting_icon?.color = HUD.ui_color
	hud_used?.gun_setting_icon?.alpha = HUD.ui_alpha
	hud_elements |= hud_used?.gun_setting_icon

	rel_set(hud_used, nameof(/datum/hud::item_use_icon), new /atom/movable/screen/gun/item(null))
	hud_used?.item_use_icon?.icon = HUD.ui_style
	hud_used?.item_use_icon?.color = HUD.ui_color
	hud_used?.item_use_icon?.alpha = HUD.ui_alpha

	rel_set(hud_used, nameof(/datum/hud::gun_move_icon), new /atom/movable/screen/gun/move(null))
	hud_used?.gun_move_icon?.icon = HUD.ui_style
	hud_used?.gun_move_icon?.color = HUD.ui_color
	hud_used?.gun_move_icon?.alpha = HUD.ui_alpha

	rel_set(hud_used, nameof(/datum/hud::radio_use_icon), new /atom/movable/screen/gun/radio(null))
	hud_used?.radio_use_icon?.icon = HUD.ui_style
	hud_used?.radio_use_icon?.color = HUD.ui_color
	hud_used?.radio_use_icon?.alpha = HUD.ui_alpha

	if(client)
		client.screen = list()

		client.screen += hud_elements
		if(length(HUD.adding))
			client.screen += HUD.adding
		if(length(HUD.hotkeybuttons))
			client.screen += HUD.hotkeybuttons
		client.screen += client.void

	HUD.inventory_shown = 0

/mob/living/carbon/human/verb/toggle_hotkey_verbs()
	set category = VERB_CAT_OOC_CLIENT_SETTINGS
	set name = "Toggle hotkey buttons"
	set desc = "This disables or enables the user interface buttons which can be used with hotkeys."

	if(hud_used.hotkey_ui_hidden)
		client.screen += hud_used.hotkeybuttons
		hud_used.hotkey_ui_hidden = 0
	else
		client.screen -= hud_used.hotkeybuttons
		hud_used.hotkey_ui_hidden = 1

//Used for new human mobs created by cloning/goleming/etc.
/mob/living/carbon/human/proc/set_cloned_appearance()
	f_style = "Shaved"
	if(dna.species == "Human") //no more xenos losing ears/tentacles
		h_style = pick("Bedhead", "Bedhead 2", "Bedhead 3")
	LAZYCLEARLIST(all_underwear)
	regenerate_icons()

/atom/movable/screen/ling
	invisibility = INVISIBILITY_ABSTRACT

/atom/movable/screen/ling/chems
	name = "chemical storage"
	icon_state = "power_display"

/atom/movable/screen/borer
	invisibility = INVISIBILITY_ABSTRACT

/atom/movable/screen/borer/chems
	name = "chemical storage"
	icon_state = "power_display"

/atom/movable/screen/wizard
	invisibility = INVISIBILITY_ABSTRACT

/atom/movable/screen/wizard/instability
	name = "instability"
	icon_state = "instability-1"
	invisibility = INVISIBILITY_NONE

/atom/movable/screen/wizard/energy
	name = "energy"
	icon_state = "wiz_energy"

/atom/movable/screen/useself
	name = "use held item on self"
	icon_state = "use"
	COOLDOWN_DECLARE(next)

/atom/movable/screen/useself/proc/can_use(mob/living/carbon/human/h, obj/item/i)	//Basically trying to use the item this way skips the cooldown
	if(!COOLDOWN_TIMELEFT(src, next))											//And trying to check the cooldown doesn't work because when you click the UI it sets a cooldown
		var/use_delay = h.get_attack_speed(i)									//So instead we'll just put a cooldown on the use button and apply the item's cooldown to the player
		h.setClickCooldown(use_delay)											//Otherwise you can click the button and yourself faster than the normal cooldown. SO WE SET BOTH!!!!
		COOLDOWN_START(src, next, use_delay)
		i.attack(h, h)
