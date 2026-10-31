ADMIN_VERB_VISIBILITY(set_server_fps, ADMIN_VERB_VISIBLITY_FLAG_MAPPING_DEBUG)
ADMIN_VERB(set_server_fps, R_DEBUG, "Set Server FPS", "Sets game speed in frames-per-second. Can potentially break the game", ADMIN_CATEGORY_DEBUG_DANGEROUS)
	// Only an actual answered request issued by this verb can supply replay answers.
	var/list/fps_answers = list()
	if(length(args) > 1)
		var/datum/request/resumed = args[2]
		if((istype(resumed, /datum/prompt/number/admin_fps) || istype(resumed, /datum/prompt/choice/admin_fps_confirm)) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(fps_answered))
			fps_answers = resumed.captured.Copy()
			fps_answers[resumed.step_name] = resumed.value
	var/cfg_fps = CONFIG_GET(number/fps)
	if(!("a1" in fps_answers))
		open_request(src, /datum/prompt/number/admin_fps, PROC_REF(fps_answered), answerer = user.mob, captured = fps_answers.Copy(), question = "Sets game frames-per-second. Can potentially break the game (default: [cfg_fps])", default = world.fps)
		return
	var/_answer_a1 = fps_answers["a1"]
	if(isnull(_answer_a1))
		return
	var/new_fps = round(_answer_a1)

	if(new_fps <= 0)
		to_chat(user, span_danger("Error: set_server_fps(): Invalid world.fps value. No changes made."), confidential = TRUE)
		return
	if(new_fps > cfg_fps * 1.5)
		if(!("a2" in fps_answers))
			open_request(src, /datum/prompt/choice/admin_fps_confirm, PROC_REF(fps_answered), answerer = user.mob, captured = fps_answers.Copy(), question = "You are setting fps to a high value:\n\t[new_fps] frames-per-second\n\tconfig.fps = [cfg_fps]")
			return
		var/_answer_a2 = fps_answers["a2"]
		if(isnull(_answer_a2))
			return
		if(_answer_a2 != "Confirm")
			return

	var/msg = "[key_name(user)] has modified world.fps to [new_fps]"
	log_admin(msg, 0)
	message_admins(msg, 0)
	//SSblackbox.record_feedback("nested tally", "admin_toggle", 1, list("Set Server FPS", "[new_fps]")) // If you are copy-pasting this, ensure the 4th parameter is unique to the new proc!
	feedback_add_details("admin_verb", "SETFPS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

	CONFIG_SET(number/fps, new_fps)
	world.change_fps(new_fps)

/datum/prompt/number/admin_fps
	title = "FPS"
	timeout = 0
	rights = R_DEBUG
	recheck_on_open = TRUE
	step_name = "a1"

/datum/prompt/number/admin_fps/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/number/admin_fps/normalize(given)
	return isnum(given) ? given : null

/datum/prompt/choice/admin_fps_confirm
	title = "Warning!"
	timeout = 0
	rights = R_DEBUG
	recheck_on_open = TRUE
	step_name = "a2"
	buttons = TRUE
	choices = list("Confirm", "ABORT-ABORT-ABORT")

/datum/prompt/choice/admin_fps_confirm/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_fps_confirm/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_fps_confirm/refusal(given)
	return null

/datum/admin_verb/set_server_fps/proc/fps_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	// The unchanged public dispatcher performs rights, tracing and metrics again.
	// Its initial advanced-proc check must see the original actor, just as the old replay did.
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)
