/mob/observer
	name = "observer"
	desc = "This shouldn't appear"
	density = FALSE
	vis_flags = NONE
	var/mob/living/body_backup = null //add reforming

/mob/observer/dead
	name = "ghost"
	desc = "It's a g-g-g-g-ghooooost!" //jinkies!
	icon = 'icons/mob/ghost.dmi'
	icon_state = "ghost"
	stat = DEAD
	canmove = FALSE
	blinded = FALSE
	anchored = TRUE	//  don't get pushed around
	var/list/visibleChunks = list() // ALLOW(instance_list): d: per-mob visibleChunks, filled at runtime; mobs are few
	var/datum/visualnet/ghost/visualnet
	var/static_visibility_range = 16

	var/can_reenter_corpse
	var/datum/hud/living/carbon/hud = null // hud
	var/bootime = 0
	var/started_as_observer //This variable is set to 1 when you enter the game as an observer.
							//If you died in the game and are a ghsot - this will remain as null.
							//Note that this is not a reliable way to determine if admins started as observers, since they change mobs a lot.
	var/has_enabled_antagHUD = FALSE
	var/medHUD = FALSE
	var/secHUD = FALSE
	var/antagHUD = FALSE
	universal_speak = TRUE
	var/admin_ghosted = FALSE
	var/anonsay = FALSE
	var/ghostvision = TRUE //is the ghost able to see things humans can't?
	var/lighting_alpha = 255
	incorporeal_move = TRUE
	/// If set to TRUE, the ghost is able to whisper. Usually only set if a cultist drags them through the veil.
	var/is_manifest = FALSE
	COOLDOWN_DECLARE(invisible_toggle_cooldown)
	var/ghost_sprite = null
	/// If TRUE, the ghost can be interacted with by the corporeal world (ghost traps, photon pack, etc)
	var/interact_with_world = TRUE
	COOLDOWN_DECLARE(revive_notification_cooldown) // world.time of last notification, used to avoid spamming players from defibs or cloners.
	var/selecting_ghostrole = FALSE

	invisibility = INVISIBILITY_OBSERVER
	layer = BELOW_MOB_LAYER
	plane = PLANE_GHOSTS
	alpha = 127
	sight = SEE_TURFS | SEE_MOBS | SEE_OBJS | SEE_SELF
	see_invisible = SEE_INVISIBLE_OBSERVER

/mob/observer/dead/Initialize(mapload, aghost = FALSE)

	appearance = loc
	invisibility = initial(invisibility)
	layer = initial(layer)
	plane = initial(plane)
	alpha = initial(alpha)
	admin_ghosted = aghost

	see_in_dark = world.view //I mean. I don't even know if byond has occlusion culling... but...

	var/turf/T
	if(ismob(loc))
		var/mob/M = loc
		T = get_turf(M)				//Where is the body located?
		gender = M.gender
		if(M.mind && M.mind.name)
			name = M.mind.name
		else
			if(M.real_name)
				name = M.real_name
			else
				if(gender == MALE)
					name = capitalize(pick(GLOB.first_names_male)) + " " + capitalize(pick(GLOB.last_names))
				else
					name = capitalize(pick(GLOB.first_names_female)) + " " + capitalize(pick(GLOB.last_names))

		mind = M.mind	//we don't transfer the mind but we keep a reference to it.

		// Fix for naked ghosts.
		// Unclear why this isn't being grabbed by appearance.
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			add_overlay(H.overlays_standing) // ALLOW(decl): copies the body's overlays
		default_pixel_x = M.default_pixel_x
		default_pixel_y = M.default_pixel_y
	if(!T && REGISTRY_COUNT(REGISTRY_LATEJOIN))
		T = get_turf(pick(REGISTRY_MEMBERS(REGISTRY_LATEJOIN)))			//Safety in case we cannot find the body's position
	if(T)
		forceMove(T, just_spawned = TRUE)
	else
		moveToNullspace()
		to_chat(src, span_danger("Could not locate an observer spawn point. Use the Teleport verb to jump to the station map."))

	if(!name)							//To prevent nameless ghosts
		name = capitalize(pick(GLOB.first_names_male)) + " " + capitalize(pick(GLOB.last_names))
	real_name = name
	animate(src, pixel_y = 2, time = 10, loop = -1)
	animate(pixel_y = default_pixel_y, time = 10, loop = -1)
	. = ..()
	visualnet = GLOB.ghostnet

/mob/observer/dead/proc/checkStatic()
	return !(check_rights_for(src.client, R_ADMIN|R_FUN|R_EVENT|R_SERVER) || (client && client.buildmode) || isbelly(loc))

/mob/observer/dead/Moved(atom/old_loc, direction, forced)
	. = ..()
	if(isbelly(loc) && !isbelly(old_loc))
		visualnet.addVisibility()
	if(visualnet && checkStatic())
		visualnet.visibility(src, client)

/mob/observer/dead/Topic(href, href_list)
	if (href_list["track"])
		var/mob/target = locate_in_list(REGISTRY_MEMBERS(REGISTRY_MOBS), href_list["track"])
		if(target)
			ManualFollow(target)
	if(href_list["reenter"])
		reenter_corpse()
		return

EXTEND_INTERACTIONS(/mob/observer/dead, INTERACT_INSERT(/obj/item/book/tome, PROC_REF(observer_tome_manifest), "Manifest"))

/// Old attackby: a tome makes the ghost manifest.
/mob/observer/dead/proc/observer_tome_manifest(mob/user, obj/item/held, datum/interaction/interaction)
	manifest(user)
	return TRUE

/mob/observer/dead/CanPass(atom/movable/mover, turf/target)
	return TRUE

/mob/observer/dead/set_stat(new_stat)
	if(new_stat != DEAD)
		CRASH("It is best if observers stay dead, thank you.")

/mob/observer/dead/examine_icon()
	var/icon/I = get_cached_examine_icon(src)
	if(!I)
		I = getFlatIcon(src, defdir = SOUTH, no_anim = TRUE)
		set_cached_examine_icon(src, I, 200 SECONDS)
	return I

/mob/observer/dead/examine(mob/user)
	. = ..()

	if(is_admin(user))
		. += "\t>" + span_admin("[ADMIN_FULLMONTY(src)]")

/*
Transfer_mind is there to check if mob is being deleted/not going to have a body.
Works together with spawning an observer, noted above.
*/

