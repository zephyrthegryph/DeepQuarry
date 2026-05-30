// Permissions Panel — structured TGUI replacement for the 1200-line legacy
// admin_log_show HTML panel.

// DQEdit — local copy of PERMISSIONS_LOGS_PER_PAGE. The original is defined
// inside permissionedit.dm where it was used in the now-removed proc body,
// and DM macros are file-scope so we can't see it from here.
#define PERMISSIONS_LOGS_PER_PAGE 20
//
// All four pages (Permissions / Ranks / Logging / Housekeeping) are rendered
// from typed tgui_data. Actions dispatch back to the existing
// /datum/admins.Topic handlers (editrightsbrowser*, editrights*, editrights*)
// via _src_=holder so the legacy add/remove/sync/rank/permissions flows and
// the DB writes they trigger continue to work unchanged.
//
// The Logging page's search filters and pagination live on the panel datum
// (per /datum/admins, since the legacy proc stored them in href params and
// re-rendered). Each refresh re-runs the DB queries — same as before, just
// with typed output instead of HTML.

/datum/admins
	/// Active page on the structured permissions panel.
	var/dq_perms_page = null
	/// Logging-page filter: ckey of the player who was acted on.
	var/dq_perms_log_target = ""
	/// Logging-page filter: ckey of the admin who acted.
	var/dq_perms_log_actor = ""
	/// Logging-page filter: operation enum value, or null for "all".
	var/dq_perms_log_operation = null
	/// Logging-page paged offset (page index, 0-based).
	var/dq_perms_log_page = 0
	/// Cached panel datum (lazy).
	var/datum/permissions_panel/dq_permissions_panel

GLOBAL_LIST_EMPTY(dq_permissions_panels)

/datum/admins/proc/edit_admin_permissions(action, log_target, log_actor, log_operation, log_page)
	if(!check_rights(R_PERMISSIONS))
		return
	if(!owner)
		return
	dq_perms_page = action || PERMISSIONS_PAGE_PERMISSIONS
	if(dq_perms_page == PERMISSIONS_PAGE_LOGGING)
		dq_perms_log_target = log_target || ""
		dq_perms_log_actor = log_actor || ""
		var/op = log_operation
		if(op == PERMISSIONS_ACTION_NONE)
			op = null
		dq_perms_log_operation = op
		dq_perms_log_page = text2num(log_page) || 0
	if(!dq_permissions_panel)
		dq_permissions_panel = new(src)
	if(QDELETED(usr) || usr.client != owner)
		dq_permissions_panel.tgui_interact(owner)
	else
		dq_permissions_panel.tgui_interact(usr)
		SStgui.update_uis(dq_permissions_panel)

/datum/permissions_panel
	var/datum/admins/holder

/datum/permissions_panel/New(datum/admins/owner_holder)
	holder = owner_holder

/datum/permissions_panel/Destroy(force, ...)
	if(holder)
		holder.dq_permissions_panel = null
	holder = null
	return ..()

/datum/permissions_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_PERMISSIONS)

/datum/permissions_panel/tgui_interact(mob/user, datum/tgui/ui)
	if(!holder)
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PermissionsPanel", "Permissions")
		ui.open()

/datum/permissions_panel/proc/page_data_permissions()
	var/list/rows = list()
	for(var/admin_ckey in GLOB.admin_datums + GLOB.deadmins)
		var/datum/admins/admin_datum = GLOB.admin_datums[admin_ckey]
		if(!admin_datum)
			admin_datum = GLOB.deadmins[admin_ckey]
			if(!admin_datum)
				continue
		var/display_ckey = admin_ckey
		if(admin_datum.owner)
			display_ckey = admin_datum.owner.key
		rows += list(list(
			"ckey" = display_ckey,
			"rank" = admin_datum.rank_names(),
			"permissions" = rights2text(admin_datum.rank_flags(), " "),
			"deadmined" = !!admin_datum.deadmined,
		))
	return rows

