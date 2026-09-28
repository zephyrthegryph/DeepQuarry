/// The SQL leaf: its query waits on the database, so callers don't wait for it.
/proc/sql_poll_population()
	set waitfor = FALSE // ALLOW(scheduler): SQL leaf (population insert)
	if(!CONFIG_GET(flag/enable_stat_tracking))
		return
	var/admincount = GLOB.admins.len
	var/playercount = 0
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(M.client)
			playercount += 1
	if(!SSdbcore.IsConnected())
		log_game("SQL ERROR during population polling. Failed to connect.")
	else
		var/sqltime = time2text(world.realtime, "YYYY-MM-DD hh:mm:ss")
		var/datum/db_query/query = SSdbcore.NewQuery(
			"INSERT INTO population (`playercount`, `admincount`, `time`) VALUES (:playercount, :admincount, :sqltime)",
			list("playercount" = playercount, "admincount" = admincount, "sqltime" = sqltime)
		)
		if(!query.Execute())
			var/err = query.ErrorMsg()
			log_game("SQL ERROR during population polling. Error : \[[err]\]\n")
		qdel(query)

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
	om_after(null, 10 MINUTES, /proc/statistic_cycle)

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
	else

		var/datum/db_query/max_query = SSdbcore.NewQuery("SELECT MAX(roundid) AS max_round_id FROM erro_feedback")
		max_query.Execute()

		var/newroundid

		while(max_query.NextRow())
			newroundid = max_query.item[1]
		qdel(max_query)
		if(!(isnum(newroundid)))
			newroundid = text2num(newroundid)

		if(isnum(newroundid))
			newroundid++
		else
			newroundid = 1

		for(var/datum/feedback_variable/item in content)
			var/variable = item.get_variable()
			var/value = item.get_value()

			var/datum/db_query/query = SSdbcore.NewQuery(
				"INSERT INTO erro_feedback (id, roundid, time, variable, value) VALUES (null, :newroundid, Now(), :variable, :value)",
				list("newroundid" = newroundid, "variable" = variable, "value" = value)
			)
			if(!query.Execute())
				var/err = query.ErrorMsg()
				log_game("SQL ERROR during feedback reporting. Error : \[[err]\]\n")
			qdel(query)