/mob/observer/dead/upkeep()
	..()
	if(!loc || !client)
		return

	refresh_hud()
	refresh_vision()
	check_area()	//RS Port #658

//RS Port #658 Start
/mob/observer/dead/proc/check_area()
	if(check_rights_for(client, R_HOLDER))
		return
	if(!isturf(loc))
		return
	var/area/A = get_area(src)
	if(A.flag_check(AREA_BLOCK_GHOSTS) && !isbelly(loc))
		to_chat(src, span_warning("Ghosts can't enter this location."))
		return_to_spawn()

/mob/observer/dead/proc/return_to_spawn()
	if(src?.following_target())
		stop_following()
	var/obj/O = locate("landmark*Observer-Start")
	if(istype(O))
		to_chat(src, span_notice("Now teleporting."))
		forceMove(O.loc)
//RS Port #658 End

/mob/proc/ghostize(can_reenter_corpse = 1, aghost = FALSE)
	reset_perspective(src) // End any remoteview we're in
	if(key)
		if(ishuman(src))
			var/mob/living/carbon/human/H = src
			if(H.vr_holder && !can_reenter_corpse)
				H.exit_vr()
				return 0
		var/mob/observer/dead/ghost = new(src, aghost)	//Transfer safety to observer spawning proc.
		ghost.can_reenter_corpse = can_reenter_corpse
		ghost.timeofdeath = src.timeofdeath
		ghost.key = key
		if(istype(loc, /obj/structure/morgue))
			var/obj/structure/morgue/M = loc
			M.update()
		else if(istype(loc, /obj/structure/closet/body_bag))
			var/obj/structure/closet/body_bag/B = loc
			B.update()
		if(ghost.client)
			ghost.client.time_died_as_mouse = ghost.timeofdeath
		if(ghost.client && !check_rights_for(ghost.client, R_HOLDER) && !CONFIG_GET(flag/antag_hud_allowed))		// For new ghosts we remove the verb from even showing up if it's not allowed.
			remove_verb(ghost, /mob/observer/dead/verb/toggle_antagHUD)	// Poor guys, don't know what they are missing!
		return ghost

/*
This is the proc mobs get to turn into a ghost. Forked from ghostize due to compatibility issues.
*/
/mob/living/verb/ghost()
	set category = "OOC.Game"
	set name = "Ghost"
	set desc = "Relinquish your life and enter the land of the dead."

	if(stat == DEAD && !forbid_seeing_deadchat)
		announce_ghost_joinleave(ghostize(1))
	else
		if(check_rights_for(src.client, R_ADMIN|R_SERVER|R_MOD)) //No need to sanity check for client and holder here as that is part of check_rights
			om_ask(src, /datum/om/prompt/choice, PROC_REF(ghost_choice_made), message = "You have the ability to Admin-Ghost. The regular Ghost verb will announce your presence to dead chat. Both variants will allow you to return to your body using 'aghost'.\n\nWhat do you wish to do?", choices = list("Admin Ghost", "Ghost", "Stay in body"), title = "Are you sure you want to ghost?", buttons = TRUE)
		else
			om_ask(src, /datum/om/prompt/choice, PROC_REF(ghost_choice_made), message = "Are you -sure- you want to ghost?\n(You are alive, or otherwise have the potential to become alive. Don't abuse ghost unless you are inside a cryopod or equivalent! You can't change your mind so choose wisely!)", choices = list("Stay in body", "Ghost"), title = "Are you sure you want to ghost?", buttons = TRUE)

/mob/living/proc/ghost_choice_made(datum/om/prompt/choice/ask)
	var/response = ask.choice
	if(response == "Admin Ghost")
		if(!src.client)
			return
		SSadmin_verbs.dynamic_invoke_verb(client, /datum/admin_verb/admin_ghost)
	if(response != "Ghost")
		return
	resting = 1
	var/turf/location = get_turf(src)
	var/special_role = check_special_role()
	if(!istype(loc,/obj/machinery/cryopod))
		log_and_message_admins("has ghosted outside cryo[special_role ? " as [special_role]" : ""]. (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[location.x];Y=[location.y];Z=[location.z]'>JMP</a>)",src)
	else if(special_role)
		log_and_message_admins("has ghosted in cryo as [special_role]. (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[location.x];Y=[location.y];Z=[location.z]'>JMP</a>)",src)
	var/mob/observer/dead/ghost = ghostize(0)	// 0 parameter is so we can never re-enter our body, "Charlie, you can never come baaaack~" :3
	if(ghost)
		EXPIRY_STAMP(ghost, timeofdeath, CLOCK_WORLD) 	// Because the living mob won't have a time of death and we want the respawn timer to work properly.
		ghost.set_respawn_timer()
		announce_ghost_joinleave(ghost)

/mob/observer/dead/can_use_hands()	return 0
/mob/observer/dead/is_active()		return 0

/mob/observer/dead/get_status_tab_items()
	. = ..()
	if(GLOB.emergency_shuttle_service)
		var/eta_status = GLOB.emergency_shuttle_service.get_status_panel_eta()
		if(eta_status)
			. += ""
			. += "[eta_status]"

/mob/observer/dead/verb/reenter_corpse()
	set category = "Ghost.Game"
	set name = "Re-enter Corpse"
	if(!client)	return
	if(!(mind && mind.current && can_reenter_corpse))
		to_chat(src, span_warning("You have no body."))
		return
	if(mind.current.key && copytext(mind.current.key,1,2)!="@")	//makes sure we don't accidentally kick any clients
		to_chat(src, span_warning("Another consciousness is in your body... it is resisting you."))
		return
	if(GLOB.prevent_respawns.Find(mind.name))
		to_chat(src, span_warning("You already quit this round as this character, sorry!"))
		return
	if(mind.current.ajourn && mind.current.stat != DEAD) //check if the corpse is astral-journeying (it's client ghosted using a cultist rune).
		var/found_rune
		for(var/obj/effect/rune/R in mind.current.loc)   //whilst corpse is alive, we can only reenter the body if it's on the rune
			if(R && R.word1 == GLOB.cultwords["hell"] && R.word2 == GLOB.cultwords["travel"] && R.word3 == GLOB.cultwords["self"]) // Found an astral journey rune.
				found_rune = 1
				break
		if(!found_rune)
			to_chat(src, span_warning("The astral cord that ties your body and your spirit has been severed. You are likely to wander the realm beyond until your body is finally dead and thus reunited with you."))
			return
	mind.current.ajourn=0
	mind.current.key = key
	mind.current.teleop = null
	if(istype(mind.current.loc, /obj/structure/morgue))
		var/obj/structure/morgue/M = mind.current.loc
		M.update(1)
	else if(istype(mind.current.loc, /obj/structure/closet/body_bag))
		var/obj/structure/closet/body_bag/B = mind.current.loc
		B.update(1)
	if(!admin_ghosted)
		announce_ghost_joinleave(mind, 0, "They now occupy their body again.")
	if(admin_ghosted)
		log_and_message_admins("Admin [key_name(src)] re-entered their body.")
	return 1

