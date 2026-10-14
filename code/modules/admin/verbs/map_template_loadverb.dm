
ADMIN_VERB(map_template_load, R_SPAWN, "Map template - Place At Loc", "Spawns a new map template at the current position.", ADMIN_CATEGORY_DEBUG_EVENTS)
	// Replay input is only a synchronous answered request from this verb.
	var/list/replay_answers = list()
	if(length(args) > 1)
		var/datum/request/resumed = args[2]
		if(istype(resumed, /datum/prompt/choice/admin_map_template_replay) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(map_template_load_replay_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	if(!("map" in replay_answers))
		open_request(src, /datum/prompt/choice/admin_map_template_replay, PROC_REF(map_template_load_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "map", question = "Choose a Map Template to place at your CURRENT LOCATION", title = "Place Map Template", choices = mapping_map_templates())
		return
	var/map = replay_answers["map"]
	if(!map)
		return
	var/datum/map_template/template = mapping_map_templates()[map]

	var/turf/T = get_turf(user.mob)
	if(!T)
		return

	// The preview stays up while the admin confirms; the answer takes it down.
	var/list/preview = list()
	template.preload_size(template.mappath)
	for(var/S in template.get_affected_turfs(T,centered = TRUE))
		preview += image('icons/misc/debug_group.dmi',S ,"red")
	user.images += preview
	var/mob/answerer = user.mob
	if(!check_rights_for(user, R_SPAWN) || QDELETED(T) || QDELETED(answerer))
		user.images -= preview
		return
	open_request(src, /datum/prompt/choice/map_template_place, PROC_REF(location_confirmed), answerer = answerer, template_name = map, place_at = T, preview = preview, question = "Confirm location.")

/// Placing a map template at a turf: confirm the location (and, for an annihilating template,
/// confirm again). The red preview stays up until the flow ends either way.
/datum/prompt/choice/map_template_place
	title = "Template Confirm"
	choices = list("No", "Yes")
	buttons = TRUE
	rights = R_SPAWN
	timeout = 0
	var/template_name
	var/turf/place_at
	var/list/preview
	var/preview_transferred = FALSE

CAPABILITIES(/datum/prompt/choice/map_template_place)
	ref_one(nameof(place_at), /turf)

/datum/prompt/choice/map_template_place/prepare(datum/act/A)
	..()
	var/turf/captured_place = place_at
	rel_clear(src, nameof(place_at))
	rel_set(src, nameof(place_at), captured_place)

/datum/prompt/choice/map_template_place/recheck_extra()
	return QDELETED(place_at) ? "gone" : null

/datum/prompt/choice/map_template_place/proc/end_preview()
	var/mob/user = answerer
	user?.client?.images -= preview

/datum/prompt/choice/map_template_place/on_destroy(force)
	if(!preview_transferred)
		end_preview()
	return ..()

/datum/admin_verb/map_template_load/proc/location_confirmed(datum/act/request/A)
	if(!A.answer || A.answer.value != "Yes")
		return
	var/datum/prompt/choice/map_template_place/ask = A.answer
	var/datum/map_template/template = mapping_map_templates()[ask.template_name]
	if(template?.annihilate)
		var/datum/request/next_request = open_request(src, /datum/prompt/choice/map_template_place, PROC_REF(place_confirmed), answerer = ask.answerer, template_name = ask.template_name, place_at = ask.place_at, preview = ask.preview, question = "This template is set to annihilate everything in the red square. EVERYTHING IN THE RED SQUARE WILL BE DELETED, ARE YOU ABSOLUTELY SURE?")
		ask.preview_transferred = !isnull(next_request)
		return
	place_confirmed(A)

/datum/admin_verb/map_template_load/proc/place_confirmed(datum/act/request/A)
	if(!A.answer || A.answer.value != "Yes")
		return
	var/datum/prompt/choice/map_template_place/ask = A.answer
	var/mob/user = ask.answerer
	ask.end_preview()
	var/datum/map_template/template = mapping_map_templates()[ask.template_name]
	if(!template)
		to_chat(user, "Failed to place map")
		return
	var/turf/place_at = ask.place_at
	template.load_async(place_at, TRUE, TYPE_PROC_REF(/datum/map_template, admin_placed), template, list(user))

ADMIN_VERB(map_template_load_on_new_z, R_SPAWN, "Map template - New Z", "Spawns a new map template at the selected z level.", ADMIN_CATEGORY_DEBUG_EVENTS)
	// Replay input is only a synchronous answered request from this verb.
	var/list/replay_answers = list()
	if(length(args) > 1)
		var/datum/request/resumed = args[2]
		if(istype(resumed, /datum/prompt/choice/admin_map_template_z_replay) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(map_template_load_on_new_z_replay_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	if(!("a1" in replay_answers))
		open_request(src, /datum/prompt/choice/admin_map_template_z_replay, PROC_REF(map_template_load_on_new_z_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a1", question = "Choose a Map Template to place on a new Z-level.", title = "Place Map Template", choices = mapping_map_templates())
		return
	var/map = replay_answers["a1"]
	if(isnull(map))
		return
	if(!map)
		return
	var/datum/map_template/template = mapping_map_templates()[map]

	if(template.width > world.maxx || template.height > world.maxx)
		if(!("a2" in replay_answers))
			open_request(src, /datum/prompt/choice/admin_map_template_z_replay, PROC_REF(map_template_load_on_new_z_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a2", buttons = TRUE, question = "This template is larger than the existing z-levels. It will EXPAND ALL Z-LEVELS to match the size of the template. This may cause chaos. Are you sure you want to do this?", title = "DANGER!!!", choices = list("Cancel","Yes"))
			return
		var/_answer_a2 = replay_answers["a2"]
		if(isnull(_answer_a2))
			return
		if(_answer_a2 == "Cancel")
			to_chat(user,"Template placement aborted.")
			return

	if(!("a3" in replay_answers))
		open_request(src, /datum/prompt/choice/admin_map_template_z_replay, PROC_REF(map_template_load_on_new_z_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a3", buttons = TRUE, question = "Confirm map load.", title = "Template Confirm", choices = list("No","Yes"))
		return
	var/_answer_a3 = replay_answers["a3"]
	if(isnull(_answer_a3))
		return
	if(_answer_a3 == "Yes")
		template.load_new_z_async(FALSE, TYPE_PROC_REF(/datum/map_template, admin_placed_z), template, list(user))

ADMIN_VERB(map_template_upload, R_SPAWN, "Map Template - Upload", "Uploads the selected map template to the template storage.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/map = input(user, "Choose a Map Template to upload to template storage","Upload Map Template") as null|file // ALLOW(scheduler): file uploads need the BYOND file dialog
	if(!map)
		return
	if(copytext("[map]",-4) != ".dmm")
		to_chat(user, "Bad map file: [map]")
		return

	var/datum/map_template/M = new(map, "[map]")
	if(M.preload_size(map))
		to_chat(user, "Map template '[map]' ready to place ([M.width]x[M.height])")
		SSmapping.map_templates[M.name] = M
		message_admins(span_adminnotice("[key_name_admin(user)] has uploaded a map template ([map])"))
	else
		to_chat(user, "Map template '[map]' failed to load properly")

/datum/prompt/choice/admin_map_template_replay
	timeout = 0
	rights = R_SPAWN
	recheck_on_open = TRUE

/datum/prompt/choice/admin_map_template_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_map_template_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_map_template_replay/refusal(given)
	return null

/datum/admin_verb/map_template_load/proc/map_template_load_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)

/datum/prompt/choice/admin_map_template_z_replay
	timeout = 0
	rights = R_SPAWN
	recheck_on_open = TRUE

/datum/prompt/choice/admin_map_template_z_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_map_template_z_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_map_template_z_replay/refusal(given)
	return null

/datum/admin_verb/map_template_load_on_new_z/proc/map_template_load_on_new_z_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)
