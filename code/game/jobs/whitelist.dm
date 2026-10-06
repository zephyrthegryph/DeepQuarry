CAPABILITIES(/datum/whitelist_editor)
	op("reload_alienwhitelist", ui_act("reload_alienwhitelist"), then(PROC_REF(ui_act_reload_alienwhitelist)))
	op("reload_jobwhitelist", ui_act("reload_jobwhitelist"), then(PROC_REF(ui_act_reload_jobwhitelist)))
	interface("WhitelistEdit", rights = R_ADMIN)
	op("add_alienwhitelist", ui_act("add_alienwhitelist", arg("ckey", schema_text(4096)), arg("role", schema_text(4096)), arg("type", schema_text(4096))), then(PROC_REF(ui_act_add_alienwhitelist)))
	op("remove_alienwhitelist", ui_act("remove_alienwhitelist", arg("ckey", schema_text(4096)), arg("role", schema_text(4096)), arg("type", schema_text(4096))), then(PROC_REF(ui_act_remove_alienwhitelist)))

#define WHITELISTFILE "data/whitelist.txt"
#define VALID_KINDS list("job", "species", "language", "robot")

GLOBAL_LIST_EMPTY(whitelist)
GLOBAL_LIST_EMPTY(job_whitelist)
GLOBAL_LIST_EMPTY(alien_whitelist)
GLOBAL_LIST_EMPTY(language_whitelist)
GLOBAL_LIST_EMPTY(robot_whitelist)

ADMIN_VERB(open_whitelist_editor, R_ADMIN|R_SERVER, "Open Whitelist Editor", "Opens the editor for alien- and jobwhitelists.", ADMIN_CATEGORY_SERVER_CONFIG)
	if(admin_can(user, 0))
		user.holder.whitelist_editor = new /datum/whitelist_editor()
		user.holder.whitelist_editor.tgui_interact(user.mob)

/datum/whitelist_editor

/// /datum/whitelist_editor's window data.
/datum/whitelist_editor/ui_data(datum/act/eval/A)
	var/list/data = list(
		"alienwhitelist" = GLOB.alien_whitelist,
		"languagewhitelist" = GLOB.language_whitelist,
		"robotwhitelist" = GLOB.robot_whitelist,
		"jobwhitelist" = GLOB.job_whitelist
	)

	return data

/datum/whitelist_editor/tgui_static_data(mob/user)
	var/list/whitelist_jobs = list()
	for(var/datum/job/our_job in SSjob.occupations)
		if(our_job.whitelist_only)
			whitelist_jobs += our_job.title

	var/list/whitelisted_language = list()
	for(var/language, value in GLOB.all_languages)
		var/datum/language/current_lang = value
		if(current_lang.flags & WHITELISTED)
			whitelisted_language += language

	var/list/data = list(
		"species_with_whitelist" = GLOB.whitelisted_species,
		"language_with_whitelist" = whitelisted_language,
		"robot_with_whitelist" = GLOB.whitelisted_module_types,
		"jobs_with_whitelist" = whitelist_jobs
	)

	return data

