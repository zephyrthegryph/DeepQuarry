/*
	Screen objects
	Todo: improve/re-implement

	Screen objects are only used for the hud and should not appear anywhere "in-game".
	They are used with the client/screen list and the screen_loc var.
	For more information, see the byond documentation on the screen_loc and screen vars.
*/
/atom/movable/screen
	name = ""
	icon = 'icons/mob/screen1.dmi'
	appearance_flags = TILE_BOUND|PIXEL_SCALE|NO_CLIENT_COLOR
	layer = LAYER_HUD_BASE
	plane = PLANE_PLAYER_HUD
	/// The object in the slot (a relation view, written with rel_set). Grabs or items, generally, but any datum will do.
	var/datum/master_ref = null
	/// A reference to the owner HUD, if any.
	//VAR_PRIVATE/datum/hud/hud = null //This SHOULD be converted to private eventually, but we're not there yet.
	var/datum/hud/hud	// A reference to the owner HUD, if any.

// L1 (doc/rewrite/lifecycle.md §2 phase 5, "release screens"): whichever
// client(s) it's shown on -- almost always exactly one, but this doesn't
// assume which -- instead of leaving a dangling ref in client.screen for
// the destroy transaction to null out later.
/atom/movable/screen/dq_lifecycle_release_screen()
	for(var/client/C as anything in GLOB.clients)
		if(src in C.screen)
			C.screen -= src

/atom/movable/screen/proc/component_click(atom/movable/screen/component_button/component, params, mob/user)
	return

/atom/movable/screen/text
	icon = null
	icon_state = null
	mouse_opacity = 0
	screen_loc = "CENTER-7,CENTER-7"
	maptext_height = 480
	maptext_width = 480

/atom/movable/screen/inventory
	var/slot_id	//The indentifier for the slot. It has nothing to do with ID cards.
	var/list/object_overlays // Required for inventory/screen overlays.

/atom/movable/screen/inventory/MouseEntered()
	..()
	add_overlays()

/atom/movable/screen/inventory/MouseExited()
	..()
	if(object_overlays) cut_overlay(object_overlays)
	LAZYCLEARLIST(object_overlays)

/atom/movable/screen/close
	name = "close"

/atom/movable/screen/close/Click()
	var/obj/master = master_ref
	if(master)
		if(istype(master, /obj/item/storage))
			var/obj/item/storage/S = master
			S.close(usr)
	return 1

/atom/movable/screen/item_action
	var/obj/item/owner

CAPABILITIES(/atom/movable/screen/item_action)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/item_action/proc/click_input(datum/act/input/A)
	return click_with_actor(A.actor, A.native["location"], A.native["control"], A.params)

/atom/movable/screen/item_action/click_with_actor(mob/user, location, control, params)
	if(!user || !owner())
		return 1
	if(!user.checkClickCooldown())
		return

	if(user.stat || user.restrained() || user.has_status(STAT_STUNNED) || user.lying)
		return 1

	if(!(owner() in user))
		return 1

	owner().ui_action_click(user)
	return 1

/atom/movable/screen/grab
	name = "grab"

/atom/movable/screen/grab/Click()
	var/obj/master = master_ref
	var/obj/item/grab/G = master
	G.s_click(src)
	return 1

// Screen grabs are clicked through Click() above; touches and items do nothing.
DECLARE_INTERACTIONS(/atom/movable/screen/grab, 	INTERACT_HAND_UNGATED("Nothing", TYPE_PROC_REF(/atom, interaction_swallow)), 	INTERACT_ITEM("Nothing", TYPE_PROC_REF(/atom, interaction_swallow)), )

/atom/movable/screen/storage
	name = "storage"

CAPABILITIES(/atom/movable/screen/storage)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/storage/proc/click_input(datum/act/input/A)
	return click_with_actor(A.actor)

/atom/movable/screen/storage/click_with_actor(mob/user, location, control, params)
	if(!user.checkClickCooldown())
		return 1
	if(user.stat || user.has_status(STAT_PARALYZED) || user.has_status(STAT_STUNNED) || user.has_status(STAT_WEAKENED))
		return 1
	if (istype(user.loc,/obj/mecha)) // stops inventory actions in a mech
		return 1
	var/obj/master = master_ref
	if(master)
		var/obj/item/I = user.get_active_hand()
		if(I)
			user.ClickOn(master)
	return 1

/atom/movable/screen/zone_sel
	name = "damage zone"
	icon_state = "zone_sel"
	screen_loc = ui_zonesel
	var/selecting = BP_TORSO
	var/static/list/hover_overlays_cache = list() // ALLOW(cache): overlay objects placed in vis_contents (pooled objects)
	var/hovering_choice
	var/mutable_appearance/selecting_appearance

CAPABILITIES(/atom/movable/screen/zone_sel)
	owns_many(nameof(hover_overlays_cache))
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/zone_sel/proc/click_input(datum/act/input/A)
	return click_with_actor(A.actor, A.native["location"], A.native["control"], A.params)

/atom/movable/screen/zone_sel/click_with_actor(mob/user, location, control, params)
	if(isobserver(user))
		return

	var/list/PL = params2list(params)
	var/icon_x = text2num(PL["icon-x"])
	var/icon_y = text2num(PL["icon-y"])
	var/choice = get_zone_at(icon_x, icon_y)
	if(!choice)
		return 1

	return set_selected_zone(choice, user)

/atom/movable/screen/zone_sel/MouseEntered(location, control, params)
	MouseMove(location, control, params)

