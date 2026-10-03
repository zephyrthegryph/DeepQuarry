/client/verb/vote()
	set category = VERB_CAT_OOC_GAME
	set name = "Vote"

	var/datum/vote/running = SSvote.get_active_vote()
	if(running)
		running.tgui_interact(usr)
	else
		to_chat(src, span_warning("There is no active vote"))

ADMIN_VERB(start_vote, R_HOLDER, "Start Vote", "Start a vote on the server.", ADMIN_CATEGORY_GAME)
	if(SSvote.get_active_vote())
		to_chat(user, span_warning("A vote is already in progress"))
		return

	var/vote_types = subtypesof(/datum/vote)
	vote_types |= "\[CUSTOM]"

	var/list/votemap = list()
	for(var/vtype in vote_types)
		votemap["[vtype]"] = vtype

	var/choice = verb_ask(user, "k22", args, /datum/om/prompt/choice, message = "Select a vote type", title = "Vote", choices = vote_types)
	if(isnull(choice))
		return

	if(isnull(choice))
		return

	if(choice != "\[CUSTOM]")
		var/datum/votetype = votemap["[choice]"]
		SSvote.start_vote(new votetype(user.ckey), user.mob)
		return

	var/question = verb_ask(user, "k32", args, /datum/om/prompt/text, message = "What is the vote for?", title = "Create Vote")
	if(isnull(question))
		return
	if(isnull(question))
		return

	var/list/choices = list()
	for(var/i in 1 to 10)
		// Cancel (or an empty option) finishes the list.
		var/option = verb_ask(user, "option[i]", args, /datum/om/prompt/text, message = "Please enter an option or hit cancel to finish", title = "Create Vote", cancel_answer = "")
		if(isnull(option))
			return
		if(!option)
			break
		choices |= option

	var/c2 = verb_ask(user, "k43", args, /datum/om/prompt/choice/alert, message = "Show counts while vote is happening?", title = "Counts", choices = list("Yes", "No"))
	if(isnull(c2))
		return
	var/c3 = verb_ask(user, "k44", args, /datum/om/prompt/choice, message = "Select a result calculation type", title = "Vote", choices = list(VOTE_RESULT_TYPE_MAJORITY))
	if(isnull(c3))
		return

	var/datum/vote/V = new /datum/vote(user.ckey, question, choices, TRUE)
	V.show_counts = (c2 == "Yes")
	if(c3)
		V.vote_result_type = c3
	SSvote.start_vote(V, user.mob)
