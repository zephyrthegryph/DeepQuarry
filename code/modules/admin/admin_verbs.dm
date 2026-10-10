/client/proc/add_admin_verbs()
	// NEW ADMIN VERBS SYSTEM
	SSadmin_verbs.assosciate_admin(src)

/client/proc/remove_admin_verbs()
	// NEW ADMIN VERBS SYSTEM
	SSadmin_verbs.deassosciate_admin(src)

ADMIN_VERB(hide_verbs, R_HOLDER, "Adminverbs - Hide All", "Hide all admin verbs.", ADMIN_CATEGORY_MISC)
	SSadmin_verbs.deassosciate_admin(user)
	grant(user, granted_verb(/client/proc/show_verbs), user.admin_datum())

	to_chat(user, span_filter_system(span_interface("Almost all of your adminverbs have been hidden.")))
	feedback_add_details("admin_verb","TAVVH") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	return

/client/proc/show_verbs()
	set name = "Adminverbs - Show"
	set category = VERB_CAT_ADMIN_MISC

	if(!check_rights_for(src, R_HOLDER))
		return

	revoke(src, granted_verb(/client/proc/show_verbs), holder)
	add_admin_verbs()

	to_chat(src, span_filter_adminlog(span_interface("All of your adminverbs are now visible.")))
	feedback_add_details("admin_verb","TAVVS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!


ADMIN_VERB(admin_ghost, R_HOLDER, "Aghost", "Ghost out of your body with the option to return at any time.", ADMIN_CATEGORY_GAME)
	// Only this verb's actual ended native request supplies replay answers.
	var/list/replay_answers = list()
	if(length(args) > 1)
		var/datum/request/resumed = args[2]
		if((istype(resumed, /datum/prompt/choice/admin_ghost_replay)) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(admin_ghost_replay_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	var/build_mode
	if(user.buildmode)
		if(!("a1" in replay_answers))
			open_request(src, /datum/prompt/choice/admin_ghost_replay, PROC_REF(admin_ghost_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a1", buttons = TRUE, question = "You appear to be currently in buildmode. Do you want to re-enter buildmode after aghosting?", title = "Buildmode", choices = list("Yes", "No"))
			return
		var/_answer_a1 = replay_answers["a1"]
		if(isnull(_answer_a1))
			return
		build_mode = _answer_a1
		if(build_mode != "Yes")
			to_chat(user, "Will not re-enter buildmode after switch.")

	var/mob/mob = user.mob
	if(isobserver(mob))
		//re-enter
		var/mob/observer/dead/ghost = mob
		if(ghost.can_reenter_corpse)
			if(build_mode)
				togglebuildmode(mob)
				ghost.reenter_corpse()
				if(build_mode == "Yes")
					togglebuildmode(mob)
			else
				ghost.reenter_corpse()
		else
			to_chat(ghost, span_filter_system(span_warning("Error:  Aghost:  Can't reenter corpse.")))
			return

		feedback_add_details("admin_verb","P") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

	else if(isnewplayer(mob))
		to_chat(user, span_filter_system(span_warning("Error: Aghost: Can't admin-ghost whilst in the lobby. Join or Observe first.")))
	else
		//ghostize
		var/mob/body = mob
		var/mob/observer/dead/ghost
		if(build_mode)
			togglebuildmode(body)
			ghost = body.ghostize(1, TRUE)
			log_and_message_admins("[key_name(user)] admin-ghosted.") // Add logging.
			if(build_mode == "Yes")
				togglebuildmode(ghost)
		else
			ghost = body.ghostize(1, TRUE)
			log_and_message_admins("[key_name(user)] admin-ghosted.") // Add logging.
		user.init_verbs()
		if(body)
			body.teleop = ghost
			if(!body.key)
				body.key = "@[user.key]"	//Haaaaaaaack. But the people have spoken. If it breaks; blame adminbus
		feedback_add_details("admin_verb","O") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(invisimin, R_ADMIN|R_MOD|R_EVENT, "Invisimin", "Toggles ghost-like invisibility (Don't abuse this).", ADMIN_CATEGORY_GAME)
	var/mob/mob = user.mob
	if(mob.invisibility > INVISIBILITY_OBSERVER)
		to_chat(user, span_warning("You can't use this, your current invisibility level ([mob.invisibility]) is above the observer level ([INVISIBILITY_OBSERVER])."))
		return

	if(mob.invisibility == INVISIBILITY_OBSERVER)
		mob.invisibility = initial(mob.invisibility)
		to_chat(mob, span_filter_system(span_danger("Invisimin off. Invisibility reset.")))
		mob.alpha = max(mob.alpha + 100, 255)
		return

	mob.invisibility = INVISIBILITY_OBSERVER
	to_chat(mob, span_filter_system(span_boldnotice("Invisimin on. You are now as invisible as a ghost.")))
	mob.alpha = max(mob.alpha - 100, 0)

ADMIN_VERB(list_bombers, R_ADMIN, "List Bombers", "Look at all bombs and their likely culprit.", ADMIN_CATEGORY_GAME)
	user.holder.list_bombers(user.mob)

ADMIN_VERB(list_signalers, R_ADMIN, "List Signalers", "View all signalers.", ADMIN_CATEGORY_GAME)
	user.holder.list_signalers(user.mob)

ADMIN_VERB(list_law_changes, R_ADMIN, "List Law Changes", "View all AI law changes.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	user.holder.list_law_changes(user.mob)

ADMIN_VERB(show_manifest, R_ADMIN, "Show Manifest", "View the shift's Manifest.", ADMIN_CATEGORY_DEBUG_GAME)
	user.holder.show_manifest(user.mob)

ADMIN_VERB(player_panel, R_HOLDER, "Player Panel", "Open the player panel.", ADMIN_CATEGORY_GAME)
	user.holder.player_panel_old(user)
	feedback_add_details("admin_verb","PP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(player_panel_new, R_HOLDER, "Player Panel New", "Open the player panel.", ADMIN_CATEGORY_GAME)
	user.holder.player_panel_new(user)
	feedback_add_details("admin_verb","PPN") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(check_antagonists, R_HOLDER, "Check Antagonists", "Open the antagonist panel.", ADMIN_CATEGORY_INVESTIGATE)
	user.holder.check_antagonists(user)
	log_admin("[key_name(user)] checked antagonists.")	//for tsar~
	feedback_add_details("admin_verb","CHA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(jobbans, R_BAN, "Display Job bans", "View job bans here.", ADMIN_CATEGORY_INVESTIGATE)
	if(CONFIG_GET(flag/ban_legacy_system))
		user.holder.Jobbans()
	else
		user.holder.DB_ban_panel(user)
	feedback_add_details("admin_verb","VJB") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(unban_panel, R_BAN, "Unbanning Panel", "Unban players here.", ADMIN_CATEGORY_GAME)
	if(CONFIG_GET(flag/ban_legacy_system))
		user.holder.unbanpanel()
	else
		user.holder.DB_ban_panel(user)
	feedback_add_details("admin_verb","UBP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(game_panel, R_ADMIN|R_SERVER|R_FUN, "Game Panel", "Look at the state of the game.", ADMIN_CATEGORY_GAME)
	user.holder.Game()
	feedback_add_details("admin_verb","GP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/// Returns this client's stealthed ckey
/client/proc/getStealthKey()
	return GLOB.stealthminID[ckey]

/client/proc/findStealthKey(txt)
	if(txt)
		for(var/P in GLOB.stealthminID)
			if(GLOB.stealthminID[P] == txt)
				return P
	txt = GLOB.stealthminID[ckey]
	return txt

/client/proc/createStealthKey()
	var/num = (rand(0,1000))
	var/i = 0
	while(i == 0)
		i = 1
		for(var/P in GLOB.stealthminID)
			if(num == GLOB.stealthminID[P])
				num++
				i = 0
	GLOB.stealthminID["[ckey]"] = "@[num2text(num)]"

ADMIN_VERB(stealth, R_STEALTH, "Stealth Mode", "Toggle stealth.", ADMIN_CATEGORY_GAME)
	return toggle_stealth(user)

/datum/admin_verb/stealth/proc/stealth_name_answered(datum/act/request/A)
	if(!A.answer)
		return
	toggle_stealth(A.request.answerer.client, A.request.value, TRUE)

/datum/admin_verb/stealth/proc/toggle_stealth(client/user, _answer_a2 = null, answered = FALSE)
	if(user.holder.fakekey)
		user.holder.fakekey = null
		if(isnewplayer(user.mob))
			user.mob.name = capitalize(user.ckey)
	else
		if(!answered)
			var/mob/answerer = user.mob
			if(QDELETED(answerer))
				return
			open_request(src, /datum/prompt/text/admin_stealth_name, PROC_REF(stealth_name_answered), answerer = answerer, default = user.key)
			return
		if(isnull(_answer_a2))
			return
		var/new_key = ckeyEx(_answer_a2)
		if(!new_key)
			return
		if(length(new_key) >= 26)
			new_key = copytext(new_key, 1, 26)
		user.holder.fakekey = new_key
		user.createStealthKey()
		if(isnewplayer(user.mob))
			user.mob.name = new_key
	log_and_message_admins("has turned stealth mode [user.holder.fakekey ? "ON" : "OFF"]", user)
	feedback_add_details("admin_verb","SM") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

#define MAX_WARNS 3
#define AUTOBANTIME 10

/client/proc/warn(warned_ckey)
	if(!admin_require(src, R_ADMIN, "warn"))	return

	if(!warned_ckey || !istext(warned_ckey))	return
	if(warned_ckey in GLOB.admin_datums)
		to_chat(src, span_warning("Error: warn(): You can't warn admins."))
		return

	var/datum/preferences/D
	var/client/C = GLOB.directory[warned_ckey]
	if(C)	D = C.prefs
	else	D = GLOB.preferences_datums[warned_ckey]

	if(!D)
		to_chat(src, span_warning("Error: warn(): No such ckey found."))
		return

	if(++D.warns >= MAX_WARNS)					//uh ohhhh...you'reee iiiiin trouuuubble O:)
		ban_unban_log_save("[ckey] warned [warned_ckey], resulting in a [AUTOBANTIME] minute autoban.")
		if(C)
			message_admins("[key_name_admin(src)] has warned [key_name_admin(C)] resulting in a [AUTOBANTIME] minute ban.")
			to_chat(C, span_filter_system(span_danger("<BIG>You have been autobanned due to a warning by [ckey].</BIG><br>This is a temporary ban, it will be removed in [AUTOBANTIME] minutes.")))
			del(C) // ALLOW(scheduler): client: kicks the client
		else
			message_admins("[key_name_admin(src)] has warned [warned_ckey] resulting in a [AUTOBANTIME] minute ban.")
		AddBan(warned_ckey, D.last_id, "Autobanning due to too many formal warnings", ckey, 1, AUTOBANTIME, user = mob)
		feedback_inc("ban_warn",1)
	else
		if(C)
			to_chat(C, span_filter_system(span_danger("<BIG>You have been formally warned by an administrator.</BIG><br>Further warnings will result in an autoban.")))
			message_admins("[key_name_admin(src)] has warned [key_name_admin(C)]. They have [MAX_WARNS-D.warns] strikes remaining.")
		else
			message_admins("[key_name_admin(src)] has warned [warned_ckey] (DC). They have [MAX_WARNS-D.warns] strikes remaining.")

	feedback_add_details("admin_verb","WARN") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

#undef MAX_WARNS
#undef AUTOBANTIME

ADMIN_VERB(drop_bomb, R_FUN, "Drop Bomb", "Cause an explosion of varying strength at your location.", ADMIN_CATEGORY_FUN_DO_NOT) // Some admin dickery that can probably be done better -- TLE
	advance_bomb(user)

/datum/admin_verb/drop_bomb/proc/advance_bomb(client/user, stage = 0, choice = null, devastation_range = null, heavy_impact_range = null, light_impact_range = null, flash_range = null)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	var/turf/epicenter = user.mob.loc
	var/list/choices = list("Small Bomb", "Medium Bomb", "Big Bomb", "Maxcap Bomb", "SM Blast", "Custom Bomb", "Cancel")
	if(stage <= 0)
		open_request(src, /datum/prompt/choice/admin_drop_bomb, PROC_REF(bomb_question_answered), answerer = answerer, question = "What size explosion would you like to produce?", title = "Explosion Choice", choices = choices)
		return
	switch(choice)
		if(null)
			return FALSE
		if("Cancel")
			return FALSE
		if("Small Bomb")
			explosion(epicenter, 1, 2, 3, 3)
		if("Medium Bomb")
			explosion(epicenter, 2, 3, 4, 4)
		if("Big Bomb")
			explosion(epicenter, 3, 5, 7, 5)
		if("Maxcap Bomb") // Being able to test what players can legally make themselves sounds good, no?~
			explosion(epicenter, BOMBCAP_DVSTN_RADIUS, BOMBCAP_HEAVY_RADIUS, BOMBCAP_LIGHT_RADIUS, BOMBCAP_FLASH_RADIUS)
		if("SM Blast")
			explosion(epicenter, 8, 16, 24, 32)
		if("Custom Bomb")
			if(stage <= 1)
				open_request(src, /datum/prompt/number/admin_drop_bomb, PROC_REF(bomb_question_answered), answerer = answerer, question = "Devastation range (in tiles):", stage = 1, devastation_range = devastation_range, heavy_impact_range = heavy_impact_range, light_impact_range = light_impact_range)
				return
			if(stage <= 2)
				open_request(src, /datum/prompt/number/admin_drop_bomb, PROC_REF(bomb_question_answered), answerer = answerer, question = "Heavy impact range (in tiles):", stage = 2, devastation_range = devastation_range, heavy_impact_range = heavy_impact_range, light_impact_range = light_impact_range)
				return
			if(stage <= 3)
				open_request(src, /datum/prompt/number/admin_drop_bomb, PROC_REF(bomb_question_answered), answerer = answerer, question = "Light impact range (in tiles):", stage = 3, devastation_range = devastation_range, heavy_impact_range = heavy_impact_range, light_impact_range = light_impact_range)
				return
			if(stage <= 4)
				open_request(src, /datum/prompt/number/admin_drop_bomb, PROC_REF(bomb_question_answered), answerer = answerer, question = "Flash range (in tiles):", stage = 4, devastation_range = devastation_range, heavy_impact_range = heavy_impact_range, light_impact_range = light_impact_range)
				return
			explosion(epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range)
	message_admins(span_blue("[user.ckey] creating an admin explosion at [epicenter.loc]."))
	feedback_add_details("admin_verb","DB") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/prompt/choice/admin_drop_bomb
	rights = R_FUN
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/number/admin_drop_bomb
	rights = R_FUN
	timeout = 0
	min_value = 0
	max_value = INFINITY
	step = 1
	var/stage
	var/devastation_range
	var/heavy_impact_range
	var/light_impact_range
	recheck_on_open = TRUE

/datum/admin_verb/drop_bomb/proc/bomb_question_answered(datum/act/request/A)
	bomb_answer(A)

/datum/admin_verb/drop_bomb/proc/bomb_answer(datum/act/request/A)
	if(!A.answer)
		return
	var/client/user = A.request.answerer?.client
	if(!user)
		return
	if(istype(A.request, /datum/prompt/choice/admin_drop_bomb))
		return advance_bomb(user, 1, A.request.value)
	var/datum/prompt/number/admin_drop_bomb/ask = A.request
	switch(ask.stage)
		if(1)
			return advance_bomb(user, 2, "Custom Bomb", ask.value)
		if(2)
			return advance_bomb(user, 3, "Custom Bomb", ask.devastation_range, ask.value)
		if(3)
			return advance_bomb(user, 4, "Custom Bomb", ask.devastation_range, ask.heavy_impact_range, ask.value)
		if(4)
			return advance_bomb(user, 5, "Custom Bomb", ask.devastation_range, ask.heavy_impact_range, ask.light_impact_range, ask.value)

/datum/prompt/number/admin_drop_bomb/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, !isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

ADMIN_VERB(admin_give_modifier, R_EVENT, "Give Modifier", "Makes a mob weaker or stronger by adding a specific modifier to them.", ADMIN_CATEGORY_DEBUG_GAME, mob/living/living_target)
	if(!living_target)
		to_chat(user, span_warning("Looks like you didn't select a mob."))
		return

	var/list/possible_modifiers = subtypesof(/datum/body_effect)

	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_body_effect, PROC_REF(modifier_answered), answerer = answerer, question = "What modifier should we add to [living_target]?", title = "Modifier Type", choices = possible_modifiers, living_target = living_target)

/datum/admin_verb/admin_give_modifier/proc/modifier_answered(datum/act/request/A)
	modifier_chosen(A)

/datum/admin_verb/admin_give_modifier/proc/modifier_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/admin_body_effect/ask = A.request
	var/client/user = ask.answerer?.client
	if(!user)
		return
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/number/admin_body_effect, PROC_REF(modifier_duration_answered), answerer = answerer, living_target = ask.living_target, modifier_type = ask.value)

/datum/admin_verb/admin_give_modifier/proc/modifier_duration_answered(datum/act/request/A)
	modifier_duration_chosen(A)

/datum/admin_verb/admin_give_modifier/proc/modifier_duration_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/number/admin_body_effect/ask = A.request
	var/client/user = ask.answerer?.client
	if(!user)
		return
	var/mob/living/living_target = ask.living_target
	var/new_modifier_type = ask.modifier_type
	var/duration = ask.value
	if(duration == 0)
		duration = null
	else
		duration = duration SECONDS

	living_target.apply_body_effect(new_modifier_type, duration)
	log_and_message_admins("has given [key_name(living_target)] the modifer [new_modifier_type], with a duration of [duration ? "[duration / 600] minutes" : "forever"].", user)

/datum/prompt/choice/admin_body_effect
	rights = R_EVENT
	timeout = 0
	var/mob/living/living_target
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/choice/admin_body_effect)
	ref_one(nameof(living_target), /mob/living)

/datum/prompt/choice/admin_body_effect/prepare(datum/act/A)
	. = ..()
	var/mob/living/captured = living_target
	rel_clear(src, nameof(living_target))
	rel_set(src, nameof(living_target), captured)

/datum/prompt/choice/admin_body_effect/recheck_extra()
	. = ..()
	if(.)
		return
	return QDELETED(living_target) ? "target is gone" : null

/datum/prompt/number/admin_body_effect
	rights = R_EVENT
	timeout = 0
	var/mob/living/living_target
	question = "How long should the new modifier last, in seconds.  To make it last forever, write '0'."
	title = "Modifier Duration"
	min_value = 0
	max_value = INFINITY
	step = 1
	var/modifier_type
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/number/admin_body_effect)
	ref_one(nameof(living_target), /mob/living)

/datum/prompt/number/admin_body_effect/prepare(datum/act/A)
	. = ..()
	var/mob/living/captured = living_target
	rel_clear(src, nameof(living_target))
	rel_set(src, nameof(living_target), captured)

/datum/prompt/number/admin_body_effect/recheck_extra()
	. = ..()
	if(.)
		return
	return QDELETED(living_target) ? "target is gone" : null

/datum/prompt/number/admin_body_effect/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, !isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

ADMIN_VERB_AND_CONTEXT_MENU(make_sound, R_FUN, "Make Sound", "Display a message to everyone who can hear the target.", ADMIN_CATEGORY_FUN_SOUNDS, obj/target_object in world)
	return sound_message_stage(user, target_object, list())

/datum/admin_verb/make_sound/proc/sound_message_stage(client/user, obj/target_object, list/sound_answers)
	if(!target_object)
		return

	if(!("a10" in sound_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/text/admin_sound_message, PROC_REF(sound_message_answered), answerer = user.mob, subject = target_object)
		return
	var/message = sound_answers["a10"]
	if(isnull(message))
		return
	if(!message)
		return
	target_object.audible_message(message)
	log_admin("[key_name(user)] made [target_object] at [target_object.x], [target_object.y], [target_object.z]. make a sound")
	message_admins(span_blue("[key_name_admin(user)] made [target_object] at [target_object.x], [target_object.y], [target_object.z]. make a sound."))
	feedback_add_details("admin_verb","MS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_AND_CONTEXT_MENU(togglebuildmodeself, R_BUILDMODE, "Toggle Build Mode Self", "Toggles buildmode on oneself.", ADMIN_CATEGORY_DEBUG_EVENTS)
	togglebuildmode(user.mob)
	feedback_add_details("admin_verb","TBMS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(object_talk, R_FUN, "oSay", "Display a message to everyone who can hear the target.", ADMIN_CATEGORY_FUN_NARRATE, msg as text)
	var/mob/user_mob = user.mob
	if(!user_mob.control_object)
		return

	if(!msg)
		return
	for(var/mob/V in hearers(user_mob.control_object))
		V.show_message(span_filter_say(span_bold("[user_mob.control_object.name]") + " says: \"[msg]\""), 2)
	feedback_add_details("admin_verb","OT") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(kill_air, R_SERVER, "Kill Air", "Toggle Air Processing.", ADMIN_CATEGORY_DEBUG_DANGEROUS)
	SSair.can_fire = !SSair.can_fire
	to_chat(user, span_filter_system(span_bold("[SSair.can_fire ? "En" : "Dis"]abled air processing.")))
	feedback_add_details("admin_verb","KA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	log_and_message_admins("used 'kill air'.", user)

ADMIN_VERB(deadmin, R_NONE, "DeAdmin", "Shed your admin powers.", ADMIN_CATEGORY_MISC)
	user.holder.deactivate()
	to_chat(user, span_interface("You are now a normal player."))
	log_admin("[key_name(user)] deadminned themselves.")
	message_admins("[key_name_admin(user)] deadminned themselves.")
	feedback_add_details("admin_verb","DAS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

	if(isobserver(user.mob))
		var/mob/observer/dead/our_mob = user.mob
		our_mob.visualnet?.removeVisibility(our_mob, user)

ADMIN_VERB(toggle_log_hrefs, R_SERVER, "Toggle href logging", "Allows to toggle the logging of used hrefs.", ADMIN_CATEGORY_SERVER_CONFIG)
	if(!config)
		return
	CONFIG_SET(flag/log_hrefs, !CONFIG_GET(flag/log_hrefs))
	message_admins(span_bold("[key_name_admin(user)] [CONFIG_GET(flag/log_hrefs) ? "started" : "stopped"] logging hrefs"))

ADMIN_VERB(check_ai_laws, R_ADMIN|R_FUN|R_EVENT, "Check AI Laws", "Display the current AI laws.", ADMIN_CATEGORY_SILICON)
	user.holder.output_ai_laws(user.mob)

ADMIN_VERB(rename_silicon, R_ADMIN|R_FUN|R_EVENT, "Rename Silicon", "Rename a silicon mob.", ADMIN_CATEGORY_SILICON)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_silicon_rename, PROC_REF(silicon_selected), answerer = answerer, choices = REGISTRY_MEMBERS(REGISTRY_SILICONS))

/datum/admin_verb/rename_silicon/proc/silicon_selected(datum/act/request/A)
	if(!A.answer)
		return
	ask_silicon_name(A)

/datum/admin_verb/rename_silicon/proc/ask_silicon_name(datum/act/request/A)
	var/mob/living/silicon/silicon_target = A.request.value
	open_request(src, /datum/prompt/text/admin_silicon_name, PROC_REF(silicon_named), answerer = A.request.answerer, title = "[silicon_target.real_name] - Enter new silicon name", default = silicon_target.real_name, target = silicon_target)

/datum/admin_verb/rename_silicon/proc/silicon_named(datum/act/request/A)
	if(!A.answer)
		return
	rename_answered(A)

/datum/admin_verb/rename_silicon/proc/rename_answered(datum/act/request/A)
	var/datum/prompt/text/admin_silicon_name/ask = A.request
	var/mob/living/silicon/silicon_target = ask.target
	var/client/user = ask.answerer.client
	var/_answer_a12 = ask.value
	var/new_name = sanitizeSafe(_answer_a12)
	if(new_name && new_name != silicon_target.real_name)
		log_and_message_admins("has renamed the silicon '[silicon_target.real_name]' to '[new_name]'", user)
		silicon_target.SetName(new_name)
	feedback_add_details("admin_verb","RAI") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(manage_silicon_laws, R_ADMIN|R_EVENT, "Manage Silicon Laws", "Allows to modify silicon laws.", ADMIN_CATEGORY_SILICON)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_law_target, PROC_REF(law_target_selected), answerer = answerer, choices = REGISTRY_MEMBERS(REGISTRY_SILICONS))

/datum/admin_verb/manage_silicon_laws/proc/law_target_selected(datum/act/request/A)
	if(!A.answer)
		return
	open_law_manager(A)

/datum/admin_verb/manage_silicon_laws/proc/open_law_manager(datum/act/request/A)
	var/mob/living/silicon/selected_silicon = A.request.value
	var/client/user = A.request.answerer.client
	var/datum/tgui_module/law_manager/admin/law_interface = new(selected_silicon)
	law_interface.tgui_interact(user.mob)
	log_and_message_admins("has opened [selected_silicon]'s law manager.", user)
	feedback_add_details("admin_verb","MSL") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(change_security_level, R_ADMIN|R_EVENT, "Set security level", "Sets the station security level.", ADMIN_CATEGORY_EVENTS)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_security_level, PROC_REF(level_selected), answerer = answerer, question = "It's currently code [get_security_level()].", title = "Select Security Level", choices = (list("green", "yellow", "violet", "orange", "blue", "red", "delta") - get_security_level()))

/datum/admin_verb/change_security_level/proc/level_selected(datum/act/request/A)
	if(!A.answer)
		return
	confirm_level(A)

/datum/admin_verb/change_security_level/proc/confirm_level(datum/act/request/A)
	var/sec_level = A.request.value
	if(!sec_level)
		return
	open_request(src, /datum/prompt/choice/admin_security_level/confirmation, PROC_REF(level_confirmed), answerer = A.request.answerer, question = "Switch from code [get_security_level()] to code [sec_level]?", selected_level = sec_level)

/datum/admin_verb/change_security_level/proc/level_confirmed(datum/act/request/A)
	if(!A.answer)
		return
	apply_level(A)

/datum/admin_verb/change_security_level/proc/apply_level(datum/act/request/A)
	var/datum/prompt/choice/admin_security_level/confirmation/ask = A.request
	var/client/user = ask.answerer.client
	var/sec_level = ask.selected_level
	var/_answer_a15 = ask.value
	if(_answer_a15 == "Yes")
		set_security_level(sec_level)
		log_admin("[key_name(user)] changed the security level to code [sec_level].")

ADMIN_VERB(shuttle_panel, R_ADMIN|R_EVENT, "Shuttle Control Panel", "Access the shuttle control panel.", ADMIN_CATEGORY_EVENTS)
	var/datum/tgui_module/admin_shuttle_controller/A = new(src)
	A.tgui_interact(user.mob)
	log_and_message_admins("has opened the shuttle panel.", user)
	feedback_add_details("admin_verb","SHCP")

ADMIN_VERB(free_slot, R_ADMIN|R_FUN|R_EVENT, "Free Job Slot", "Frees another job slot.", ADMIN_CATEGORY_EVENTS)
	return job_slot_stage(user, list())

/datum/admin_verb/free_slot/proc/job_slot_stage(client/user, list/job_answers)
	var/mob/actor = user?.mob
	var/list/jobs = list()
	for(var/datum/job/J in job_occupations())
		if (J.current_positions >= J.total_positions && J.total_positions != -1)
			jobs += J.title
	if(!jobs.len)
		to_chat(actor, "There are no fully staffed jobs.")
		return
	if(!("a16" in job_answers))
		if(!actor || QDELETED(actor))
			return
		open_request(src, /datum/prompt/choice/admin_job_slot, PROC_REF(job_slot_answered), answerer = actor, choices = jobs)
		return
	var/job = job_answers["a16"]
	if(isnull(job))
		return
	if(job)
		SSjob.free_role(job)
		message_admins("A job slot for [job] has been opened by [key_name_admin(actor)]")
		return

ADMIN_VERB(toggleghostwriters, R_ADMIN|R_FUN|R_EVENT, "Toggle ghost writers", "Toggles ghost writing.", ADMIN_CATEGORY_SERVER_GAME)
	if(!config)
		return
	CONFIG_SET(flag/cult_ghostwriter, !CONFIG_GET(flag/cult_ghostwriter))
	message_admins("Admin [key_name_admin(user)] has [CONFIG_GET(flag/cult_ghostwriter) ? "en" : "dis"]abled ghost writers.")

ADMIN_VERB(toggledrones, R_ADMIN|R_FUN|R_EVENT, "Toggle maintenance drones", "Toggles maintenance drone.", ADMIN_CATEGORY_SERVER_GAME)
	if(!config)
		return
	CONFIG_SET(flag/allow_drone_spawn, !CONFIG_GET(flag/allow_drone_spawn))
	message_admins("Admin [key_name_admin(user)] has [CONFIG_GET(flag/allow_drone_spawn) ? "en" : "dis"]abled maintenance drones.")

ADMIN_VERB(man_up, R_ADMIN|R_FUN, "Man Up", "Tells mob to man up and deal with it.", ADMIN_CATEGORY_FUN_DO_NOT)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_man_up, PROC_REF(target_chosen), answerer = answerer, question = "Who to tell to man up and deal with it.", title = "Man up", choices = REGISTRY_MEMBERS(REGISTRY_MOBS))

/datum/admin_verb/man_up/proc/target_chosen(datum/act/request/A)
	ask_target_confirmation(A)

/datum/admin_verb/man_up/proc/ask_target_confirmation(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/living_target = A.request.value
	if(QDELETED(living_target))
		return
	open_request(src, /datum/prompt/choice/admin_man_up/confirmation, PROC_REF(target_confirmed), answerer = A.request.answerer, question = "Are you sure you want to tell them to man up?", title = "Confirmation", choices = list("Deal with it", "No"), buttons = TRUE, target = living_target)

/datum/admin_verb/man_up/proc/target_confirmed(datum/act/request/A)
	tell_target(A)

/datum/admin_verb/man_up/proc/tell_target(datum/act/request/A)
	if(!A.answer || A.request.value != "Deal with it")
		return
	var/datum/prompt/choice/admin_man_up/confirmation/ask = A.request
	var/mob/living/living_target = ask.target
	var/client/user = ask.answerer.client
	to_chat(living_target, span_filter_system(span_boldnotice(span_large("Man up and deal with it."))))
	to_chat(living_target, span_filter_system(span_notice("Move along.")))

	log_admin("[key_name(user)] told [key_name(living_target)] to man up and deal with it.")
	message_admins(span_blue("[key_name_admin(user)] told [key_name(living_target)] to man up and deal with it."), 1)
ADMIN_VERB(global_man_up, R_ADMIN|R_FUN, "Man Up Global", "Tells everyone to man up and deal with it.", ADMIN_CATEGORY_FUN_DO_NOT)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_man_up, PROC_REF(everyone_confirmed), answerer = answerer, question = "Are you sure you want to tell the whole server up?", title = "Confirmation", choices = list("Deal with it", "No"), buttons = TRUE)

/datum/admin_verb/global_man_up/proc/everyone_confirmed(datum/act/request/A)
	tell_everyone(A)

/datum/admin_verb/global_man_up/proc/tell_everyone(datum/act/request/A)
	if(!A.answer || A.request.value != "Deal with it")
		return
	var/client/user = A.request.answerer.client
	for (var/mob/target_mob in REGISTRY_MEMBERS(REGISTRY_MOBS))
		to_chat(target_mob, "<br><center>" + span_filter_system(span_notice(span_bold(span_huge("Man up.<br> Deal with it.")) + "<br>Move along.")) + "</center><br>")
		DIRECT_OUTPUT(target_mob, 'sound/voice/manup1.ogg')

	log_and_message_admins("told everyone to man up and deal with it.", user)

ADMIN_VERB(give_spell, R_FUN, "Give Spell", ADMIN_VERB_NO_DESCRIPTION, ADMIN_CATEGORY_HIDDEN, mob/spell_recipient)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_spell, PROC_REF(spell_given), answerer = answerer, question = "Choose the spell to give to that guy", title = "ABRAKADABRA", choices = typesof(/datum/spell), target_mob = spell_recipient)

/datum/admin_verb/give_spell/proc/spell_given(datum/act/request/A)
	give_spell_answered(A)

/datum/admin_verb/give_spell/proc/give_spell_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/admin_spell/ask = A.request
	var/mob/spell_recipient = ask.target_mob
	var/mob/actor = ask.answerer
	var/datum/spell/S = ask.value
	if(!S)
		return
	spell_recipient.spell_list += new S
	feedback_add_details("admin_verb","GS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	log_admin("[key_name(actor)] gave [key_name(spell_recipient)] the spell [S].")
	message_admins(span_blue("[key_name_admin(actor)] gave [key_name(spell_recipient)] the spell [S]."), 1)

ADMIN_VERB(remove_spell, R_FUN, "Remove Spell", ADMIN_VERB_NO_DESCRIPTION, ADMIN_CATEGORY_HIDDEN, mob/removal_target)
	var/list/target_spell_list = list()
	for(var/datum/spell/spell in removal_target.spell_list)
		target_spell_list[spell.name] = spell

	if(!length(target_spell_list))
		return

	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_spell, PROC_REF(spell_removed), answerer = answerer, question = "Choose the spell to remove from [removal_target]", title = "ABRAKADABRA", choices = sortList(target_spell_list), target_mob = removal_target)

/datum/admin_verb/remove_spell/proc/spell_removed(datum/act/request/A)
	remove_spell_answered(A)

/datum/admin_verb/remove_spell/proc/remove_spell_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/admin_spell/ask = A.request
	var/client/user = ask.answerer?.client
	if(!user)
		return
	var/mob/removal_target = ask.target_mob
	var/list/target_spell_list = list()
	for(var/datum/spell/spell in removal_target.spell_list)
		target_spell_list[spell.name] = spell
	if(!length(target_spell_list))
		return
	var/chosen_spell = ask.value
	var/datum/spell/to_remove = target_spell_list[chosen_spell]
	if(!istype(to_remove))
		return

	spent(to_remove)
	log_admin("[key_name(user)] removed the spell [chosen_spell] from [key_name(removal_target)].")
	message_admins("[key_name_admin(user)] removed the spell [chosen_spell] from [key_name_admin(removal_target)].")
	feedback_add_details("admin_verb","RS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/prompt/choice/admin_spell
	rights = R_FUN
	timeout = 0
	var/mob/target_mob
	var/target_expected = FALSE
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/choice/admin_spell)
	ref_one(nameof(target_mob), /mob)

/datum/prompt/choice/admin_spell/prepare(datum/act/A)
	. = ..()
	var/mob/captured = target_mob
	target_expected = !isnull(captured)
	rel_clear(src, nameof(target_mob))
	rel_set(src, nameof(target_mob), captured)

/datum/prompt/choice/admin_spell/recheck_extra()
	. = ..()
	if(.)
		return
	return target_expected && QDELETED(target_mob) ? "target is gone" : null

ADMIN_VERB(debug_statpanel, R_DEBUG, "Debug Stat Panel", "Toggles local debug of the stat panel.", ADMIN_CATEGORY_DEBUG_MISC)
	user.stat_panel.send_message("create_debug")

ADMIN_VERB(spawn_reagent, R_DEBUG|R_EVENT, "Spawn Reagent", "Spawn any reagent.", ADMIN_CATEGORY_DEBUG_GAME)
	return reagent_spawn_stage(user, list())

/datum/admin_verb/spawn_reagent/proc/reagent_spawn_stage(client/user, list/reagent_answers)
	if(!("a22" in reagent_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/choice/admin_reagent_spawn, PROC_REF(reagent_spawn_answered), answerer = user.mob, choices = subtypesof(/datum/reagent))
		return
	var/datum/reagent/new_reagent = reagent_answers["a22"]
	if(isnull(new_reagent))
		return
	if(!new_reagent)
		return

	var/mob/user_mob = user.mob
	var/obj/item/reagent_containers/glass/bottle/new_bottle = new(user_mob.loc)

	new_bottle.icon_state = "bottle-1"
	new_bottle.reagents.add_reagent(new_reagent.id, 60)
	new_bottle.name = "[new_bottle.name] of [new_reagent.name]"

ADMIN_VERB(add_hidden_area, R_ADMIN|R_FUN, "Add Ghostsight Block Area", "Blocks ghost sight in the taget area.", ADMIN_CATEGORY_GAME)
	var/list/blocked_areas = list()
	for(var/type, value in GLOB.areas_by_type)
		var/area/current_area = value
		if(!current_area.flag_check(AREA_BLOCK_GHOST_SIGHT))
			blocked_areas[current_area.name] = current_area
	blocked_areas = sortTim(blocked_areas, GLOBAL_PROC_REF(cmp_text_asc))
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_ghostsight_area, PROC_REF(area_hidden), answerer = answerer, question = "Pick an area to hide from ghost", title = "Select Area to hide", choices = blocked_areas)

/datum/admin_verb/add_hidden_area/proc/area_hidden(datum/act/request/A)
	area_answered(A)

/datum/admin_verb/add_hidden_area/proc/area_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/selected_area = A.request.value
	var/list/blocked_areas = list()
	for(var/type, value in GLOB.areas_by_type)
		var/area/current_area = value
		if(!current_area.flag_check(AREA_BLOCK_GHOST_SIGHT))
			blocked_areas[current_area.name] = current_area
	blocked_areas = sortTim(blocked_areas, GLOBAL_PROC_REF(cmp_text_asc))
	if(isnull(selected_area))
		return
	var/area/target_area = blocked_areas[selected_area]
	if(!target_area)
		return
	target_area.flags |= AREA_BLOCK_GHOST_SIGHT
	GLOB.ghostnet.addArea(target_area)

ADMIN_VERB(remove_hidden_area, R_ADMIN|R_FUN, "Remove Ghostsight Block Area", "Unblocks ghost sight in the taget area.", ADMIN_CATEGORY_GAME)
	var/list/blocked_areas = list()
	for(var/type, value in GLOB.areas_by_type)
		var/area/current_area = value
		if(current_area.flag_check(AREA_BLOCK_GHOST_SIGHT))
			blocked_areas[current_area.name] = current_area
	blocked_areas = sortTim(blocked_areas, GLOBAL_PROC_REF(cmp_text_asc))
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_ghostsight_area, PROC_REF(area_revealed), answerer = answerer, question = "Pick a from ghost hidden area to let them see it again", title = "Select Hidden Area", choices = blocked_areas)

/datum/admin_verb/remove_hidden_area/proc/area_revealed(datum/act/request/A)
	area_answered(A)

/datum/admin_verb/remove_hidden_area/proc/area_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/selected_area = A.request.value
	var/list/blocked_areas = list()
	for(var/type, value in GLOB.areas_by_type)
		var/area/current_area = value
		if(current_area.flag_check(AREA_BLOCK_GHOST_SIGHT))
			blocked_areas[current_area.name] = current_area
	blocked_areas = sortTim(blocked_areas, GLOBAL_PROC_REF(cmp_text_asc))
	if(isnull(selected_area))
		return
	var/area/target_area = blocked_areas[selected_area]
	if(!target_area)
		return
	target_area.flags &= ~(AREA_BLOCK_GHOST_SIGHT)
	GLOB.ghostnet.removeArea(target_area)

ADMIN_VERB(hide_motion_tracker_feedback, R_ADMIN|R_EVENT, "Toggle Motion Echos", "Hides or reveals motion tracker echos globally.", ADMIN_CATEGORY_EVENTS)
	SSmotiontracker.hide_all = !motiontracker_hide_all()
	log_admin("[key_name(user)] changed the motion echo visibility to [motiontracker_hide_all() ? "hidden" : "visible"].")

ADMIN_VERB(adminorbit, R_FUN, "Orbit Things", "Makes something orbit around something else.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/center
	var/atom/movable/orbiter
	var/input

	var/datum/marked_datum = user.holder.marked_datum()
	if(marked_datum)
		var/_answer_a25 = verb_ask(user, "a25", args, /datum/prompt/choice, question = "You have \n[marked_datum] marked, should this be the center of the orbit, or the orbiter?", title = "Orbit", choices = list("Center", "Orbiter", "Neither"), buttons = TRUE)
		if(isnull(_answer_a25))
			return
		input = _answer_a25
		switch(input)
			if("Center")
				center = marked_datum
			if("Orbiter")
				orbiter = marked_datum
	var/list/possible_things = list()
	for(var/T as mob in view(user.view))	//Let's do mobs before objects
		if(ismob(T))
			possible_things |= T
	for(var/T as obj in view(user.view))
		if(isobj(T))
			possible_things |= T
	if(!center)
		var/_answer_a26 = verb_ask(user, "a26", args, /datum/prompt/choice, question = "What should act as the center of the orbit?", title = "Center", choices = possible_things)
		if(isnull(_answer_a26))
			return
		center = _answer_a26
		possible_things -= center
	if(!orbiter)
		var/_answer_a27 = verb_ask(user, "a27", args, /datum/prompt/choice, question = "What should act as the orbiter of the orbit?", title = "Orbiter", choices = possible_things)
		if(isnull(_answer_a27))
			return
		orbiter = _answer_a27
	if(!center || !orbiter)
		to_chat(user, span_warning("A center of orbit and an orbiter must be configured. You can also do this by marking a target."))
		return
	if(center == orbiter)
		to_chat(user, span_warning("The center of the orbit cannot also be the orbiter."))
		return
	if(isturf(orbiter))
		to_chat(user, span_warning("The orbiter cannot be a turf. It can only be used as a center."))
		return
	var/distance = verb_ask(user, "a28", args, /datum/prompt/number, question = "How large will their orbit radius be? (In pixels. 32 is 'near around a character)", title = "Orbit Radius", default = 32)
	if(isnull(distance))
		return
	var/speed = verb_ask(user, "a29", args, /datum/prompt/number, question = "How fast will they orbit (negative numbers spin clockwise)", title = "Orbit Speed", default = 20)
	if(isnull(speed))
		return
	var/segments = verb_ask(user, "a30", args, /datum/prompt/number, question = "How many segments will they have in their orbit? (3 is a triangle, 36 is a circle, etc)", title = "Orbit Segments", default = 36)
	if(isnull(segments))
		return
	var/clock = FALSE
	if(!distance)
		distance = 32
	if(!speed)
		speed = 20
	else if (speed < 0)
		clock = TRUE
		speed *= -1
	if(!segments)
		segments = 36
	var/_answer_a31 = verb_ask(user, "a31", args, /datum/prompt/choice, question = "\The [orbiter] will orbit around [center]. Is this okay?", title = "Confirm Orbit", choices = list("Yes", "No"), buttons = TRUE)
	if(isnull(_answer_a31))
		return
	if(_answer_a31 == "Yes")
		orbiter.orbit(center, distance, clock, speed, segments)

ADMIN_VERB(removetickets, R_ADMIN, "Security Tickets", "Allows one to remove tickets from the global list.", ADMIN_CATEGORY_INVESTIGATE)
	return security_ticket_stage(user, list())

/datum/admin_verb/removetickets/proc/security_ticket_stage(client/user, list/ticket_answers)
	if(GLOB.security_printer_tickets.len >= 1)
		if(!("a32" in ticket_answers))
			if(!user || !user.mob || QDELETED(user.mob))
				return
			open_request(src, /datum/prompt/choice/security_ticket_review, PROC_REF(security_ticket_answered), answerer = user.mob, ticket_answers = ticket_answers, ticket_key = "a32", question = "Which message?", title = "Security Tickets", choices = GLOB.security_printer_tickets)
			return
		var/input = ticket_answers["a32"]
		if(isnull(input))
			return
		if(!input)
			return
		if(!("a33" in ticket_answers))
			if(!user || !user.mob || QDELETED(user.mob))
				return
			open_request(src, /datum/prompt/choice/security_ticket_review, PROC_REF(security_ticket_answered), answerer = user.mob, ticket_answers = ticket_answers, ticket_key = "a33", question = "Do you want to remove the following message from the global list? \"[input]\"", title = "Remove Ticket", choices = list("Yes", "No"), buttons = TRUE)
			return
		var/_answer_a33 = ticket_answers["a33"]
		if(isnull(_answer_a33))
			return
		if(_answer_a33 == "Yes")
			GLOB.security_printer_tickets -= input
			log_and_message_admins("removed a security ticket from the global list: \"[input]\"", user)

	else
		open_request(user.mob, /datum/prompt/choice/security_ticket_empty_notification, null, answerer = user.mob, question = "The ticket list is empty.", title = "Empty", choices = list("Ok"))

ADMIN_VERB(delbook, R_ADMIN, "Delete Book", "Permamently deletes a book from the database.", ADMIN_CATEGORY_GAME)
	var/obj/machinery/librarycomp/our_comp
	for(var/obj/machinery/librarycomp/l in world)
		our_comp = l
		break

	if(!our_comp)
		to_chat(user, span_warning("Unable to locate a library computer to use for book deleting."))
		return

	// Delete Book panel now opens a structured TGUI panel, once the book list arrives (io_job).
	if(!SSdbcore.IsConnected())
		var/datum/dq_delete_book_panel/offline_panel = new(our_comp, list(), "Unable to contact External Archive. Please contact your system administrator for assistance.")
		offline_panel.tgui_interact(user.mob)
		return
	// Map sortby to a fixed column literal so ORDER BY can never be injected.
	io_job(our_comp, /datum/io_backend/sql, "SELECT id, author, title, category FROM library ORDER BY [our_comp.safe_sortby_column()]", null, TYPE_PROC_REF(/obj/machinery/librarycomp, delbook_rows_arrived), user.ckey)

/// io_job() callback for Delete Book: opens the panel for the admin, if they still are one.
/obj/machinery/librarycomp/proc/delbook_rows_arrived(list/result, error, admin_ckey)
	var/client/C = GLOB.directory[admin_ckey]
	if(!C || !check_rights_for(C, R_ADMIN))
		return
	var/list/book_rows = list()
	for(var/list/row as anything in result?["rows"])
		book_rows += list(list(
			"id" = "[row[1]]",
			"author" = "[row[2]]",
			"title" = "[row[3]]",
			"category" = "[row[4]]",
		))
	var/datum/dq_delete_book_panel/panel = new(src, book_rows, error ? "The External Archive query failed." : "")
	panel.tgui_interact(C.mob)

ADMIN_VERB(toggle_spawning_with_recolour, R_ADMIN|R_EVENT|R_FUN, "Toggle Simple/Robot recolour verb", "Makes it so new robots/simple_mobs spawn with a verb to recolour themselves for this round. You must set them separately.", ADMIN_CATEGORY_SERVER_GAME)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_recolour_grant, PROC_REF(recolour_chosen), answerer = answerer)

/datum/admin_verb/toggle_spawning_with_recolour/proc/recolour_chosen(datum/act/request/A)
	apply_recolour_choice(A)

/datum/admin_verb/toggle_spawning_with_recolour/proc/apply_recolour_choice(datum/act/request/A)
	if(!A.answer)
		return
	var/which = A.request.value
	var/client/user = A.request.answerer.client
	switch(which)
		if("Robot")
			CONFIG_SET(flag/allow_robot_recolor, !CONFIG_GET(flag/allow_robot_recolor))
			to_chat(user, "You have [CONFIG_GET(flag/allow_robot_recolor) ? "enabled" : "disabled"] newly spawned cyborgs to spawn with the recolour verb")
		if("Simple Mob")
			CONFIG_SET(flag/allow_simple_mob_recolor, !CONFIG_GET(flag/allow_simple_mob_recolor))
			to_chat(user, "You have [CONFIG_GET(flag/allow_simple_mob_recolor) ? "enabled" : "disabled"] newly spawned simple mobs to spawn with the recolour verb")

ADMIN_VERB(modify_shift_end, (R_ADMIN|R_EVENT|R_SERVER), "Modify Shift End", "Modifies the hard shift end time.", ADMIN_CATEGORY_SERVER_GAME)
	SStransfer.modify_hard_end(user)

/datum/prompt/choice/admin_ghostsight_area
	rights = R_ADMIN|R_FUN
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/admin_man_up
	rights = R_ADMIN|R_FUN
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/admin_man_up/recheck_extra()
	. = ..()
	if(.)
		return
	if(istype(value, /datum))
		var/datum/picked = value
		return QDELETED(picked) ? "target is gone" : null

/datum/prompt/choice/admin_man_up/confirmation
	var/mob/living/target

CAPABILITIES(/datum/prompt/choice/admin_man_up/confirmation)
	ref_one(nameof(target), /mob/living)

/datum/prompt/choice/admin_man_up/confirmation/prepare(datum/act/A)
	. = ..()
	var/mob/living/captured = target
	rel_clear(src, nameof(target))
	rel_set(src, nameof(target), captured)

/datum/prompt/choice/admin_man_up/confirmation/recheck_extra()
	. = ..()
	if(.)
		return
	return QDELETED(target) ? "target is gone" : null

/datum/prompt/choice/admin_recolour_grant
	rights = R_ADMIN|R_EVENT|R_FUN
	timeout = 0
	question = "Which do you want to toggle?"
	title = "Choose Recolour Toggle"
	buttons = TRUE
	choices = list("Robot", "Simple Mob")
	recheck_on_open = TRUE

/datum/prompt/text/admin_stealth_name
	rights = R_STEALTH
	timeout = 0
	question = "Enter your desired display name."
	title = "Fake Key"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_silicon_rename
	rights = R_ADMIN|R_FUN|R_EVENT
	timeout = 0
	question = "Select silicon."
	title = "Rename Silicon."
	recheck_on_open = TRUE

/datum/prompt/choice/admin_silicon_rename/recheck_extra()
	. = ..()
	if(.)
		return
	if(!isnull(value))
		var/mob/living/silicon/picked = value
		return QDELETED(picked) ? "target is gone" : null

/datum/prompt/text/admin_silicon_name
	rights = R_ADMIN|R_FUN|R_EVENT
	timeout = 0
	question = "Enter new name. Leave blank or as is to cancel."
	encode = FALSE
	var/mob/living/silicon/target
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/text/admin_silicon_name)
	ref_one(nameof(target), /mob/living/silicon)

/datum/prompt/text/admin_silicon_name/prepare(datum/act/A)
	. = ..()
	var/mob/living/silicon/captured = target
	rel_clear(src, nameof(target))
	rel_set(src, nameof(target), captured)

/datum/prompt/text/admin_silicon_name/recheck_extra()
	. = ..()
	if(.)
		return
	return QDELETED(target) ? "target is gone" : null

/datum/prompt/choice/admin_law_target
	rights = R_ADMIN|R_EVENT
	timeout = 0
	question = "Select silicon."
	title = "Manage Silicon Laws"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_law_target/recheck_extra()
	. = ..()
	if(.)
		return
	if(!isnull(value))
		var/mob/living/silicon/picked = value
		return QDELETED(picked) ? "target is gone" : null

/datum/prompt/choice/admin_security_level
	rights = R_ADMIN|R_EVENT
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/admin_security_level/confirmation
	title = "Change security level?"
	buttons = TRUE
	choices = list("Yes", "No")
	var/selected_level

/datum/prompt/choice/security_ticket_review
	recheck_on_open = TRUE
	timeout = 0
	rights = R_ADMIN
	var/list/ticket_answers
	var/ticket_key

/datum/prompt/choice/security_ticket_review/recheck_extra()
	if(!admin_can(answerer?.client, 0))
		return "no admin rights"

/proc/security_ticket_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/admin_verb/removetickets/proc/security_ticket_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(security_ticket_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	var/datum/prompt/choice/security_ticket_review/ask = context.answer
	var/list/ticket_answers = ask.ticket_answers.Copy()
	ticket_answers[ask.ticket_key] = ask.value
	return security_ticket_stage(user, ticket_answers)

/datum/prompt/choice/admin_reagent_spawn
	recheck_on_open = TRUE
	timeout = 0
	rights = R_DEBUG|R_EVENT
	question = "Select a reagent to spawn"
	title = "Reagent Spawner"

/datum/prompt/choice/admin_reagent_spawn/recheck_extra()
	if(!admin_can(answerer?.client, 0))
		return "no admin rights"

/proc/reagent_spawn_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/admin_verb/spawn_reagent/proc/reagent_spawn_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(reagent_spawn_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	return reagent_spawn_stage(user, list("a22" = context.answer.value))

/datum/prompt/choice/admin_job_slot
	recheck_on_open = TRUE
	timeout = 0
	rights = R_ADMIN|R_FUN|R_EVENT
	question = "Please select job slot to free"
	title = "Free job slot"

/datum/prompt/choice/admin_job_slot/recheck_extra()
	if(!admin_can(answerer?.client, 0))
		return "no admin rights"

/proc/job_slot_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/admin_verb/free_slot/proc/job_slot_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(job_slot_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	return job_slot_stage(user, list("a16" = context.answer.value))

/datum/prompt/text/admin_sound_message
	recheck_on_open = TRUE
	timeout = 0
	rights = R_FUN
	question = "What do you want the message to be?"
	title = "Make Sound"

/datum/prompt/text/admin_sound_message/recheck_extra()
	if(!admin_can(answerer?.client, 0))
		return "no admin rights"
	var/obj/target_object = subject
	if(!istype(target_object) || QDELETED(target_object))
		return "gone"

/datum/prompt/text/admin_sound_message/normalize(given)
	return istext(given) ? given : null

/proc/sound_message_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/admin_verb/make_sound/proc/sound_message_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(sound_message_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	var/obj/target_object = context.request.subject
	return sound_message_stage(user, target_object, list("a10" = context.answer.value))

/datum/prompt/choice/admin_ghost_replay
	timeout = 0
	rights = R_HOLDER
	recheck_on_open = TRUE

/datum/prompt/choice/admin_ghost_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_ghost_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_ghost_replay/refusal(given)
	return null

/datum/admin_verb/admin_ghost/proc/admin_ghost_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)

/datum/prompt/choice/security_ticket_empty_notification
	timeout = 0
	buttons = TRUE
	recheck_on_open = TRUE

/datum/prompt/choice/security_ticket_empty_notification/recheck_extra()
	return answerer?.client ? null : "gone"