/atom/movable/screen/zone_sel/MouseMove(location, control, params)
	if(isobserver(usr))
		return

	var/list/PL = params2list(params)
	var/icon_x = text2num(PL["icon-x"])
	var/icon_y = text2num(PL["icon-y"])
	var/choice = get_zone_at(icon_x, icon_y)

	if(hovering_choice == choice)
		return
	vis_contents -= hover_overlays_cache[hovering_choice]
	hovering_choice = choice

	if(!choice)
		return

	var/obj/effect/overlay/zone_sel/overlay_object = hover_overlays_cache[choice]
	if(!overlay_object)
		overlay_object = new
		overlay_object.icon_state = "[choice]"
		rel_add(src, nameof(hover_overlays_cache), overlay_object, choice)
	vis_contents += overlay_object

/obj/effect/overlay/zone_sel
	icon = 'icons/mob/zone_sel.dmi'
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	alpha = 128
	anchored = TRUE
	layer = LAYER_HUD_ABOVE
	plane = PLANE_PLAYER_HUD_ABOVE

/atom/movable/screen/zone_sel/MouseExited(location, control, params)
	if(!isobserver(usr) && hovering_choice)
		vis_contents -= hover_overlays_cache[hovering_choice]
		hovering_choice = null

/atom/movable/screen/zone_sel/proc/get_zone_at(icon_x, icon_y)
	switch(icon_y)
		if(1 to 3) //Feet
			switch(icon_x)
				if(10 to 15)
					return BP_R_FOOT
				if(17 to 22)
					return BP_L_FOOT
		if(4 to 9) //Legs
			switch(icon_x)
				if(10 to 15)
					return BP_R_LEG
				if(17 to 22)
					return BP_L_LEG
		if(10 to 13) //Hands and groin
			switch(icon_x)
				if(8 to 11)
					return BP_R_HAND
				if(12 to 20)
					return BP_GROIN
				if(21 to 24)
					return BP_L_HAND
		if(14 to 22) //Chest and arms to shoulders
			switch(icon_x)
				if(8 to 11)
					return BP_R_ARM
				if(12 to 20)
					return BP_TORSO
				if(21 to 24)
					return BP_L_ARM
		if(23 to 30) //Head, but we need to check for eye or mouth
			if(icon_x in 12 to 20)
				switch(icon_y)
					if(23 to 24)
						if(icon_x in 15 to 17)
							return O_MOUTH
					if(26) //Eyeline, eyes are on 15 and 17
						if(icon_x in 14 to 18)
							return O_EYES
					if(25 to 27)
						if(icon_x in 15 to 17)
							return O_EYES
				return BP_HEAD

/atom/movable/screen/zone_sel/proc/set_selected_zone(choice, mob/user)
	if(isobserver(user))
		return
	if(choice != selecting)
		selecting = choice
		update_icon()
		if(user)
			changed(user, CHANGE_MOB_TARGETING)

DECLARE_APPEARANCE_PROC(/atom/movable/screen/zone_sel, TYPE_PROC_REF(/atom, appearance_overlays), list())
/atom/movable/screen/zone_sel/appearance_overlays()
	. = list()
	selecting_appearance = mutable_appearance('icons/mob/zone_sel.dmi', "[selecting]")
	. += selecting_appearance