/mob/observer/dead/verb/toggle_medHUD()
	set category = "Ghost.Settings"
	set name = "Toggle MedicHUD"
	set desc = "Toggles Medical HUD allowing you to see how everyone is doing"

	medHUD = !medHUD
	plane_holder.set_vis(VIS_CH_HEALTH, medHUD)
	plane_holder.set_vis(VIS_CH_STATUS_OOC, medHUD)
	to_chat(src, span_boldnotice("Medical HUD [medHUD ? "Enabled" : "Disabled"]"))

/mob/observer/dead/verb/toggle_secHUD()
	set category = "Ghost.Settings"
	set name = "Toggle Security HUD"
	set desc = "Toggles Security HUD allowing you to see people's displayed ID's job, wanted status, etc"

	secHUD = !secHUD
	plane_holder.set_vis(VIS_CH_ID, secHUD)
	plane_holder.set_vis(VIS_CH_WANTED, secHUD)
	plane_holder.set_vis(VIS_CH_IMPTRACK, secHUD)
	plane_holder.set_vis(VIS_CH_IMPLOYAL, secHUD)
	plane_holder.set_vis(VIS_CH_IMPCHEM, secHUD)
	to_chat(src, span_boldnotice("Security HUD [secHUD ? "Enabled" : "Disabled"]"))

/mob/observer/dead/verb/toggle_antagHUD()
	set category = "Ghost.Settings"
	set name = "Toggle AntagHUD"
	set desc = "Toggles AntagHUD allowing you to see who is the antagonist"

	if(!CONFIG_GET(flag/antag_hud_allowed) && !check_rights_for(client, R_HOLDER))
		to_chat(src, span_filter_notice(span_red("Admins have disabled this for this round.")))
		return
	if(jobban_isbanned(src, JOB_ANTAGHUD))
		to_chat(src, span_filter_notice(span_red(span_bold("You have been banned from using this feature"))))
		return
	if(CONFIG_GET(flag/antag_hud_restricted) && !has_enabled_antagHUD && !check_rights_for(client, R_HOLDER))
		om_ask(src, /datum/om/prompt/confirm, PROC_REF(antag_hud_confirmed), title = "Are you sure you want to turn this feature on?", message = "If you turn this on, you will not be able to take any part in the round.")
		return
	toggle_antag_hud_now()

/mob/observer/dead/proc/antag_hud_confirmed(datum/om/prompt/confirm/ask)
	can_reenter_corpse = FALSE
	set_respawn_timer(-1) // Foreeeever
	toggle_antag_hud_now()

/mob/observer/dead/proc/toggle_antag_hud_now()
	if(!has_enabled_antagHUD && !check_rights_for(client, R_HOLDER))
		has_enabled_antagHUD = TRUE

	antagHUD = !antagHUD
	plane_holder.set_vis(VIS_CH_SPECIAL, antagHUD)
	to_chat(src, span_boldnotice("AntagHUD [antagHUD ? "Enabled" : "Disabled"]"))

/mob/observer/dead/proc/jumpable_areas()
	var/list/areas = return_sorted_areas()
	if(check_rights_for(client, R_HOLDER))
		return areas

	for(var/key in areas)
		var/area/A = areas[key]
		if(A.z in using_map?.secret_levels)
			areas -= key
		if(A.z in using_map?.hidden_levels)
			areas -= key

	return areas

/mob/observer/dead/proc/jumpable_mobs()
	var/list/mobs = getmobs()
	if(check_rights_for(client, R_HOLDER))
		return mobs

	for(var/key in mobs)
		var/mobz = get_z(mobs[key])
		if(mobz in using_map?.secret_levels)
			mobs -= key
		if(mobz in using_map?.hidden_levels)
			mobs -= key

	return mobs

/mob/observer/dead/verb/dead_tele(areaname as anything in jumpable_areas())
	set name = "Teleport"
	set category = "Ghost.Game"
	set desc = "Teleport to a location."

	if(!isobserver(src))
		to_chat(src, span_filter_notice("Not when you're not dead!"))
		return

	var/area/A

	if(areaname)
		A = return_sorted_areas()[areaname]
	else
		om_ask(src, /datum/om/prompt/choice, PROC_REF(dead_tele_chosen), title = "Ghost Teleport", message = "Select an area:", choices = jumpable_areas())
		return
	dead_tele_to(A)

/mob/observer/dead/proc/dead_tele_chosen(datum/om/prompt/choice/ask)
	dead_tele_to(return_sorted_areas()[ask.choice])

/mob/observer/dead/proc/dead_tele_to(area/A)
	if(!A)
		return

	if(!isobserver(src))
		to_chat(src, "Not when you're not dead!")
		return

	src.forceMove(pick(get_area_turfs(A)))
	src.on_mob_jump()

/mob/observer/dead/verb/follow(mobname as anything in jumpable_mobs())
	set name = "Follow"
	set category = "Ghost.Game"
	set desc = "Follow and haunt a mob."

	if(!isobserver(src))
		to_chat(src, "Not when you're not dead!")
		return

	if(!mobname)
		var/list/possible_mobs = jumpable_mobs()
		om_ask(src, /datum/om/prompt/choice, PROC_REF(follow_target_chosen), title = "Ghost Follow", message = "Select a mob:", choices = possible_mobs)
		return
	follow_mob(jumpable_mobs()[mobname])

/mob/observer/dead/proc/follow_target_chosen(datum/om/prompt/choice/ask)
	follow_mob(ask.choices[ask.choice])

/mob/observer/dead/proc/follow_mob(mob/M)
	if(!M)
		return
	if(!isobserver(src))
		to_chat(src, "Not when you're not dead!")
		return

	ManualFollow(M)

