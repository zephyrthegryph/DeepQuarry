/client/verb/vote()
	set category = VERB_CAT_OOC_GAME
	set name = "Vote"

	var/datum/vote/running = SSvote.get_active_vote()
	if(running)
		running.tgui_interact(usr)
	else
		to_chat(src, span_warning("There is no active vote"))

ADMIN_VERB(start_vote, R_HOLDER, "Start Vote", "Start a vote on the server.", ADMIN_CATEGORY_GAME)
	return vote_setup_stage(user, list())

/datum/admin_verb/start_vote/proc/vote_setup_stage(client/user, list/vote_answers)
	if(SSvote.get_active_vote())
		to_chat(user, span_warning("A vote is already in progress"))
		return

	var/vote_types = subtypesof(/datum/vote)
	vote_types |= "\[CUSTOM]"

	var/list/votemap = list()
	for(var/vtype in vote_types)
		votemap["[vtype]"] = vtype

	if(!("k22" in vote_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/choice/vote_setup_review, PROC_REF(vote_setup_answered), answerer = user.mob, vote_answers = vote_answers, vote_key = "k22", finish_options = FALSE, question = "Select a vote type", title = "Vote", choices = vote_types)
		return
	var/choice = vote_answers["k22"]
	if(isnull(choice))
		return

	if(isnull(choice))
		return

	if(choice != "\[CUSTOM]")
		var/datum/votetype = votemap["[choice]"]
		SSvote.start_vote(new votetype(user.ckey), user.mob)
		return

	if(!("k32" in vote_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/text/vote_setup_review, PROC_REF(vote_setup_answered), answerer = user.mob, vote_answers = vote_answers, vote_key = "k32", finish_options = FALSE, question = "What is the vote for?", title = "Create Vote")
		return
	var/question = vote_answers["k32"]
	if(isnull(question))
		return
	if(isnull(question))
		return

	var/list/choices = list()
	for(var/i in 1 to 10)
		// Cancel (or an empty option) finishes the list.
		if(!("option[i]" in vote_answers))
			if(!user || !user.mob || QDELETED(user.mob))
				return
			open_request(src, /datum/prompt/text/vote_setup_review, PROC_REF(vote_setup_answered), answerer = user.mob, vote_answers = vote_answers, vote_key = "option[i]", finish_options = TRUE, question = "Please enter an option or hit cancel to finish", title = "Create Vote")
			return
		var/option = vote_answers["option[i]"]
		if(isnull(option))
			return
		if(!option)
			break
		choices |= option

	if(!("k43" in vote_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/choice/vote_setup_review, PROC_REF(vote_setup_answered), answerer = user.mob, vote_answers = vote_answers, vote_key = "k43", finish_options = FALSE, question = "Show counts while vote is happening?", title = "Counts", choices = list("Yes", "No"), buttons = TRUE)
		return
	var/c2 = vote_answers["k43"]
	if(isnull(c2))
		return
	if(!("k44" in vote_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/choice/vote_setup_review, PROC_REF(vote_setup_answered), answerer = user.mob, vote_answers = vote_answers, vote_key = "k44", finish_options = FALSE, question = "Select a result calculation type", title = "Vote", choices = list(VOTE_RESULT_TYPE_MAJORITY))
		return
	var/c3 = vote_answers["k44"]
	if(isnull(c3))
		return

	var/datum/vote/V = new /datum/vote(user.ckey, question, choices, TRUE)
	V.show_counts = (c2 == "Yes")
	if(c3)
		V.vote_result_type = c3
	SSvote.start_vote(V, user.mob)

/datum/prompt/choice/vote_setup_review
	recheck_on_open = TRUE
	timeout = 0
	rights = R_HOLDER
	var/list/vote_answers
	var/vote_key
	var/finish_options = FALSE

/datum/prompt/choice/vote_setup_review/recheck_extra()
	if(!admin_can(answerer?.client, 0))
		return "no admin rights"

/datum/prompt/text/vote_setup_review
	recheck_on_open = TRUE
	timeout = 0
	rights = R_HOLDER
	var/list/vote_answers
	var/vote_key
	var/finish_options = FALSE

/datum/prompt/text/vote_setup_review/recheck_extra()
	if(!admin_can(answerer?.client, 0))
		return "no admin rights"

/datum/prompt/text/vote_setup_review/normalize(given)
	return istext(given) ? given : null

/proc/vote_setup_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/admin_verb/start_vote/proc/vote_setup_answered(datum/act/request/context)
	var/list/vote_answers
	var/vote_key
	var/finish_options = FALSE
	if(istype(context.request, /datum/prompt/text/vote_setup_review))
		var/datum/prompt/text/vote_setup_review/ask = context.request
		vote_answers = ask.vote_answers.Copy()
		vote_key = ask.vote_key
		finish_options = ask.finish_options
	else
		var/datum/prompt/choice/vote_setup_review/ask = context.request
		vote_answers = ask.vote_answers.Copy()
		vote_key = ask.vote_key
	if(!context.answer && !(finish_options && context.request.outcome == REQ_CANCELLED && isnull(context.request.answer_value)))
		return
	var/mob/answerer = context.request.answerer
	if(!answerer || QDELETED(answerer))
		return
	// Old cancel-answer continuation silently rechecked its flow rights before dispatch.
	if(!context.answer && request_recheck(context.request))
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(vote_setup_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(!admin_can(user, permissions))
		admin_log_denial(user, "verb:[src.type]", permissions)
		to_chat(user, span_adminnotice("You lack the permissions to do this."))
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	vote_answers[vote_key] = context.answer ? context.answer.answer_value : ""
	return vote_setup_stage(user, vote_answers)