CAPABILITIES(/atom/movable/screen)
	click_on(PROC_REF(screen_click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm). The click goes to the clicker's
/// input inbox as any atom's does (/atom/Click()), then the named HUD controls act on it.
/atom/movable/screen/proc/screen_click_input(datum/act/input/A)
	input_submit(new /datum/input_event/click(A.actor, src, A.native["location"], A.native["control"], A.params))
	click_with_actor(A.actor, A.native["location"], A.native["control"], A.params)
	return TRUE

/// The named HUD controls act on the mob supplied by their native click boundary.
/atom/movable/screen/proc/click_with_actor(mob/user, location, control, params)
	if(!user)	return 1
	switch(name)
		if("toggle")
			if(user.hud_used.inventory_shown)
				user.hud_used.inventory_shown = 0
				user.client.screen -= user.hud_used.other
			else
				user.hud_used.inventory_shown = 1
				user.client.screen += user.hud_used.other

			user.hud_used.hidden_inventory_update()

		if("equip")
			if (istype(user.loc,/obj/mecha)) // stops inventory actions in a mech
				return 1
			if(ishuman(user))
				var/mob/living/carbon/human/H = user
				H.quick_equip()

		if("resist")
			if(isliving(user))
				var/mob/living/L = user
				L.resist()

		if("control_vtec")
			if(isrobot(user))
				var/mob/living/silicon/robot/R = user
				if(R.speed == 0 && R.vtec_active)
					R.speed = -0.5
					R.hud_used.control_vtec.icon_state = "speed_1"
				else if(R.speed == -0.5 && R.vtec_active)
					R.speed = -1
					R.hud_used.control_vtec.icon_state = "speed_2"
				else
					R.speed = 0
					R.hud_used.control_vtec.icon_state = "speed_0"

		if("mov_intent")
			if(isliving(user))
				if(iscarbon(user))
					var/mob/living/carbon/C = user
					if(C.get_equipped_item(SLOT_ID_LEGCUFFED))
						to_chat(C, span_notice("You are legcuffed! You cannot run until you get [C.get_equipped_item(SLOT_ID_LEGCUFFED)] removed!"))
						C.m_intent = I_WALK	//Just incase
						C.hud_used.move_intent.icon_state = "walking"
						return 1
				var/mob/living/L = user
				switch(L.m_intent)
					if(I_RUN)
						L.m_intent = I_WALK
						L.hud_used.move_intent.icon_state = "walking"
					if(I_WALK)
						L.m_intent = I_RUN
						L.hud_used.move_intent.icon_state = "running"
		if("m_intent")
			if(!user.m_int)
				switch(user.m_intent)
					if(I_RUN)
						user.m_int = "13,14"
					if(I_WALK)
						user.m_int = "14,14"
					if("face")
						user.m_int = "15,14"
			else
				user.m_int = null
		if(I_WALK)
			user.m_intent = I_WALK
			user.m_int = "14,14"
		if("face")
			user.m_intent = "face"
			user.m_int = "15,14"
		if(I_RUN)
			user.m_intent = I_RUN
			user.m_int = "13,14"
		if("Reset Machine")
			user.unset_machine()
		if("internal") //dear god this entire thing needs to be rewritten this is literally assaulting my eyes with how awful it is. FUCK.
			if(iscarbon(user))
				var/mob/living/carbon/C = user
				if(!C.stat && !C.has_status(STAT_STUNNED) && !C.has_status(STAT_PARALYZED) && !C.restrained())
					if(C.internal)
						rel_clear(C, nameof(C.internal)) // a relation: the tank stays in its inventory slot
						to_chat(C, span_notice("No longer running on internals."))
						if(C.internals)
							C.internals.icon_state = "internal0"
					else

						var/no_mask
						if(!(C.get_equipped_item(SLOT_ID_MASK) && C.get_equipped_item(SLOT_ID_MASK).item_flags & AIRTIGHT))
							var/mob/living/carbon/human/H = C
							if(!(H.get_equipped_item(SLOT_ID_HEAD) && H.get_equipped_item(SLOT_ID_HEAD).item_flags & AIRTIGHT))
								no_mask = 1

						if(no_mask)
							to_chat(C, span_notice("You are not wearing a suitable mask or helmet."))
							return 1
						else
							var/list/nicename = null
							var/list/tankcheck = null
							var/breathes = GAS_O2    //default, we'll check later
							var/list/tank_moles = list()
							var/from = "on"

							if(ishuman(C))
								var/mob/living/carbon/human/H = C
								breathes = H.species.breath_type
								nicename = list ("suit", "back", "belt", "right hand", "left hand", "left pocket", "right pocket")
								tankcheck = list (H.get_equipped_item(SLOT_ID_SUIT_STORAGE), C.get_equipped_item(SLOT_ID_BACK), H.get_equipped_item(SLOT_ID_BELT), C.get_equipped_item(SLOT_ID_HAND_R), C.get_equipped_item(SLOT_ID_HAND_L), H.get_equipped_item(SLOT_ID_POCKET_L), H.get_equipped_item(SLOT_ID_POCKET_R))
							else
								nicename = list("right hand", "left hand", "back")
								tankcheck = list(C.get_equipped_item(SLOT_ID_HAND_R), C.get_equipped_item(SLOT_ID_HAND_L), C.get_equipped_item(SLOT_ID_BACK))

							// Rigs are a fucking pain since they keep an air tank in nullspace.
							var/obj/item/rig/Rig = C.get_rig()
							if(Rig)
								if(Rig.air_supply && !Rig.offline)
									from = "in"
									nicename |= "hardsuit"
									tankcheck |= Rig.air_supply

							var/obj/item/clothing/suit/space/void/Void = C.get_voidsuit()
							if(Void && Void.tank)
								from = "in"
								nicename |= "hardsuit"
								tankcheck |= Void.tank

							for(var/i=1, i<tankcheck.len+1, ++i)
								if(istype(tankcheck[i], /obj/item/tank))
									var/obj/item/tank/t = tankcheck[i]
									if (!isnull(t.manipulated_by) && t.manipulated_by != C.real_name && findtext(t.desc,breathes))
										tank_moles.Add(t.air_contents.total_moles())	//Someone messed with the tank and put unknown gasses
										continue					//in it, so we're going to believe the tank is what it says it is
									switch(breathes)
																		//These tanks we're sure of their contents
										if(GAS_N2) 							//So we're a bit more picky about them.

											if(LINDA_GAS_AMT(t.air_contents, GAS_N2) && !LINDA_GAS_AMT(t.air_contents, GAS_O2))
												tank_moles.Add(LINDA_GAS_AMT(t.air_contents, GAS_N2))
											else
												tank_moles.Add(0)

										if (GAS_O2)
											if(LINDA_GAS_AMT(t.air_contents, GAS_O2) && !LINDA_GAS_AMT(t.air_contents, GAS_PHORON))
												tank_moles.Add(LINDA_GAS_AMT(t.air_contents, GAS_O2))
											else
												tank_moles.Add(0)

										// No races breath this, but never know about downstream servers.
										if (GAS_CO2)
											if(LINDA_GAS_AMT(t.air_contents, GAS_CO2) && !LINDA_GAS_AMT(t.air_contents, GAS_PHORON))
												tank_moles.Add(LINDA_GAS_AMT(t.air_contents, GAS_CO2))
											else
												tank_moles.Add(0)

										// And here's for the Vox
										if (GAS_PHORON)
											if(LINDA_GAS_AMT(t.air_contents, GAS_PHORON) && !LINDA_GAS_AMT(t.air_contents, GAS_O2))
												tank_moles.Add(LINDA_GAS_AMT(t.air_contents, GAS_PHORON))
											else
												tank_moles.Add(0)

										// Grunts rejoice!
										if (GAS_CH4)
											if(LINDA_GAS_AMT(t.air_contents, GAS_CH4) && !LINDA_GAS_AMT(t.air_contents, GAS_O2))
												tank_moles.Add(LINDA_GAS_AMT(t.air_contents, GAS_CH4))
											else
												tank_moles.Add(0)

								else
									//no tank so we set contents to 0
									tank_moles.Add(0)

							//Alright now we know the contents of the tanks so we have to pick the best one.

							var/best = 0
							var/bestcontents = 0
							for(var/i=1, i <  tank_moles.len + 1 , ++i)
								if(!tank_moles[i])
									continue
								if(tank_moles[i] > bestcontents)
									best = i
									bestcontents = tank_moles[i]

							//We've determined the best container now we set it as our internals

							if(best)
								to_chat(C, span_notice("You are now running on internals from [tankcheck[best]] [from] your [nicename[best]]."))
								rel_set(C, nameof(C.internal), tankcheck[best])

							if(C.internal)
								if(C.internals)
									C.internals.icon_state = "internal1"
							else
								to_chat(C, span_notice("You don't have a[breathes==GAS_O2 ? "n " + GAS_O2 : addtext(" ",breathes)] tank."))

		if("pull")
			user.stop_pulling()
		if("throw")
			if(!user.stat && isturf(user.loc) && !user.restrained())
				user.toggle_throw_mode()
		if("drop")
			if(user.client)
				user.client.drop_item()
		if("autowhisper")
			if(isliving(user))
				var/mob/living/u = user
				u.toggle_autowhisper()
		if("autowhisper mode")
			if(isliving(user))
				var/mob/living/u = user
				u.autowhisper_mode()
		if("check known languages")
			user.check_languages()
		if("set pose")
			if(ishuman(user))
				var/mob/living/carbon/human/u = user
				u.pose()
			else if (issilicon(user))
				var/mob/living/silicon/u = user
				u.pose()

		if("move upwards")
			user.up()
		if("Move Up") // AI version
			user.zMove(UP)

		if("move downwards")
			user.down()
		if("Move Down") // AI version
			user.zMove(DOWN)

		if("use held item on self")
			var/atom/movable/screen/useself/s = src
			if(ishuman(user))
				var/mob/living/carbon/human/u = user
				var/obj/item/i = u.get_active_hand()
				if(i)
					s.can_use(u,i)
				else
					to_chat(user, span_notice("You're not holding anything to use. You need to have something in your active hand to use it."))

		if("module")
			if(isrobot(user))
				var/mob/living/silicon/robot/R = user
				R.pick_module()

		if("inventory")
			if(isrobot(user))
				var/mob/living/silicon/robot/R = user
				if(R.module)
					R.hud_used.toggle_show_robot_modules()
					return 1
				else
					to_chat(R, "You haven't selected a module yet.")

		if("radio")
			if(isrobot(user))
				var/mob/living/silicon/robot/R = user
				R.radio_menu()
		if("panel")
			if(isrobot(user))
				var/mob/living/silicon/robot/R = user
				R.installed_modules()

		if("store")
			if(isrobot(user))
				var/mob/living/silicon/robot/R = user
				if(R.module)
					R.uneq_active()
				else
					to_chat(R, "You haven't selected a module yet.")

		if("module1")
			if(isrobot(user))
				var/mob/living/silicon/robot/R = user
				R.toggle_module(1)

		if("module2")
			if(isrobot(user))
				var/mob/living/silicon/robot/R = user
				R.toggle_module(2)

		if("module3")
			if(isrobot(user))
				var/mob/living/silicon/robot/R = user
				R.toggle_module(3)

		if("AI Core")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.view_core()

		if("Show Camera List")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				var/camera = rerun_ask(ai_user, "k545", PROC_REF(click_with_actor), args, /datum/prompt/choice, question = "Pick Camera:", title = "Camera Choice", choices = ai_user.get_camera_list())
				if(isnull(camera))
					return
				ai_user.ai_camera_list(camera)

		if("Track With Camera")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				var/target_name = rerun_ask(ai_user, "k551", PROC_REF(click_with_actor), args, /datum/prompt/choice, question = "Pick Mob:", title = "Mob Choice", choices = ai_user.trackable_mobs())
				if(isnull(target_name))
					return
				ai_user.ai_camera_track(target_name)

		if("Toggle Camera Light")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.toggle_camera_light()

		if("Crew Monitoring")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.subsystem_crew_monitor()

		if("Show Crew Manifest")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.subsystem_crew_manifest()

		if("Show Alerts")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.subsystem_alarm_monitor()

		if("Announcement")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.ai_announcement()

		if("Call Emergency Shuttle")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.ai_call_shuttle()

		if("State Laws")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.ai_checklaws()

		if("PDA - Messenger")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.aiPDA.start_program(ai_user.aiPDA.find_program(/datum/data/pda/app/messenger))
				ai_user.aiPDA.cmd_pda_open_ui(user)

		if("Take Image")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.take_image()

		if("View Images")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.view_images()

		if("Multicamera Mode")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.toggle_multicam()

		if("New Camera")
			if(isAI(user))
				var/mob/living/silicon/ai/ai_user = user
				ai_user.drop_new_multicam()

		if("shadekin status")
			var/turf/T = get_turf(user)
			if(T)
				var/darkness = round(1 - T.get_lumcount(),0.1)
				to_chat(user,span_notice(span_bold("Darkness:") + " [darkness]"))
			var/mob/living/H = user
			if(ismob(H))
				var/datum/shadekin/SK = H.get_shadekin_state()
				if(SK)
					to_chat(user,span_notice(span_bold("Energy:") + " [SK.shadekin_get_energy()]"))

		if("glamour")
			var/mob/living/carbon/human/H = user
			if(istype(H))
				to_chat(user,span_notice(span_bold("Energy:") + " [H.species.lleill_energy]/[H.species.lleill_energy_max]"))

		if("danger level")
			var/mob/living/carbon/human/H = user
			var/datum/xenochimera/xc = H.get_xenochimera_state()
			if(xc)
				if(xc.feral > 50)
					to_chat(user, span_warning("You are currently <b>completely feral.</b>"))
				else if(xc.feral > 10)
					to_chat(user, span_warning("You are currently <b>crazed and confused.</b>"))
				else if(xc.feral > 0)
					to_chat(user, span_warning("You are currently <b>acting on instinct.</b>"))
				else
					to_chat(user, span_notice("You are currently <b>calm and collected.</b>"))
				if(xc.feral > 0)
					var/feral_passing = TRUE
					if(H.traumatic_shock > min(60, H.nutrition/10))
						to_chat(user, span_warning("Your pain prevents you from regaining focus."))
						feral_passing = FALSE
					if(xc.feral + H.nutrition < 150)
						to_chat(user, span_warning("Your hunger prevents you from regaining focus."))
						feral_passing = FALSE
					if(H.status_units(STAT_JITTERY) >= 100)
						to_chat(user, span_warning("Your jitterness prevents you from regaining focus."))
						feral_passing = FALSE
					if(feral_passing)
						var/turf/T = get_turf(H)
						if(T.get_lumcount() <= 0.1)
							to_chat(user, span_notice("You are slowly calming down in darkness' safety..."))
						else if(isbelly(H.loc)) // Safety message for if inside a belly.
							to_chat(user, span_notice("You are slowly calming down within the darkness of something's belly, listening to their body as it moves around you. ...safe..."))
						else
							to_chat(user, span_notice("You are slowly calming down... But safety of darkness is much preferred."))
				else
					if(H.nutrition < 150)
						to_chat(user, span_warning("Your hunger is slowly making you unstable."))

		if("Reconstructing Form") // Allow Viewing Reconstruction Timer + Hatching for 'chimera
			var/mob/living/carbon/human/H = user
			var/datum/xenochimera/xc = H.get_xenochimera_state()
			if(xc) // If you're somehow able to click this while not a chimera, this should prevent weird runtimes. Will need changing if regeneration is ever opened to non-chimera using the same alert.
				if(xc.revive_ready == REVIVING_NOW)
					to_chat(user, span_notice("We are currently reviving, and will be done in [round((xc.revive_finished - world.time) / 10)] seconds, or [round(((xc.revive_finished - world.time) * 0.1) / 60)] minutes."))
				else if(xc.revive_ready == REVIVING_DONE)
					to_chat(user, span_warning("You should have a notification + alert for this! Bug report that this is still here!"))

		if("Ready to Hatch") // Allow Viewing Reconstruction Timer + Hatching for 'chimera
			var/mob/living/carbon/human/H = user
			var/datum/xenochimera/xc = H.get_xenochimera_state()
			if(xc) // If you're somehow able to click this while not a chimera, this should prevent weird runtimes. Will need changing if regeneration is ever opened to non-chimera using the same alert.
				if(xc.revive_ready == REVIVING_DONE) // Sanity check.
					H.hatch() // Hatch.
	return 1

CAPABILITIES(/atom/movable/screen/inventory)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/inventory/proc/click_input(datum/act/input/A)
	return click_with_actor(A.actor, A.native["location"], A.native["control"], A.params)

/atom/movable/screen/inventory/click_with_actor(mob/user, location, control, params)
	if(!user)
		return 1
	// At this point in client Click() code we have passed the 1/10 sec check and little else
	// We don't even know if it's a middle click
	if(!user.checkClickCooldown())
		return 1
	if(user.stat || user.has_status(STAT_PARALYZED) || user.has_status(STAT_STUNNED) || user.has_status(STAT_WEAKENED))
		return 1
	if (istype(user.loc,/obj/mecha)) // stops inventory actions in a mech
		return 1
	switch(name)
		if("r_hand")
			if(iscarbon(user))
				var/mob/living/carbon/C = user
				C.activate_hand("r")
		if("l_hand")
			if(iscarbon(user))
				var/mob/living/carbon/C = user
				C.activate_hand("l")
		if("swap")
			user.swap_hand()
		if("hand")
			user.swap_hand()
		else
			if(user.attack_ui(slot_id))
				user.update_inv_l_hand(0)
				user.update_inv_r_hand(0)
	return 1

// Hand slots are special to handle the handcuffs overlay
/atom/movable/screen/inventory/hand
	var/image/handcuff_overlay

DECLARE_APPEARANCE_PROC(/atom/movable/screen/inventory/hand, TYPE_PROC_REF(/atom, appearance_overlays), list())
/atom/movable/screen/inventory/hand/appearance_overlays()
	. = list()
	. += ..()
	if(!owner_hud())
		return .
	if(!handcuff_overlay)
		var/state = (owner_hud().l_hand_hud_object == src) ? "l_hand_hud_handcuffs" : "r_hand_hud_handcuffs"
		handcuff_overlay = image("icon"='icons/mob/screen_gen.dmi', "icon_state"=state)
	if(owner_hud().mymob() && iscarbon(owner_hud().mymob()))
		var/mob/living/carbon/C = owner_hud().mymob()
		if(C.get_equipped_item(SLOT_ID_HANDCUFFED))
			. += handcuff_overlay

// PIP stuff
/atom/movable/screen/component_button
	var/atom/movable/screen/parent

CAPABILITIES(/atom/movable/screen/component_button)
	param(nameof(parent), pos = 1)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/component_button/proc/click_input(datum/act/input/A)
	if(parent())
		parent().component_click(src, A.native["location"], A.actor)
	return TRUE

// Character setup stuff
/atom/movable/screen/setup_preview

	var/datum/preferences/pref

// Background 'floor'
/atom/movable/screen/setup_preview/pm_helper
	icon = null
	icon_state = null
	appearance_flags = PLANE_MASTER
	plane = PLANE_EMISSIVE
	alpha = 0

/atom/movable/screen/setup_preview/bg
	mouse_over_pointer = MOUSE_HAND_POINTER

/atom/movable/screen/setup_preview/bg/Click(params)
	// migrated bgstate
	if(pref())
		// bgstate_options moved onto the pref subtype as bgstate_choices.
		// Cast through the typed local rather than reaching the subtype member with `:`;
		// the `:` operator skips compile-time validation (CLAUDE.md §6b).
		var/datum/preference/text/human/bgstate/bg_pref = GLOB.preference_entries[/datum/preference/text/human/bgstate]
		var/list/options = bg_pref?.bgstate_choices
		pref().update_preference_by_type(/datum/preference/text/human/bgstate, next_in_list(pref().read_preference(/datum/preference/text/human/bgstate), options))
		pref().update_preview_icon()
/**
 * This object holds all the on-screen elements of the mapping unit.
 * It has a decorative frame and onscreen buttons. The map itself is drawn
 * using a white mask and multiplying the mask against it to crop it to the
 * size of the screen. This is not ideal, as filter() is faster, and has
 * alpha masks, but the alpha masks it has can't be animated, so the 'ping'
 * mode of this device isn't possible using that technique.
 *
 * The markers use that technique, though, so at least there's that.
 */
/atom/movable/screen/movable/mapper_holder
	name = "gps unit"
	icon = null
	icon_state = ""
	screen_loc = "CENTER,CENTER"
	alpha = 255
	appearance_flags = KEEP_TOGETHER
	mouse_opacity = 1
	plane = PLANE_HOLOMAP

	var/running = FALSE

	var/atom/movable/screen/mapper/mask_full/mask_full
	var/atom/movable/screen/mapper/mask_ping/mask_ping
	var/atom/movable/screen/mapper/bg/bg

	var/atom/movable/screen/mapper/frame/frame
	var/atom/movable/screen/mapper/powbutton/powbutton
	var/atom/movable/screen/mapper/mapbutton/mapbutton

	var/obj/item/mapping_unit/owner
	var/atom/movable/screen/mapper/extras_holder/extras_holder

CAPABILITIES(/atom/movable/screen/movable/mapper_holder)
	owns_one(nameof(mask_full), starts = /atom/movable/screen/mapper/mask_full)
	owns_one(nameof(mask_ping), starts = /atom/movable/screen/mapper/mask_ping)
	owns_one(nameof(bg), starts = /atom/movable/screen/mapper/bg)
	owns_one(nameof(frame), starts = /atom/movable/screen/mapper/frame)
	owns_one(nameof(powbutton), starts = /atom/movable/screen/mapper/powbutton)
	owns_one(nameof(mapbutton), starts = /atom/movable/screen/mapper/mapbutton)
	param(nameof(owner), pos = 1)

// ALLOW(init/INSTANCE_STATE): the minimap holder frames itself for its owner's HUD and lays out its layers
/atom/movable/screen/movable/mapper_holder/Initialize(mapload)
	. = ..()

	frame.icon_state = initial(frame.icon_state)+owner().hud_frame_hint

	/**
	 * The vis_contents layout is: this(frame,extras_holder(),mask(bg(map)))
	 * bg is set to BLEND_MULTIPLY against the mask to crop it.
	 */

	mask_full.vis_contents.Add(bg)
	mask_ping.vis_contents.Add(bg)
	frame.vis_contents.Add(powbutton,mapbutton)
	vis_contents.Add(frame)


/atom/movable/screen/movable/mapper_holder/proc/update(atom/movable/screen/mapper/map, atom/movable/screen/mapper/extras_holder/extras, ping = FALSE)
	if(!running)
		running = TRUE
		if(ping)
			vis_contents.Add(mask_ping)
		else
			vis_contents.Add(mask_full)

	bg.vis_contents.Cut()
	bg.vis_contents.Add(map)

	if(extras && !extras_holder())
		rel_set(src, nameof(extras_holder), extras)
		vis_contents += extras_holder()
	if(!extras && extras_holder())
		vis_contents -= extras_holder()
		rel_clear(src, nameof(extras_holder))

/atom/movable/screen/movable/mapper_holder/proc/powerClick()
	if(running)
		off()
	else
		on()

/atom/movable/screen/movable/mapper_holder/proc/mapClick()
	if(owner())
		if(running)
			off()
		owner().pinging = !owner().pinging
		on()

/atom/movable/screen/movable/mapper_holder/proc/off(inform = TRUE)
	frame.cut_overlay("powlight")
	bg.vis_contents.Cut()
	vis_contents.Remove(mask_ping, mask_full, extras_holder())
	rel_clear(src, nameof(extras_holder))
	running = FALSE
	if(inform)
		owner().stop_updates()

/atom/movable/screen/movable/mapper_holder/proc/on(inform = TRUE)
	frame.add_overlay("powlight")
	if(inform)
		owner().start_updates()

// Prototype
/atom/movable/screen/mapper
	plane = PLANE_HOLOMAP
	mouse_opacity = 0
	var/atom/movable/screen/movable/mapper_holder/parent

// ALLOW(init/INSTANCE_STATE): its parent is the atom it is created inside
/atom/movable/screen/mapper/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(parent), loc)

