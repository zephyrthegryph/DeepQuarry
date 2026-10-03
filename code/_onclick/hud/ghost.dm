/atom/movable/screen/ghost
	icon = 'icons/mob/screen_ghost.dmi'

/atom/movable/screen/ghost/MouseEntered(location,control,params)
	flick(icon_state + "_anim", src)
	openToolTip(usr, src, params, title = name, content = desc)

/atom/movable/screen/ghost/MouseExited()
	closeToolTip(usr, src)

/atom/movable/screen/ghost/Click(location, control, params)
	return click_with_actor(usr, location, control, params) // ALLOW(sys_usr_outside_verb): BYOND native ghost HUD clicks provide their actor only through usr

/atom/movable/screen/ghost/click_with_actor(mob/user, location, control, params)
	closeToolTip(user, src)

/atom/movable/screen/ghost/returntomenu
	name = "Return to menu"
	desc = "Return to the title screen menu."
	icon_state = "returntomenu"

/atom/movable/screen/ghost/returntomenu/click_with_actor(mob/user, location, control, params)
	..()
	if(!isobserver(user))
		return
	var/mob/observer/dead/G = user
	G.abandon_mob()

/atom/movable/screen/ghost/jumptomob
	name = "Jump to mob"
	desc = "Pick a mob from a list to jump to."
	icon_state = "jumptomob"

/atom/movable/screen/ghost/jumptomob/click_with_actor(mob/user, location, control, params)
	..()
	if(!isobserver(user))
		return
	var/mob/observer/dead/G = user
	G.jumptomob()

/atom/movable/screen/ghost/orbit
	name = "Orbit"
	desc = "Pick a mob to follow and orbit."
	icon_state = "orbit"

/atom/movable/screen/ghost/orbit/click_with_actor(mob/user, location, control, params)
	..()
	if(!isobserver(user))
		return
	var/mob/observer/dead/G = user
	G.follow()

/atom/movable/screen/ghost/reenter_corpse
	name = "Reenter corpse"
	desc = "Only applicable if you HAVE a corpse..."
	icon_state = "reenter_corpse"

/atom/movable/screen/ghost/reenter_corpse/click_with_actor(mob/user, location, control, params)
	..()
	if(!isobserver(user))
		return
	var/mob/observer/dead/G = user
	G.reenter_corpse()

/atom/movable/screen/ghost/teleport
	name = "Teleport"
	desc = "Pick an area to teleport to."
	icon_state = "teleport"

/atom/movable/screen/ghost/teleport/click_with_actor(mob/user, location, control, params)
	..()
	if(!isobserver(user))
		return
	var/mob/observer/dead/G = user
	G.dead_tele()

/atom/movable/screen/ghost/pai
	name = "pAI Alert"
	desc = "Ping all the unoccupied pAI devices in the world."
	icon_state = "pai"

/atom/movable/screen/ghost/pai/click_with_actor(mob/user, location, control, params)
	..()
	if(!isobserver(user))
		return
	var/mob/observer/dead/G = user
	G.paialert()

/atom/movable/screen/ghost/up
	name = "Move Upwards"
	desc = "Move up a z-level."
	icon_state = "up"

/atom/movable/screen/ghost/up/click_with_actor(mob/user, location, control, params)
	..()
	if(!isobserver(user))
		return
	var/mob/observer/dead/G = user
	G.zMove(UP)

/atom/movable/screen/ghost/down
	name = "Move Downwards"
	desc = "Move down a z-level."
	icon_state = "down"

/atom/movable/screen/ghost/down/click_with_actor(mob/user, location, control, params)
	..()
	if(!isobserver(user))
		return
	var/mob/observer/dead/G = user
	G.zMove(DOWN)

/atom/movable/screen/ghost/vr
	name = "Enter VR"
	desc = "Enter virtual reality."
	icon = 'icons/mob/screen_ghost.dmi'
	icon_state = "entervr"

/atom/movable/screen/ghost/vr/click_with_actor(mob/user, location, control, params)
	..()
	if(!isobserver(user))
		return
	var/mob/observer/dead/G = user
	var/datum/data/record/record_found
	record_found = find_general_record("name", G.client.prefs.read_preference(/datum/preference/name/real_name))
	// Found their record, they were spawned previously. Remind them corpses cannot play games.
	if(record_found)
		var/answer = rerun_ask(G, "k107", PROC_REF(click_with_actor), args, /datum/om/prompt/choice/alert, message = "You seem to have previously joined this round. If you are currently dead, you should not enter VR as this character. Would you still like to proceed?", title = "Previously spawned", choices = list("Yes", "No"))
		if(isnull(answer))
			return
		if(answer != "Yes")
			return

	var/S = null
	var/list/vr_landmarks = list()
	for(var/obj/effect/landmark/virtual_reality/sloc in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		vr_landmarks += sloc.name
	if(!LAZYLEN(vr_landmarks))
		to_chat(G, "There are no available spawn locations in virtual reality.")
		return
	var/_answer_k118 = rerun_ask(G, "k118", PROC_REF(click_with_actor), args, /datum/om/prompt/choice, message = "Please select a location to spawn your avatar at:", title = "Spawn location", choices = vr_landmarks)
	if(isnull(_answer_k118))
		return
	S = _answer_k118
	if(!S)
		return 0
	for(var/obj/effect/landmark/virtual_reality/i in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		if(i.name == S)
			S = i
			break

	G.fake_enter_vr(S)

/mob/observer/dead/create_mob_hud(datum/hud/HUD, apply_to_client = TRUE)
	..()

	var/atom/movable/screen/using
	using = new /atom/movable/screen/ghost/returntomenu()
	using.screen_loc = ui_ghost_returntomenu
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/ghost/jumptomob()
	using.screen_loc = ui_ghost_jumptomob
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/ghost/orbit()
	using.screen_loc = ui_ghost_orbit
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/ghost/reenter_corpse()
	using.screen_loc = ui_ghost_reenter_corpse
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/ghost/teleport()
	using.screen_loc = ui_ghost_teleport
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/ghost/pai()
	using.screen_loc = ui_ghost_pai
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/ghost/up()
	using.screen_loc = ui_ghost_updown
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/ghost/down()
	using.screen_loc = ui_ghost_updown
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/ghost/vr()
	using.screen_loc = ui_ghost_vr
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)
	if(client && apply_to_client)
		client.screen = list()
		if(length(HUD.adding))
			client.screen += HUD.adding
		client.screen += client.void

