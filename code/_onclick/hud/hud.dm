#define MAX_AMMO_HUD_POSSIBLE 4 // Cap the amount of HUDs at 4.
/*
	The global hud:
	Uses the same visual objects for all players.
*/
GLOBAL_DATUM_INIT(global_hud, /datum/global_hud, new)
GLOBAL_LIST_INIT(global_huds, list(
		GLOB.global_hud.druggy,
		GLOB.global_hud.blurry,
		GLOB.global_hud.whitense,
		GLOB.global_hud.heavy_whitense,
		GLOB.global_hud.vimpaired,
		GLOB.global_hud.darkMask,
		GLOB.global_hud.centermarker,
		GLOB.global_hud.nvg,
		GLOB.global_hud.thermal,
		GLOB.global_hud.meson,
		GLOB.global_hud.science,
		GLOB.global_hud.material,
		GLOB.global_hud.holomap
))

/datum/global_hud
	var/atom/movable/screen/druggy
	var/atom/movable/screen/blurry
	var/atom/movable/screen/whitense
	var/atom/movable/screen/heavy_whitense
	var/list/vimpaired
	var/list/darkMask
	var/atom/movable/screen/centermarker
	var/atom/movable/screen/darksight
	var/atom/movable/screen/nvg
	var/atom/movable/screen/thermal
	var/atom/movable/screen/meson
	var/atom/movable/screen/science
	var/atom/movable/screen/material
	var/atom/movable/screen/holomap

/datum/global_hud/proc/setup_overlay(icon_state)
	var/atom/movable/screen/screen = new /atom/movable/screen()
	screen.alpha = 30 // Adjut this if you want goggle overlays to be thinner or thicker. //
	screen.screen_loc = "SOUTHWEST to NORTHEAST" // Will tile up to the whole screen, scaling beyond 15x15 if needed.
	screen.icon = 'icons/obj/hud_tiled_vr.dmi'
	screen.icon_state = icon_state
	screen.layer = SCREEN_LAYER
	screen.plane = PLANE_FULLSCREEN
	screen.mouse_opacity = 0

	return screen

/atom/movable/screen/global_screen
	screen_loc = ui_entire_screen
	plane = PLANE_FULLSCREEN
	mouse_opacity = 0

