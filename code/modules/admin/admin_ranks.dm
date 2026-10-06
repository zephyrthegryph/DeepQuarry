GLOBAL_LIST_EMPTY(admin_ranks) //list of all admin_rank datums
GLOBAL_PROTECT(admin_ranks)

GLOBAL_LIST_EMPTY(protected_ranks) //admin ranks loaded from txt
GLOBAL_PROTECT(protected_ranks)

/datum/admin_rank
	/// Rank name, key'd to the db
	var/name = "NoRank"
	/// Rank source, see RANK_SOURCE_TXT and friends
	var/source = null
	/// Our functional rights, these are what we actually use in game
	var/rights = R_DEFAULT
	/// Rights we're allowed to use, pre filtering
	var/include_rights = NONE
	/// These are the rights of include_rights we aren't allowed to use. Frankly I have no idea why this exists
	var/exclude_rights = NONE
	/// Rights we're allowed to edit on other folks, impact of this is dependent on R_PERMISSIONS and R_DBRANKS
	var/can_edit_rights = NONE

/datum/admin_rank/New(init_name, init_source, init_rights, init_exclude_rights, init_edit_rights)
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		if (name == "NoRank") //only del if this is a true creation (and not just a New() proc call), other wise trialmins/coders could abuse this to deadmin other admins
			om_qdel_after(src, 0)
			CRASH("Admin proc call creation of admin datum")
		return
	name = init_name
	source = init_source
	if(!source)
		spent(src)
		CRASH("Admin rank created without a source.")
	if(!name)
		spent(src)
		CRASH("Admin rank created without name.")
	if(init_rights)
		rights = init_rights
	include_rights = rights
	if(init_exclude_rights)
		exclude_rights = init_exclude_rights
		rights &= ~exclude_rights
	if(init_edit_rights)
		can_edit_rights = init_edit_rights

// Refuses deletion from advanced proc calls (permission elevation).
/datum/admin_rank/lifecycle_keep(force)
	if(!IsAdminAdvancedProcCall())
		return FALSE
	alert_to_permissions_elevation_attempt(usr)
	return TRUE

/datum/admin_rank/vv_edit_var(var_name, var_value)
	return FALSE

// Adds/removes rights to this admin_rank
/datum/admin_rank/proc/process_keyword(group, group_count, datum/admin_rank/previous_rank)
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		return
	var/list/keywords = splittext(group, " ")
	var/flag = 0
	for(var/k in keywords)
		switch(k)
			if("BUILD")
				flag = R_BUILDMODE
			if("ADMIN")
				flag = R_ADMIN
			if("BAN")
				flag = R_BAN
			if("FUN")
				flag = R_FUN
			if("SERVER")
				flag = R_SERVER
			if("DEBUG")
				flag = R_DEBUG
			if("PERMISSIONS")
				flag = R_PERMISSIONS
			if("POSSESS")
				flag = R_POSSESS
			if("STEALTH")
				flag = R_STEALTH
			if("REJUVINATE")
				flag = R_REJUVINATE
			if("VAREDIT")
				flag = R_VAREDIT
			if("EVERYTHING")
				flag = R_EVERYTHING
			if("SOUND")
				flag = R_SOUNDS
			if("SPAWN")
				flag = R_SPAWN
			if("MOD")
				flag = R_MOD
			if("EVENT")
				flag = R_EVENT
			if("MENTOR")
				flag = R_MENTOR
			if("DBRANKS")
				flag = R_DBRANKS
			if("@")
				if(previous_rank)
					switch(group_count)
						if(1)
							flag = previous_rank.include_rights
						if(2)
							flag = previous_rank.exclude_rights
						if(3)
							flag = previous_rank.can_edit_rights
				else
					continue
		switch(group_count)
			if(1)
				rights |= flag
				include_rights |= flag
			if(2)
				rights &= ~flag
				exclude_rights |= flag
			if(3)
				can_edit_rights |= flag

/datum/admin_rank/proc/pretty_print_source()
	switch(source)
		if(RANK_SOURCE_LOCAL)
			return "Localhost"
		if(RANK_SOURCE_TXT)
			return "admin_ranks.txt"
		if(RANK_SOURCE_DB)
			return "Database"
		if(RANK_SOURCE_BACKUP)
			return "Backup JSON"
		if(RANK_SOURCE_TEMPORARY)
			return "Temporary"

