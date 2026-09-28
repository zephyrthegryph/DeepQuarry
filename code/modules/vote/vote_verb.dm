/client/verb/vote()
	set category = "OOC.Game"
	set name = "Vote"

	if(GLOB.vote_service.active_vote)
		GLOB.vote_service.active_vote.tgui_interact(usr)
	else
		to_chat(src, span_warning("There is no active vote"))

ADMIN_VERB(start_vote, R_HOLDER, "Start Vote", "Start a vote on the server.", ADMIN_CATEGORY_GAME)
	if(GLOB.vote_service.active_vote)
		to_chat(user, span_warning("A vote is already in progress"))
		return

	var/vote_types = subtypesof(/datum/vote)
	vote_types |= "\[CUSTOM]"

	var/list/votemap = list()
	for(var/vtype in vote_types)
		votemap["[vtype]"] = vtype

	var/choice = verb_prompt(user, "k22", list("kind" = "list", "message" = "Select a vote type", "title" = "Vote", "choices" = vote_types), args)
	if(isnull(choice))
		return

	if(isnull(choice))
		return

	if(choice != "\[CUSTOM]")
		var/datum/votetype = votemap["[choice]"]
		GLOB.vote_service.start_vote(new votetype(user.ckey))
		return

	var/question = verb_prompt(user, "k32", list("kind" = "text", "message" = "What is the vote for?", "title" = "Create Vote", "max_length" = MAX_MESSAGE_LEN), args)
	if(isnull(question))
		return
	if(isnull(question))
		return

	var/list/choices = list()
	for(var/i in 1 to 10)
		// Cancel (or an empty option) finishes the list.
		var/option = verb_prompt(user, "option[i]", list("kind" = "text", "message" = "Please enter an option or hit cancel to finish", "title" = "Create Vote", "max_length" = MAX_MESSAGE_LEN, "cancel_answer" = ""), args)
		if(isnull(option))
			return
		if(!option)
			break
		choices |= option

	var/c2 = verb_prompt(user, "k43", list("message" = "Show counts while vote is happening?", "title" = "Counts", "choices" = list("Yes", "No")), args)
	if(isnull(c2))
		return
	var/c3 = verb_prompt(user, "k44", list("kind" = "list", "message" = "Select a result calculation type", "title" = "Vote", "choices" = list(VOTE_RESULT_TYPE_MAJORITY)), args)
	if(isnull(c3))
		return

	var/datum/vote/V = new /datum/vote(user.ckey, question, choices, TRUE)
	V.show_counts = (c2 == "Yes")
	if(c3)
		V.vote_result_type = c3
	GLOB.vote_service.start_vote(V)
