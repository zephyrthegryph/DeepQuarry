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
		// ALLOW(lifecycle): a feedback viewer opened without staff rights is refused at once
		qdel(src)
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
	query.Execute(SSsqlite.sqlite_db)
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
		query.Execute(SSsqlite.sqlite_db)
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

TOPIC_ACTION(/datum/managed_browser/feedback_viewer, "close", PROC_REF(topic_close))
TOPIC_ACTION(/datum/managed_browser/feedback_viewer, "show_full_feedback", PROC_REF(topic_show_full_feedback), TOPIC_TEXT("feedback_author"), TOPIC_TEXT("feedback_content"))
TOPIC_ACTION(/datum/managed_browser/feedback_viewer, "filter_id", PROC_REF(topic_filter_id))
TOPIC_ACTION(/datum/managed_browser/feedback_viewer, "filter_author", PROC_REF(topic_filter_author))
TOPIC_ACTION(/datum/managed_browser/feedback_viewer, "filter_topic", PROC_REF(topic_filter_topic))
TOPIC_ACTION(/datum/managed_browser/feedback_viewer, "filter_content", PROC_REF(topic_filter_content))
TOPIC_ACTION(/datum/managed_browser/feedback_viewer, "filter_datetime", PROC_REF(topic_filter_datetime))

// Only the viewer's own client drives it.
/datum/managed_browser/feedback_viewer/topic_allowed(mob/user, list/href_list)
	var/client/C = my_client()
	return C && user?.client == C

/datum/managed_browser/feedback_viewer/proc/topic_close(mob/user, list/args)
	return TRUE // To avoid refreshing.

/datum/managed_browser/feedback_viewer/proc/topic_show_full_feedback(mob/user, list/args)
	display_big_feedback(args["feedback_author"], args["feedback_content"])
	return TRUE

/datum/managed_browser/feedback_viewer/proc/topic_filter_id(mob/user, list/args)
	var/question = "Write feedback ID here."
	var/datum/request/replayed = feedback_filter_request(user, args, "k130")
	if(!replayed)
		var/list/original_href = args[TOPIC_HREF]
		open_request(src, /datum/prompt/number/feedback_filter, PROC_REF(feedback_filter_answered), answerer = my_client()?.mob, question = question, title = "Filter by ID", captured = list("href" = feedback_scalar_href(original_href), "feedback_key" = "k130"))
		return
	var/id_to_search = replayed.value
	if(isnull(id_to_search))
		return
	if(id_to_search)
		last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_ID, id_to_search, TRUE)
	display()
	return TRUE

/datum/managed_browser/feedback_viewer/proc/topic_filter_author(mob/user, list/args)
	var/question = "Write desired key or hash here. Partial keys/hashes are allowed."
	var/datum/request/replayed = feedback_filter_request(user, args, "k135")
	if(!replayed)
		var/list/original_href = args[TOPIC_HREF]
		open_request(src, /datum/prompt/text/feedback_filter, PROC_REF(feedback_filter_answered), answerer = my_client()?.mob, question = question, title = "Filter by Author", captured = list("href" = feedback_scalar_href(original_href), "feedback_key" = "k135"))
		return
	var/author_to_search = replayed.value
	if(isnull(author_to_search))
		return
	if(author_to_search)
		last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_AUTHOR, author_to_search)
	display()
	return TRUE

/datum/managed_browser/feedback_viewer/proc/topic_filter_topic(mob/user, list/args)
	var/question = "Write desired topic here. Partial topics are allowed. \nThe current topics in the config are [english_list(CONFIG_GET(str_list/sqlite_feedback_topics))]."
	var/datum/request/replayed = feedback_filter_request(user, args, "k140")
	if(!replayed)
		var/list/original_href = args[TOPIC_HREF]
		open_request(src, /datum/prompt/text/feedback_filter, PROC_REF(feedback_filter_answered), answerer = my_client()?.mob, question = question, title = "Filter by Topic", captured = list("href" = feedback_scalar_href(original_href), "feedback_key" = "k140"))
		return
	var/topic_to_search = replayed.value
	if(isnull(topic_to_search))
		return
	if(topic_to_search)
		last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_TOPIC, topic_to_search)
	display()
	return TRUE

/datum/managed_browser/feedback_viewer/proc/topic_filter_content(mob/user, list/args)
	var/question = "Write desired content to find here. Partial matches are allowed."
	var/datum/request/replayed = feedback_filter_request(user, args, "k145")
	if(!replayed)
		var/list/original_href = args[TOPIC_HREF]
		open_request(src, /datum/prompt/text/feedback_filter, PROC_REF(feedback_filter_answered), answerer = my_client()?.mob, question = question, title = "Filter by Content", multiline = TRUE, max_len = MAX_TGUI_INPUT, captured = list("href" = feedback_scalar_href(original_href), "feedback_key" = "k145"))
		return
	var/content_to_search = replayed.value
	if(isnull(content_to_search))
		return
	if(content_to_search)
		last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_CONTENT, content_to_search)
	display()
	return TRUE

/datum/managed_browser/feedback_viewer/proc/topic_filter_datetime(mob/user, list/args)
	var/question = "Write desired datetime. Partial matches are allowed.\nFormat is 'YYYY-MM-DD HH:MM:SS'."
	var/datum/request/replayed = feedback_filter_request(user, args, "k150")
	if(!replayed)
		var/list/original_href = args[TOPIC_HREF]
		open_request(src, /datum/prompt/text/feedback_filter, PROC_REF(feedback_filter_answered), answerer = my_client()?.mob, question = question, title = "Filter by Datetime", captured = list("href" = feedback_scalar_href(original_href), "feedback_key" = "k150"))
		return
	var/datetime_to_search = replayed.value
	if(isnull(datetime_to_search))
		return
	if(datetime_to_search)
		last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_DATETIME, datetime_to_search)
	display()
	return TRUE




/// A new question keeps the original URL scalars, never a preceding ended request.
/datum/managed_browser/feedback_viewer/proc/feedback_scalar_href(list/original_href)
	var/list/scalars = original_href.Copy()
	scalars -= "feedback_request"
	return scalars

/// Only an actual ended native filter request supplies server-side answers.
/datum/managed_browser/feedback_viewer/proc/feedback_filter_request(mob/user, list/args, key)
	var/list/original_href = args[TOPIC_HREF]
	var/datum/request/resumed
	if(original_href)
		resumed = original_href["feedback_request"]
	if((istype(resumed, /datum/prompt/text/feedback_filter) || istype(resumed, /datum/prompt/number/feedback_filter)) && resumed.owner == src && resumed.answerer == user && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(feedback_filter_answered) && resumed.captured?["feedback_key"] == key)
		return resumed
	return null

/datum/managed_browser/feedback_viewer/proc/feedback_filter_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/list/captured_href = A.answer.captured["href"]
	var/list/replayed_href = captured_href.Copy()
	replayed_href["feedback_request"] = A.answer
	world.push_usr(A.request.answerer, new /datum/callback(GLOBAL_PROC, GLOBAL_PROC_REF(topic_dispatch)), src, A.request.answerer, replayed_href)

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