/datum/global_hud/New()
	//420erryday psychedellic colours screen overlay for when you are high
	druggy = new /atom/movable/screen/global_screen()
	druggy.icon_state = "druggy"

	//that white blurry effect you get when you eyes are damaged
	blurry = new /atom/movable/screen/global_screen()
	blurry.icon_state = "blurry"

	//static overlay effect for cameras and the like
	whitense = new /atom/movable/screen/global_screen()
	whitense.icon = 'icons/effects/static.dmi'
	whitense.icon_state = "1 light"

	//static overlay effect for cameras and the like
	heavy_whitense = new /atom/movable/screen/global_screen()
	heavy_whitense.icon = 'icons/effects/static.dmi'
	heavy_whitense.icon_state = "1 heavy"

	//darksight 'hanger' for attached icons
	darksight = new /atom/movable/screen()
	darksight.icon = null
	darksight.screen_loc = "1,1"
	darksight.plane = PLANE_LIGHTING

	//Marks the center of the screen, for things like ventcrawl
	centermarker = new /atom/movable/screen()
	centermarker.icon = 'icons/mob/screen1.dmi'
	centermarker.icon_state = "centermarker"
	centermarker.screen_loc = "CENTER,CENTER"

	//Marks the center of the screen, for things like ventcrawl
	centermarker = new /atom/movable/screen()
	centermarker.icon = 'icons/mob/screen1.dmi'
	centermarker.icon_state = "centermarker"
	centermarker.screen_loc = "CENTER,CENTER"

	nvg = setup_overlay("nvg_hud")
	thermal = setup_overlay("thermal_hud")
	meson = setup_overlay("meson_hud")
	science = setup_overlay("science_hud")
	material = setup_overlay("material_hud")

	holomap = new /atom/movable/screen()
	holomap.name = "holomap"
	holomap.icon = null
	holomap.screen_loc = ui_holomap
	holomap.mouse_opacity = 0

	var/atom/movable/screen/O
	var/i
	//that nasty looking dither you  get when you're short-sighted
	vimpaired = newlist(/atom/movable/screen,/atom/movable/screen,/atom/movable/screen,/atom/movable/screen)
	O = vimpaired[1]
	O.screen_loc = "1,1 to 5,15"
	O.plane = PLANE_FULLSCREEN
	O = vimpaired[2]
	O.screen_loc = "5,1 to 10,5"
	O.plane = PLANE_FULLSCREEN
	O = vimpaired[3]
	O.screen_loc = "6,11 to 10,15"
	O.plane = PLANE_FULLSCREEN
	O = vimpaired[4]
	O.screen_loc = "11,1 to 15,15"
	O.plane = PLANE_FULLSCREEN

	//welding mask overlay black/dither
	darkMask = newlist(/atom/movable/screen, /atom/movable/screen, /atom/movable/screen, /atom/movable/screen, /atom/movable/screen, /atom/movable/screen, /atom/movable/screen, /atom/movable/screen)
	O = darkMask[1]
	O.screen_loc = "WEST+2,SOUTH+2 to WEST+4,NORTH-2"
	O = darkMask[2]
	O.screen_loc = "WEST+4,SOUTH+2 to EAST-5,SOUTH+4"
	O = darkMask[3]
	O.screen_loc = "WEST+5,NORTH-4 to EAST-5,NORTH-2"
	O = darkMask[4]
	O.screen_loc = "EAST-4,SOUTH+2 to EAST-2,NORTH-2"
	O = darkMask[5]
	O.screen_loc = "WEST,SOUTH to EAST,SOUTH+1"
	O = darkMask[6]
	O.screen_loc = "WEST,SOUTH+2 to WEST+1,NORTH"
	O = darkMask[7]
	O.screen_loc = "EAST-1,SOUTH+2 to EAST,NORTH"
	O = darkMask[8]
	O.screen_loc = "WEST+2,NORTH-1 to EAST-2,NORTH"

	for(i = 1, i <= 4, i++)
		O = vimpaired[i]
		O.icon_state = "dither50"
		O.plane = PLANE_FULLSCREEN
		O.mouse_opacity = 0

		O = darkMask[i]
		O.icon_state = "dither50"
		O.plane = PLANE_FULLSCREEN
		O.mouse_opacity = 0

	for(i = 5, i <= 8, i++)
		O = darkMask[i]
		O.icon_state = "black"
		O.plane = PLANE_FULLSCREEN
		O.mouse_opacity = 2

/*
	The hud datum
	Used to show and hide huds for all the different mob types,
	including inventories and item quick actions.
*/

/datum/hud
	var/mymob_handle

	var/hud_shown = 1			//Used for the HUD toggle (F12)
	var/inventory_shown = 1		//the inventory
	var/show_intent_icons = 0
	var/hotkey_ui_hidden = 0	//This is to hide the buttons that can be used via hotkeys. (hotkeybuttons list of buttons)

	var/atom/movable/screen/lingchemdisplay
	var/atom/movable/screen/wiz_instability_display
	var/atom/movable/screen/wiz_energy_display
	var/atom/movable/screen/blobpwrdisplay
	var/atom/movable/screen/blobhealthdisplay
	var/atom/movable/screen/r_hand_hud_object
	var/atom/movable/screen/l_hand_hud_object
	/// The combat mode toggle (code/modules/mob/combat_mode.dm).
	var/atom/movable/screen/combat_mode/combat_mode_button
	var/atom/movable/screen/move_intent
	var/atom/movable/screen/control_vtec

	var/list/adding
	/// Misc hud elements that are hidden when the hud is minimized
	var/list/other
	/// Same, but always shown even when the hud is minimized
	var/list/other_important
	var/list/miniobjs
	var/list/atom/movable/screen/hotkeybuttons

	var/atom/movable/screen/button_palette/toggle_palette
	var/atom/movable/screen/palette_scroll/down/palette_down
	var/atom/movable/screen/palette_scroll/up/palette_up

	var/datum/action_group/palette/palette_actions
	var/datum/action_group/listed/listed_actions
	var/list/floating_actions

	var/list/slot_info

	var/icon/ui_style
	var/ui_color
	var/ui_alpha

	// TGMC Ammo HUD Port
	/// Gun OM handle -> its ammo hud (owned).
	var/list/atom/movable/screen/ammo_hud_list

	var/list/minihuds

/datum/hud/New(mob/owner)
	mymob_handle = om_handle(owner)
	instantiate()
	..()