// Holds the actual map image
/atom/movable/screen/mapper/map
	var/offset_x = 32
	var/offset_y = 32

// I really wish I could use filters for this instead of this multiplication-masking technique
// but alpha filters can't be animated, which means I can't use them for the 'sonar ping' mode.
// If filters start supporting animated icons in the future (for the alpha mask filter),
// you should definitely replace these with that technique instead.
/atom/movable/screen/mapper/mask_full
	icon = 'icons/effects/64x64.dmi'
	icon_state = "mapper_mask"

/atom/movable/screen/mapper/mask_ping
	icon = 'icons/effects/64x64.dmi'
	icon_state = "mapper_ping"

/atom/movable/screen/mapper/bg
	icon = 'icons/effects/64x64.dmi'
	icon_state = "mapper_bg"

	blend_mode = BLEND_MULTIPLY
	appearance_flags = KEEP_TOGETHER

// Frame/deco components
/atom/movable/screen/mapper/frame
	icon = 'icons/effects/gpshud.dmi'
	icon_state = "frame"
	plane = PLANE_HOLOMAP_FRAME
	pixel_x = -18
	pixel_y = -29
	mouse_opacity = 1
	vis_flags = VIS_INHERIT_ID

/atom/movable/screen/mapper/powbutton
	icon = 'icons/effects/gpshud.dmi'
	icon_state = "powbutton"
	plane = PLANE_HOLOMAP_FRAME
	mouse_opacity = 1