/mob/observer/dead/forceMove(atom/destination, direction, movetime, just_spawned = FALSE) // pass movetime through
	if(check_rights_for(client, R_HOLDER))
		return ..()

	if(get_z(destination) in using_map?.secret_levels)
		to_chat(src,span_warning("Sorry, that z-level does not allow ghosts."))
		if(src?.following_target())
			stop_following()
		return

	//RS Port #658 Start
	var/area/A = get_area(destination)
	if(A?.flag_check(AREA_BLOCK_GHOSTS) && !isbelly(destination) && !admin_ghosted && !just_spawned)
		to_chat(src,span_warning("Sorry, that area does not allow ghosts."))
		if(src?.following_target())
			stop_following()
		return
	//RS Port #658 End
	return ..()

/mob/observer/dead/Move(atom/newloc, direct = 0, movetime)
	if(check_rights_for(client, R_HOLDER))
		return ..()

	if(get_z(newloc) in using_map?.secret_levels)
		to_chat(src,span_warning("Sorry, that z-level does not allow ghosts."))
		if(src?.following_target())
			stop_following()
		return

	return ..()

// This is the ghost's follow verb with an argument
/mob/observer/dead/proc/ManualFollow(atom/movable/target)
	if(!target)
		return

	var/turf/targetloc = get_turf(target)
	if(check_holy(targetloc))
		to_chat(src, span_warning("You cannot follow a mob standing on holy grounds!"))
		return
	if(get_z(target) in using_map?.secret_levels)
		to_chat(src, span_warning("Sorry, that target is in an area that ghosts aren't allowed to go."))
		return

	var/icon/I = icon(target.icon,target.icon_state,target.dir)

	var/orbitsize = (I.Width()+I.Height())*0.5
	orbitsize -= (orbitsize/world.icon_size)*(world.icon_size*0.25)

	var/rot_seg

	/* We don't have this pref yet
	switch(ghost_orbit)
		if(GHOST_ORBIT_TRIANGLE)
			rot_seg = 3
		if(GHOST_ORBIT_SQUARE)
			rot_seg = 4
		if(GHOST_ORBIT_PENTAGON)
			rot_seg = 5
		if(GHOST_ORBIT_HEXAGON)
			rot_seg = 6
		else //Circular
			rot_seg = 36 //360/10 bby, smooth enough aproximation of a circle
	*/

	om_link(src, target, /datum/om/relation/following) // replaces any previous follow
	orbit(target, orbitsize, FALSE, 20, rot_seg)

/mob/observer/dead/orbit()
	set_dir(2) //reset dir so the right directional sprites show up
	return ..()

/mob/observer/dead/orbit_ended(atom/center)
	. = ..()
	//restart our floating animation after orbit is done.
	pixel_y = default_pixel_y
	pixel_x = default_pixel_x
	transform = null
	animate(src, pixel_y = 2, time = 10, loop = -1)
	animate(pixel_y = default_pixel_y, time = 10, loop = -1)

/mob/observer/dead/proc/stop_following()
	var/atom/movable/followed = src?.following_target()
	if(followed)
		om_unlink(src, followed, /datum/om/relation/following)
	stop_orbit()

/mob/proc/update_following()
	. = get_turf(src)
	for(var/mob/observer/dead/M in src?.follower_list())
		if(!.)
			M.stop_following()
		else if(M.loc != .)
			M.forceMove(., movetime = MOVE_GLIDE_CALC(glide_size, moving_diagonally)) // pass movespeed

REGISTRY_MEMBERSHIP(/mob/observer/dead, REGISTRY_OBSERVERS)

// its exonet address is released before phase 4 deletes the owned exonet.
/mob/observer/dead/on_destroy(force)
	exonet?.remove_address()
	..()

// a ghost leaves the ghost visualnet and its chunks; one with a client is re-ghosted.
/mob/observer/dead/on_destroy(force)
	visualnet.addVisibility(src, src.client)
	stop_following()
	for(var/datum/chunk/ghost/ghost_chunks in visibleChunks)
		ghost_chunks.remove(src)
	// deal with weird behavior on qdelled ghosts
	if(client) //qdelling a ghost with a client = make a new ghost i guess
		ghostize()
	if(key)
		key = null
	..()

/mob/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	update_following()

/// Observer upkeep, run by the observer_upkeep behaviour every OBSERVER_UPKEEP_INTERVAL
/// (code/modules/mob/living/life/life_om.dm). Living mobs do the same in their upkeep system.
/mob/observer/proc/upkeep()
	// to catch teleports etc which directly set loc
	update_following()
	update_spell_masters()

/mob/proc/check_holy(turf/T)
	return FALSE

/mob/observer/dead/check_holy(turf/T)
	if(check_rights_for(src.client, R_ADMIN|R_FUN|R_EVENT))
		return FALSE

	return (T && T.holy) && (is_manifest || (mind in GLOB.cult.current_antagonists))

/mob/observer/dead/verb/jumptomob() //Moves the ghost instead of just changing the ghosts's eye -Nodrak
	set category = "Ghost.Game"
	set name = "Jump to Mob"
	set desc = "Teleport to a mob"
	set popup_menu = FALSE

	if(!isobserver(src)) //Make sure they're an observer!
		return

	var/list/possible_mobs = jumpable_mobs()
	om_ask(src, /datum/om/prompt/choice, PROC_REF(jump_target_chosen), title = "Ghost Jump", message = "Select a mob:", choices = possible_mobs)

/mob/observer/dead/proc/jump_target_chosen(datum/om/prompt/choice/ask)
	if(!isobserver(src)) //Make sure they're an observer!
		return

	var/target = ask.choices[ask.choice]
	if (!target)//Make sure we actually have a target
		return
	else
		var/mob/M = target //Destination mob
		var/turf/T = get_turf(M) //Turf of the destination mob

		if(T && isturf(T))	//Make sure the turf exists, then move the source to that destination.
			forceMove(T)
			stop_following()
		else
			to_chat(src, span_filter_notice("This mob is not located in the game world."))

/mob/observer/dead/memory()
	set hidden = 1
	to_chat(src, span_filter_notice(span_red("You are dead! You have no mind to store memory!")))

/mob/observer/dead/add_memory()
	set hidden = 1
	to_chat(src, span_filter_notice(span_red("You are dead! You have no mind to store memory!")))

/mob/observer/dead/Post_Incorpmove()
	if(src?.following_target()) //This wasn't here before. It meant that we would do stop_following repeatedly every movement we made...Resulting in a DOS on our client.
		stop_following()

