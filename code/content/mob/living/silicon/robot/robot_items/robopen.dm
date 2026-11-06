// A special pen for service droids. Can be toggled to switch between normal writting mode, and paper rename mode
// Allows service droids to rename paper items.

/obj/item/pen/robopen
	desc = "A black ink printing attachment with a paper naming mode."
	name = "Printing Pen"
	var/mode = 1
	special_handling = TRUE

CAPABILITIES(/obj/item/pen/robopen)
	op("robopen", in_hand(), label("Change colour or mode"),
		asks(/datum/prompt/choice, fields = list("ask_flags" = ASK_CARRIED | ASK_CAPABLE, "title" = "Change What?", "question" = "Would you like to change colour or mode?", "choices" = list("Colour", "Mode", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "what"),
		asks(/datum/prompt/choice, fields = list("ask_flags" = ASK_CARRIED | ASK_CAPABLE, "title" = "Color Choice", "question" = "Which colour would you like to use?", "choices" = list("black", "blue", "red", "green", "yellow"), "timeout" = 0), step = "colour", when = PROC_REF(robopen_wants_colour)),
		then(PROC_REF(interaction_robopen)))

/obj/item/pen/robopen/proc/robopen_wants_colour(datum/act/op/A)
	return A.step_value("what") == "Colour"

/// Old attack_self: the colour or the mode the questions were answered with.
/obj/item/pen/robopen/proc/interaction_robopen(datum/act/op/A)
	var/mob/user = A.actor
	var/choice = A.step_value("what")
	if(isnull(choice) || choice == "Cancel")
		return

	play_sfx(src, SFX_EFFECTS_POP)

	switch(choice)
		if("Colour")
			var/chosen_colour = A.step_value("colour")
			if(!isnull(chosen_colour))
				colour = text_or_null(chosen_colour)

		if("Mode")
			if (mode == 1)
				mode = 2
			else
				mode = 1
			to_chat(user, span_filter_notice("Changed printing mode to '[mode == 2 ? "Rename Paper" : "Write Paper"]'"))

// Copied over from paper's rename verb
// see code\modules\paperwork\paper.dm line 62

/obj/item/pen/robopen/proc/RenamePaper(mob/user, obj/item/paper/paper)
	if ( !user || !paper )
		return
	open_request(src, /datum/prompt/text, PROC_REF(paper_label_entered), answerer = user, subject = paper, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, title = "Paper Labelling", question = "What would you like to label the paper?", max_len = 32, encode = FALSE, name_text = TRUE, timeout = 0)

/obj/item/pen/robopen/proc/paper_label_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/paper/paper = A.request.subject
	if(QDELETED(paper))
		return
	var/n_name = sanitizeSafe(A.answer.value, 32)
	paper.name = "paper[(n_name ? text("- '[n_name]'") : null)]"
	paper.last_modified_ckey = user.ckey
	add_fingerprint(user)
