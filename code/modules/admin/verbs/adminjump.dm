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
		var/_answer_a1 = verb_ask(user, "a1", args, /datum/om/prompt/choice, message = "Pick an area:", title = "Jump to Area", choices = return_sorted_areas())
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
	if(!admin_require(src, R_ADMIN|R_MOD|R_DEBUG|R_EVENT, "adminjump.do_jumptomob"))
		return
	if(!CONFIG_GET(flag/allow_admin_jump))
		tgui_alert_async(src, "Admin jumping disabled")
		return

	if(!M)
		om_ask(mob, /datum/om/prompt/choice/admin_jump, PROC_REF(jump_mob_picked), title = "Jump to Mob", message = "Pick a mob:", choices = REGISTRY_MEMBERS(REGISTRY_MOBS))
		return

	var/mob/A = src.mob // Impossible to be unset, enforced by byond
	var/turf/T = get_turf(M)
	if(isturf(T))
		A.on_mob_jump()
		A.reset_perspective(A)
		A.forceMove(T)
		log_admin("[key_name(src)] jumped to [key_name(M)]")
		message_admins("[key_name_admin(src)] jumped to [key_name_admin(M)]", 1)
		feedback_add_details("admin_verb","JM") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	else
		to_chat(A, span_filter_adminlog("This mob is not located in the game world."))

ADMIN_VERB(jumptocoord, R_ADMIN|R_MOD|R_DEBUG|R_EVENT,"Jump to Coordinate", "Jump to the target coordinates.", ADMIN_CATEGORY_GAME, tx as num|null, ty as num|null, tz as num|null)
	if(!CONFIG_GET(flag/allow_admin_jump))
		tgui_alert_async(user, "Admin jumping disabled")
		return
	if(!tx || !ty || !tz)
		var/_answer_a2 = verb_ask(user, "a2", args, /datum/om/prompt/number, message = "Select the target x coordinate", title = "X Loc", default = 1, max = world.maxx, min = 1)
		if(isnull(_answer_a2))
			return
		tx = _answer_a2
		var/_answer_a3 = verb_ask(user, "a3", args, /datum/om/prompt/number, message = "Select the target y coordinate", title = "Y Loc", default = 1, max = world.maxy, min = 1)
		if(isnull(_answer_a3))
			return
		ty = _answer_a3
		var/_answer_a4 = verb_ask(user, "a4", args, /datum/om/prompt/number, message = "Select the target z coordinate", title = "Z Loc", default = 1, max = world.maxz, min = 1)
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
	var/client/selection = verb_ask(user, "a5", args, /datum/om/prompt/choice, message = "Select a key:", title = "Jump to Key", choices = sortKey(keys))
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
		var/_answer_a6 = verb_ask(user, "a6", args, /datum/om/prompt/choice, message = "Pick a mob:", title = "Get Mob", choices = REGISTRY_MEMBERS(REGISTRY_MOBS))
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
	var/client/selection = verb_ask(user, "a7", args, /datum/om/prompt/choice, message = "Pick a key:", title = "Get Key", choices = sortKey(keys))
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
	set category = VERB_CAT_ADMIN_GAME
	set name = "Send Mob"
	if(!check_rights(R_ADMIN|R_MOD|R_DEBUG|R_EVENT))
		return

	if(CONFIG_GET(flag/allow_admin_jump))
		var/mob/answerer = usr
		if(QDELETED(answerer))
			return
		open_request(src, /datum/prompt/choice/admin_sendmob, PROC_REF(sendmob_area_picked), answerer = answerer, title = "Send Mob", question = "Pick an area:", choices = return_sorted_areas())
	else
		tgui_alert_async(usr, "Admin jumping disabled")

/datum/prompt/choice/admin_sendmob
	timeout = 0
	rights = R_ADMIN|R_MOD|R_DEBUG|R_EVENT
	var/area/area

CAPABILITIES(/datum/prompt/choice/admin_sendmob)
	ref_one(nameof(area), /area)

/datum/prompt/choice/admin_sendmob/prepare(datum/act/A)
	..()
	var/area/captured_area = area
	rel_clear(src, nameof(area))
	rel_set(src, nameof(area), captured_area)

/datum/prompt/choice/admin_sendmob/recheck_extra()
	return isnull(area) || !QDELETED(area) ? null : "gone"