/mob/observer/dead/verb/analyze_air()
	set name = "Analyze Air"
	set category = "Ghost.Game"

	if(!isobserver(src)) return

	// Shamelessly copied from the Gas Analyzers
	if (!( istype(src.loc, /turf) ))
		return

	var/datum/gas_mixture/environment = src.loc.return_air()

	var/pressure = environment.return_pressure()
	var/total_moles = environment.total_moles()
	var/list/gas_analyzing = list()
	gas_analyzing += span_bold("Results:")
	if(abs(pressure - ONE_ATMOSPHERE) < 10)
		gas_analyzing += "Pressure: [round(pressure,0.1)] kPa"
	else
		gas_analyzing += span_red("Pressure: [round(pressure,0.1)] kPa")
	if(total_moles)
		// XGM env.gas[g] iteration → LINDA env.gases[/datum/gas/X][MOLES].
		for(var/datum/gas/g as anything in environment.get_gases())
			var/_moles = environment.get_moles(g)
			gas_analyzing += "[initial(g.name)]: [round((_moles / total_moles) * 100)]% ([round(_moles, 0.01)] moles)"
		gas_analyzing += "Temperature: [round(environment.return_temperature()-T0C,0.1)]&deg;C ([round(environment.return_temperature(),0.1)]K)"
		gas_analyzing += "Heat Capacity: [round(environment.heat_capacity(),0.1)]"
	to_chat(src, span_notice("[jointext(gas_analyzing, "<br>")]"))
/*
/mob/observer/dead/verb/check_radiation()
	set name = "Check Radiation"
	set category = "Ghost.Game"

	var/turf/t = get_turf(src)
	if(t)
		var/rads = GLOB.radiation_service.get_rads_at_turf(t)
		to_chat(src, span_notice("Radiation level: [rads ? rads : "0"] Bq."))
*/
/mob/observer/dead/verb/view_manfiest()
	set name = "Show Crew Manifest"
	set category = "Ghost.Game"

	var/datum/tgui_module/crew_manifest/self_deleting/S = new(src)
	S.tgui_interact(src)

//This is called when a ghost is drag clicked to something.
/mob/observer/dead/MouseDrop(atom/over)
	if(!usr || !over) return
	if (isobserver(usr) && usr.client && check_rights_for(usr.client, R_HOLDER) && isliving(over))
		if (usr.client.holder.cmd_ghost_drag(src,over))
			return

	return ..()

//Used for drawing on walls with blood puddles as a spooky ghost.
/mob/observer/dead/verb/bloody_doodle()

	set category = "Ghost.Game"
	set name = "Write in blood"
	set desc = "If the round is sufficiently spooky, write a short message in blood on the floor or a wall. Remember, no IC in OOC or OOC in IC."

	if(!CONFIG_GET(flag/cult_ghostwriter))
		to_chat(src, span_filter_notice(span_red("That verb is not currently permitted.")))
		return

	if (!src.stat)
		return

	if (usr != src)
		return 0 //something is terribly wrong

	var/ghosts_can_write
	if(SSticker.mode.name == "cult")
		if(length(GLOB.cult.current_antagonists) > CONFIG_GET(number/cult_ghostwriter_req_cultists))
			ghosts_can_write = 1

	if(!ghosts_can_write && !check_rights(R_ADMIN|R_EVENT|R_FUN, 0)) //Let's allow for admins to write in blood for events and the such.
		to_chat(src, span_filter_notice(span_red("The veil is not thin enough for you to do that.")))
		return

	var/list/choices = list()
	for(var/obj/effect/decal/cleanable/blood/B in view(1,src))
		if(B.amount > 0)
			choices += B

	if(!choices.len)
		to_chat(src, span_warning("There is no blood to use nearby."))
		return

	om_flow_start(/datum/om/flow/bloody_doodle, src, null, choices = choices)

/// A ghost writing in blood: which blood, which tile, then the message.
/datum/om/flow/bloody_doodle
	name = "bloody doodle"
	var/list/choices
	var/obj/effect/decal/cleanable/blood/blood
	var/direction

/datum/om/flow/bloody_doodle/start()
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(blood_picked), title = "Blood Choice", message = "What blood would you like to use?", choices = choices)

/datum/om/flow/bloody_doodle/proc/blood_picked(datum/om/prompt/choice/ask)
	blood = ask.choice
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(direction_picked), title = "Tile selection", message = "Which way?", choices = list("Here","North","South","East","West"))

/datum/om/flow/bloody_doodle/proc/direction_picked(datum/om/prompt/choice/ask)
	direction = ask.choice
	om_ask(actor, /datum/om/prompt/text, PROC_REF(message_written), title = "Blood writing", message = "Write a message. It cannot be longer than 50 characters.", default = "", max_length = 50)

/datum/om/flow/bloody_doodle/proc/message_written(datum/om/prompt/text/ask)
	var/mob/observer/dead/ghost = actor
	ghost.bloody_doodle_written(blood, direction, ask.text)

/mob/observer/dead/proc/bloody_doodle_written(obj/effect/decal/cleanable/blood/choice, direction, message)
	var/turf/simulated/T = src.loc
	if (direction != "Here")
		T = get_step(T,text2dir(direction))

	if (!istype(T))
		to_chat(src, span_warning("You cannot doodle there."))
		return

	if(!choice || choice.amount == 0 || !(src.Adjacent(choice)))
		return

	var/doodle_color = (choice.basecolor) ? choice.basecolor : "#A10808"

	var/num_doodles = 0
	for (var/obj/effect/decal/cleanable/blood/writing/W in turf_contents_of_type(T, /obj/effect/decal/cleanable/blood/writing))
		num_doodles++
	if (num_doodles > 4)
		to_chat(src, span_warning("There is no space to write on!"))
		return

	var/max_length = 50

	if (message)

		if (length(message) > max_length)
			message += "-"
			to_chat(src, span_warning("You ran out of blood to write with!"))

		var/obj/effect/decal/cleanable/blood/writing/W = new(T)
		W.basecolor = doodle_color
		W.update_icon()
		W.message = message
		W.add_hiddenprint(src)
		W.visible_message(span_filter_notice(span_red("Invisible fingers crudely paint something in blood on [T]...")))

/mob/observer/dead/_pointed(atom/pointed_at)
	if(!..())
		return FALSE

	visible_message(span_deadsay(span_bold("[src]") + " points to [pointed_at]."))