/// Loads admin ranks.
///	Return a list containing the backup data if they were loaded from the database backup json
/// `prefetched`: reload_admins_async()'s rows (list("ranks" = rows)); without it the query
/// blocks, which only boot does (load_admins(initial = TRUE)).
/proc/load_admin_ranks(dbfail, no_update, list/prefetched, mob/user)
	if(IsAdminAdvancedProcCall())
		to_chat(user, span_adminprefix("Admin Reload blocked: Advanced ProcCall detected."), confidential = TRUE)
		return
	GLOB.admin_ranks.Cut()
	GLOB.protected_ranks.Cut()
	//load text from file and process each entry
	var/ranks_text = file2text("[global.config.directory]/admin_ranks.txt")
	var/datum/admin_rank/previous_rank
	var/regex/admin_ranks_regex = new(@"^Name\s*=\s*(.+?)\s*\n+Include\s*=\s*([\l @]*?)\s*\n+Exclude\s*=\s*([\l @]*?)\s*\n+Edit\s*=\s*([\l @]*?)\s*\n*$", "gm")
	while(admin_ranks_regex.Find(ranks_text))
		var/datum/admin_rank/txt_rank = new(admin_ranks_regex.group[1], RANK_SOURCE_TXT)
		if(QDELETED(txt_rank))
			continue
		var/count = 1
		for(var/i in admin_ranks_regex.group - admin_ranks_regex.group[1])
			if(i)
				txt_rank.process_keyword(i, count, previous_rank)
			count++
		GLOB.admin_ranks += txt_rank
		GLOB.protected_ranks += txt_rank
		previous_rank = txt_rank
	if(!CONFIG_GET(flag/admin_legacy_system) && !dbfail)
		if(CONFIG_GET(flag/load_legacy_ranks_only))
			if(!no_update)
				sync_ranks_with_db(user)
		else
			var/list/rank_rows
			if(prefetched)
				rank_rows = prefetched["ranks"]
			else
				rank_rows = db_query_now("SELECT `rank`, flags, exclude_flags, can_edit_flags FROM [format_table_name("admin_ranks")]") // boot only: the ranks load before the kernel ticks, so nothing can wait on an io_job query yet
			if(isnull(rank_rows))
				message_admins("Error loading admin ranks from database. Loading from backup.")
				log_sql("Error loading admin ranks from database. Loading from backup.")
				dbfail = TRUE
			else
				for(var/list/row as anything in rank_rows)
					var/skip
					var/rank_name = row[1]
					for(var/datum/admin_rank/R in GLOB.admin_ranks)
						if(R.name == rank_name) //this rank was already loaded from txt override
							skip = 1
							break
					if(skip)
						continue
					var/rank_flags = text2num("[row[2]]")
					var/rank_exclude_flags = text2num("[row[3]]")
					var/rank_can_edit_flags = text2num("[row[4]]")
					var/datum/admin_rank/db_rank = new(rank_name, RANK_SOURCE_DB, rank_flags, rank_exclude_flags, rank_can_edit_flags)
					if(QDELETED(db_rank))
						continue
					GLOB.admin_ranks += db_rank
	//load ranks from backup file
	if(dbfail)
		var/backup_file = file2text("data/admins_backup.json")
		if(backup_file == null)
			log_world("Unable to locate admins backup file.")
			return FALSE
		var/list/json = json_decode(backup_file)
		for(var/J in json["ranks"])
			var/skip
			for(var/datum/admin_rank/R in GLOB.admin_ranks)
				if(R.name == "[J]") //this rank was already loaded from txt override
					skip = TRUE
			if(skip)
				continue
			var/datum/admin_rank/json_rank = new("[J]", RANK_SOURCE_BACKUP, json["ranks"]["[J]"]["include rights"], json["ranks"]["[J]"]["exclude rights"], json["ranks"]["[J]"]["can edit rights"])
			if(QDELETED(json_rank))
				continue
			GLOB.admin_ranks += json_rank
		return json
	#ifdef TESTING
	var/msg = "Permission Sets Built:\n"
	for(var/datum/admin_rank/R in GLOB.admin_ranks)
		msg += "\t[R.name]"
		var/rights = rights2text(R.rights,"\n\t\t")
		if(rights)
			msg += "\t\t[rights]\n"
	testing(msg)
	#endif

