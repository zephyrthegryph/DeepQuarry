/mob/proc/on_mob_jump()
	return

/mob/observer/dead/on_mob_jump()
	stop_following()

ADMIN_VERB(Jump, R_ADMIN|R_MOD|R_DEBUG|R_EVENT, "Jump to Area", "Area to jump to.", ADMIN_CATEGORY_GAME, areaname as null|anything in return_sorted_areas())
	if(!CONFIG_GET(flag/allow_admin_jump))
		tgui_alert_async(user, "Admin jumping disabled")
		return

	var/area/target_area

	if(areaname)
		target_area = return_sorted_areas()[areaname]
	else
		var/_answer_a1 = verb_prompt(user, "a1", list("kind" = "list", "message" = "Pick an area:", "title" = "Jump to Area", "choices" = return_sorted_areas()), args)
		if(isnull(_answer_a1))
			return
		target_area = return_sorted_areas()[_answer_a1]

	if(!target_area)
		return

	user.mob.on_mob_jump()
	user.mob.reset_perspective(user.mob)
	var/turf/target = pick(get_area_turfs(target_area))
	if(!target)
		to_chat(user, span_warning("Selected area [target_area] has no turfs!"))
		return
	user.mob.forceMove(target)
	log_and_message_admins("jumped to [target_area]", user)
	feedback_add_details("admin_verb","JA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_AND_CONTEXT_MENU(jumptoturf, R_ADMIN|R_MOD|R_DEBUG|R_EVENT, "Jump to Turf", "Jump to a specific turf in the game.", ADMIN_CATEGORY_GAME, turf/T in world)
	if(CONFIG_GET(flag/allow_admin_jump))
		log_and_message_admins("jumped to [T.x],[T.y],[T.z] in [T.loc]", user)
		user.mob.on_mob_jump()
		user.mob.reset_perspective(user)
		user.mob.forceMove(T)
		feedback_add_details("admin_verb","JT") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		return
	tgui_alert_async(user, "Admin jumping disabled")

/// Verb wrapper around do_jumptomob()
ADMIN_VERB_AND_CONTEXT_MENU(jumptomob, R_ADMIN|R_MOD|R_DEBUG|R_EVENT, "Jump to Mob", "Jump to the selected mob.", ADMIN_CATEGORY_GAME, mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
	user.do_jumptomob(M)

/// An admin jump/send pick (title, message and choices set at the call).
/datum/om/prompt/choice/admin_jump
	requires = PROMPT_ADMIN(R_ADMIN|R_MOD|R_DEBUG|R_EVENT)
	/// Send Mob: the area picked first.
	var/area/area

/client/proc/jump_mob_picked(datum/om/prompt/choice/admin_jump/ask)
	do_jumptomob(ask.choice)

/// Performs the jumps, also called from admin Topic() for JMP links
/client/proc/do_jumptomob(mob/M)
	if(!CONFIG_GET(flag/allow_admin_jump))
		tgui_alert_async(usr, "Admin jumping disabled")
		return

	if(!M)
		om_ask(usr, /datum/om/prompt/choice/admin_jump, PROC_REF(jump_mob_picked), title = "Jump to Mob", message = "Pick a mob:", choices = REGISTRY_MEMBERS(REGISTRY_MOBS))
		return

	var/mob/A = src.mob // Impossible to be unset, enforced by byond
	var/turf/T = get_turf(M)
	if(isturf(T))
		A.on_mob_jump()
		A.reset_perspective(A)
		A.forceMove(T)
		log_admin("[key_name(usr)] jumped to [key_name(M)]")
		message_admins("[key_name_admin(usr)] jumped to [key_name_admin(M)]", 1)
		feedback_add_details("admin_verb","JM") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	else
		to_chat(A, span_filter_adminlog("This mob is not located in the game world."))

ADMIN_VERB(jumptocoord, R_ADMIN|R_MOD|R_DEBUG|R_EVENT,"Jump to Coordinate", "Jump to the target coordinates.", ADMIN_CATEGORY_GAME, tx as num|null, ty as num|null, tz as num|null)
	if(!CONFIG_GET(flag/allow_admin_jump))
		tgui_alert_async(user, "Admin jumping disabled")
		return
	if(!tx || !ty || !tz)
		var/_answer_a2 = verb_prompt(user, "a2", list("kind" = "number", "message" = "Select the target x coordinate", "title" = "X Loc", "default" = 1, "max" = world.maxx, "min" = 1), args)
		if(isnull(_answer_a2))
			return
		tx = _answer_a2
		var/_answer_a3 = verb_prompt(user, "a3", list("kind" = "number", "message" = "Select the target y coordinate", "title" = "Y Loc", "default" = 1, "max" = world.maxy, "min" = 1), args)
		if(isnull(_answer_a3))
			return
		ty = _answer_a3
		var/_answer_a4 = verb_prompt(user, "a4", list("kind" = "number", "message" = "Select the target z coordinate", "title" = "Z Loc", "default" = 1, "max" = world.maxz, "min" = 1), args)
		if(isnull(_answer_a4))
			return
		tz = _answer_a4

	var/mob/user_mob = user.mob
	user_mob.on_mob_jump()
	var/turf/target_turf = locate(tx, ty, tz)
	if(!target_turf)
		to_chat(user, span_warning("Those coordinates are outside the boundaries of the map."))
		return
	user_mob.reset_perspective(user_mob)
	user_mob.forceMove(target_turf)
	feedback_add_details("admin_verb","JC") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	message_admins("[key_name_admin(user)] jumped to coordinates [tx], [ty], [tz]")

ADMIN_VERB(jumptokey, R_ADMIN|R_MOD|R_DEBUG|R_EVENT, "Jump to Key", "Jump to a player.", ADMIN_CATEGORY_GAME)
	if(!CONFIG_GET(flag/allow_admin_jump))
		tgui_alert_async(user, "Admin jumping disabled")
		return

	var/list/keys = list()
	for(var/mob/player_mob in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		keys += player_mob.client
	var/client/selection = verb_prompt(user, "a5", list("kind" = "list", "message" = "Select a key:", "title" = "Jump to Key", "choices" = sortKey(keys)), args)
	if(isnull(selection))
		return
	if(!selection)
		return
	var/mob/selected_mob = selection.mob
	var/turf/target_turf = get_turf(selected_mob)
	if(!target_turf)
		return
	log_and_message_admins("jumped to [key_name(selected_mob)]", user)
	user.mob.on_mob_jump()
	user.mob.reset_perspective(user.mob)
	user.mob.forceMove(target_turf)
	feedback_add_details("admin_verb","JK") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_AND_CONTEXT_MENU(Getmob, R_ADMIN|R_MOD|R_DEBUG|R_EVENT, "Get Mob",  "Mob to teleport.", ADMIN_CATEGORY_GAME, mob/living/living_mob in REGISTRY_MEMBERS(REGISTRY_MOBS))
	if(!CONFIG_GET(flag/allow_admin_jump))
		tgui_alert_async(user, "Admin jumping disabled")
		return

	if(!living_mob)
		var/_answer_a6 = verb_prompt(user, "a6", list("kind" = "list", "message" = "Pick a mob:", "title" = "Get Mob", "choices" = REGISTRY_MEMBERS(REGISTRY_MOBS)), args)
		if(isnull(_answer_a6))
			return
		living_mob = _answer_a6
	if(!living_mob)
		return
	var/msg = "jumped [key_name(living_mob)] to them."
	log_and_message_admins(msg, user)
	admin_ticket_log(living_mob, "[key_name_admin(user)] " + msg)
	living_mob.on_mob_jump()
	living_mob.reset_perspective(living_mob)
	living_mob.forceMove(get_turf(user.mob))
	feedback_add_details("admin_verb","GM") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(Getkey, R_ADMIN|R_MOD|R_DEBUG|R_EVENT, "Get Key",  "Key to teleport.", ADMIN_CATEGORY_GAME)
	if(!CONFIG_GET(flag/allow_admin_jump))
		tgui_alert_async(user, "Admin jumping disabled")
		return

	var/list/keys = list()
	for(var/mob/curernt_mob in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		keys += curernt_mob.client
	var/client/selection = verb_prompt(user, "a7", list("kind" = "list", "message" = "Pick a key:", "title" = "Get Key", "choices" = sortKey(keys)), args)
	if(isnull(selection))
		return
	if(!selection)
		return

	var/mob/selected_mob = selection.mob
	if(!selected_mob)
		return

	log_admin("[key_name(user)] teleported [key_name(selected_mob)]")
	var/msg = "[key_name_admin(user)] teleported [ADMIN_LOOKUPFLW(selected_mob)]"
	message_admins(msg)
	admin_ticket_log(selected_mob, msg)
	selected_mob.on_mob_jump()
	selected_mob.reset_perspective(selected_mob) // Force reset to self before teleport
	selected_mob.forceMove(get_turf(user))
	feedback_add_details("admin_verb","GK") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/client/proc/sendmob()
	set category = "Admin.Game"
	set name = "Send Mob"
	if(!check_rights(R_ADMIN|R_MOD|R_DEBUG|R_EVENT))
		return

	if(CONFIG_GET(flag/allow_admin_jump))
		om_ask(usr, /datum/om/prompt/choice/admin_jump, PROC_REF(sendmob_area_picked), title = "Send Mob", message = "Pick an area:", choices = return_sorted_areas())
	else
		tgui_alert_async(usr, "Admin jumping disabled")

/client/proc/sendmob_area_picked(datum/om/prompt/choice/admin_jump/ask)
	om_ask(ask.answerer, /datum/om/prompt/choice/admin_jump, PROC_REF(sendmob_answered), title = "Send Mob", message = "Pick a mob:", choices = REGISTRY_MEMBERS(REGISTRY_MOBS), area = ask.choice)

/client/proc/sendmob_answered(datum/om/prompt/choice/admin_jump/ask)
	var/area/A = ask.area
	var/mob/M = ask.choice
	if(CONFIG_GET(flag/allow_admin_jump))
		M.on_mob_jump()
		M.reset_perspective(M) // Force reset to self before teleport
		M.forceMove(pick(get_area_turfs(A)))
		feedback_add_details("admin_verb","SMOB") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

		log_admin("[key_name(usr)] teleported [key_name(M)]")
		var/msg = "[key_name_admin(usr)] teleported [ADMIN_LOOKUPFLW(M)]"
		message_admins(msg)
		admin_ticket_log(M, msg)
	else
		tgui_alert_async(usr, "Admin jumping disabled")

/// One missing coordinate for Move Atom; the answer re-enters cmd_admin_move_atom(), which asks for the next.
/datum/om/prompt/number/move_atom_coord
	title = "Move Atom"
	requires = PROMPT_ADMIN(R_ADMIN|R_DEBUG|R_EVENT)
	var/atom/movable/moved
	var/tx
	var/ty
	var/tz

/datum/om/prompt/number/move_atom_coord/prepare()
	if(isnull(tx))
		message = "Select X coordinate"
		max = world.maxx
	else if(isnull(ty))
		message = "Select Y coordinate"
		max = world.maxy
	else
		message = "Select Z coordinate"
		max = world.maxz
	return TRUE

/client/proc/move_atom_coords_chosen(datum/om/prompt/number/move_atom_coord/ask)
	if(isnull(ask.number))
		return
	if(isnull(ask.tx))
		ask.tx = ask.number
	else if(isnull(ask.ty))
		ask.ty = ask.number
	else
		ask.tz = ask.number
	cmd_admin_move_atom(ask.moved, ask.tx, ask.ty, ask.tz)

/client/proc/cmd_admin_move_atom(atom/movable/AM, tx as num, ty as num, tz as num)
	set category = "Admin.Game"
	set name = "Move Atom to Coordinate"

	if(!check_rights(R_ADMIN|R_DEBUG|R_EVENT))
		return

	if(CONFIG_GET(flag/allow_admin_jump))
		if(isnull(tx) || isnull(ty) || isnull(tz))
			om_ask(usr, /datum/om/prompt/number/move_atom_coord, PROC_REF(move_atom_coords_chosen), moved = AM, tx = tx, ty = ty, tz = tz)
			return
		if(!tx || !ty || !tz)
			return
		var/turf/T = locate(tx, ty, tz)
		if(!T)
			to_chat(usr, span_warning("Those coordinates are outside the boundaries of the map."))
			return
		if(ismob(AM))
			var/mob/M = AM
			M.on_mob_jump()
			M.reset_perspective(M) // Force reset to self before teleport
		AM.forceMove(T)
		feedback_add_details("admin_verb", "MA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		message_admins("[key_name_admin(usr)] jumped [AM] to coordinates [tx], [ty], [tz]")
	else
		tgui_alert_async(usr, "Admin jumping disabled")
