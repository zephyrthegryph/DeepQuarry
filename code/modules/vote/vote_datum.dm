/datum/vote
	// Person who started the vote
	var/initiator = "the server"
	// world.time the bote started at
	EXPIRY_DECLARE(started_time)
	// The question being asked
	var/question
	// Vote type text, for showing in UIs and stuff
	var/vote_type_text = "unset"
	// Do we want to show the vote count as it goes
	var/show_counts = FALSE
	// Vote result type. This determines how a winner is picked
	var/vote_result_type = VOTE_RESULT_TYPE_MAJORITY
	// Was this this vote custom started?
	var/is_custom = FALSE
	// Choices available in the vote
	var/list/choices
	// Assoc list of [ckeys => choice] who have voted. We don't want to hold clients refs.
	var/list/voted
	// For how long will it be up
	var/vote_time = 60 SECONDS

/datum/vote/New(_initiator, _question, list/_choices, _is_custom = FALSE)
	if(SSvote.get_active_vote())
		CRASH("Attempted to start another vote with one already in progress!")

	if(_initiator)
		initiator = _initiator
	if(_question)
		question = _question
	if(_choices)
		choices = _choices

	is_custom = _is_custom

	// If we have no choices, dynamically generate them
	if(!length(choices))
		generate_choices()

/datum/vote/proc/start(mob/user)
	var/text = "[capitalize(vote_type_text)] vote started by [initiator]."
	if(is_custom)
		vote_type_text = "custom"
		text += "\n[question]"
		if(user)
			log_admin("[capitalize(vote_type_text)] ([question]) vote started by [key_name(user)].")

	else if(user)
		log_admin("[capitalize(vote_type_text)] vote started by [key_name(user)].")

	log_vote(text)
	EXPIRY_STAMP(src, started_time, CLOCK_WORLD)
	announce(text)

/datum/vote/proc/remaining()
	return max(((started_time + vote_time - world.time)/10), 0)

/datum/vote/proc/calculate_result()
	if(!length(voted))
		to_chat(world, span_interface("No votes were cast. Do you all hate democracy?!"))
		return null

	return calculate_vote_result(voted || list(), choices, vote_result_type)

/datum/vote/proc/calculate_vote_result(list/voted, list/choices, vote_result_type)
	var/list/results = list()

	for(var/ck in voted)
		if(voted[ck] in results)
			results[voted[ck]]++
		else
			results[voted[ck]] = 1

	var/maxvotes = 0
	for(var/res in results)
		maxvotes = max(results[res], maxvotes)

	var/list/winning_options = list()

	for(var/res in results)
		if(results[res] == maxvotes)
			winning_options |= res

	for(var/res in results)
		to_chat(world, span_interface("<code>[res]</code> - [results[res]] vote\s"))

	switch(vote_result_type)
		if(VOTE_RESULT_TYPE_MAJORITY)
			if(length(winning_options) == 1)
				var/res = winning_options[1]
				if(res in choices)
					to_chat(world, span_interface(span_bold("<code>[res]</code> won the vote!")))
					return res
				else
					to_chat(world, span_interface("The winner of the vote ([sanitize(res)]) isn't a valid choice? What the heck?"))
					stack_trace("Vote concluded with an invalid answer. Answer was [sanitize(res)], choices were [json_encode(choices)]")
					return null

			to_chat(world, span_interface(span_bold("No clear winner. The vote did not pass.")))
			return null

		if(VOTE_RESULT_TYPE_SKEWED)
			var/required_votes = ceil(length(voted) * 0.7)  // 70% of total votes
			if(maxvotes >= required_votes && length(winning_options) == 1)
				var/res = winning_options[1]
				if(res in choices)
					to_chat(world, span_interface(span_bold("<code>[res]</code> won the vote with a 70% majority!")))
					return res
				else
					to_chat(world, span_interface("The winner of the vote ([sanitize(res)]) isn't a valid choice? What the heck?"))
					stack_trace("Vote concluded with an invalid answer. Answer was [sanitize(res)], choices were [json_encode(choices)]")
					return null

			to_chat(world, span_interface(span_bold("No option received 70% of the votes. The vote did not pass.")))
			return null

	return null

/datum/vote/proc/announce(start_text, time = vote_time)
	to_chat(world, span_lightpurple("Type <b>vote</b> or click <a href='byond://?src=\ref[src];[HrefToken()];vote=open'>here</a> to place your vote. \
		You have [time/10] seconds to vote."))
	world << sound('sound/ambience/alarm4.ogg', repeat = 0, wait = 0, volume = 50, channel = 3)


/datum/vote/proc/topic_open(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return TRUE

/datum/vote/proc/tick()
	if(remaining() == 0)
		var/result = calculate_result()
		handle_result(result)
		lapsed(src)

// SSvote forgets it.
/datum/vote/lifecycle_dematerialize()
	..()
	SSvote.forget_vote(src)

/datum/vote/proc/handle_result(result)
	return

/datum/vote/proc/generate_choices()
	return

/*
	UI STUFFS
*/

CAPABILITIES(/datum/vote)
	interface("VotePanel", title = "Vote Panel", state = nameof(GLOB.tgui_always_state))
	op("vote", ui_act("vote", arg("target", schema_text(4096))), then(PROC_REF(ui_act_vote)))
	op("vote_open", topic("vote=open"), then(PROC_REF(topic_open)))

/datum/vote/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["question"] = question
	var/list/merged_1 = ui_data_datum_vote(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/vote's window data.
/datum/vote/proc/ui_data_datum_vote(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["remaining"] = remaining()
	data["user_vote"] = null
	if(user.ckey in voted)
		data["user_vote"] = LAZYACCESS(voted, user.ckey)

	data["choices"] = (choices || list())

	if(show_counts || check_rights_for(user.client, R_ADMIN))
		data["show_counts"] = TRUE

		var/list/counts = list()
		for(var/ck in voted)
			if(LAZYACCESS(voted, ck) in counts)
				counts[LAZYACCESS(voted, ck)]++
			else
				counts[LAZYACCESS(voted, ck)] = 1

		data["counts"] = counts
	else
		data["show_counts"] = FALSE
		data["counts"] = list()

	return data

/datum/vote/proc/ui_act_vote(datum/act/op/A, target)
	var/mob/user = A.actor
	. = TRUE
	if(target in choices)
		LAZYSET(voted, user.ckey, target)
	else
		message_admins(span_warning("User [key_name_admin(user)] spoofed a vote in the vote panel!"))