/// Converts a rank name (such as "Coder+Moth") into a list of /datum/admin_rank
/proc/ranks_from_rank_name(rank_name)
	var/list/rank_names = splittext(rank_name, "+")
	var/list/ranks = list()

	for (var/datum/admin_rank/rank as anything in GLOB.admin_ranks)
		if (rank.name in rank_names)
			rank_names -= rank.name
			ranks += rank

			if (rank_names.len == 0)
				break

	if (rank_names.len > 0)
		log_config("Admin rank names were invalid: [jointext(ranks, ", ")]")

	return ranks

/// Takes a list of rank names and joins them with +
/proc/join_admin_ranks(list/datum/admin_rank/ranks)
	var/list/names = list()

	for (var/datum/admin_rank/rank as anything in ranks)
		names += rank.name

	return jointext(names, "+")

/// (Re)Loads the admin list.
/// returns TRUE if database admins had to be loaded from the backup json
/// At runtime go through reload_admins_async(), which reads the tables on the I/O lane first
/// and passes the rows as `prefetched`; only boot (initial) reads them blocking.
/proc/load_admins(no_update, initial = FALSE, list/prefetched, mob/user)
	if(!initial)
		if(!global.config.PreConfigReload(user))
			return

	var/dbfail
	if(!CONFIG_GET(flag/admin_legacy_system) && !SSdbcore.Connect())
		message_admins("Failed to connect to database while loading admins. Loading from backup.")
		log_sql("Failed to connect to database while loading admins. Loading from backup.")
		dbfail = TRUE
	//clear the datums references
	GLOB.admin_datums.Cut()
	for(var/client/current_client in GLOB.admins)
		current_client.remove_admin_verbs()
		current_client.holder = null
	GLOB.admins.Cut()
	GLOB.protected_admins.Cut()
	GLOB.deadmins.Cut()
	var/list/backup_file_json = load_admin_ranks(dbfail, no_update, prefetched, user)
	dbfail = backup_file_json != null
	//Clear profile access
	for(var/A in world.GetConfig("admin"))
		world.SetConfig("APP/admin", A, null)
	var/list/rank_names = list()
	for(var/datum/admin_rank/R in GLOB.admin_ranks)
		rank_names[R.name] = R
	//ckeys listed in admins.txt are always made admins before sql loading is attempted
	var/admins_text = file2text("[global.config.directory]/admins.txt")
	var/regex/admins_regex = new(@"^(?!#)(.+?)\s+=\s+(.+)", "gm")

	while(admins_regex.Find(admins_text))
		var/admin_key = admins_regex.group[1]
		var/admin_rank = admins_regex.group[2]
		new /datum/admins(ranks_from_rank_name(admin_rank), ckey(admin_key), force_active = FALSE, protected = TRUE)

	if(!CONFIG_GET(flag/admin_legacy_system) && !dbfail)
		var/list/admin_rows
		if(prefetched)
			admin_rows = prefetched["admins"]
		else
			admin_rows = db_query_now("SELECT ckey, `rank`, feedback FROM [format_table_name("admin")] ORDER BY `rank`") // boot only: the admins load before the kernel ticks, so nothing can wait on an io_job query yet
		if(isnull(admin_rows))
			message_admins("Error loading admins from database. Loading from backup.")
			log_sql("Error loading admins from database. Loading from backup.")
			dbfail = 1
		else
			for(var/list/row as anything in admin_rows)
				var/admin_ckey = ckey(row[1])
				var/admin_rank = row[2]
				var/admin_feedback = row[3]
				var/skip

				var/list/admin_ranks = ranks_from_rank_name(admin_rank)

				if(admin_ranks.len == 0)
					message_admins("[admin_ckey] loaded with invalid admin rank [admin_rank].")
					skip = 1
				if(GLOB.admin_datums[admin_ckey] || GLOB.deadmins[admin_ckey])
					skip = 1
				if(!skip)
					var/datum/admins/admin_holder = new(admin_ranks, admin_ckey)
					admin_holder.fetched_feedback_link = admin_feedback || NO_FEEDBACK_LINK
		if (!no_update)
			save_admin_backup(user)
			sync_admins_with_db(user)
	//load admins from backup file
	if(dbfail)
		if(!backup_file_json)
			if(backup_file_json != null)
				//already tried
				return
			var/backup_file = file2text("data/admins_backup.json")
			if(backup_file == null)
				log_world("Unable to locate admins backup file.")
				return
			backup_file_json = json_decode(backup_file)
		for(var/backup_admin_ckey in backup_file_json["admins"])
			var/skip
			for(var/admin_ckey in GLOB.admin_datums + GLOB.deadmins)
				if(ckey(admin_ckey) == ckey("[backup_admin_ckey]")) //this admin was already loaded from txt override
					skip = TRUE
					break
			if(skip)
				continue
			new /datum/admins(ranks_from_rank_name(backup_file_json["admins"]["[backup_admin_ckey]"]), ckey("[backup_admin_ckey]"))
	#ifdef TESTING
	var/msg = "Admins Built:\n"
	for(var/ckey in GLOB.admin_datums)
		var/datum/admins/D = GLOB.admin_datums[ckey]
		msg += "\t[ckey] - [D.rank_names()]\n"
	testing(msg)
	#endif
	return dbfail