/datum/permissions_panel/proc/page_data_ranks()
	var/list/data = list()
	// Pull admin->rank mapping from DB to feed "held by" counts.
	var/list/admins_by_rank = list()
	var/datum/db_query/q_admins = SSdbcore.NewQuery("SELECT IFNULL((SELECT ckey FROM [format_table_name("erro_player")] WHERE [format_table_name("erro_player")].ckey = [format_table_name("admin")].ckey), ckey), [format_table_name("admin")].`rank` FROM [format_table_name("admin")]")
	if(q_admins.warn_execute())
		while(q_admins.NextRow())
			var/admin_rank_text = q_admins.item[2]
			for(var/datum/admin_rank/composed_rank as anything in ranks_from_rank_name(admin_rank_text))
				admins_by_rank[composed_rank.name] ||= list()
				admins_by_rank[composed_rank.name] |= list(q_admins.item[1])
	QDEL_NULL(q_admins)
	for(var/stored_key in GLOB.admin_datums)
		var/datum/admins/live_holder = GLOB.admin_datums[stored_key]
		for(var/datum/admin_rank/composed_rank as anything in live_holder.ranks)
			admins_by_rank[composed_rank.name] ||= list()
			admins_by_rank[composed_rank.name] |= list(stored_key)

	// Collect rank rows from DB + live datums (DB is source of truth where it has the rank).
	var/list/all_ranks = list()
	var/datum/db_query/q_ranks = SSdbcore.NewQuery("SELECT rank, flags, exclude_flags, can_edit_flags FROM [format_table_name("admin_ranks")]")
	if(q_ranks.warn_execute())
		while(q_ranks.NextRow())
			all_ranks[q_ranks.item[1]] = list(
				"rank" = q_ranks.item[1],
				"flags" = text2num(q_ranks.item[2]),
				"exclude_flags" = text2num(q_ranks.item[3]),
				"can_edit_flags" = text2num(q_ranks.item[4]),
			)
	QDEL_NULL(q_ranks)
	for(var/datum/admin_rank/rank as anything in GLOB.admin_ranks)
		if(all_ranks[rank.name])
			continue
		all_ranks[rank.name] = list(
			"rank" = rank.name,
			"flags" = rank.include_rights,
			"exclude_flags" = rank.exclude_rights,
			"can_edit_flags" = rank.can_edit_rights,
		)
	sortTim(all_ranks, GLOBAL_PROC_REF(cmp_text_asc), associative = TRUE)

	var/list/rows = list()
	for(var/rank_name in all_ranks)
		var/list/datum/admin_rank/rank_datums = ranks_from_rank_name(rank_name)
		if(!length(rank_datums))
			continue
		var/datum/admin_rank/rank_datum = rank_datums[1]
		var/list/rank_info = all_ranks[rank_name]
		var/can_modify = FALSE
		var/can_delete = FALSE
		if((rank_datum.source == RANK_SOURCE_DB && check_rights(R_DBRANKS)) || rank_datum.source == RANK_SOURCE_TEMPORARY)
			can_modify = TRUE
			can_delete = TRUE
		if(length(admins_by_rank[rank_name]) != 0)
			can_delete = FALSE
		if((holder.can_edit_rights_flags() & rank_datum.rights) != rank_datum.rights)
			can_modify = FALSE
			can_delete = FALSE
		rows += list(list(
			"name" = rank_name,
			"source" = rank_datum.pretty_print_source(),
			"held_by" = length(admins_by_rank[rank_name]),
			"permissions" = rights2text(rank_info["flags"], seperator = " ", prefix = "+"),
			"denied" = rights2text(rank_info["exclude_flags"], seperator = " ", prefix = "-"),
			"editable" = rights2text(rank_info["can_edit_flags"], seperator = " ", prefix = "*"),
			"can_modify" = !!can_modify,
			"can_delete" = !!can_delete,
		))
	data["rows"] = rows
	data["can_create"] = check_rights(R_PERMISSIONS) && holder.can_edit_rights_flags() != NONE
	return data