/datum/whitelist_editor/proc/ui_act_add_alienwhitelist(datum/act/op/A, ckey_arg, role_arg, type)
	var/mob/user = A.actor
	if (!CONFIG_GET(flag/sql_enabled))
		to_chat(user, span_warning("This action is not supported while the database is disabled. Please edit [global.config.directory]/alienwhitelist.txt."))
		return
	var/ckey = ckey_arg
	if(ckey != ckey(ckey))
		to_chat(user, span_warning("Error, invalid ckey. Did you enter the key?"))
		return FALSE
	var/kind = type
	if(!(kind in VALID_KINDS))
		to_chat(user, span_warning("Error, invalid type entered."))
		return FALSE
	var/role = role_arg
	switch(kind)
		if("job")
			var/datum/job/job = SSjob.get_job(role)
			if(!job)
				to_chat(user, span_warning("Error, invalid job entered. Check spelling and capitalization."))
				return FALSE
			if(!job.whitelist_only)
				to_chat(user, span_warning("Error, job \"[role]\" is not a whitelist job."))
				return FALSE
		if("species")
			if(!(role in GLOB.playable_species))
				to_chat(user, span_warning("Error, invalid species entered. Check spelling and capitalization."))
				return FALSE
			if(!(role in GLOB.whitelisted_species))
				to_chat(user, span_warning("Error, species \"[role]\" is not a whitelist species."))
				return FALSE
		if("language")
			var/datum/language/chosen_language = GLOB.all_languages[role]
			if(!chosen_language)
				to_chat(user, span_warning("Error, invalid language entered. Check spelling and capitalization."))
				return FALSE
			if(!(chosen_language.flags & WHITELISTED))
				to_chat(user, span_warning("Error, language \"[role]\" is not a whitelist language."))
				return FALSE
		if("robot")
			if(!(role in GLOB.robot_modules))
				to_chat(user, span_warning("Error, invalid robot module entered. Check spelling and capitalization."))
				return FALSE
			if(!(role in GLOB.whitelisted_module_types))
				to_chat(user, span_warning("Error, robot module \"[role]\" is not a whitelist robot module."))
				return FALSE
	// om_io: the result is reported to the admin when it arrives.
	om_io(null, /datum/om/io/sql,
		"INSERT INTO [format_table_name("whitelist")] (ckey, kind, entry) VALUES (:ckey, :kind, :entry)",
		list("ckey" = ckey, "kind" = kind, "entry" = role),
		/proc/whitelist_edit_done, user.ckey, "add [ckey] to the [role] [kind] whitelist", "added [ckey]'s [role] entry to [kind] whitelsit.")
	return TRUE

/datum/whitelist_editor/proc/ui_act_remove_alienwhitelist(datum/act/op/A, ckey_arg, role_arg, type)
	var/mob/user = A.actor
	if (!CONFIG_GET(flag/sql_enabled))
		to_chat(user, "This action is not supported while the database is disabled. Please edit [global.config.directory]/alienwhitelist.txt.")
		return FALSE
	var/ckey = ckey_arg
	if(ckey != ckey(ckey))
		to_chat(user, span_warning("Error, invalid ckey. Did you enter the key?"))
		return FALSE
	var/kind = type
	if(!(kind in VALID_KINDS))
		to_chat(user, span_warning("Error, invalid type entered."))
		return FALSE
	var/role = role_arg
	om_io(null, /datum/om/io/sql,
		"DELETE FROM [format_table_name("whitelist")] WHERE ckey = :ckey AND kind = :kind AND entry = :entry",
		list("ckey" = ckey, "kind" = kind, "entry" = role),
		/proc/whitelist_edit_done, user.ckey, "remove [ckey] from the [role] [kind] whitelist", "removed [ckey]'s [role] entry from [kind] whitelsit.")
	return TRUE

/datum/whitelist_editor/proc/ui_act_reload_alienwhitelist(datum/act/op/A)
	reload_alienwhitelist()
	return OP_OK

/datum/whitelist_editor/proc/ui_act_reload_jobwhitelist(datum/act/op/A)
	reload_jobwhitelist()
	return OP_OK

/// om_io() callback for the whitelist editor's writes: reports and logs the outcome.
/proc/whitelist_edit_done(list/result, error, admin_ckey, what, done_message)
	var/client/C = GLOB.directory[admin_ckey]
	if(error)
		log_sql("Error while trying to [what]: [error]")
		if(C)
			to_chat(C, span_warning("Error while trying to [what]. Please review SQL logs."))
		return
	log_and_message_admins(done_message, C?.mob)

/proc/load_whitelist()
	GLOB.whitelist = world.file2list(WHITELISTFILE)
	if(!GLOB.whitelist.len)	GLOB.whitelist = null

/proc/check_whitelist(mob/M /*rank*/)
	READS_FROM() // the whitelist is an admin record, not round state
	if(!CONFIG_GET(flag/usewhitelist)) //I guess this is an override for the blanket whitelist system.
		return 1
	if(!GLOB.whitelist)
		return 0
	return ("[M.ckey]" in GLOB.whitelist)