/// Reloads the admins at runtime without waiting: reads the rank and admin tables on the I/O
/// lane (io_job), then runs load_admins() with the rows. A failed read loads from the backup.
/proc/reload_admins_async(no_update, mob/user)
	if(IsAdminAdvancedProcCall())
		to_chat(user, span_adminprefix("Admin Reload blocked: Advanced ProcCall detected."), confidential = TRUE)
		return
	if(CONFIG_GET(flag/admin_legacy_system) || !SSdbcore.IsConnected())
		load_admins(no_update, FALSE, list("ranks" = null, "admins" = null), user)
		return
	var/datum/request/admin_reload/request = open_request(global.config, /datum/request/admin_reload, TYPE_PROC_REF(/datum/controller/configuration, admin_reload_finished), asker = user, no_update = no_update)
	request?.read_ranks()

/// Runtime reload context: the request registry retains it, independently of its initiating mob.
/// No answerer or ASK flags: deleting the initiator never cancels the global reload.
/datum/request/admin_reload
	timeout = 10 MINUTES // The two sequential IO reads each have a five-minute backend budget.
	var/no_update
	var/list/rank_rows

/// The exact initiating mob, never a ckey lookup that could bind a replacement.
/datum/request/admin_reload/proc/initiator() as /mob
	return QDELETED(asker) ? null : asker

/datum/request/admin_reload/proc/read_ranks()
	io_job(src, /datum/io_backend/sql, "SELECT `rank`, flags, exclude_flags, can_edit_flags FROM [format_table_name("admin_ranks")]", null, PROC_REF(ranks_arrived))

/// The first query is in; preserve the original query ordering and backup-on-error convention.
/datum/request/admin_reload/proc/ranks_arrived(list/result, error)
	rank_rows = error ? null : (result["rows"] || list())
	io_job(src, /datum/io_backend/sql, "SELECT ckey, `rank`, feedback FROM [format_table_name("admin")] ORDER BY `rank`", null, PROC_REF(admins_arrived))

/// Both tables are in: completion calls the owner's handler before disposing this context.
/datum/request/admin_reload/proc/admins_arrived(list/result, error)
	var/list/admin_rows = error ? null : (result["rows"] || list())
	request_end(src, REQ_ANSWERED, list("ranks" = rank_rows, "admins" = admin_rows))

