ADMIN_VERB(cinematic, R_FUN, "Cinematic", "Show a cinematic to all players.", ADMIN_CATEGORY_FUN_DO_NOT)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_cinematic, PROC_REF(cinematic_selected), answerer = answerer, choices = sortList(subtypesof(/datum/cinematic), GLOBAL_PROC_REF(cmp_typepaths_asc)))

/datum/admin_verb/cinematic/proc/cinematic_selected(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/result/result = safe_call(PROC_REF(play_selected_cinematic), context)
	if(!result.ok)
		stack_trace("om flow cinematic answer cinematic_selected: [result.error]")

/datum/admin_verb/cinematic/proc/play_selected_cinematic(datum/act/request/context)
	var/choice = context.request.answer_value
	if(!choice || !ispath(choice, /datum/cinematic))
		return
	play_cinematic(choice, world)

/datum/prompt/choice/admin_cinematic
	rights = R_FUN
	timeout = 0
	question = "Chose a cinematic to play to everyone in the server."
	title = "Choose Cinematic"

/datum/prompt/choice/admin_cinematic/begin()
	if(request_recheck(src))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()