/// Loads the alien whitelists: from the database (om_io; the lists are replaced when the rows
/// arrive) or from the config file.
/proc/load_alienwhitelist(dbfail = FALSE)
	if (CONFIG_GET(flag/sql_enabled) && !dbfail)
		om_io(null, /datum/om/io/sql, "SELECT ckey, entry, kind FROM [format_table_name("whitelist")] WHERE kind IN ('species', 'language', 'robot')", null, /proc/alienwhitelist_rows_arrived)
		return
	else
		GLOB.alien_whitelist.Cut()
		GLOB.language_whitelist.Cut()
		GLOB.robot_whitelist.Cut()
		var/text = file2text("[global.config.directory]/alienwhitelist.txt")
		if (!text)
			log_world("Failed to load [global.config.directory]/alienwhitelist.txt")
		else
			var/lines = splittext(text, "\n") // Now we've got a bunch of "ckey = something" strings in a list
			for(var/line in lines)
				var/list/data_entry = splittext(line, " - ") // Split it on the dash into left and right
				if(LAZYLEN(data_entry) != 3)
					WARNING("Alien whitelist entry is invalid: [line]") // If we didn't end up with a left and right, the line is bad
					continue
				var/key = data_entry[2]
				if(key != ckey(key))
					WARNING("Alien whitelist entry appears to have key, not ckey: [line]") // The key contains invalid ckey characters
					continue
				var/type = data_entry[1]
				switch(type)
					if("species")
						LAZYADD(GLOB.alien_whitelist[key], data_entry[3])
					if("language")
						LAZYADD(GLOB.language_whitelist[key], data_entry[3])
					if("robot")
						LAZYADD(GLOB.robot_whitelist[key], data_entry[3])
					else
						WARNING("Alien whitelist entry type is invalid: [line]")
						return

	#ifdef TESTING
	var/msg = "Alienwhitelist Built:\n"
	for(var/key in GLOB.alien_whitelist)
		msg += "\t[key]:\n"
		for(var/value in GLOB.alien_whitelist[key])
			msg += "\t\t- [value]\n"
	testing(msg)
	#endif

/proc/reload_alienwhitelist()
	load_alienwhitelist()

/// om_io() callback: replaces the alien whitelists with the database's rows.
/proc/alienwhitelist_rows_arrived(list/result, error)
	if(error)
		message_admins("Error loading alienwhitelist from database. Loading from [global.config.directory]/alienwhitelist.txt.")
		log_sql("Error loading alienwhitelist from database ([error]). Loading from [global.config.directory]/alienwhitelist.txt.")
		load_alienwhitelist(dbfail = TRUE)
		return
	GLOB.alien_whitelist.Cut()
	GLOB.language_whitelist.Cut()
	GLOB.robot_whitelist.Cut()
	for(var/list/row as anything in result["rows"])
		var/ckey = row[1]
		var/entry = row[2]
		switch(row[3])
			if("species")
				LAZYADD(GLOB.alien_whitelist[ckey], entry)
			if("language")
				LAZYADD(GLOB.language_whitelist[ckey], entry)
			if("robot")
				LAZYADD(GLOB.robot_whitelist[ckey], entry)

/proc/is_alien_whitelisted(client/C, datum/species/species)
	//They are admin or the whitelist isn't in use
	if(whitelist_overrides(C))
		return TRUE

	//You did something wrong
	if(!C || !species)
		return FALSE

	//The species isn't even whitelisted
	if(!(species.spawn_flags & SPECIES_IS_WHITELISTED))
		return TRUE

	//Search the whitelist
	var/list/our_whitelists = GLOB.alien_whitelist[C.ckey]
	if("All" in our_whitelists)
		return TRUE
	if(species.name in our_whitelists)
		return TRUE

	// Go apply!
	return FALSE