// The hud's own elements, deleted with it (their screens are released in phase 5). The ammo huds
// are keyed by the gun's OM handle.
REF_OWNED(/datum/hud, list("lingchemdisplay", "wiz_instability_display", "wiz_energy_display", "blobpwrdisplay", "blobhealthdisplay", "r_hand_hud_object", "l_hand_hud_object", "combat_mode_button", "move_intent", "control_vtec", "toggle_palette", "palette_down", "palette_up", "palette_actions", "listed_actions", "ui_style"))
REF_OWNED_LIST(/datum/hud, list("minihuds", "floating_actions", "hotkeybuttons"))
REF_OWNED_VALUES(/datum/hud, "ammo_hud_list")

// the mob's hud_used points at us (our side is a handle); a hud going clears it.
/datum/hud/on_destroy(force)
	if(mymob()?.hud_used == src)
		mymob().hud_used = null
	for (var/x in ammo_hud_list)
		remove_ammo_hud(mymob(), x)
	ammo_hud_list = null
	..()

/datum/hud/proc/hidden_inventory_update()
	if(!mymob()) return
	if(ishuman(mymob()))
		var/mob/living/carbon/human/H = mymob()
		for(var/gear_slot in H.species.hud.gear)
			var/list/hud_data = H.species.hud.gear[gear_slot]
			if(inventory_shown && hud_shown)
				switch(hud_data["slot"])
					if(SLOT_ID_HEAD)
						if(H.get_equipped_item(SLOT_ID_HEAD))      H.get_equipped_item(SLOT_ID_HEAD).screen_loc =      hud_data["loc"]
					if(SLOT_ID_SHOES)
						if(H.get_equipped_item(SLOT_ID_SHOES))     H.get_equipped_item(SLOT_ID_SHOES).screen_loc =     hud_data["loc"]
					if(SLOT_ID_EAR_L)
						if(H.get_equipped_item(SLOT_ID_EAR_L))     H.get_equipped_item(SLOT_ID_EAR_L).screen_loc =     hud_data["loc"]
					if(SLOT_ID_EAR_R)
						if(H.get_equipped_item(SLOT_ID_EAR_R))     H.get_equipped_item(SLOT_ID_EAR_R).screen_loc =     hud_data["loc"]
					if(SLOT_ID_GLOVES)
						if(H.get_equipped_item(SLOT_ID_GLOVES))    H.get_equipped_item(SLOT_ID_GLOVES).screen_loc =    hud_data["loc"]
					if(SLOT_ID_EYES)
						if(H.get_equipped_item(SLOT_ID_EYES))   H.get_equipped_item(SLOT_ID_EYES).screen_loc =   hud_data["loc"]
					if(SLOT_ID_UNIFORM)
						if(H.get_equipped_item(SLOT_ID_UNIFORM)) H.get_equipped_item(SLOT_ID_UNIFORM).screen_loc = hud_data["loc"]
					if(SLOT_ID_SUIT)
						if(H.get_equipped_item(SLOT_ID_SUIT)) H.get_equipped_item(SLOT_ID_SUIT).screen_loc = hud_data["loc"]
					if(SLOT_ID_MASK)
						if(H.get_equipped_item(SLOT_ID_MASK)) H.get_equipped_item(SLOT_ID_MASK).screen_loc = hud_data["loc"]
			else
				switch(hud_data["slot"])
					if(SLOT_ID_HEAD)
						if(H.get_equipped_item(SLOT_ID_HEAD))      H.get_equipped_item(SLOT_ID_HEAD).screen_loc =      null
					if(SLOT_ID_SHOES)
						if(H.get_equipped_item(SLOT_ID_SHOES))     H.get_equipped_item(SLOT_ID_SHOES).screen_loc =     null
					if(SLOT_ID_EAR_L)
						if(H.get_equipped_item(SLOT_ID_EAR_L))     H.get_equipped_item(SLOT_ID_EAR_L).screen_loc =     null
					if(SLOT_ID_EAR_R)
						if(H.get_equipped_item(SLOT_ID_EAR_R))     H.get_equipped_item(SLOT_ID_EAR_R).screen_loc =     null
					if(SLOT_ID_GLOVES)
						if(H.get_equipped_item(SLOT_ID_GLOVES))    H.get_equipped_item(SLOT_ID_GLOVES).screen_loc =    null
					if(SLOT_ID_EYES)
						if(H.get_equipped_item(SLOT_ID_EYES))   H.get_equipped_item(SLOT_ID_EYES).screen_loc =   null
					if(SLOT_ID_UNIFORM)
						if(H.get_equipped_item(SLOT_ID_UNIFORM)) H.get_equipped_item(SLOT_ID_UNIFORM).screen_loc = null
					if(SLOT_ID_SUIT)
						if(H.get_equipped_item(SLOT_ID_SUIT)) H.get_equipped_item(SLOT_ID_SUIT).screen_loc = null
					if(SLOT_ID_MASK)
						if(H.get_equipped_item(SLOT_ID_MASK)) H.get_equipped_item(SLOT_ID_MASK).screen_loc = null