/mob/observer/dead/proc/manifest(mob/user)
	is_manifest = TRUE
	// Allows them to use the 'toggle_visibility' verb add_verb(src, /mob/observer/dead/verb/toggle_visibility)
	// Allows them to use the 'ghost  whisper' verb add_verb(src, /mob/observer/dead/verb/ghost_whisper)
	to_chat(src, span_filter_notice(span_purple("As you are now in the realm of the living, you can whisper to the living with the " + span_bold("Spectral Whisper") + " verb, inside the IC tab.")))
	if(!user)
		visible_message(span_deadsay("The ghost of \the [src] is dragged back in to our plane of reality!"))
		toggle_ghost_visibility(TRUE)
		return
	if(plane != PLANE_WORLD)
		user.visible_message( \
			span_warning("\The [user] drags ghost, [src], to our plane of reality!"), \
			span_warning("You drag [src] to our plane of reality!") \
		)
		toggle_ghost_visibility(TRUE)
	else
		user.visible_message ( \
			span_warning("\The [user] just tried to smash [user.p_their()] book into that ghost!  It's not very effective."), \
			span_warning("You get the feeling that the ghost can't become any more visible.") \
		)

/mob/observer/dead/proc/toggle_icon(icon)
	if(!client)
		return

	var/iconRemoved = 0
	for(var/image/I in client.images)
		if(I.icon_state == icon)
			iconRemoved = 1
			qdel(I)

	if(!iconRemoved)
		var/image/J = image('icons/mob/mob.dmi', loc = src, icon_state = icon)
		client.images += J

/mob/observer/dead/verb/toggle_interactions()

	set name = "Toggle Interactions"
	set desc = "Allows you to toggle if you wish for the corporeal world to interact with you!"
	set category = "Ghost.Settings"
	toggle_ghost_interactions()

/mob/observer/dead/proc/toggle_ghost_interactions()
	if(is_manifest)
		to_chat(src, span_info("You are currently manifested into the world and can not toggle this!"))
		return

	interact_with_world = !interact_with_world
	to_chat(src, span_info("You will [interact_with_world ? "now" : "no longer"] be able to be interacted with by the corporeal world!"))

/mob/observer/dead/verb/toggle_visibility()

	set name = "Toggle Visibility"
	set desc = "Allows you to turn (in)visible (almost) at will."
	set category = "Ghost.Settings"
	toggle_ghost_visibility()

/mob/observer/dead/proc/toggle_ghost_visibility(forced = FALSE)
	if(!is_manifest)
		to_chat(src, span_filter_notice("You are not strong enough to pierce the veil..."))
		return
	if(!forced && plane == PLANE_GHOSTS && !COOLDOWN_FINISHED(src, invisible_toggle_cooldown))
		to_chat(src, span_filter_notice("You must gather strength before you can turn visible again..."))
		return

	if(plane == PLANE_WORLD)
		COOLDOWN_START(src, invisible_toggle_cooldown, 600)
		visible_message(span_emote("It fades from sight..."), span_info("You are now invisible."))
	else
		to_chat(src, span_info("You are now visible!"))

	plane = (plane == PLANE_GHOSTS) ? PLANE_WORLD : PLANE_GHOSTS
	invisibility = (plane == PLANE_WORLD) ? INVISIBILITY_NONE : INVISIBILITY_OBSERVER

	// Give the ghost a cult icon which should be visible only to itself
	toggle_icon("cult")

/mob/observer/dead/verb/toggle_anonsay()
	set category = "Ghost.Settings"
	set name = "Toggle Anonymous Chat"
	set desc = "Toggles showing your key in dead chat."

	src.anonsay = !src.anonsay
	if(anonsay)
		to_chat(src, span_info("Your key won't be shown when you speak in dead chat."))
	else
		to_chat(src, span_info("Your key will be publicly visible again."))

/mob/observer/dead/canface()
	return 1

/mob/observer/dead/proc/can_admin_interact()
	return check_rights_for(src.client, R_ADMIN|R_EVENT|R_DEBUG)

/mob/observer/dead/verb/toggle_ghostsee()
	set name = "Toggle Ghost Vision"
	set desc = "Toggles your ability to see things only ghosts can see, like other ghosts"
	set category = "Ghost.Settings"
	ghostvision = !ghostvision
	updateghostsight()
	to_chat(src, span_filter_notice("You [ghostvision ? "now" : "no longer"] have ghost vision."))

/mob/observer/dead/verb/toggle_darkness()
	set name = "Toggle Darkness"
	set desc = "Toggles your ability to see lighting overlays, and the darkness they create."
	set category = "Ghost.Settings"

	var/static/list/darkness_names = list("normal darkness levels", "30% darkness removed", "70% darkness removed", "no darkness")
	var/static/list/darkness_levels = list(255, 178, 76, 0)

	var/index = darkness_levels.Find(lighting_alpha)
	if(!index || index >= darkness_levels.len)
		index = 1
	else
		index++

	lighting_alpha = darkness_levels[index]
	updateghostsight()
	to_chat(src, span_filter_notice("Your vision now has [darkness_names[index]]."))

/mob/observer/dead/proc/updateghostsight()
	plane_holder.set_desired_alpha(VIS_LIGHTING, lighting_alpha)
	plane_holder.set_vis(VIS_LIGHTING, lighting_alpha)
	plane_holder.set_vis(VIS_GHOSTS, ghostvision)

/mob/observer/dead/MayRespawn(feedback = FALSE)
	if(!client)
		return FALSE
	if(mind && mind.current && mind.current.stat != DEAD && can_reenter_corpse)
		if(feedback)
			to_chat(src, span_warning("Your non-dead body prevents you from respawning."))
		return FALSE
	if(CONFIG_GET(flag/antag_hud_restricted) && has_enabled_antagHUD == 1)
		if(feedback)
			to_chat(src, span_warning("antagHUD restrictions prevent you from respawning."))
		return FALSE
	return TRUE

/proc/extra_ghost_link(atom/target, atom/ghost)
	if(isobserver(target))
		var/mob/observer/dead/dead = target
		if(dead.mind && dead.mind.current)
			return "|<a href='byond://?src=\ref[ghost];track=\ref[dead.mind.current]'>body</a>"
		return
	if(ismob(target))
		var/mob/M = target
		var/mob/observer/eye/eyeobj = M?.active_eye()
		if(M.client && eyeobj)
			return "|<a href='byond://?src=\ref[ghost];track=\ref[eyeobj]'>eye</a>"