/// Loads the job whitelist: from the database (om_io; replaced when the rows arrive) or the file.
/proc/load_jobwhitelist(dbfail = FALSE)
	if (CONFIG_GET(flag/sql_enabled) && !dbfail)
		om_io(null, /datum/om/io/sql, "SELECT ckey, entry FROM [format_table_name("whitelist")] WHERE kind = 'job'", null, /proc/jobwhitelist_rows_arrived)
		return
	else
		GLOB.job_whitelist.Cut()
		var/text = file2text("[global.config.directory]/jobwhitelist.txt")
		if (!text)
			log_world("Failed to load [global.config.directory]/jobwhitelist.txt")
		else
			var/lines = splittext(text, "\n") // Now we've got a bunch of "ckey = something" strings in a list
			for(var/line in lines)
				line = trim(line)
				// Blank lines and `#` comments (the example file documents its format in them) are not entries.
				if(!length(line) || copytext(line, 1, 2) == "#")
					continue
				var/list/left_and_right = splittext(line, " - ") // Split it on the dash into left and right
				if(LAZYLEN(left_and_right) != 2)
					WARNING("Job whitelist entry is invalid: [line]") // If we didn't end up with a left and right, the line is bad
					continue
				var/key = left_and_right[1]
				if(key != ckey(key))
					WARNING("Job whitelist entry appears to have key, not ckey: [line]") // The key contains invalid ckey characters
					continue
				var/list/our_whitelists = GLOB.job_whitelist[key] // Try to see if we have one already and add to it
				if(!our_whitelists) // Guess this is their first/only whitelist entry
					our_whitelists = list()
					GLOB.job_whitelist[key] = our_whitelists
				our_whitelists += left_and_right[2]

/proc/reload_jobwhitelist()
	load_jobwhitelist()

/// om_io() callback: replaces the job whitelist with the database's rows.
/proc/jobwhitelist_rows_arrived(list/result, error)
	if(error)
		message_admins("Error loading jobwhitelist from database. Loading from [global.config.directory]/jobwhitelist.txt.")
		log_sql("Error loading jobwhitelist from database ([error]). Loading from [global.config.directory]/jobwhitelist.txt.")
		load_jobwhitelist(dbfail = TRUE)
		return
	GLOB.job_whitelist.Cut()
	for(var/list/row as anything in result["rows"])
		var/ckey = row[1]
		var/list/our_whitelists = GLOB.job_whitelist[ckey]
		if(!our_whitelists) // Guess this is their first/only whitelist entry
			our_whitelists = list()
			GLOB.job_whitelist[ckey] = our_whitelists
		our_whitelists += row[2]

/proc/is_job_whitelisted(mob/M, rank)
	// Check if the job actually requires a whitelist
	var/datum/job/job = SSjob.get_job(rank)
	if(!job)
		return TRUE
	if(!job.whitelist_only)
		return TRUE

	// Visitor not Assistant
	if(rank == JOB_ALT_VISITOR)
		return TRUE

	// Let R_ADMIN permission bypass the whitelist
	if(check_rights(R_ADMIN, 0))
		return TRUE

	// Whitelist empty
	if(!GLOB.job_whitelist)
		return FALSE

	//Search the whitelist
	if(M && M.client && rank)
		var/list/our_whitelists = GLOB.job_whitelist[M.client.ckey]
		if("All" in our_whitelists)
			return TRUE
		if(rank in our_whitelists)
			return TRUE

	return FALSE

/proc/is_lang_whitelisted(mob/M, datum/language/language)
	//They are admin or the whitelist isn't in use
	if(whitelist_overrides(M))
		return TRUE

	//You did something wrong
	if(!M || !language)
		return FALSE

	//The language isn't even whitelisted
	if(!(language.flags & WHITELISTED))
		return TRUE

	//Search the whitelist
	var/list/our_whitelists = GLOB.language_whitelist[M.ckey]
	if("All" in our_whitelists)
		return TRUE
	if(language.name in our_whitelists)
		return TRUE

	return FALSE

/proc/is_borg_whitelisted(mob/M, module)
	//They are admin or the whitelist isn't in use
	if(whitelist_overrides(M))
		return 1

	//You did something wrong
	if(!M || !module)
		return 0

	//Module is not even whitelisted
	if(!(module in GLOB.whitelisted_module_types))
		return 1

	//If we have a loaded file, search it
	var/list/our_whitelists = GLOB.robot_whitelist[M.ckey]
	if("All" in our_whitelists)
		return TRUE
	if(module in our_whitelists)
		return TRUE

/proc/whitelist_overrides(client/C)
	if(!CONFIG_GET(flag/usealienwhitelist))
		return TRUE
	if(ismob(C)) //Someone fed a mob into this by mistake. Bad, but we planned ahead for these mistakes.
		var/mob/mob = C
		C = mob.client

	if(check_rights_for(C, R_ADMIN|R_EVENT|R_DEBUG))
		return TRUE

	return FALSE

#undef WHITELISTFILE
#undef VALID_KINDS
