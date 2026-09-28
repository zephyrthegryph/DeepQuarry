/client
	var/datum/managed_browser/feedback_viewer/feedback_viewer = null

ADMIN_VERB(view_feedback, R_ADMIN|R_DEBUG|R_EVENT, "View Feedback", "Open the Feedback Viewer.", ADMIN_CATEGORY_MISC)
	if(!check_rights())
		return

	if(user.feedback_viewer)
		user.feedback_viewer.display()
		return

	user.feedback_viewer = new(user)

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
		qdel(src)
		return

	..()

// LIFECYCLE: clears the client's back-reference (clients aren't datums).
/datum/managed_browser/feedback_viewer/Destroy()
	if(my_client)
		my_client.feedback_viewer = null
	return ..()

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
	dq_admin_report_html(my_client.mob, "[author]'s Feedback", dat, src)

/datum/managed_browser/feedback_viewer/Topic(href, href_list[])
	if(!my_client)
		return FALSE

	if(href_list["close"]) // To avoid refreshing.
		return

	if(href_list["show_full_feedback"])
		display_big_feedback(href_list["feedback_author"], href_list["feedback_content"])
		return

	if(href_list["filter_id"])
		var/id_to_search = topic_ask(my_client, href_list, "k130", /datum/om/prompt/number, message = "Write feedback ID here.", title = "Filter by ID")
		if(isnull(id_to_search))
			return
		if(id_to_search)
			last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_ID, id_to_search, TRUE)

	if(href_list["filter_author"])
		var/author_to_search = topic_ask(my_client, href_list, "k135", /datum/om/prompt/text, message = "Write desired key or hash here. Partial keys/hashes are allowed.", title = "Filter by Author")
		if(isnull(author_to_search))
			return
		if(author_to_search)
			last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_AUTHOR, author_to_search)

	if(href_list["filter_topic"])
		var/topic_to_search = topic_ask(my_client, href_list, "k140", /datum/om/prompt/text, message = "Write desired topic here. Partial topics are allowed. \nThe current topics in the config are [english_list(CONFIG_GET(str_list/sqlite_feedback_topics))].", title = "Filter by Topic")
		if(isnull(topic_to_search))
			return
		if(topic_to_search)
			last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_TOPIC, topic_to_search)

	if(href_list["filter_content"])
		var/content_to_search = topic_ask(my_client, href_list, "k145", /datum/om/prompt/text, message = "Write desired content to find here. Partial matches are allowed.", title = "Filter by Content", multiline = TRUE, max_length = MAX_TGUI_INPUT)
		if(isnull(content_to_search))
			return
		if(content_to_search)
			last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_CONTENT, content_to_search)

	if(href_list["filter_datetime"])
		var/datetime_to_search = topic_ask(my_client, href_list, "k150", /datum/om/prompt/text, message = "Write desired datetime. Partial matches are allowed.\nFormat is 'YYYY-MM-DD HH:MM:SS'.", title = "Filter by Datetime")
		if(isnull(datetime_to_search))
			return
		if(datetime_to_search)
			last_query = feedback_filter(SQLITE_FEEDBACK_COLUMN_DATETIME, datetime_to_search)

	// Refresh.
	display()
