ADMIN_VERB(get_server_logs, (R_ADMIN | R_SERVER), "Get Server Logs", "View or retrieve logfiles.", ADMIN_CATEGORY_LOGS)
	user.browseserverlogs()

ADMIN_VERB(get_current_logs, (R_ADMIN | R_SERVER), "Get Current Logs", "View or retrieve logfiles for the current round.", ADMIN_CATEGORY_LOGS)
	user.browseserverlogs(current=TRUE)

/client/proc/browseserverlogs(current=FALSE)
	browse_files(current ? BROWSE_ROOT_CURRENT_LOGS : BROWSE_ROOT_ALL_LOGS, PROC_REF(serverlog_chosen))

/client/proc/serverlog_chosen(path)
	if(file_spam_check())
		return

	message_admins("[key_name_admin(src)] accessed file: [path]")
	feedback_add_details("admin_verb","VTL") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

	om_ask(src, /datum/om/prompt/choice/serverlog_action, PROC_REF(serverlog_action_chosen), title = path, path = path)

/// What to do with a picked log file. Re-checked on the answer: still an admin with server rights.
/datum/om/prompt/choice/serverlog_action
	message = "View (in game), Open (in your system's text editor), or Download?"
	buttons = TRUE
	choices = list("View", "Open", "Download")
	requires = PROMPT_ADMIN(R_ADMIN|R_SERVER)
	var/path

/client/proc/serverlog_action_chosen(datum/om/prompt/choice/serverlog_action/ask)
	var/path = ask.path
	switch(ask.choice)
		if ("View")
			// structured TGUI AdminReport.
			dq_admin_report_html(src.mob, path, "<pre style='word-wrap: break-word; white-space: pre-wrap;'>[html_encode(file2text(file(path)))]</pre>")
		if ("Open")
			src << run(file(path))
		if ("Download")
			src << ftp(file(path))
		else
			return
	to_chat(src, "Attempting to send [path], this may take a fair few minutes if the file is very large.", confidential = TRUE)