CAPABILITIES(/atom/movable/screen/mapper/powbutton)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/mapper/powbutton/proc/click_input(datum/act/input/A)
	return click_with_actor(A.actor)

/atom/movable/screen/mapper/powbutton/click_with_actor(mob/user, location, control, params)
	if(!user.checkClickCooldown())
		return TRUE
	if(user.stat || user.has_status(STAT_PARALYZED) || user.has_status(STAT_STUNNED) || user.has_status(STAT_WEAKENED))
		return TRUE
	if(istype(user.loc,/obj/mecha)) // stops inventory actions in a mech
		return TRUE
	parent().powerClick()
	flick("powClick",src)
	user << get_sfx(SFX_BUTTON)
	return TRUE

/atom/movable/screen/mapper/mapbutton
	icon = 'icons/effects/gpshud.dmi'
	icon_state = "mapbutton"
	plane = PLANE_HOLOMAP_FRAME
	mouse_opacity = 1

CAPABILITIES(/atom/movable/screen/mapper/mapbutton)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/mapper/mapbutton/proc/click_input(datum/act/input/A)
	return click_with_actor(A.actor)

/atom/movable/screen/mapper/mapbutton/click_with_actor(mob/user, location, control, params)
	if(!user.checkClickCooldown())
		return TRUE
	if(user.stat || user.has_status(STAT_PARALYZED) || user.has_status(STAT_STUNNED) || user.has_status(STAT_WEAKENED))
		return TRUE
	if(istype(user.loc,/obj/mecha)) // stops inventory actions in a mech
		return TRUE
	parent().mapClick()
	flick("mapClick",src)
	user << get_sfx(SFX_BUTTON)
	return TRUE

