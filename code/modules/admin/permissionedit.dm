
ADMIN_VERB(edit_admin_permissions, R_PERMISSIONS, "Permissions Panel", "Edit admin permissions.", ADMIN_CATEGORY_SECRETS)
	user.holder.edit_admin_permissions(PERMISSIONS_PAGE_PERMISSIONS)

#define PERMISSIONS_LOGS_PER_PAGE 20
/// List of all the actions you have ever been able to take in admin logs, keep in parity with the
/// operation enum in the admin_log table
GLOBAL_LIST_INIT(permission_action_types, list(
	PERMISSIONS_ACTION_ADMIN_ADDED,
	PERMISSIONS_ACTION_ADMIN_REMOVED,
	PERMISSIONS_ACTION_ADMIN_RANK_CHANGED,
	PERMISSIONS_ACTION_RANK_ADDED,
	PERMISSIONS_ACTION_RANK_REMOVED,
	PERMISSIONS_ACTION_RANK_CHANGED,
	PERMISSIONS_ACTION_NONE
))

// edit_admin_permissions body relocated to code/modules/admin/permissions_panel.dm (structured TGUI).
// The legacy 400-line HTML/asset-cache builder is gone; edit_rights_topic and topic.dm's editrightsbrowser* handlers still own the actions and call edit_admin_permissions() at the end to refresh — that now opens the structured panel.

/// Runs as a prompt flow (flow_ask()): every question is asked before anything changes, and the
/// answers re-run this proc, so the rights checks below run again when they arrive.
/datum/admins/proc/edit_rights_topic(task, admin_key)
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(edit_rights_topic), args)
	if(!check_rights(R_PERMISSIONS))
		message_admins("[key_name_admin(usr)] attempted to edit admin permissions without sufficient rights.")
		log_admin("[key_name(usr)] attempted to edit admin permissions without sufficient rights.")
		return
	if(IsAdminAdvancedProcCall())
		to_chat(usr, span_adminprefix("Admin Edit blocked: Advanced ProcCall detected."), confidential = TRUE)
		return
	var/datum/asset/permissions_assets = get_asset_datum(/datum/asset/simple/namespaced/common)
	permissions_assets.send(usr.client)
	var/admin_ckey = ckey(admin_key)

	var/datum/admins/target_admin_datum = GLOB.admin_datums[admin_ckey]
	if(!target_admin_datum)
		target_admin_datum = GLOB.deadmins[admin_ckey]
	if (!target_admin_datum && task != "add")
		return
	var/use_db
	var/skip
	var/legacy_only
	if(task == "activate" || task == "deactivate" || task == "sync" || task == "verify" || task == "permissions")
		skip = TRUE
	if(!CONFIG_GET(flag/admin_legacy_system) && CONFIG_GET(flag/protect_legacy_admins) && task == "rank")
		if(admin_ckey in GLOB.protected_admins)
			to_chat(usr, span_adminprefix("Editing the rank of this admin is blocked by server configuration."), confidential = TRUE)
			return
	if(!CONFIG_GET(flag/admin_legacy_system) && CONFIG_GET(flag/protect_legacy_ranks) && task == "permissions")
		if((target_admin_datum.ranks & GLOB.protected_ranks).len > 0)
			to_chat(usr, span_adminprefix("Editing the flags of this rank is blocked by server configuration."), confidential = TRUE)
			return
	if(CONFIG_GET(flag/load_legacy_ranks_only) && (task == "add" || task == "rank" || task == "permissions"))
		to_chat(usr, span_adminprefix("Database rank loading is disabled, only temporary changes can be made to a rank's permissions and permanently creating a new rank is blocked."), confidential = TRUE)
		legacy_only = TRUE

	if(check_rights(R_DBRANKS, FALSE) && !skip)
		if(!SSdbcore.Connect())
			to_chat(usr, span_danger("Unable to connect to database, changes are temporary only."), confidential = TRUE)
			use_db = FALSE
		else
			use_db = flow_ask(usr, "use_db", /datum/om/prompt/choice/alert, message = "Permanent changes are saved to the database for future rounds, temporary changes will affect only the current round", title = "Permanent or Temporary?", choices = list("Permanent", "Temporary", "Cancel"))
			if(isnull(use_db) || use_db == "Cancel")
				return
			if(use_db == "Permanent")
				use_db = TRUE
			else
				use_db = FALSE
		if(QDELETED(usr))
			return

	if(target_admin_datum && (task != "sync" && task != "verify") && !check_if_greater_rights_than_holder(target_admin_datum))
		message_admins("[key_name_admin(usr)] attempted to change the rank of [admin_key] without sufficient rights.")
		log_admin("[key_name(usr)] attempted to change the rank of [admin_key] without sufficient rights.")
		return
	switch(task)
		if("add")
			// Ask the key and the ranks first; nothing is added until both are answered.
			if(!admin_ckey)
				admin_key = flow_ask(usr, "admin_key", /datum/om/prompt/text, message = "New admin's key", title = "Admin key")
				if(!ckey(admin_key))
					return
				if(ckey(admin_key) in (GLOB.admin_datums + GLOB.deadmins))
					to_chat(usr, span_danger("[admin_key] is already an admin."), confidential = TRUE)
					return
			var/list/picked = pick_admin_ranks(use_db, null, legacy_only)
			if(isnull(picked))
				return
			admin_ckey = add_admin(admin_ckey, admin_key, use_db)
			if(!admin_ckey)
				return

			if(!admin_key) // Prevents failures in logging admin rank changes.
				admin_key = admin_ckey

			change_admin_rank(admin_ckey, admin_key, use_db, null, legacy_only, picked)
		if("remove")
			remove_admin(admin_ckey, admin_key, use_db, target_admin_datum)
		if("rank")
			change_admin_rank(admin_ckey, admin_key, use_db, target_admin_datum, legacy_only)
		if("permissions")
			change_admin_flags(admin_ckey, admin_key, target_admin_datum)
		if("activate")
			force_readmin(admin_key, target_admin_datum)
		if("deactivate")
			force_deadmin(admin_key, target_admin_datum)
		if("sync")
			sync_lastadminrank(admin_ckey, admin_key, target_admin_datum)
	edit_admin_permissions(PERMISSIONS_PAGE_PERMISSIONS)