/datum/permissions_panel/proc/page_data_logging()
	var/list/data = list()
	data["log_target"] = holder.dq_perms_log_target
	data["log_actor"] = holder.dq_perms_log_actor
	data["log_operation"] = holder.dq_perms_log_operation || PERMISSIONS_ACTION_NONE
	data["log_page"] = holder.dq_perms_log_page
	data["action_options"] = GLOB.permission_action_types.Copy()

	var/log_count = 0
	var/datum/db_query/q_count = SSdbcore.NewQuery({"
		SELECT COUNT(id) FROM [format_table_name("admin_log")]
		WHERE target LIKE CONCAT('%',:target,'%')
			AND adminckey LIKE CONCAT('%',:adminckey,'%')
			AND (:operation IS NULL OR operation = :operation)
		"},
		list("target" = holder.dq_perms_log_target, "adminckey" = holder.dq_perms_log_actor, "operation" = holder.dq_perms_log_operation)
	)
	if(q_count.warn_execute() && q_count.NextRow())
		log_count = text2num(q_count.item[1])
	QDEL_NULL(q_count)
	data["log_count"] = log_count
	data["per_page"] = PERMISSIONS_LOGS_PER_PAGE

	var/list/entries = list()
	var/datum/db_query/q_search = SSdbcore.NewQuery({"
		SELECT
			datetime,
			round_id,
			IFNULL((SELECT ckey FROM [format_table_name("erro_player")] WHERE ckey = adminckey), adminckey),
			operation,
			IF(ckey IS NULL, target, ckey),
			log
		FROM [format_table_name("admin_log")]
		LEFT JOIN [format_table_name("erro_player")] ON target = ckey
		WHERE target LIKE CONCAT('%',:target,'%')
			AND adminckey LIKE CONCAT('%',:adminckey,'%')
			AND (:operation IS NULL OR operation = :operation)
		ORDER BY datetime DESC
		LIMIT :skip, :take
	"}, list(
		"target" = holder.dq_perms_log_target,
		"adminckey" = holder.dq_perms_log_actor,
		"operation" = holder.dq_perms_log_operation,
		"skip" = PERMISSIONS_LOGS_PER_PAGE * holder.dq_perms_log_page,
		"take" = PERMISSIONS_LOGS_PER_PAGE,
	))
	if(q_search.warn_execute())
		while(q_search.NextRow())
			entries += list(list(
				"datetime" = q_search.item[1],
				"round_id" = "[q_search.item[2]]",
				"admin_key" = q_search.item[3],
				"operation" = q_search.item[4],
				"ckey_actioned" = q_search.item[5],
				"log" = q_search.item[6],
			))
	QDEL_NULL(q_search)
	data["entries"] = entries
	return data

/datum/permissions_panel/proc/page_data_housekeeping()
	var/list/data = list()
	var/list/admins_by_rank = list()
	var/datum/db_query/q_admins = SSdbcore.NewQuery("SELECT IFNULL((SELECT ckey FROM [format_table_name("erro_player")] WHERE [format_table_name("erro_player")].ckey = [format_table_name("admin")].ckey), ckey), [format_table_name("admin")].`rank` FROM [format_table_name("admin")]")
	if(q_admins.warn_execute())
		while(q_admins.NextRow())
			var/admin_rank_text = q_admins.item[2]
			for(var/datum/admin_rank/composed_rank as anything in ranks_from_rank_name(admin_rank_text))
				admins_by_rank[composed_rank.name] += list(q_admins.item[1])
	QDEL_NULL(q_admins)

	var/list/all_db_ranks = list()
	var/datum/db_query/q_ranks = SSdbcore.NewQuery("SELECT rank, flags, exclude_flags, can_edit_flags FROM [format_table_name("admin_ranks")]")
	if(q_ranks.warn_execute())
		while(q_ranks.NextRow())
			all_db_ranks[q_ranks.item[1]] = list(
				"rank" = q_ranks.item[1],
				"flags" = q_ranks.item[2],
				"exclude_flags" = q_ranks.item[3],
				"can_edit_flags" = q_ranks.item[4],
			)
	QDEL_NULL(q_ranks)

	var/list/invalid_admin_rows = list()
	var/list/invalid_admin_ranks = admins_by_rank - all_db_ranks
	for(var/illegal_rank in invalid_admin_ranks)
		for(var/admin_ckey in admins_by_rank[illegal_rank])
			invalid_admin_rows += list(list(
				"admin" = admin_ckey,
				"rank" = illegal_rank,
			))
	data["invalid_admins"] = invalid_admin_rows

	var/list/unused_rank_rows = list()
	var/list/unused_ranks = all_db_ranks - admins_by_rank
	sortTim(unused_ranks, GLOBAL_PROC_REF(cmp_text_asc))
	for(var/unused_rank in unused_ranks)
		var/list/datum/admin_rank/rank_datums = ranks_from_rank_name(unused_rank)
		if(!length(rank_datums))
			continue
		var/datum/admin_rank/rank_datum = rank_datums[1]
		var/list/rank_info = all_db_ranks[unused_rank]
		var/can_delete = FALSE
		if(rank_datum.source == RANK_SOURCE_DB && check_rights(R_DBRANKS))
			can_delete = TRUE
		if((holder.can_edit_rights_flags() & rank_datum.rights) == rank_datum.rights)
			can_delete = FALSE
		unused_rank_rows += list(list(
			"name" = unused_rank,
			"source" = rank_datum.pretty_print_source(),
			"permissions" = rights2text(text2num(rank_info["flags"]), seperator = " ", prefix = "+"),
			"denied" = rights2text(text2num(rank_info["exclude_flags"]), seperator = " ", prefix = "-"),
			"editable" = rights2text(text2num(rank_info["can_edit_flags"]), seperator = " ", prefix = "*"),
			"can_delete" = !!can_delete,
		))
	data["unused_ranks"] = unused_rank_rows
	return data

/datum/permissions_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!holder)
		return data
	data["page"] = holder.dq_perms_page || PERMISSIONS_PAGE_PERMISSIONS
	data["PERMISSIONS_PAGE_PERMISSIONS"] = PERMISSIONS_PAGE_PERMISSIONS
	data["PERMISSIONS_PAGE_RANKS"] = PERMISSIONS_PAGE_RANKS
	data["PERMISSIONS_PAGE_LOGGING"] = PERMISSIONS_PAGE_LOGGING
	data["PERMISSIONS_PAGE_HOUSEKEEPING"] = PERMISSIONS_PAGE_HOUSEKEEPING
	switch(data["page"])
		if(PERMISSIONS_PAGE_PERMISSIONS)
			data["permissions_rows"] = page_data_permissions()
		if(PERMISSIONS_PAGE_RANKS)
			data["ranks_page"] = page_data_ranks()
		if(PERMISSIONS_PAGE_LOGGING)
			data["logging_page"] = page_data_logging()
		if(PERMISSIONS_PAGE_HOUSEKEEPING)
			data["housekeeping_page"] = page_data_housekeeping()
	return data