// Markers are 16x16, people have apparently settled on centering them on the 8,8 pixel
/atom/movable/screen/mapper/marker
	icon = 'icons/holomap_markers.dmi'
	plane = PLANE_HOLOMAP_ICONS

	var/offset_x = -8
	var/offset_y = -8

// Holds markers in its vis_contents. It uses an alpha filter to crop them to the HUD screen size
/atom/movable/screen/mapper/extras_holder
	icon = null
	icon_state = null
	plane = PLANE_HOLOMAP_ICONS
	appearance_flags = KEEP_TOGETHER

// Begin TGMC Ammo HUD Port
/atom/movable/screen/ammo
	name = "ammo"
	icon = 'icons/mob/screen_ammo.dmi'
	icon_state = "ammo"
	screen_loc = ui_ammo_hud1
	var/warned = FALSE
	var/static/list/ammo_screen_loc_list = list(ui_ammo_hud1, ui_ammo_hud2, ui_ammo_hud3 ,ui_ammo_hud4)
	/// The gun this hud reports (a relation view)
	var/obj/item/gun/our_gun

/atom/movable/screen/ammo/Click()
	var/mob/user = usr
	if(!user.checkClickCooldown())
		return TRUE
	if(user.stat || user.has_status(STAT_PARALYZED) || user.has_status(STAT_STUNNED) || user.has_status(STAT_WEAKENED))
		return TRUE
	if(istype(user.loc,/obj/mecha)) // stops inventory actions in a mech
		return TRUE
	var/obj/item/gun/gun = our_gun
	if(!gun)
		return TRUE
	gun.switch_firemodes(user)
	return TRUE