/datum/admins/proc/add_admin(admin_ckey, admin_key, use_db)
	if(!check_rights(R_PERMISSIONS) || (use_db && !check_rights(R_DBRANKS)))
		return
	if(IsAdminAdvancedProcCall())
		to_chat(usr, span_adminprefix("Admin Addition blocked: Advanced ProcCall detected."), confidential = TRUE)
		return
	if(admin_ckey)
		. = admin_ckey
	else // A new admin: edit_rights_topic() asked for the key.
		. = ckey(admin_key)
	if(!.)
		return FALSE
	if(!admin_ckey && (. in (GLOB.admin_datums+GLOB.deadmins)))
		to_chat(usr, span_danger("[admin_key] is already an admin."), confidential = TRUE)
		return FALSE
	if(!use_db)
		return
	//if an admin exists without a datum they won't be caught by the above
	var/datum/db_query/query_admin_in_db = SSdbcore.NewQuery(
		"SELECT 1 FROM [format_table_name("admin")] WHERE ckey = :ckey",
		list("ckey" = .)
	)
	if(!query_admin_in_db.warn_execute())
		qdel(query_admin_in_db)
		return FALSE
	if(query_admin_in_db.NextRow())
		qdel(query_admin_in_db)
		to_chat(usr, span_danger("[admin_key] already listed in admin database. Check the Housekeeping tab if they don't appear in the list of admins."), confidential = TRUE)
		return FALSE
	QDEL_NULL(query_admin_in_db)
	// The row is written by change_admin_rank(), which the add always runs next, with the picked
	// rank: a separate insert here would race that proc's read of the admin table.