/datum/hud/proc/persistant_inventory_update()
	if(!mymob())
		return

	if(ishuman(mymob()))
		var/mob/living/carbon/human/H = mymob()
		for(var/gear_slot in H.species.hud.gear)
			var/list/hud_data = H.species.hud.gear[gear_slot]
			if(hud_shown)
				switch(hud_data["slot"])
					if(SLOT_ID_SUIT_STORAGE)
						if(H.get_equipped_item(SLOT_ID_SUIT_STORAGE)) H.get_equipped_item(SLOT_ID_SUIT_STORAGE).screen_loc = hud_data["loc"]
					if(SLOT_ID_ID)
						if(H.get_equipped_item(SLOT_ID_ID)) H.get_equipped_item(SLOT_ID_ID).screen_loc = hud_data["loc"]
					if(SLOT_ID_BELT)
						if(H.get_equipped_item(SLOT_ID_BELT))    H.get_equipped_item(SLOT_ID_BELT).screen_loc =    hud_data["loc"]
					if(SLOT_ID_BACK)
						if(H.get_equipped_item(SLOT_ID_BACK))    H.get_equipped_item(SLOT_ID_BACK).screen_loc =    hud_data["loc"]
					if(SLOT_ID_POCKET_L)
						if(H.get_equipped_item(SLOT_ID_POCKET_L)) H.get_equipped_item(SLOT_ID_POCKET_L).screen_loc = hud_data["loc"]
					if(SLOT_ID_POCKET_R)
						if(H.get_equipped_item(SLOT_ID_POCKET_R)) H.get_equipped_item(SLOT_ID_POCKET_R).screen_loc = hud_data["loc"]
			else
				switch(hud_data["slot"])
					if(SLOT_ID_SUIT_STORAGE)
						if(H.get_equipped_item(SLOT_ID_SUIT_STORAGE)) H.get_equipped_item(SLOT_ID_SUIT_STORAGE).screen_loc = null
					if(SLOT_ID_ID)
						if(H.get_equipped_item(SLOT_ID_ID)) H.get_equipped_item(SLOT_ID_ID).screen_loc = null
					if(SLOT_ID_BELT)
						if(H.get_equipped_item(SLOT_ID_BELT))    H.get_equipped_item(SLOT_ID_BELT).screen_loc =    null
					if(SLOT_ID_BACK)
						if(H.get_equipped_item(SLOT_ID_BACK))    H.get_equipped_item(SLOT_ID_BACK).screen_loc =    null
					if(SLOT_ID_POCKET_L)
						if(H.get_equipped_item(SLOT_ID_POCKET_L)) H.get_equipped_item(SLOT_ID_POCKET_L).screen_loc = null
					if(SLOT_ID_POCKET_R)
						if(H.get_equipped_item(SLOT_ID_POCKET_R)) H.get_equipped_item(SLOT_ID_POCKET_R).screen_loc = null

/datum/hud/proc/instantiate()
	if(!ismob(mymob()))
		return 0

	toggle_palette = new()
	palette_down = new()
	palette_up = new()
	mymob().create_mob_hud(src)

	// Past this point, mymob.hud_used is set

	toggle_palette.set_hud(src)
	palette_down.set_hud(src)
	palette_up.set_hud(src)

	persistant_inventory_update()
	mymob().reload_fullscreen() // Reload any fullscreen overlays this mob has.
	mymob().update_action_buttons(TRUE)
	reorganize_alerts()

/mob/proc/create_mob_hud(datum/hud/HUD, apply_to_client = TRUE)
	if(!client)
		return 0

	HUD.ui_style = ui_style2icon(read_preference(/datum/preference/choiced/ui_style))
	HUD.ui_color = read_preference(/datum/preference/color/ui_style_color)
	HUD.ui_alpha = read_preference(/datum/preference/numeric/ui_style_alpha)
	set_hud_used(HUD)