/datum/permissions_panel/proc/forward_topic(qs)
	forward_holder_topic(holder, qs)

/datum/permissions_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(. || !holder)
		return
	switch(action)
		// Page navigation.
		if("nav_permissions")
			forward_topic("editrightsbrowser=1")
			return TRUE
		if("nav_ranks")
			forward_topic("editrightsbrowserranks=1")
			return TRUE
		if("nav_logging")
			forward_topic("editrightsbrowserlogging=1;editrightslogpage=0")
			return TRUE
		if("nav_housekeeping")
			forward_topic("editrightsbrowserhousekeep=1")
			return TRUE
		// Permissions page row actions.
		if("admin_add")
			forward_topic("editrights=add")
			return TRUE
		if("admin_remove")
			var/key = "[params["key"]]"
			forward_topic("editrights=remove;key=[key]")
			return TRUE
		if("admin_rank")
			var/key = "[params["key"]]"
			forward_topic("editrights=rank;key=[key]")
			return TRUE
		if("admin_permissions")
			var/key = "[params["key"]]"
			forward_topic("editrights=permissions;key=[key]")
			return TRUE
		if("admin_activate")
			var/key = "[params["key"]]"
			forward_topic("editrights=activate;key=[key]")
			return TRUE
		if("admin_deactivate")
			var/key = "[params["key"]]"
			forward_topic("editrights=deactivate;key=[key]")
			return TRUE
		if("admin_sync")
			var/key = "[params["key"]]"
			forward_topic("editrights=sync;key=[key]")
			return TRUE
		// Ranks page actions.
		if("ranks_create")
			forward_topic("editrightsbrowserranks=1;editrightsaddrank=1")
			return TRUE
		if("ranks_edit")
			var/name = "[params["name"]]"
			forward_topic("editrightsbrowserranks=1;editrightseditrank=[name]")
			return TRUE
		if("ranks_delete")
			var/name = "[params["name"]]"
			forward_topic("editrightsbrowserranks=1;editrightsremoverank=[name]")
			return TRUE
		// Logging page actions.
		if("log_search")
			holder.dq_perms_log_target = "[params["target"]]"
			holder.dq_perms_log_actor = "[params["actor"]]"
			var/op = "[params["operation"]]"
			if(op == PERMISSIONS_ACTION_NONE || op == "")
				holder.dq_perms_log_operation = null
			else
				holder.dq_perms_log_operation = op
			holder.dq_perms_log_page = 0
			SStgui.update_uis(src)
			return TRUE
		if("log_page")
			holder.dq_perms_log_page = text2num(params["page"]) || 0
			SStgui.update_uis(src)
			return TRUE
		// Housekeeping page actions.
		if("housekeep_change")
			var/admin = "[params["admin"]]"
			forward_topic("editrightsbrowserhousekeep=1;editrightschange=[admin]")
			return TRUE
		if("housekeep_remove_admin")
			var/admin = "[params["admin"]]"
			forward_topic("editrightsbrowserhousekeep=1;editrightsremove=[admin]")
			return TRUE
		if("housekeep_remove_rank")
			var/name = "[params["name"]]"
			forward_topic("editrightsbrowserhousekeep=1;editrightsremoverank=[name]")
			return TRUE