/proc/ghost_follow_link(atom/target, atom/ghost)
	if((!target) || (!ghost)) return
	. = "<a href='byond://?src=\ref[ghost];track=\ref[target]'>follow</a>"
	. += extra_ghost_link(target, ghost)

//Culted Ghosts

/mob/observer/dead/verb/ghost_whisper()
	set name = "Spectral Whisper"
	set category = "IC.Subtle"

	if(is_manifest)  //Only able to whisper if it's hit with a tome.
		var/list/options = list()
		for(var/mob/living/Ms in view(src))
			options += Ms
		om_ask(src, /datum/om/prompt/choice/spectral_whisper_target, PROC_REF(spectral_whisper_target_chosen), choices = options)
		return 1
	else
		to_chat(src, span_danger("You have not been pulled past the veil! You can not whisper to the living."))

/// Only a manifested ghost can whisper: re-checked when each answer arrives.
/datum/om/prompt/choice/spectral_whisper_target
	title = "Whisper to?"
	message = "Select who to whisper to:"

/datum/om/prompt/choice/spectral_whisper_target/valid()
	var/mob/observer/dead/ghost = answerer
	return (istype(ghost) && ghost.is_manifest) ? null : "not manifest"

/datum/om/prompt/text/spectral_whisper
	title = "Spectral Whisper"
	message = "Message:"
	default = ""
	max_length = MAX_MESSAGE_LEN

/datum/om/prompt/text/spectral_whisper/valid()
	var/mob/observer/dead/ghost = answerer
	return (istype(ghost) && ghost.is_manifest) ? null : "not manifest"

/mob/observer/dead/proc/spectral_whisper_target_chosen(datum/om/prompt/choice/spectral_whisper_target/ask)
	om_ask(src, /datum/om/prompt/text/spectral_whisper, PROC_REF(spectral_whisper_written), subject = ask.choice)

/mob/observer/dead/proc/spectral_whisper_written(datum/om/prompt/text/spectral_whisper/ask)
	var/mob/living/M = ask.subject
	var/msg = ask.text
	if(msg)
		log_talk("(SPECWHISP to [key_name(M)]): [msg]", LOG_WHISPER)
		to_chat(M, span_warning(" You hear a strange, unidentifiable voice in your head... [span_purple("[msg]")]"))
		to_chat(src, span_warning(" You said: '[msg]' to [M]."))
	else
		return
	return 1

/mob/observer/dead/verb/choose_ghost_sprite()
	set category = "Ghost.Settings"
	set name = "Choose Sprite"

	ask_ghost_sprite(icon_state)

/// Picks a sprite (shown at once), then asks to keep it; a no picks again, a cancel puts the old one back.
/mob/observer/dead/proc/ask_ghost_sprite(previous_state)
	om_ask(src, /datum/om/prompt/choice/ghost_sprite, PROC_REF(ghost_sprite_chosen), previous = previous_state)

/datum/om/prompt/choice/ghost_sprite
	title = "Ghost Sprite"
	message = "What would you like to use for your ghost sprite?"
	/// The icon_state before the first pick.
	var/previous

/datum/om/prompt/choice/ghost_sprite/New()
	..()
	choices = GLOB.possible_ghost_sprites

/datum/om/prompt/confirm/ghost_sprite
	title = "Ghost Sprite"
	message = "Look at your sprite. Is this what you wish to use?"
	no_first = TRUE
	answer_on_no = TRUE
	var/previous
	var/picked_sprite

/datum/om/prompt/confirm/ghost_sprite/cancelled()
	var/mob/observer/dead/ghost = answerer
	if(istype(ghost))
		ghost.icon_state = previous

/mob/observer/dead/proc/ghost_sprite_chosen(datum/om/prompt/choice/ghost_sprite/ask)
	icon = 'icons/mob/ghost.dmi'
	cut_overlays()
	icon_state = GLOB.possible_ghost_sprites[ask.choice]
	om_ask(src, /datum/om/prompt/confirm/ghost_sprite, PROC_REF(ghost_sprite_confirmed), previous = ask.previous, picked_sprite = ask.choice)

/mob/observer/dead/proc/ghost_sprite_confirmed(datum/om/prompt/confirm/ghost_sprite/ask)
	if(!ask.yes)
		icon_state = ask.previous
		ask_ghost_sprite(ask.previous)
		return
	ghost_sprite = GLOB.possible_ghost_sprites[ask.picked_sprite]
	if(ghost_sprite == "blank")
		log_and_message_admins("[key_name(src)] has set their ghost sprite to invisible.", src)

/mob/observer/dead/is_blind()
	return FALSE

/mob/observer/dead/is_deaf()
	return FALSE

/mob/observer/dead/verb/paialert()
	set category = "Ghost.Message"
	set name = "Blank pAI alert"
	set desc = "Flash an indicator light on available blank pAI devices for a smidgen of hope."

	var/time_till_respawn = time_till_respawn()
	if(time_till_respawn == -1) // Special case, never allowed to respawn
		to_chat(src, span_warning("Respawning is not allowed!"))
	else if(time_till_respawn) // Nonzero time to respawn
		to_chat(src, span_warning("You can't do that yet! You died too recently. You need to wait another [round(time_till_respawn/10/60, 0.1)] minutes."))
		return

	if(jobban_isbanned(src, "pAI"))
		to_chat(src,span_warning("You cannot alert pAI cards when you are banned from playing as a pAI."))
		return

	if(!(src.client.prefs?.read_preference(/datum/preference/numeric/human/be_special) & BE_PAI)) // migrated
		to_chat(src,span_warning("You have 'Be pAI' disabled in your character prefs."))
		return

	om_ask(src, /datum/om/prompt/confirm, PROC_REF(pai_alert_confirmed), title = "Confirmation", message = "Would you like to submit yourself to the recruitment list too?", no_first = TRUE)

/mob/observer/dead/proc/pai_alert_confirmed(datum/om/prompt/confirm/ask)

	to_chat(src,span_notice("Flashing the displays of [pai_card_ping()] unoccupied PAIs."))

/mob/observer/dead/proc/pai_card_ping()
	var/count = 0
	for(var/obj/item/paicard/p in REGISTRY_MEMBERS(REGISTRY_PAI_CARDS))
		var/obj/item/paicard/PP = p
		if(PP.pai)
			continue
		count++
		PP.cut_overlays()
		PP.add_overlay("pai-ghostalert")
		PP.alertUpdate()
		om_after(PP, 1 MINUTE, TYPE_PROC_REF(/obj/item/paicard, clear_invite_overlay))
	return count