/datum/admins/proc/remove_admin(admin_ckey, admin_key, use_db, datum/admins/target_holder)
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(remove_admin), args)
	if(!check_rights(R_PERMISSIONS) || (use_db && !check_rights(R_DBRANKS)))
		return
	if(IsAdminAdvancedProcCall())
		to_chat(usr, span_adminprefix("Admin Removal blocked: Advanced ProcCall detected."), confidential = TRUE)
		return
	if(flow_ask(usr, "remove_admin", /datum/om/prompt/choice/alert, message = "Are you sure you want to remove [admin_ckey]?", title = "Confirm Removal", choices = list("Do it", "Cancel")) != "Do it")
		return
	if(!(admin_ckey in (GLOB.admin_datums + GLOB.deadmins)) && !use_db)
		return
	GLOB.admin_datums -= admin_ckey
	GLOB.deadmins -= admin_ckey
	if(target_holder)
		target_holder.disassociate()
	var/m1 = "[key_name_admin(usr)] removed [admin_key] from the admins list [use_db ? "permanently" : "temporarily"]"
	var/m2 = "[key_name(usr)] removed [admin_key] from the admins list [use_db ? "permanently" : "temporarily"]"

	if(!use_db)
		message_admins(m1)
		log_admin(m2)
		return
	om_sql_write(
		"DELETE FROM [format_table_name("admin")] WHERE ckey = :ckey",
		list("ckey" = admin_ckey)
	)
	message_admins(m1)
	log_admin(m2)
	om_sql_write({"
		INSERT INTO [format_table_name("admin_log")] (datetime, round_id, adminckey, adminip, operation, target, log)
		VALUES (NOW(), :round_id, :adminckey, INET_ATON(:adminip), '[PERMISSIONS_ACTION_ADMIN_REMOVED]', :admin_ckey, CONCAT('Admin removed: ', :admin_ckey))
	"}, list("round_id" = "[GLOB.round_id]", "adminckey" = usr.ckey, "adminip" = usr.client.address, "admin_ckey" = admin_ckey))
	sync_lastadminrank(admin_ckey, admin_key)

/datum/admins/proc/force_readmin(admin_key, datum/admins/target_holder)
	if(!target_holder || !target_holder.deadmined)
		return
	target_holder.activate()
	message_admins("[key_name_admin(usr)] forcefully readmined [admin_key]")
	log_admin("[key_name(usr)] forcefully readmined [admin_key]")

/datum/admins/proc/force_deadmin(admin_key, datum/admins/target_holder)
	if(!target_holder || target_holder.deadmined)
		return
	message_admins("[key_name_admin(usr)] forcefully deadmined [admin_key]")
	log_admin("[key_name(usr)] forcefully deadmined [admin_key]")
	target_holder.deactivate() //after logs so the deadmined admin can see the message.

/datum/admins/proc/auto_deadmin()
	if(owner().is_localhost())
		return FALSE

	to_chat(owner(), span_interface("You are now a normal player."), confidential = TRUE)
	var/old_owner = owner()
	deactivate()
	message_admins("[old_owner] deadmined via auto-deadmin config.")
	log_admin("[old_owner] deadmined via auto-deadmin config.")
	return TRUE

#define RANK_DONE ":) I'm Done"

/// Asks (flow_ask()) which ranks an admin gets, one pick per question, until RANK_DONE.
/// Returns list("names" = picked rank names, "custom" = new custom rank names), or null while
/// unanswered or cancelled. Creates nothing: change_admin_rank() makes the custom ranks.
/datum/admins/proc/pick_admin_ranks(use_db, datum/admins/target_holder, legacy_only)
	var/list/rank_names = list()
	if(!use_db || (use_db && !legacy_only))
		rank_names += "*New Rank*"
	for(var/datum/admin_rank/admin_rank as anything in GLOB.admin_ranks)
		if((admin_rank.rights & usr.client.holder.can_edit_rights_flags()) != admin_rank.rights)
			continue
		if(use_db && admin_rank.source != RANK_SOURCE_DB && admin_rank.source != RANK_SOURCE_TXT)
			continue
		rank_names[admin_rank.name] = admin_rank

	var/list/new_rank_names = list()
	var/list/custom_names = list()
	var/step = 0

	while (TRUE)
		step++
		var/list/display_rank_names = list(RANK_DONE)

		if (new_rank_names.len > 0)
			display_rank_names += "** SELECTED **"
			for (var/rank_name in new_rank_names)
				display_rank_names += rank_name
			display_rank_names += "---------"

		for (var/rank_name in rank_names)
			if (!(rank_name in display_rank_names))
				display_rank_names += rank_name

		// Each pick is its own question: the flow replays the earlier picks from their answers.
		var/next_rank = flow_ask(usr, "rank:[step]", /datum/om/prompt/choice, message = "Please select a rank, or select [RANK_DONE] if you are finished.", title = "Admin rank", choices = display_rank_names)

		if (isnull(next_rank) || !(next_rank in display_rank_names))
			return null

		if (next_rank == RANK_DONE)
			break

		if (next_rank in new_rank_names)
			new_rank_names -= next_rank
			custom_names -= next_rank
			continue

		// They clicked "** SELECTED **" or something silly.
		if (!(next_rank in rank_names))
			continue

		if (next_rank == "*New Rank*")
			var/new_rank_name = flow_ask(usr, "new_rank:[step]", /datum/om/prompt/text, message = "Please input a new rank", title = "New custom rank")
			if (!new_rank_name)
				return null
			if(!isnull(rank_names[new_rank_name]) || (new_rank_name in new_rank_names))
				continue
			custom_names += new_rank_name
			new_rank_names += new_rank_name
			continue

		new_rank_names += next_rank

	return list("names" = new_rank_names, "custom" = custom_names)

/// Sets an admin's ranks. `picked` is pick_admin_ranks()'s answer when the caller asked already;
/// otherwise this runs as a prompt flow and asks.
/datum/admins/proc/change_admin_rank(admin_ckey, admin_key, use_db, datum/admins/target_holder, legacy_only, list/picked)
	if(!picked && !GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(change_admin_rank), args)
	if(!check_rights(R_PERMISSIONS) || (use_db && !check_rights(R_DBRANKS)))
		return
	if(IsAdminAdvancedProcCall())
		to_chat(usr, span_adminprefix("Rank Modification blocked: Advanced ProcCall detected."), confidential = TRUE)
		return

	if(!picked)
		picked = pick_admin_ranks(use_db, target_holder, legacy_only)
		if(isnull(picked))
			return

	var/rank_type = RANK_SOURCE_TEMPORARY
	if(use_db)
		rank_type = RANK_SOURCE_DB

	// Reads first (each is a flow re-run); nothing changes until they are all answered.
	var/old_rank
	var/list/custom_names_in_db = list()
	if(use_db)
		//if a player was tempminned before having a permanent change made to their rank they won't yet be in the db
		var/datum/db_query/query_admin_in_db = SSdbcore.NewQuery(
			"SELECT `rank` FROM [format_table_name("admin")] WHERE ckey = :admin_ckey",
			list("admin_ckey" = admin_ckey)
		)
		if(!query_admin_in_db.warn_execute())
			qdel(query_admin_in_db)
			return
		if(query_admin_in_db.NextRow())
			old_rank = query_admin_in_db.item[1]
		QDEL_NULL(query_admin_in_db)
		for(var/new_rank_name in picked["custom"])
			//similarly if a temp rank is created it won't be in the db if someone is permanently changed to it
			var/datum/db_query/query_rank_in_db = SSdbcore.NewQuery(
				"SELECT 1 FROM [format_table_name("admin_ranks")] WHERE `rank` = :new_rank",
				list("new_rank" = new_rank_name)
			)
			if(!query_rank_in_db.warn_execute())
				qdel(query_rank_in_db)
				return
			if(query_rank_in_db.NextRow())
				custom_names_in_db[new_rank_name] = TRUE
			QDEL_NULL(query_rank_in_db)

	var/list/picked_names = picked["names"]
	var/list/new_rank_names = picked_names.Copy()
	var/list/custom_ranks = list()
	for(var/new_rank_name in picked["custom"])
		if(length(ranks_from_rank_name(new_rank_name)))
			continue // Made meanwhile; the pick uses the existing one.
		var/datum/admin_rank/custom_rank
		if (target_holder)
			custom_rank = new(new_rank_name, rank_type, target_holder.rank_flags())
		else
			custom_rank = new(new_rank_name, rank_type)
		if(QDELETED(custom_rank))
			new_rank_names -= new_rank_name
			continue
		GLOB.admin_ranks += custom_rank
		custom_ranks += custom_rank

	var/list/new_ranks = list()
	for (var/datum/admin_rank/admin_rank as anything in GLOB.admin_ranks)
		if (admin_rank.name in new_rank_names)
			new_ranks += admin_rank
			new_rank_names -= admin_rank.name

			if (new_rank_names.len == 0)
				break

	var/joined_rank = join_admin_ranks(new_ranks)
	var/m1 = "[key_name_admin(usr)] edited the admin rank of [admin_key] to [joined_rank] [use_db ? "permanently" : "temporarily"]"
	var/m2 = "[key_name(usr)] edited the admin rank of [admin_key] to [joined_rank] [use_db ? "permanently" : "temporarily"]"
	if(use_db)
		for (var/datum/admin_rank/custom_rank in custom_ranks)
			if(custom_names_in_db[custom_rank.name])
				continue
			om_sql_write({"
				INSERT INTO [format_table_name("admin_ranks")] (`rank`, flags, exclude_flags, can_edit_flags)
				VALUES (:new_rank, '0', '0', '0')
			"}, list("new_rank" = custom_rank.name))
			om_sql_write({"
				INSERT INTO [format_table_name("admin_log")] (datetime, round_id, adminckey, adminip, operation, target, log)
				VALUES (NOW(), :round_id, :adminckey, INET_ATON(:adminip), '[PERMISSIONS_ACTION_RANK_ADDED]', :new_rank, CONCAT('New rank added: ', :new_rank))
			"}, list("round_id" = "[GLOB.round_id]", "adminckey" = usr.ckey, "adminip" = usr.client.address, "new_rank" = custom_rank.name))
		if(isnull(old_rank))
			// Not in the admin table yet (a new or temporary admin): one insert, with the rank.
			old_rank = "NEW ADMIN"
			om_sql_write(
				"INSERT INTO [format_table_name("admin")] (ckey, `rank`) VALUES (:ckey, :new_rank)",
				list("ckey" = admin_ckey, "new_rank" = joined_rank)
			)
			om_sql_write({"
				INSERT INTO [format_table_name("admin_log")] (datetime, round_id, adminckey, adminip, operation, target, log)
				VALUES (NOW(), :round_id, :adminckey, INET_ATON(:adminip), '[PERMISSIONS_ACTION_ADMIN_ADDED]', :target, CONCAT('New admin added: ', :target))
			"}, list("round_id" = "[GLOB.round_id]",  "adminckey" = usr.ckey, "adminip" = usr.client.address, "target" = admin_ckey))
		else
			om_sql_write(
				"UPDATE [format_table_name("admin")] SET `rank` = :new_rank WHERE ckey = :admin_ckey",
				list("new_rank" = joined_rank, "admin_ckey" = admin_ckey)
			)
		message_admins(m1)
		log_admin(m2)
		om_sql_write({"
			INSERT INTO [format_table_name("admin_log")] (datetime, round_id, adminckey, adminip, operation, target, log)
			VALUES (NOW(), :round_id, :adminckey, INET_ATON(:adminip), '[PERMISSIONS_ACTION_ADMIN_RANK_CHANGED]', :target, CONCAT('Rank of ', :target, ' changed from ', :old_rank, ' to ', :new_rank))
		"}, list("round_id" = "[GLOB.round_id]", "adminckey" = usr.ckey, "adminip" = usr.client.address, "target" = admin_ckey, "old_rank" = old_rank, "new_rank" = joined_rank))
	else
		message_admins(m1)
		log_admin(m2)
	if(target_holder) //they were previously an admin
		target_holder.disassociate() //existing admin needs to be disassociated
		target_holder.ranks = new_ranks //set the admin_rank as our rank
		//target_holder.bypass_2fa = TRUE // Another admin has cleared us
		var/client/target_client = GLOB.directory[admin_ckey]
		target_holder.associate(target_client)
	else
		target_holder = new(new_ranks, admin_ckey) //new admin
		//target_holder.bypass_2fa = TRUE // Another admin has cleared us
		target_holder.activate()

#undef RANK_DONE

/// Changes, for this round only, the flags a particular admin gets to use
/datum/admins/proc/change_admin_flags(admin_ckey, admin_key, datum/admins/admin_holder)
	if(!check_rights(R_PERMISSIONS))
		return
	if(IsAdminAdvancedProcCall())
		to_chat(usr, span_adminprefix("Rank Modification blocked: Advanced ProcCall detected."), confidential = TRUE)
		return
	var/new_flags = flow_ask(usr, "admin_flags", /datum/om/prompt/bitfield, title = "Admin rights of [admin_ckey] (this round only)", bitfield = "admin_flags", default = admin_holder.rank_flags(), editable = usr.client.holder.can_edit_rights_flags())
	if(isnull(new_flags))
		return

	admin_holder.disassociate()

	if (findtext(admin_holder.rank_names(), "([admin_ckey])"))
		var/datum/admin_rank/rank = admin_holder.ranks[1]
		rank.rights = new_flags
		rank.include_rights = new_flags
		rank.exclude_rights = NONE
		rank.can_edit_rights = rank.can_edit_rights
	else
		// Not a modified subrank, need to duplicate the admin_rank datum to prevent modifying others too.
		var/datum/admin_rank/new_admin_rank = new(
			/* init_name = */ "[admin_holder.rank_names()]([admin_ckey])",
			/* init_source = */ RANK_SOURCE_TEMPORARY,
			/* init_rights = */ new_flags,

			// rank_flags() includes the exclude rights, so we no longer need to handle them separately.
			/* init_exclude_rights = */ NONE,

			/* init_edit_rights = */ admin_holder.can_edit_rights_flags(),
		)

		own_set(admin_holder, "custom_rank", new_admin_rank)
		admin_holder.set_ranks(list(new_admin_rank))

	var/log = "[key_name(usr)] has updated the admin rights of [admin_ckey] into [rights2text(new_flags)]"
	message_admins(log)
	log_admin(log)

	var/client/admin_client = GLOB.directory[admin_ckey]
	admin_holder.associate(admin_client)

/// Polls usr for a new rank to add to either JUST this round, or the DB
/datum/admins/proc/add_rank()
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(add_rank), args)
	if(!check_rights(R_PERMISSIONS))
		to_chat(usr, span_adminprefix("You don't have the permissions for this."), confidential = TRUE)
		return
	if(IsAdminAdvancedProcCall())
		to_chat(usr, span_adminprefix("Rank Addition blocked: Advanced ProcCall detected."), confidential = TRUE)
		return
	if(usr.client.holder.can_edit_rights_flags() == NONE)
		to_chat(usr, span_adminprefix("You are not allowed to add any rights."), confidential = TRUE)
		return

	var/new_rank_name = flow_ask(usr, "rank_name", /datum/om/prompt/text, message = "Please input a new rank", title = "New custom rank")
	if (!new_rank_name)
		return

	var/list/datum/admin_rank/existing_ranks = ranks_from_rank_name(new_rank_name)
	if (length(existing_ranks))
		to_chat(usr, span_adminprefix("A rank by this name already exists, sorry!."), confidential = TRUE)
		return

	var/rights = flow_ask(usr, "rights", /datum/om/prompt/bitfield, title = "New rights for [new_rank_name]", bitfield = "admin_flags", default = NONE, editable = usr.client.holder.can_edit_rights_flags())
	if(isnull(rights))
		return
	var/excluded_rights = flow_ask(usr, "excluded_rights", /datum/om/prompt/bitfield, title = "New excluded rights for [new_rank_name]", bitfield = "admin_flags", default = NONE, editable = usr.client.holder.can_edit_rights_flags())
	if(isnull(excluded_rights))
		return
	var/edit_rights = flow_ask(usr, "edit_rights", /datum/om/prompt/bitfield, title = "New editing rights for [new_rank_name]", bitfield = "admin_flags", default = NONE, editable = usr.client.holder.can_edit_rights_flags())
	if(isnull(edit_rights))
		return

	var/use_db = FALSE
	if(check_rights(R_DBRANKS, FALSE))
		if(!SSdbcore.Connect())
			to_chat(usr, span_danger("Unable to connect to database, changes are temporary only."), confidential = TRUE)
			use_db = FALSE
		else
			var/use_db_response = flow_ask(usr, "use_db", /datum/om/prompt/choice/alert, message = "Permanent changes are saved to the database for future rounds, temporary changes will affect only the current round", title = "Permanent or Temporary?", choices = list("Permanent", "Temporary", "Cancel"))
			if(isnull(use_db_response) || use_db_response == "Cancel")
				return
			if(use_db_response == "Permanent")
				use_db = TRUE
			else
				use_db = FALSE
		if(QDELETED(usr))
			return

	if(length(ranks_from_rank_name(new_rank_name))) // Made while we were asking.
		to_chat(usr, span_adminprefix("A rank by this name already exists, sorry!."), confidential = TRUE)
		return
	if(use_db)
		// Shit check for conflicts, before anything is made (a read: the flow re-runs on its answer)
		var/datum/db_query/query_rank_in_db = SSdbcore.NewQuery(
			"SELECT 1 FROM [format_table_name("admin_ranks")] WHERE `rank` = :new_rank",
			list("new_rank" = new_rank_name)
		)
		if(!query_rank_in_db.warn_execute())
			qdel(query_rank_in_db)
			return
		if(query_rank_in_db.NextRow())
			qdel(query_rank_in_db)
			to_chat(usr, span_adminprefix("A rank by this name already exists in the database."), confidential = TRUE)
			return
		QDEL_NULL(query_rank_in_db)
	var/datum/admin_rank/custom_rank
	if(use_db)
		custom_rank = new(new_rank_name, RANK_SOURCE_DB, rights, excluded_rights, edit_rights)
	else
		custom_rank = new(new_rank_name, RANK_SOURCE_TEMPORARY, rights, excluded_rights, edit_rights)
	if(QDELETED(custom_rank))
		to_chat(usr, span_danger("Rank creation failed, check runtimes."), confidential = TRUE)
		return

	GLOB.admin_ranks += custom_rank

	var/m1 = "[key_name_admin(usr)] created the new [use_db ? "permanent" : "temporary"] rank [new_rank_name]"
	var/m2 = "[key_name(usr)] created the new [use_db ? "permanent" : "temporary"] rank [new_rank_name]"

	if(!use_db)
		message_admins(m1)
		log_admin(m2)
		return
	om_sql_write({"
		INSERT INTO [format_table_name("admin_ranks")] (`rank`, flags, exclude_flags, can_edit_flags)
		VALUES (:new_rank, :rights, :excluded_rights, :edit_rights)
	"}, list("new_rank" = custom_rank.name, "rights" = rights, "excluded_rights" = excluded_rights, "edit_rights" = edit_rights))
	message_admins(m1)
	log_admin(m2)
	om_sql_write({"
		INSERT INTO [format_table_name("admin_log")] (datetime, round_id, adminckey, adminip, operation, target, log)
		VALUES (NOW(), :round_id, :adminckey, INET_ATON(:adminip), '[PERMISSIONS_ACTION_RANK_ADDED]', :new_rank,
		CONCAT('New rank added: ', :new_rank, ' (', :rights, ')', ' (', :excluded_rights, ')', ' (', :edit_rights, ')'))
	"}, list("round_id" = "[GLOB.round_id]", "adminckey" = usr.ckey, "adminip" = usr.client.address, "new_rank" = custom_rank.name,
		"rights" = rights, "excluded_rights" = excluded_rights, "edit_rights" = edit_rights))

/// Removes a rank from the db/temp loading
/datum/admins/proc/remove_rank(admin_rank)
	if(!admin_rank)
		return
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(remove_rank), args)
	if(!check_rights(R_PERMISSIONS))
		message_admins("[key_name_admin(usr)] attempted to remove a rank without sufficient rights.")
		log_admin("[key_name(usr)] attempted to remove a rank without sufficient rights.")
		return
	if(IsAdminAdvancedProcCall())
		to_chat(usr, span_adminprefix("Rank Deletion blocked: Advanced ProcCall detected."), confidential = TRUE)
		return
	for(var/datum/admin_rank/R in GLOB.admin_ranks)
		if(R.name == admin_rank && ((R.rights & usr.client.holder.can_edit_rights_flags()) != R.rights))
			to_chat(usr, span_adminprefix("You don't have edit rights to all the rights this rank has, rank deletion not permitted."), confidential = TRUE)
			return

	var/list/datum/admin_rank/target_ranks = ranks_from_rank_name(admin_rank)
	if (!target_ranks || length(target_ranks) > 1)
		return
	var/datum/admin_rank/target_rank = target_ranks[1]

	var/local_only_deletion
	switch(target_rank.source)
		if(RANK_SOURCE_LOCAL)
			to_chat(usr, span_adminprefix("Localhost rank cannot be deleted."), confidential = TRUE)
			return
		// This handles protected ranks on its own
		if(RANK_SOURCE_TXT)
			to_chat(usr, span_adminprefix("Text ranks cannot be meaningfully deleted, go modify admin_ranks.txt"), confidential = TRUE)
			return
		if(RANK_SOURCE_BACKUP)
			to_chat(usr, span_adminprefix("Backup ranks cannot usefully be deleted, as they are stored in a temp json, go uh... edit that? I guess?."), confidential = TRUE)
			return
		if(RANK_SOURCE_TEMPORARY)
			local_only_deletion = TRUE
		if(RANK_SOURCE_DB)
			local_only_deletion = FALSE

	if(!local_only_deletion && CONFIG_GET(flag/load_legacy_ranks_only))
		to_chat(usr, span_adminprefix("Database Rank deletion not permitted while database rank loading is disabled, deleting our local copy."), confidential = TRUE)
		local_only_deletion = TRUE

	if(!local_only_deletion)
		var/datum/db_query/query_admins_with_rank = SSdbcore.NewQuery(
			"SELECT 1 FROM [format_table_name("admin")] WHERE `rank` = :admin_rank",
			list("admin_rank" = admin_rank)
		)
		if(!query_admins_with_rank.warn_execute())
			qdel(query_admins_with_rank)
			return
		if(query_admins_with_rank.NextRow())
			qdel(query_admins_with_rank)
			to_chat(usr, span_danger("Error: Rank deletion attempted while db rank still used; Tell a coder, this shouldn't happen."), confidential = TRUE)
			return
		QDEL_NULL(query_admins_with_rank)

	for(var/admin_name in GLOB.admin_datums)
		var/datum/admins/existing_min = GLOB.admin_datums[admin_name]
		if(target_rank in existing_min.ranks)
			to_chat(usr, span_danger("Error: Rank deletion attempted while rank still used; Tell a coder, this shouldn't happen."), confidential = TRUE)
			return

	// Asked last, after every check above ran again on this answer's re-run.
	if(flow_ask(usr, "remove_rank", /datum/om/prompt/choice/alert, message = "Are you sure you want to remove [admin_rank]?", title = "Confirm Removal", choices = list("Do it", "Cancel")) != "Do it")
		return

	var/m1 = "[key_name_admin(usr)] removed rank [admin_rank] [local_only_deletion ? "temporarially" : "permanently"]"
	var/m2 = "[key_name(usr)] removed rank [admin_rank] [local_only_deletion ? "temporarially" : "permanently"]"
	GLOB.admin_ranks -= target_rank
	QDEL_NULL(target_rank)

	if(local_only_deletion)
		message_admins(m1)
		log_admin(m2)
		return
	om_sql_write(
		"DELETE FROM [format_table_name("admin_ranks")] WHERE `rank` = :admin_rank",
		list("admin_rank" = admin_rank)
	)
	message_admins(m1)
	log_admin(m2)
	om_sql_write({"
		INSERT INTO [format_table_name("admin_log")] (datetime, round_id, adminckey, adminip, operation, target, log)
		VALUES (NOW(), :round_id, :adminckey, INET_ATON(:adminip), '[PERMISSIONS_ACTION_RANK_REMOVED]', :admin_rank, CONCAT('Rank removed: ', :admin_rank))
	"}, list("round_id" = "[GLOB.round_id]", "adminckey" = usr.ckey, "adminip" = usr.client.address, "admin_rank" = admin_rank))

/// Changes the flags on either a DB or local rank
/// Edits one of the rank's flag sets per use (a prompt flow: both questions are asked, and every
/// check re-run, before anything changes).
/datum/admins/proc/change_rank(admin_rank)
	if(!admin_rank)
		return
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(change_rank), args)
	if(!check_rights(R_PERMISSIONS))
		message_admins("[key_name_admin(usr)] attempted to edit rank permissions without sufficient rights.")
		log_admin("[key_name(usr)] attempted to edit rank permissions without sufficient rights.")
		return
	if(IsAdminAdvancedProcCall())
		to_chat(usr, span_adminprefix("Rank Edit blocked: Advanced ProcCall detected."), confidential = TRUE)
		return
	var/datum/asset/permissions_assets = get_asset_datum(/datum/asset/simple/namespaced/common)
	permissions_assets.send(usr.client)

	var/list/datum/admin_rank/target_ranks = ranks_from_rank_name(admin_rank)
	if (!target_ranks || length(target_ranks) > 1)
		return
	var/datum/admin_rank/target_rank = target_ranks[1]
	if(target_rank.name != admin_rank) // Somehow
		to_chat(usr, span_adminprefix("Passed rank does not match target, somehow."), confidential = TRUE)
		return
	if((target_rank.rights & usr.client.holder.can_edit_rights_flags()) != target_rank.rights)
		to_chat(usr, span_adminprefix("You don't have edit rights to all the rights this rank has, you aren't allowed to modify it."), confidential = TRUE)
		return

	var/attempt_db = FALSE
	switch(target_rank.source)
		if(RANK_SOURCE_LOCAL)
			to_chat(usr, span_adminprefix("Localhost rank cannot be modified."), confidential = TRUE)
			return
		// This handles protected ranks on its own
		if(RANK_SOURCE_TXT)
			to_chat(usr, span_adminprefix("Text ranks cannot be meaningfully modified, go modify admin_ranks.txt"), confidential = TRUE)
			return
		if(RANK_SOURCE_BACKUP)
			to_chat(usr, span_adminprefix("Backup ranks cannot usefully be modified, as they are stored in a temp json, go uh... edit that? I guess?."), confidential = TRUE)
			return
		// For completeness
		if(RANK_SOURCE_TEMPORARY)
			attempt_db = FALSE
		if(RANK_SOURCE_DB)
			if(!check_rights(R_DBRANKS, FALSE))
				message_admins("[key_name_admin(usr)] attempted to edit db rank permissions without sufficient rights.")
				log_admin("[key_name(usr)] attempted to edit db rank permissions without sufficient rights.")
				return
			attempt_db = TRUE

	// We do not block editing ranks on protected admins which are not also protected
	// This means an admin could in theory bypass protections if they modified a linked rank (such as game admin) which is not also protected
	// It might be wise to make the permissions afforded by protected ranks inviolable. I'm unsure.
	if(CONFIG_GET(flag/load_legacy_ranks_only))
		to_chat(usr, span_adminprefix("Database rank loading is disabled, only temporary changes can be made to a rank's permissions."), confidential = TRUE)
		attempt_db = FALSE

	var/use_db = FALSE
	if(attempt_db)
		if(!SSdbcore.Connect())
			to_chat(usr, span_danger("Unable to connect to database, canceling."), confidential = TRUE)
			return
		use_db = TRUE

	// Similarly, I want to shit check flags. This is sort of... paranoid but I want to be careful here
	var/working_rights = NONE
	var/working_exclude_rights = NONE
	var/working_can_edit_rights = NONE

	// Not allowed to permenantly edit a rank if it isn't IN the db already
	// This is a real shitcheck but just to be sure
	if(use_db)
		var/datum/db_query/query_db_rank_info = SSdbcore.NewQuery({"
			SELECT flags, exclude_flags, can_edit_flags FROM [format_table_name("admin_ranks")]
			WHERE rank = :rank_name
		"}, list("rank_name" = admin_rank))
		if(!query_db_rank_info.warn_execute())
			qdel(query_db_rank_info)
		if(query_db_rank_info.NextRow())
			working_rights = query_db_rank_info.item[1]
			working_exclude_rights = query_db_rank_info.item[2]
			working_can_edit_rights = query_db_rank_info.item[3]
		else // Couldn't find anything, no db memes then
			to_chat(usr, span_adminprefix("Rank does not exist in database, exiting."), confidential = TRUE)
			qdel(query_db_rank_info)
			return
		QDEL_NULL(query_db_rank_info)
	else
		working_rights = target_rank.include_rights
		working_exclude_rights = target_rank.exclude_rights
		working_can_edit_rights = target_rank.can_edit_rights

	// One edit per use: the flow re-runs this proc for each answer, so a loop would replay edits.
	for(var/pass in 1 to 1)
		var/what_to_edit = flow_ask(usr, "what", /datum/om/prompt/choice, message = "What do you want to edit", title = "Rank Editing", choices = list("Rights", "Excluded Rights", "Edit Rights", "Finished"))
		var/existing_flags = NONE
		var/pretty_name
		switch(what_to_edit)
			if("Rights")
				existing_flags = working_rights
				pretty_name = "rights"
			if("Excluded Rights")
				existing_flags = working_exclude_rights
				pretty_name = "excluded rights"
			if("Edit Rights")
				existing_flags = working_can_edit_rights
				pretty_name = "editing rights"
			else
				return
		var/new_flags = flow_ask(usr, "flags:[what_to_edit]", /datum/om/prompt/bitfield, title = "Editing [target_rank.name] [what_to_edit]", bitfield = "admin_flags", default = existing_flags, editable = usr.client.holder.can_edit_rights_flags())
		if(isnull(new_flags))
			return

		// Gotta turn it off and on again
		var/list/datum/admins/impacted_admins_to_client = list()
		for(var/admin_key in GLOB.admin_datums)
			var/datum/admins/checking = GLOB.admin_datums[admin_key]
			if(!checking.owner())
				continue
			if(!(target_rank in checking.ranks))
				continue
			impacted_admins_to_client[checking] = checking.owner()
			checking.disassociate()

		switch(what_to_edit)
			if("Rights")
				target_rank.include_rights = new_flags
				working_rights = new_flags
			if("Excluded Rights")
				target_rank.exclude_rights = new_flags
				working_exclude_rights = new_flags
			if("Edit Rights")
				target_rank.can_edit_rights = new_flags
				working_can_edit_rights = new_flags

		var/log = "[key_name(usr)] has [use_db ? "permenantly" : "temporarially"] updated the [pretty_name] of the [admin_rank] rank to [rights2text(new_flags)]"
		message_admins(log)
		log_admin(log)

		for(var/datum/admins/modified as anything in impacted_admins_to_client)
			modified.associate(impacted_admins_to_client[modified])

		if(!use_db)
			continue

		// Only one at a time to avoid carrying over temp changes
		// Doing it as we are does technically mean conflicts can occur, but that's rare enough I'm ok with it
		switch(what_to_edit)
			if("Rights")
				om_sql_write({"
					UPDATE [format_table_name("admin_ranks")]
					SET flags = :flags
					WHERE rank = :rank_name
				"}, list("rank_name" = admin_rank, "flags" = new_flags))
			if("Excluded Rights")
				om_sql_write({"
					UPDATE [format_table_name("admin_ranks")]
					SET exclude_flags = :exclude_flags
					WHERE rank = :rank_name
				"}, list("rank_name" = admin_rank, "exclude_flags" = new_flags))
			if("Edit Rights")
				om_sql_write({"
					UPDATE [format_table_name("admin_ranks")]
					SET can_edit_flags = :can_edit_flags
					WHERE rank = :rank_name
				"}, list("rank_name" = admin_rank, "can_edit_flags" = new_flags))


		om_sql_write({"
			INSERT INTO [format_table_name("admin_log")] (datetime, round_id, adminckey, adminip, operation, target, log)
			VALUES (NOW(), :round_id, :adminckey, INET_ATON(:adminip), '[PERMISSIONS_ACTION_RANK_CHANGED]', :admin_rank, CONCAT('Rank changed: ', :admin_rank))
		"}, list("round_id" = "[GLOB.round_id]", "adminckey" = usr.ckey, "adminip" = usr.client.address, "admin_rank" = admin_rank))

/datum/admins/proc/sync_lastadminrank(admin_ckey, admin_key, datum/admins/target_holder)
	var/sqlrank = "Player"
	if (target_holder)
		sqlrank = target_holder.rank_names()
	om_io(null, /datum/om/io/sql,
		"UPDATE [format_table_name("erro_player")] SET lastadminrank = :rank WHERE ckey = :ckey",
		list("rank" = sqlrank, "ckey" = admin_ckey),
		/proc/sync_lastadminrank_done, usr?.ckey, admin_key)

/// om_io() callback: tells the admin who asked how the sync went.
/proc/sync_lastadminrank_done(list/result, error, asker_ckey, admin_key)
	var/client/C = GLOB.directory[asker_ckey]
	if(error)
		log_sql("[error] | sync_lastadminrank of [admin_key]")
		if(C)
			to_chat(C, span_danger("A SQL error occurred during this operation, check the server logs."), confidential = TRUE)
		return
	if(C)
		to_chat(C, span_admin("Sync of [admin_key] successful."), confidential = TRUE)

#undef PERMISSIONS_LOGS_PER_PAGE
