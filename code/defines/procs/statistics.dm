/// Records the population in the stats database: a write on the I/O lane (io_job), so
/// nothing waits on the database.
/proc/sql_poll_population()
	if(!CONFIG_GET(flag/enable_stat_tracking))
		return
	var/admincount = GLOB.admins.len
	var/playercount = 0
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(M.client)
			playercount += 1
	if(!SSdbcore.IsConnected())
		log_game("SQL ERROR during population polling. Failed to connect.")
		return
	var/sqltime = time2text(world.realtime, "YYYY-MM-DD hh:mm:ss")
	io_job(null, /datum/io_backend/sql,
		"INSERT INTO population (`playercount`, `admincount`, `time`) VALUES (:playercount, :admincount, :sqltime)",
		list("playercount" = playercount, "admincount" = admincount, "sqltime" = sqltime),
		/proc/sql_poll_population_done)

/proc/sql_poll_population_done(list/result, error)
	if(error)
		log_game("SQL ERROR during population polling. Error : \[[error]\]")

/proc/sql_report_round_start()
	// TODO
	if(!CONFIG_GET(flag/enable_stat_tracking))
		return
/proc/sql_report_round_end()
	// TODO
	if(!CONFIG_GET(flag/enable_stat_tracking))
		return

/// Polls the population into the stats database every ten minutes: a timer on the global owner.
/proc/statistic_cycle()
	if(!CONFIG_GET(flag/enable_stat_tracking))
		return
	sql_poll_population()
	after(null, 10 MINUTES, /proc/statistic_cycle)

//This proc is used for feedback. It is executed at round end.
/proc/sql_commit_feedback()
	if(!GLOB.blackbox)
		log_game("Round ended without a blackbox recorder. No feedback was sent to the database.")
		return

	//content is a list of lists. Each item in the list is a list with two fields, a variable name and a value. Items MUST only have these two values.
	var/list/datum/feedback_variable/content = GLOB.blackbox.get_round_feedback()

	if(!content)
		log_game("Round ended without any feedback being generated. No feedback was sent to the database.")
		return

	if(!SSdbcore.IsConnected())
		log_game("SQL ERROR during feedback reporting. Failed to connect.")
		return
	// The feedback is captured now (text and numbers); the rows are written once the next
	// round id is known. Both steps run on the I/O lane.
	var/list/rows = list()
	for(var/datum/feedback_variable/item in content)
		rows += list(list(item.get_variable(), item.get_value()))
	io_job(null, /datum/io_backend/sql, "SELECT MAX(roundid) AS max_round_id FROM erro_feedback", null, /proc/sql_commit_feedback_rows, rows)

/// io_job() callback: the next feedback round id is known; writes the captured rows.
/proc/sql_commit_feedback_rows(list/result, error, list/rows)
	if(error)
		log_game("SQL ERROR during feedback reporting. Error : \[[error]\]")
		return
	var/newroundid
	for(var/list/row in result["rows"])
		newroundid = row[1]
	if(!(isnum(newroundid)))
		newroundid = text2num(newroundid)
	if(isnum(newroundid))
		newroundid++
	else
		newroundid = 1
	for(var/list/row in rows)
		io_job(null, /datum/io_backend/sql,
			"INSERT INTO erro_feedback (id, roundid, time, variable, value) VALUES (null, :newroundid, Now(), :variable, :value)",
			list("newroundid" = newroundid, "variable" = row[1], "value" = row[2]),
			/proc/sql_commit_feedback_done)

/proc/sql_commit_feedback_done(list/result, error)
	if(error)
		log_game("SQL ERROR during feedback reporting. Error : \[[error]\]")