/mob/observer/dead/speech_bubble_appearance()
	return "ghost"

// Lets a ghost know someone's trying to bring them back, and for them to get into their body.
// Mostly the same as TG's sans the hud element, since we don't have TG huds.
/mob/observer/dead/proc/notify_revive(message, sound, flashwindow = TRUE, atom/source)
	if(!COOLDOWN_FINISHED(src, revive_notification_cooldown))
		return
	COOLDOWN_START(src, revive_notification_cooldown, 2 MINUTES)

	if(flashwindow)
		window_flash(client)
	if(message)
		to_chat(src, span_ghostalert(span_huge("[message]")))
		if(source)
			throw_alert("\ref[source]_notify_revive", /atom/movable/screen/alert/notify_cloning, new_master = source)
	to_chat(src, span_ghostalert("<a href='byond://?src=[REF(src)];reenter=1'>(Click to re-enter)</a>"))
	if(sound)
		SEND_SOUND(src, sound(sound))

/mob/observer/dead/verb/respawn()
	set name = "Respawn"
	set category = "Ghost.Join"
	src.abandon_mob()

/mob/observer/dead/verb/backup_ping()
	set category = "Ghost.Join"
	set name = "Notify Transcore"
	set desc = "If your past-due backup notification was missed or ignored, you can use this to send a new one."

	if(!mind)
		to_chat(src,span_warning("Your ghost is missing game values that allow this functionality, sorry."))
		return
	var/datum/transcore_db/db = GLOB.transcore_service.db_by_mind_name(mind.name)
	if(db)
		var/datum/transhuman/mind_record/record = db.backed_up[src.mind.name]
		if(!(record.dead_state == MR_DEAD))
			if(ELAPSED(src, timeofdeath, CLOCK_WORLD) > 5 MINUTES)	//Allows notify transcore to be used if you have an entry but for some reason weren't marked as dead
				record.dead_state = MR_DEAD				//Such as if you got scanned but didn't take an implant. It's a little funky, but I mean, you got scanned
				db.notify(record)						//So you probably will want to let someone know if you die.
				EXPIRY_STAMP(record, last_notification, CLOCK_WORLD)
				to_chat(src, span_notice("New notification has been sent."))
			else
				to_chat(src, span_warning("Your backup is not past-due yet."))
		else if(ELAPSED(record, last_notification, CLOCK_WORLD) < 5 MINUTES)
			to_chat(src, span_warning("Too little time has passed since your last notification."))
		else
			db.notify(record)
			EXPIRY_STAMP(record, last_notification, CLOCK_WORLD)
			to_chat(src, span_notice("New notification has been sent."))
	else
		to_chat(src,span_warning("No backup record could be found, sorry."))
// Revert Removal
/mob/observer/dead/verb/backup_delay()
	set category = "Ghost.Settings"
	set name = "Cancel Transcore Notification"
	set desc = "You can use this to avoid automatic backup notification happening. Manual notification can still be used."

	if(!mind)
		to_chat(src,span_warning("Your ghost is missing game values that allow this functionality, sorry."))
		return
	var/datum/transcore_db/db = GLOB.transcore_service.db_by_mind_name(mind.name)
	if(db)
		var/datum/transhuman/mind_record/record = db.backed_up[src.mind.name]
		if(record.dead_state == MR_DEAD || !(record.do_notify))
			to_chat(src, span_warning("The notification has already happened or been delayed."))
		else
			record.do_notify = FALSE
			to_chat(src, span_notice("Overdue mind backup notification delayed successfully."))
	else
		to_chat(src,span_warning("No backup record could be found, sorry."))

/mob/observer/dead/verb/findghostpod() //Moves the ghost instead of just changing the ghosts's eye -Nodrak
	set category = "Ghost.Join"
	set name = "Ghost Spawn"
	set desc = "Open Ghost Spawn Menu"

	if(!isobserver(src)) //Make sure they're an observer!
		return

	if(selecting_ghostrole)
		return

	var/datum/tgui_module/ghost_spawn_menu/ui = new(src)
	ui.tgui_interact(src)

/mob/observer/dead/verb/findautoresleever()
	set category = "Ghost.Join"
	set name = "Find Auto Resleever"
	set desc = "Find a Auto Resleever"
	set popup_menu = FALSE

	if(!isobserver(src)) //Make sure they're an observer!
		return

	// Set up an assorted list of auto-resleevers using their area name as the key, (as there should only ever be one per area)
	var/list/autoresleevers = list()
	for(var/obj/machinery/transhuman/autoresleever/A in REGISTRY_MEMBERS(REGISTRY_AUTORESLEEVERS))
		if(A.spawntype)
			continue
		else
			var/area/resleever_area = get_area(A)
			autoresleevers[resleever_area.name] = A

	var/obj/machinery/transhuman/autoresleever/chosen_resleever = null
	if(length(autoresleevers) > 1)
		// Prompt user to choose which one they wanna go to
		om_ask(src, /datum/om/prompt/choice, PROC_REF(autoresleever_chosen), title = "Choose Auto-Resleever", message = "There are multiple auto-resleevers available! Choose one.", choices = autoresleevers)
		return
	else
		// If there's less than one, just choose whatever one is available (if any)
		chosen_resleever = autoresleevers[pick(autoresleevers)]
	go_to_autoresleever(chosen_resleever)

/mob/observer/dead/proc/autoresleever_chosen(datum/om/prompt/choice/ask)
	go_to_autoresleever(ask.choices[ask.choice])

/mob/observer/dead/proc/go_to_autoresleever(obj/machinery/transhuman/autoresleever/chosen_resleever)
	if(!chosen_resleever)
		to_chat(src, span_warning("There appears to be no auto-resleevers available."))
		return
	var/L = get_turf(chosen_resleever)
	if(!L)
		to_chat(src, span_warning("There appears to be something wrong with this auto-resleever, try again."))
		return

	forceMove(L)

/mob/observer
	low_priority = TRUE

DECLARE_REF(/mob/observer, "body_backup", OWNED, null)
DECLARE_REF(/mob/observer/dead, "visualnet", STATIC, null)
DECLARE_REF(/mob/observer/dead, "hud", HELD, null)
