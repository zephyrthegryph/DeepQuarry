/client
	var/datum/managed_browser/feedback_form/feedback_form = null

/client/can_vv_get(var_name)//no snooping but doesn't break shit
	if(var_name == NAMEOF(src, feedback_form))
		return FALSE
	return ..()

GENERAL_PROTECT_DATUM(/datum/managed_browser/feedback_form)

// A fairly simple object to hold information about a player's feedback as it's being written.
// Having this be it's own object instead of being baked into /mob/new_player allows for it to be used
// from other places than just the lobby, and makes it a lot harder for people with dev powers to be naughty with it using VV/proccall.
/datum/managed_browser/feedback_form
	base_browser_id = "feedback_form"
	title = "Server Feedback"
	size_x = 480
	size_y = 520
	display_when_created = FALSE
	var/feedback_topic = null
	var/feedback_body = null
	var/feedback_hide_author = FALSE

/datum/managed_browser/feedback_form/New(client/new_client)
	feedback_topic = CONFIG_GET(str_list/sqlite_feedback_topics)[1]
	..(new_client)
	display()

// LIFECYCLE: clears the client's back-reference (clients aren't datums).
/datum/managed_browser/feedback_form/Destroy()
	if(my_client)
		my_client.feedback_form = null
	return ..()

// Privacy option is allowed if both the config allows it, and the pepper file exists and isn't blank.
/datum/managed_browser/feedback_form/proc/can_be_private()
	return CONFIG_GET(flag/sqlite_feedback_privacy) && SSsqlite.get_feedback_pepper()

// TGUI migration. Replaces the legacy /datum/browser
// renderer with a structured TGUI feedback form. The Topic() href
// dispatch and get_html() are gone; everything flows through tgui_act.
/datum/managed_browser/feedback_form/display()
	if(!my_client)
		return
	if(!SSsqlite.can_submit_feedback(my_client))
		return
	tgui_interact(my_client.mob)

/datum/managed_browser/feedback_form/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/managed_browser/feedback_form/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "FeedbackForm", title)
		ui.open()

/datum/managed_browser/feedback_form/tgui_data(mob/user)
	var/list/data = list()
	data["topic"] = feedback_topic
	data["body"] = feedback_body || ""
	data["hide_author"] = feedback_hide_author
	data["author_ckey"] = my_client?.ckey
	data["author_hashed"] = my_client ? md5(ckey(lowertext(my_client.ckey + (SSsqlite.get_feedback_pepper() || "")))) : ""
	data["can_be_private"] = can_be_private() ? TRUE : FALSE
	data["topics"] = CONFIG_GET(str_list/sqlite_feedback_topics)
	data["max_length"] = MAX_FEEDBACK_LENGTH
	data["cooldown_days"] = CONFIG_GET(number/sqlite_feedback_cooldown)
	return data

/datum/managed_browser/feedback_form/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!my_client)
		return

	switch(action)
		if("edit_body")
			var/_answer_k80 = act_prompt(my_client, action, params, ui, "k80", list("kind" = "text", "message" = "Please write your feedback here.", "title" = "Feedback Body", "default" = feedback_body, "multiline" = TRUE))
			if(isnull(_answer_k80))
				return
			feedback_body = _answer_k80
			return TRUE

		if("set_hide_author")
			if(!can_be_private())
				feedback_hide_author = FALSE
			else
				feedback_hide_author = !!params["hide"]
			return TRUE

		if("choose_topic")
			var/picked = act_prompt(my_client, action, params, ui, "k91", list("kind" = "list", "message" = "Choose the topic you want to submit your feedback under.", "title" = "Feedback Topic", "choices" = CONFIG_GET(str_list/sqlite_feedback_topics)))
			if(isnull(picked))
				return
			if(picked)
				feedback_topic = picked
			return TRUE

		if("submit")
			if(length(feedback_body) > MAX_FEEDBACK_LENGTH)
				to_chat(my_client, span_warning("Your feedback is too long, at [length(feedback_body)] characters, where as the \
				limit is [MAX_FEEDBACK_LENGTH]. Please shorten it and try again."))
				return TRUE

			var/text = sanitize(feedback_body, max_length = 0, encode = TRUE, trim = FALSE, extra = FALSE)
			if(!text)
				to_chat(my_client, span_warning("It appears you didn't write anything, or it was invalid."))
				return TRUE

			var/_answer_k107 = act_prompt(my_client, action, params, ui, "k107", list("message" = "Are you sure you want to submit your feedback?", "title" = "Confirm Submission", "choices" = list("No", "Yes")))
			if(isnull(_answer_k107))
				return
			if(_answer_k107 != "Yes")
				return TRUE

			var/author_text = my_client.ckey
			if(can_be_private() && feedback_hide_author)
				author_text = md5(my_client.ckey + SSsqlite.get_feedback_pepper())

			var/success = SSsqlite.insert_feedback(author = author_text, topic = feedback_topic, content = feedback_body, sqlite_object = SSsqlite.sqlite_db)
			if(!success)
				to_chat(my_client, span_warning("Something went wrong while inserting your feedback into the database. Please try again. \
				If this happens again, you should contact a developer."))
				return TRUE

			SStgui.close_uis(src)
			qdel(src)
			return TRUE