/atom/movable/screen/ammo/proc/add_hud(mob/living/user, obj/item/gun/G)

	if(!user?.client)
		return

	if(!G)
		CRASH("/atom/movable/screen/ammo/proc/add_hud() has been called from [src] without the required param of G")

	// start
	if(!G.hud_enabled)
		return

	if(!G.has_ammo_counter())
		return

	user.client.screen += src

/atom/movable/screen/ammo/proc/remove_hud(mob/living/user)
	user?.client?.screen -= src

/atom/movable/screen/ammo/proc/update_hud(mob/living/user, obj/item/gun/G)
	if(!user?.client?.screen.Find(src))
		return

	if(!G || !istype(G) || !G.has_ammo_counter() || !G.get_ammo_type() || isnull(G.get_ammo_count()))
		remove_hud(user)
		return

	var/list/ammo_type = G.get_ammo_type()
	var/rounds = G.get_ammo_count()

	var/hud_state = ammo_type[1]
	var/hud_state_empty = ammo_type[2]

	overlays.Cut()

	var/empty = image('icons/mob/screen_ammo.dmi', src, "[hud_state_empty]")

	if(rounds == 0)
		if(warned)
			overlays += empty
		else
			warned = TRUE
			var/atom/movable/screen/ammo/F = new /atom/movable/screen/ammo(src)
			F.icon_state = "frame"
			user.client.screen += F
			flick("[hud_state_empty]_flash", F)
			after(src, 2 SECONDS, PROC_REF(end_empty_flash), with = list(user, F, empty))
	else
		warned = FALSE
		overlays += image('icons/mob/screen_ammo.dmi', src, "[hud_state]")

	rounds = num2text(rounds)
	//Handle the amount of rounds
	switch(length(rounds))
		if(1)
			overlays += image('icons/mob/screen_ammo.dmi', src, "o[rounds[1]]")
		if(2)
			overlays += image('icons/mob/screen_ammo.dmi', src, "o[rounds[2]]")
			overlays += image('icons/mob/screen_ammo.dmi', src, "t[rounds[1]]")
		if(3)
			overlays += image('icons/mob/screen_ammo.dmi', src, "o[rounds[3]]")
			overlays += image('icons/mob/screen_ammo.dmi', src, "t[rounds[2]]")
			overlays += image('icons/mob/screen_ammo.dmi', src, "h[rounds[1]]")
		else //"0" is still length 1 so this means it's over 999
			overlays += image('icons/mob/screen_ammo.dmi', src, "o9")
			overlays += image('icons/mob/screen_ammo.dmi', src, "t9")
			overlays += image('icons/mob/screen_ammo.dmi', src, "h9")