/datum/controller/configuration/proc/admin_reload_finished(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/request/admin_reload/request = A.request
	var/mob/user = request.initiator()
	load_admins(request.no_update, FALSE, request.value, user)

/// Writes the protected ranks to the database on the I/O lane (io_job); returns at once.
/proc/sync_ranks_with_db(mob/user)
	if(IsAdminAdvancedProcCall())
		to_chat(user, span_adminprefix("Admin rank DB Sync blocked: Advanced ProcCall detected."), confidential = TRUE)
		return

	var/list/sql_ranks = list()
	for(var/datum/admin_rank/R as anything in GLOB.protected_ranks)
		sql_ranks += list(list("rank" = R.name, "flags" = R.include_rights, "exclude_flags" = R.exclude_rights, "can_edit_flags" = R.can_edit_rights))
	if(!SSdbcore.mass_insert_io(null, format_table_name("admin_ranks"), sql_ranks, TRUE, FALSE, null, /proc/sync_ranks_with_db_done))
		update_everything_flag_in_db()

/// io_job() callback: the rank rows are written; now fix up R_EVERYTHING flags.
/proc/sync_ranks_with_db_done(list/result, error)
	if(error)
		log_sql("Admin rank DB sync failed: [error]")
		return
	update_everything_flag_in_db()

/// For each rank holding R_EVERYTHING, checks (then fixes) its stored flags on the I/O lane.
/proc/update_everything_flag_in_db()
	for(var/datum/admin_rank/R as anything in GLOB.admin_ranks)
		var/list/flags = list()
		if(R.include_rights == R_EVERYTHING)
			flags += "flags"
		if(R.exclude_rights == R_EVERYTHING)
			flags += "exclude_flags"
		if(R.can_edit_rights == R_EVERYTHING)
			flags += "can_edit_flags"
		if(!flags.len)
			continue
		var/flags_to_check = flags.Join(" != [R_EVERYTHING] AND ") + " != [R_EVERYTHING]"
		var/flags_to_update = flags.Join(" = [R_EVERYTHING], ") + " = [R_EVERYTHING]"
		io_job(null, /datum/io_backend/sql,
			"SELECT flags, exclude_flags, can_edit_flags FROM [format_table_name("admin_ranks")] WHERE rank = :rank AND ([flags_to_check])",
			list("rank" = R.name),
			/proc/update_everything_flag_checked, R.name, flags_to_update)

/// io_job() callback: a row back means the rank's stored flags are stale; rewrite them.
/proc/update_everything_flag_checked(list/result, error, rank_name, flags_to_update)
	if(error)
		log_sql("Admin rank R_EVERYTHING check failed for [rank_name]: [error]")
		return
	if(!length(result["rows"])) //no row is returned if the rank already has the correct flag value
		return
	sql_write(
		"UPDATE [format_table_name("admin_ranks")] SET [flags_to_update] WHERE rank = :rank",
		list("rank" = rank_name)
	)

/// Writes the protected ranks and admins to the database on the I/O lane; returns at once.
/proc/sync_admins_with_db(mob/user)
	if(IsAdminAdvancedProcCall())
		to_chat(user, span_adminprefix("Admin rank DB Sync blocked: Advanced ProcCall detected."))
		return

	if(CONFIG_GET(flag/admin_legacy_system) || !SSdbcore.IsConnected()) //we're already using legacy system so there's nothing to save
		return
	sync_ranks_with_db(user)
	var/list/sql_admins = list()
	for(var/holder_ckey in GLOB.protected_admins)
		var/datum/admins/holder = GLOB.protected_admins[holder_ckey]
		sql_admins += list(list("ckey" = holder.target, "rank" = holder.rank_names()))
	if(!SSdbcore.mass_insert_io(null, format_table_name("admin"), sql_admins, TRUE, FALSE, null, /proc/sync_admins_with_db_done))
		sync_admins_with_db_done()

/// io_job() callback: the admin rows are written; copy each admin's rank onto their player row.
/proc/sync_admins_with_db_done(list/result, error)
	if(error)
		log_sql("Admin DB sync failed: [error]")
		return
	sql_write("UPDATE [format_table_name("erro_player")] AS p INNER JOIN [format_table_name("admin")] AS a ON p.ckey = a.ckey SET p.lastadminrank = a.rank")

/proc/save_admin_backup(mob/user)
	if(IsAdminAdvancedProcCall())
		to_chat(user, span_adminprefix("Admin rank DB Sync blocked: Advanced ProcCall detected."))
		return

	if(CONFIG_GET(flag/admin_legacy_system)) //we're already using legacy system so there's nothing to save
		return

	//json format backup file generation stored per server
	var/json_file = file("data/admins_backup.json")
	var/list/file_data = list(
		"ranks" = list(),
		"admins" = list()
	)
	for(var/datum/admin_rank/R as anything in GLOB.admin_ranks)
		file_data["ranks"]["[R.name]"] = list()
		file_data["ranks"]["[R.name]"]["include rights"] = R.include_rights
		file_data["ranks"]["[R.name]"]["exclude rights"] = R.exclude_rights
		file_data["ranks"]["[R.name]"]["can edit rights"] = R.can_edit_rights

	for(var/admin_ckey in GLOB.admin_datums + GLOB.deadmins)
		var/datum/admins/admin = GLOB.admin_datums[admin_ckey]

		if(!admin)
			admin = GLOB.deadmins[admin_ckey]
			if (!admin)
				continue

		file_data["admins"][admin_ckey] = admin.rank_names()


	fdel(json_file)
	WRITE_FILE(json_file, json_encode(file_data, JSON_PRETTY_PRINT))