/mob/proc/set_hud_used(datum/hud/new_hud)
	hud_used = new_hud
	new_hud.build_action_groups()

/mob/proc/update_ui_style(UI_style_new, UI_style_alpha_new, UI_style_color_new)
	if(!hud_used)
		return

	if(!UI_style_alpha_new)
		UI_style_alpha_new = hud_used.ui_alpha
	hud_used.ui_alpha = UI_style_alpha_new
	if(!UI_style_color_new)
		UI_style_color_new = hud_used.ui_color
	hud_used.ui_color = UI_style_color_new

	var/list/icons = hud_used.adding + hud_used.other + hud_used.hotkeybuttons + hud_used.other_important
	icons.Add(zone_sel)
	icons.Add(gun_setting_icon)
	icons.Add(item_use_icon)
	icons.Add(gun_move_icon)
	icons.Add(radio_use_icon)

	var/icon/ic

	if(UI_style_new)
		if(isrobot(src))
			ic = GLOB.all_ui_styles_robot[UI_style_new]
		else
			ic = GLOB.all_ui_styles[UI_style_new]
		hud_used.ui_style = ic
	else
		ic = hud_used.ui_style

	for(var/atom/movable/screen/I in icons)
		if(!(I.name in list("check known languages", "autowhisper", "autowhisper mode", "move downwards", "move upwards", "set pose")))
			I.icon = ic
		I.color = UI_style_color_new
		I.alpha = UI_style_alpha_new

/datum/hud/proc/apply_minihud(datum/mini_hud/MH)
	if(MH in minihuds)
		return
	LAZYADD(minihuds, MH)
	if(mymob().client)
		mymob().client.screen -= miniobjs
	miniobjs += MH.get_screen_objs()
	if(mymob().client)
		mymob().client.screen += miniobjs

/datum/hud/proc/remove_minihud(datum/mini_hud/MH)
	if(!(MH in minihuds))
		return
	LAZYREMOVE(minihuds, MH)
	if(mymob().client)
		mymob().client.screen -= miniobjs
	miniobjs -= MH.get_screen_objs()
	if(mymob().client)
		mymob().client.screen += miniobjs

//Triggered when F12 is pressed (Unless someone changed something in the DMF)
/mob/verb/button_pressed_F12(full = 0 as null)
	set name = "F12"
	set hidden = 1

	if(!hud_used)
		to_chat(src, span_warning("This mob type does not use a HUD."))
		return FALSE
	if(!client)
		return FALSE
	if(client.view != world.view)
		return FALSE

	toggle_hud_vis(full)

/mob/proc/toggle_hud_vis(full)
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

		if(hud_used?.combat_mode_button)
			hud_used.combat_mode_button.screen_loc = ui_acti //Restore the combat mode button to its original position
		client.screen += zone_sel				//This one is a special snowflake
		client.screen += hud_used.toggle_palette

	hud_used.hidden_inventory_update()
	hud_used.persistant_inventory_update()
	update_action_buttons(TRUE)
	hud_used.reorganize_alerts()
	return TRUE

/mob/living/carbon/human/toggle_hud_vis(full)
	if(!(. = ..()))
		return FALSE

	// Prevents humans from hiding a few hud elements
	if(!hud_used.hud_shown) // transitioning to hidden
		//Due to some poor coding some things need special treatment:
		//These ones are a part of 'adding', 'other' or 'hotkeybuttons' but we want them to stay
		if(!full)
			client.screen += hud_used.l_hand_hud_object	//we want the hands to be visible
			client.screen += hud_used.r_hand_hud_object	//we want the hands to be visible
			if(hud_used.combat_mode_button)
				client.screen += hud_used.combat_mode_button		//we want the combat mode button visible
				hud_used.combat_mode_button.screen_loc = ui_acti_alt	//move this to the alternative position, where zone_select usually is.
		else
			client.screen -= healths
			client.screen -= internals
			client.screen -= gun_setting_icon

		//These ones are not a part of 'adding', 'other' or 'hotkeybuttons' but we want them gone.
		client.screen -= zone_sel	//zone_sel is a mob variable for some reason.

