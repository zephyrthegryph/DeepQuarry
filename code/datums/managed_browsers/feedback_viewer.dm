/client
	var/datum/managed_browser/feedback_viewer/feedback_viewer = null

ADMIN_VERB(view_feedback, R_ADMIN|R_DEBUG|R_EVENT, "View Feedback", "Open the Feedback Viewer.", ADMIN_CATEGORY_MISC)
	if(!check_rights())
		return

	if(user.feedback_viewer)
		user.feedback_viewer.display()
		return

	var/datum/managed_browser/feedback_viewer/viewer = new(user)
	if(!QDELETED(viewer))
		rel_set(user, nameof(/client::feedback_viewer), viewer) // the client owns its viewer; viewer.my_client is the back view

// This object holds the code to run the admin feedback viewer.
/datum/managed_browser/feedback_viewer
	base_browser_id = "feedback_viewer"
	title = "Submitted Feedback"
	size_x = 900
	size_y = 500
	var/database/query/last_query = null

/datum/managed_browser/feedback_viewer/New(client/new_client)
	if(!check_rights_for(new_client, R_ADMIN|R_DEBUG|R_EVENT)) // Just in case someone figures out a way to spawn this as non-staff.
		message_admins("[new_client] tried to view feedback with insufficent permissions.")
		spent(src)
		return

	..()