/client/proc/sendmob_area_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/area/selected_area = A.answer.answer_value
	if(!istype(selected_area) || QDELETED(selected_area))
		return
	open_request(src, /datum/prompt/choice/admin_sendmob, PROC_REF(sendmob_answered), answerer = A.request.answerer, title = "Send Mob", question = "Pick a mob:", choices = REGISTRY_MEMBERS(REGISTRY_MOBS), area = selected_area)

/client/proc/sendmob_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/admin_sendmob/ask = context.answer
	var/mob/selected_mob = ask.answer_value
	if(!istype(ask.area, /area) || QDELETED(ask.area) || !istype(selected_mob) || QDELETED(selected_mob))
		return
	if(!admin_require(src, R_ADMIN|R_MOD|R_DEBUG|R_EVENT, "adminjump.sendmob_answered"))
		return
	var/area/A = ask.area
	var/mob/M = ask.answer_value
	if(CONFIG_GET(flag/allow_admin_jump))
		M.on_mob_jump()
		M.reset_perspective(M) // Force reset to self before teleport
		M.forceMove(pick(get_area_turfs(A)))
		feedback_add_details("admin_verb","SMOB") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

		log_admin("[key_name(src)] teleported [key_name(M)]")
		var/msg = "[key_name_admin(src)] teleported [ADMIN_LOOKUPFLW(M)]"
		message_admins(msg)
		admin_ticket_log(M, msg)
	else
		tgui_alert_async(src, "Admin jumping disabled")

/// One missing coordinate for Move Atom; the answer retains its initiating actor for the next coordinate.
/datum/prompt/number/move_atom_coord
	title = "Move Atom"
	rights = R_ADMIN|R_DEBUG|R_EVENT
	timeout = 0
	step = 1
	var/atom/movable/moved
	var/tx
	var/ty
	var/tz
	var/denial_entry
	var/moved_required = FALSE

CAPABILITIES(/datum/prompt/number/move_atom_coord)
	ref_one(nameof(moved), /atom/movable)

/datum/prompt/number/move_atom_coord/prepare(datum/act/A)
	..()
	var/atom/movable/captured_moved = moved
	moved_required = !isnull(captured_moved)
	rel_clear(src, nameof(moved))
	rel_set(src, nameof(moved), captured_moved)
	if(isnull(tx))
		question = "Select X coordinate"
		max_value = world.maxx
	else if(isnull(ty))
		question = "Select Y coordinate"
		max_value = world.maxy
	else
		question = "Select Z coordinate"
		max_value = world.maxz


/datum/prompt/number/move_atom_coord/recheck_extra()
	return moved_required && QDELETED(moved) ? "gone" : null

/client/proc/move_atom_coords_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/number/move_atom_coord/ask = A.answer
	if(isnull(ask.answer_value))
		return
	if(isnull(ask.tx))
		ask.tx = ask.answer_value
	else if(isnull(ask.ty))
		ask.ty = ask.answer_value
	else
		ask.tz = ask.answer_value
	move_atom_with_actor(ask.answerer, ask.moved, ask.tx, ask.ty, ask.tz, ask.denial_entry)

/client/proc/cmd_admin_move_atom(atom/movable/AM, tx as num, ty as num, tz as num)
	set category = VERB_CAT_ADMIN_GAME
	set name = "Move Atom to Coordinate"

	move_atom_with_actor(usr, AM, tx, ty, tz, "check_rights in [callee?.proc]")

/client/proc/move_atom_with_actor(mob/user, atom/movable/AM, tx, ty, tz, denial_entry)
	if(!admin_require(user?.client, R_ADMIN|R_DEBUG|R_EVENT, denial_entry))
		return

	if(CONFIG_GET(flag/allow_admin_jump))
		if(isnull(tx) || isnull(ty) || isnull(tz))
			open_request(src, /datum/prompt/number/move_atom_coord, PROC_REF(move_atom_coords_chosen), answerer = user, moved = AM, tx = tx, ty = ty, tz = tz, denial_entry = denial_entry)
			return
		if(!tx || !ty || !tz)
			return
		var/turf/T = locate(tx, ty, tz)
		if(!T)
			to_chat(user, span_warning("Those coordinates are outside the boundaries of the map."))
			return
		if(ismob(AM))
			var/mob/M = AM
			M.on_mob_jump()
			M.reset_perspective(M) // Force reset to self before teleport
		AM.forceMove(T)
		feedback_add_details("admin_verb", "MA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		message_admins("[key_name_admin(user)] jumped [AM] to coordinates [tx], [ty], [tz]")
	else
		tgui_alert_async(user, "Admin jumping disabled")