//Similar to button_pressed_F12() but keeps zone_sel, gun_setting_icon, and healths.
/mob/proc/toggle_zoom_hud()
	if(!hud_used)
		return
	if(!ishuman(src))
		return
	if(!client)
		return
	if(client.view != world.view)
		return

	if(hud_used.hud_shown)
		hud_used.hud_shown = 0
		if(hud_used.adding)
			client.screen -= hud_used.adding
		if(hud_used.other)
			client.screen -= hud_used.other
		if(hud_used.hotkeybuttons)
			client.screen -= hud_used.hotkeybuttons
		client.screen -= internals
		if(hud_used.combat_mode_button)
			client.screen += hud_used.combat_mode_button		//we want the combat mode button visible
	else
		hud_used.hud_shown = 1
		if(hud_used.adding)
			client.screen += hud_used.adding
		if(hud_used.other && hud_used.inventory_shown)
			client.screen += hud_used.other
		if(hud_used.hotkeybuttons && !hud_used.hotkey_ui_hidden)
			client.screen += hud_used.hotkeybuttons
		if(internals)
			client.screen |= internals
		if(hud_used.combat_mode_button)
			hud_used.combat_mode_button.screen_loc = ui_acti //Restore the combat mode button to its original position

	hud_used.hidden_inventory_update()
	hud_used.persistant_inventory_update()
	update_action_buttons(TRUE)

/mob/proc/add_click_catcher()
	client.screen += client.void

/mob/new_player/add_click_catcher()
	return

/mob/living/create_mob_hud(datum/hud/HUD, apply_to_client = TRUE)
	..()

	var/list/hud_elements = list()
	shadekin_display = new /atom/movable/screen/shadekin()
	shadekin_display.screen_loc = ui_shadekin_display
	shadekin_display.icon_state = "shadekin"
	hud_elements |= shadekin_display

	xenochimera_danger_display = new /atom/movable/screen/xenochimera/danger_level()
	xenochimera_danger_display.screen_loc = ui_xenochimera_danger_display
	xenochimera_danger_display.icon_state = "danger00"
	hud_elements |= xenochimera_danger_display

	lleill_display = new /atom/movable/screen/lleill()
	lleill_display.screen_loc = ui_lleill_display
	lleill_display.icon_state = "lleill"
	hud_elements |= lleill_display

	if(client)
		client.screen = list()

		client.screen += hud_elements
		client.screen += client.void

/* TGMC Ammo HUD Port
 * These procs call to screen_objects.dm's respective procs.
 * All these do is manage the amount of huds on screen and set the HUD.
*/
///Add an ammo hud to the user informing of the ammo count of G
/datum/hud/proc/add_ammo_hud(mob/living/user, obj/item/gun/G)
	if(length(ammo_hud_list) >= MAX_AMMO_HUD_POSSIBLE)
		return
	var/atom/movable/screen/ammo/ammo_hud = new
	LAZYSET(ammo_hud_list, om_handle(G), ammo_hud)
	ammo_hud.screen_loc = ammo_hud.ammo_screen_loc_list[length(ammo_hud_list)]
	ammo_hud.our_gun = om_handle(G)
	ammo_hud.add_hud(user, G)
	ammo_hud.update_hud(user, G)

///Remove the ammo hud related to the gun G from the user
/datum/hud/proc/remove_ammo_hud(mob/living/user, obj/item/gun/G)
	var/gun_handle = om_handle_of(G) // the gun may be on its way out
	var/atom/movable/screen/ammo/ammo_hud = gun_handle && LAZYACCESS(ammo_hud_list, gun_handle)
	if(isnull(ammo_hud))
		return
	ammo_hud.our_gun = null
	ammo_hud.remove_hud(user, G)
	qdel(ammo_hud)
	LAZYREMOVE(ammo_hud_list, gun_handle)
	var/i = 1
	for(var/key in ammo_hud_list)
		ammo_hud = LAZYACCESS(ammo_hud_list, key)
		ammo_hud.screen_loc = ammo_hud.ammo_screen_loc_list[i]
		i++

///Update the ammo hud related to the gun G
/datum/hud/proc/update_ammo_hud(mob/living/user, obj/item/gun/G)
	var/atom/movable/screen/ammo/ammo_hud = LAZYACCESS(ammo_hud_list, om_handle(G))
	ammo_hud?.update_hud(user, G)

#undef MAX_AMMO_HUD_POSSIBLE

/// LC-refs: the mob this hud belongs to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/hud/proc/mymob() as /mob
	return om_resolve(mymob_handle)

REF_OWNED(/datum/global_hud, list("druggy", "blurry", "whitense", "heavy_whitense", "centermarker", "darksight", "nvg", "thermal", "meson", "science", "material", "holomap"))