/datum/managed_browser/feedback_viewer/proc/feedback_filter(row_name, thing_to_find, exact = FALSE)
	var/database/query/query = null
	if(exact) // Useful for ID searches, so searching for 'id 10' doesn't also get 'id 101'.
		query = new({"
			SELECT *
			FROM [SQLITE_TABLE_FEEDBACK]
			WHERE [row_name] == ?
			ORDER BY [SQLITE_FEEDBACK_COLUMN_ID]
			DESC LIMIT 50;
		"},
		thing_to_find
		)

	else
		// Wrap the thing in %s so LIKE will work.
		thing_to_find = "%[thing_to_find]%"
		query = new({"
			SELECT *
			FROM [SQLITE_TABLE_FEEDBACK]
			WHERE [row_name] LIKE ?
			ORDER BY [SQLITE_FEEDBACK_COLUMN_ID]
			DESC LIMIT 50;
		"},
		thing_to_find
		)
	query.Execute(sqlite_sqlite_db())
	SSsqlite.sqlite_check_for_errors(query, "Admin Feedback Viewer - Filter by [row_name] to find [thing_to_find]")
	return query

// Builds the window for players to review their feedback.
/datum/managed_browser/feedback_viewer/get_html()
	var/list/dat = list("<html><body>")
	if(!last_query) // If no query was done before, just show the most recent feedbacks.
		var/database/query/query = new({"
			SELECT *
			FROM [SQLITE_TABLE_FEEDBACK]
			ORDER BY [SQLITE_FEEDBACK_COLUMN_ID]
			DESC LIMIT 50;
			"}
			)
		query.Execute(sqlite_sqlite_db())
		SSsqlite.sqlite_check_for_errors(query, "Admin Feedback Viewer")
		last_query = query

	dat += "<table border='1' style='width:100%'>"
	dat += "<tr>"
	dat += "<th>[href(src, list("filter_id" = 1), "ID")]</th>"
	dat += "<th>[href(src, list("filter_topic" = 1), "Topic")]</th>"
	dat += "<th>[href(src, list("filter_author" = 1), "Author")]</th>"
	dat += "<th>[href(src, list("filter_content" = 1), "Content")]</th>"
	dat += "<th>[href(src, list("filter_datetime" = 1), "Datetime")]</th>"
	dat += "</tr>"

	while(last_query.NextRow())
		var/list/row_data = last_query.GetRowData()
		dat += "<tr>"
		dat += "<td>[row_data[SQLITE_FEEDBACK_COLUMN_ID]]</td>"
		dat += "<td>[row_data[SQLITE_FEEDBACK_COLUMN_TOPIC]]</td>"
		dat += "<td>[row_data[SQLITE_FEEDBACK_COLUMN_AUTHOR]]</td>" // TODO: Color this to make hashed keys more distinguishable.
		var/text = row_data[SQLITE_FEEDBACK_COLUMN_CONTENT]
		if(length(text) > 512)
			text = href(src, list(
				"show_full_feedback" = 1,
				"feedback_author" = row_data[SQLITE_FEEDBACK_COLUMN_AUTHOR],
				"feedback_content" = row_data[SQLITE_FEEDBACK_COLUMN_CONTENT]
				), "[copytext(text, 1, 64)]... ([length(text)])")
		else
			text = replacetext(text, "\n", "<br>")
		dat += "<td>[text]</td>"
		dat += "<td>[row_data[SQLITE_FEEDBACK_COLUMN_DATETIME]]</td>"
		dat += "</tr>"
	dat += "</table>"

	dat += "</body></html>"
	return dat.Join()

// Used to show the full version of feedback in a seperate window.
/datum/managed_browser/feedback_viewer/proc/display_big_feedback(author, text)
	var/dat = replacetext(text, "\n", "<br>")
	// structured TGUI AdminReport.
	dq_admin_report_html(my_client().mob, "[author]'s Feedback", dat, src)

CAPABILITIES(/datum/managed_browser/feedback_viewer)
	extend(TAG_TOPIC, needs(req_topic_ok()))
	op("close", topic("close"), then(PROC_REF(topic_close)))
	op("show_full_feedback", topic("show_full_feedback", arg("feedback_author", schema_text(), optional = TRUE), arg("feedback_content", schema_text(), optional = TRUE)), then(PROC_REF(topic_show_full_feedback)))
	op("filter_id", topic("filter_id"), asks(/datum/prompt/number/feedback_filter, fields = list("question" = "Write feedback ID here.", "title" = "Filter by ID"), step = "value"), then(PROC_REF(topic_filter_id)))
	op("filter_author", topic("filter_author"), asks(/datum/prompt/text/feedback_filter, fields = list("question" = "Write desired key or hash here. Partial keys/hashes are allowed.", "title" = "Filter by Author"), step = "value"), then(PROC_REF(topic_filter_author)))
	op("filter_topic", topic("filter_topic"), asks(/datum/prompt/text/feedback_filter, fields = list("question" = computed(PROC_REF(filter_topic_question)), "title" = "Filter by Topic"), step = "value"), then(PROC_REF(topic_filter_topic)))
	op("filter_content", topic("filter_content"), asks(/datum/prompt/text/feedback_filter, fields = list("question" = "Write desired content to find here. Partial matches are allowed.", "title" = "Filter by Content", "multiline" = TRUE, "max_len" = MAX_TGUI_INPUT), step = "value"), then(PROC_REF(topic_filter_content)))
	op("filter_datetime", topic("filter_datetime"), asks(/datum/prompt/text/feedback_filter, fields = list("question" = "Write desired datetime. Partial matches are allowed.\nFormat is 'YYYY-MM-DD HH:MM:SS'.", "title" = "Filter by Datetime"), step = "value"), then(PROC_REF(topic_filter_datetime)))

// Only the viewer's own client drives it.
/datum/managed_browser/feedback_viewer/op_topic_actor_ok(mob/actor)
	var/client/C = my_client()
	return C && actor.client == C

/datum/managed_browser/feedback_viewer/proc/topic_close(datum/act/op/A)
	return TRUE // To avoid refreshing.

/datum/managed_browser/feedback_viewer/proc/topic_show_full_feedback(datum/act/op/A, href_feedback_author, href_feedback_content)
	display_big_feedback(href_feedback_author, href_feedback_content)
	return TRUE

/datum/managed_browser/feedback_viewer/proc/topic_filter_id(datum/act/op/A)
	var/id_to_search = A.step_value("value")
	if(isnull(id_to_search))
		return
	if(id_to_search)
		last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_ID, id_to_search, TRUE)
	display()
	return TRUE

/datum/managed_browser/feedback_viewer/proc/topic_filter_author(datum/act/op/A)
	var/author_to_search = A.step_value("value")
	if(isnull(author_to_search))
		return
	if(author_to_search)
		last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_AUTHOR, author_to_search)
	display()
	return TRUE

/// The question of the topic filter lists the topics the config knows.
/datum/managed_browser/feedback_viewer/proc/filter_topic_question(datum/act/op/A)
	return "Write desired topic here. Partial topics are allowed. \nThe current topics in the config are [english_list(CONFIG_GET(str_list/sqlite_feedback_topics))]."

/datum/managed_browser/feedback_viewer/proc/topic_filter_topic(datum/act/op/A)
	var/topic_to_search = A.step_value("value")
	if(isnull(topic_to_search))
		return
	if(topic_to_search)
		last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_TOPIC, topic_to_search)
	display()
	return TRUE

/datum/managed_browser/feedback_viewer/proc/topic_filter_content(datum/act/op/A)
	var/content_to_search = A.step_value("value")
	if(isnull(content_to_search))
		return
	if(content_to_search)
		last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_CONTENT, content_to_search)
	display()
	return TRUE

/datum/managed_browser/feedback_viewer/proc/topic_filter_datetime(datum/act/op/A)
	var/datetime_to_search = A.step_value("value")
	if(isnull(datetime_to_search))
		return
	if(datetime_to_search)
		last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_DATETIME, datetime_to_search)
	display()
	return TRUE




/datum/prompt/text/feedback_filter
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/feedback_filter/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return null

/datum/prompt/text/feedback_filter/normalize(given)
	return istext(given) ? given : null

/datum/prompt/number/feedback_filter
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/number/feedback_filter/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return null

/datum/prompt/number/feedback_filter/normalize(given)
	return isnum(given) ? given : null

/datum/prompt/number/feedback_filter/refusal(given)
	return null
