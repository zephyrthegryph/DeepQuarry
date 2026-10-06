/client
	var/datum/managed_browser/feedback_form/feedback_form = null

CAPABILITIES(/client)
	owns_one(nameof(verb_store), /datum/client_verbs)
	owns_one(nameof(feedback_form), /datum/managed_browser/feedback_form)
	owns_one(nameof(feedback_viewer), /datum/managed_browser/feedback_viewer)
	owns_one(nameof(interaction_menu), /datum/interaction_menu)

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

// Privacy option is allowed if both the config allows it, and the pepper file exists and isn't blank.
/datum/managed_browser/feedback_form/proc/can_be_private()
	return CONFIG_GET(flag/sqlite_feedback_privacy) && SSsqlite.get_feedback_pepper()

// TGUI migration. Replaces the legacy /datum/browser
// renderer with a structured TGUI feedback form. The Topic() href
// dispatch and get_html() are gone; everything flows through tgui_act.
/datum/managed_browser/feedback_form/display()
	if(!my_client())
		return
	if(!SSsqlite.can_submit_feedback(my_client()))
		return
	tgui_interact(my_client().mob)

CAPABILITIES(/datum/managed_browser/feedback_form)
	interface("FeedbackForm", state = nameof(GLOB.tgui_always_state))
	op("edit_body", ui_act("edit_body"), asks(/datum/prompt/text/feedback_body, fields = list("default" = computed(PROC_REF(body_default))), step = "body"), then(PROC_REF(ui_act_edit_body)))
	op("set_hide_author", ui_act("set_hide_author", arg("hide", bool())), then(PROC_REF(ui_act_set_hide_author)))
	op("choose_topic", ui_act("choose_topic"), asks(/datum/prompt/choice/feedback_topic, fields = list("choices" = computed(PROC_REF(topic_choices))), step = "topic"), then(PROC_REF(ui_act_choose_topic)))
	op("submit", ui_act("submit"), asks(/datum/prompt/choice/feedback_submit, step = "confirm", when = PROC_REF(feedback_submittable)), then(PROC_REF(ui_act_submit)))

/datum/managed_browser/feedback_form/ui_title(mob/user)
	return title

/datum/managed_browser/feedback_form/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["topic"] = feedback_topic
	data["hide_author"] = feedback_hide_author
	var/list/merged_1 = ui_data_datum_managed_browser_feedback_form(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/managed_browser/feedback_form's window data.
/datum/managed_browser/feedback_form/proc/ui_data_datum_managed_browser_feedback_form(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["body"] = feedback_body || ""
	data["author_ckey"] = my_client()?.ckey
	data["author_hashed"] = my_client() ? md5(ckey(lowertext(my_client().ckey + (SSsqlite.get_feedback_pepper() || "")))) : ""
	data["can_be_private"] = can_be_private() ? TRUE : FALSE
	data["topics"] = CONFIG_GET(str_list/sqlite_feedback_topics)
	data["max_length"] = MAX_FEEDBACK_LENGTH
	data["cooldown_days"] = CONFIG_GET(number/sqlite_feedback_cooldown)
	return data

/datum/managed_browser/feedback_form/proc/ui_gate(datum/act/op/A)
	if(!my_client())
		return FALSE
	return TRUE

/datum/managed_browser/feedback_form/proc/ui_act_edit_body(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	apply_feedback_body(A.step_value("body"))
	return TRUE

/datum/managed_browser/feedback_form/proc/ui_act_set_hide_author(datum/act/op/A, hide)
	if(!ui_gate(A))
		return FALSE
	if(!can_be_private())
		feedback_hide_author = FALSE
	else
		feedback_hide_author = !!hide
	return TRUE

/datum/managed_browser/feedback_form/proc/ui_act_choose_topic(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	apply_feedback_topic(A.step_value("topic"))
	return TRUE

/datum/managed_browser/feedback_form/proc/ui_act_submit(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(length(feedback_body) > MAX_FEEDBACK_LENGTH)
		to_chat(my_client(), span_warning("Your feedback is too long, at [length(feedback_body)] characters, where as the \
		limit is [MAX_FEEDBACK_LENGTH]. Please shorten it and try again."))
		return TRUE

	var/text = sanitize(feedback_body, max_length = 0, encode = TRUE, trim = FALSE, extra = FALSE)
	if(!text)
		to_chat(my_client(), span_warning("It appears you didn't write anything, or it was invalid."))
		return TRUE

	return apply_feedback_submission(A.step_value("confirm"))

/datum/managed_browser/feedback_form/proc/body_default(datum/act/op/A)
	return feedback_body

/datum/managed_browser/feedback_form/proc/topic_choices(datum/act/op/A)
	return CONFIG_GET(str_list/sqlite_feedback_topics)

/// The submission is confirmed only for a body that fits and says something (the handler tells the writer otherwise).
/datum/managed_browser/feedback_form/proc/feedback_submittable(datum/act/op/A)
	return length(feedback_body) && length(feedback_body) <= MAX_FEEDBACK_LENGTH // ALLOW(reads): asked once, when the button is pressed, to decide whether its question opens

/datum/managed_browser/feedback_form/proc/apply_feedback_submission(selected)
	if(selected != "Yes")
		return TRUE

	var/author_text = my_client().ckey
	if(can_be_private() && feedback_hide_author)
		author_text = md5(my_client().ckey + SSsqlite.get_feedback_pepper())

	var/success = SSsqlite.insert_feedback(author = author_text, topic = feedback_topic, content = feedback_body, sqlite_object = SSsqlite.sqlite_db)
	if(!success)
		to_chat(my_client(), span_warning("Something went wrong while inserting your feedback into the database. Please try again. \
		If this happens again, you should contact a developer."))
		return TRUE

	SStgui.close_uis(src)
	spent(src)
	return TRUE


/datum/managed_browser/feedback_form/proc/apply_feedback_body(value)
	feedback_body = value

/datum/managed_browser/feedback_form/proc/apply_feedback_topic(value)
	if(value)
		feedback_topic = value

/datum/prompt/text/feedback_body
	question = "Please write your feedback here."
	title = "Feedback Body"
	max_len = MAX_TGUI_INPUT
	multiline = TRUE
	timeout = 0

/datum/prompt/text/feedback_body/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/feedback_topic
	question = "Choose the topic you want to submit your feedback under."
	title = "Feedback Topic"
	timeout = 0

/datum/prompt/choice/feedback_submit
	question = "Are you sure you want to submit your feedback?"
	title = "Confirm Submission"
	choices = list("No", "Yes")
	buttons = TRUE
	timeout = 0