//Invesitgating a runtime made me discover that all simplemobs have HUD on hands set to themselves
//Which cause this original code to die because the mob does not have a mymob var...
//So yeah this is why we now check if it is type of mob first...
//Is this pretty? Fuck no, but its how i know to fix it -shark
//Oh also the swap button on simple mob hands has hud set to null so we also need to catch that.
/atom/movable/screen/inventory/proc/add_overlays()
	if(!owner_hud()) //Simplemob swap hands button has this set to null :)
		return
	var/mob/user
	if(ismob(owner_hud())) //Simplemob hands directly reference the mob in hud, dont ask me.
		user = owner_hud()
	else
		user = owner_hud().mymob() //original intended behaviour
	if(owner_hud() && user && slot_id)

		var/obj/item/holding = user.get_active_hand()

		if(!holding || user.get_equipped_item(slot_id))
			return

		var/image/item_overlay = image(holding)
		item_overlay.alpha = 92

		if(holding.equip_refusal(user, slot_id, disable_warning = TRUE))
			item_overlay.color = "#ff0000"
		else
			item_overlay.color = "#00ff00"

		LAZYADD(object_overlays, item_overlay)
		add_overlay(object_overlays)

/atom/movable/screen/ammo/proc/end_empty_flash(mob/user, atom/movable/screen/ammo/F, image/empty)
	user.client?.screen -= F
	spent(F, user)
	overlays += empty

/// The hud this screen object belongs to (a relation view: null once that is deleted).
/atom/movable/screen/proc/owner_hud() as /datum/hud
	return hud

/// The item this button acts for (a relation view: null once that is deleted).
/atom/movable/screen/item_action/proc/owner() as /obj/item
	return owner

/// The screen object this button belongs to (a relation view: null once that is deleted).
/atom/movable/screen/component_button/proc/parent() as /atom/movable/screen
	return parent

/// The preferences this preview shows (a relation view: null once that is deleted).
/atom/movable/screen/setup_preview/proc/pref() as /datum/preferences
	return pref

/// The mapping unit this holder shows (a relation view: null once that is deleted).
/atom/movable/screen/movable/mapper_holder/proc/owner() as /obj/item/mapping_unit
	return owner

/// The extras overlay the mapping unit handed us (a relation view: null once that is deleted).
/atom/movable/screen/movable/mapper_holder/proc/extras_holder() as /atom/movable/screen/mapper/extras_holder
	return extras_holder

/// The mapper holder this element belongs to (a relation view: null once that is deleted).
/atom/movable/screen/mapper/proc/parent() as /atom/movable/screen/movable/mapper_holder
	return parent

