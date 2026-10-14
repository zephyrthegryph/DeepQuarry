// Permissions Panel — structured TGUI replacement for the 1200-line legacy
// admin_log_show HTML panel.

// local copy of PERMISSIONS_LOGS_PER_PAGE. The original is defined
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
	var/client/panel_owner = owner()
	if(!admin_require(panel_owner, R_PERMISSIONS, "permissions.panel"))
		return
	if(!panel_owner?.mob)
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
		rel_set(src, nameof(dq_permissions_panel), new /datum/permissions_panel(src))
	dq_permissions_panel.tgui_interact(panel_owner.mob)
	SStgui.update_uis(dq_permissions_panel)
	dq_permissions_panel.refresh_db()

/datum/permissions_panel
	var/tmp/datum/admins/holder
	/// The database rows the pages show, by query key (om_sql_view); a missing key is loading.
	var/list/db_rows

/// Fetches the current page's database rows (io_job: nothing waits); tgui_data shows what has
/// arrived and the rest as loading.
/datum/permissions_panel/proc/refresh_db()
	if(!holder() || !SSdbcore.IsConnected())
		return
	db_rows = null
	switch(holder().dq_perms_page)
		if(PERMISSIONS_PAGE_RANKS, PERMISSIONS_PAGE_HOUSEKEEPING)
			sql_view(src, "admins", "SELECT IFNULL((SELECT ckey FROM [format_table_name("erro_player")] WHERE [format_table_name("erro_player")].ckey = [format_table_name("admin")].ckey), ckey), [format_table_name("admin")].`rank` FROM [format_table_name("admin")]", PROC_REF(sql_rows_arrived))
			sql_view(src, "ranks", "SELECT rank, flags, exclude_flags, can_edit_flags FROM [format_table_name("admin_ranks")]", PROC_REF(sql_rows_arrived))
		if(PERMISSIONS_PAGE_LOGGING)
			var/list/filter = list("target" = holder().dq_perms_log_target, "adminckey" = holder().dq_perms_log_actor, "operation" = holder().dq_perms_log_operation)
			sql_view(src, "log_count", {"
				SELECT COUNT(id) FROM [format_table_name("admin_log")]
				WHERE target LIKE CONCAT('%',:target,'%')
					AND adminckey LIKE CONCAT('%',:adminckey,'%')
					AND (:operation IS NULL OR operation = :operation)
				"}, filter, PROC_REF(sql_rows_arrived))
			var/list/search_args = filter.Copy()
			search_args["skip"] = PERMISSIONS_LOGS_PER_PAGE * holder().dq_perms_log_page
			search_args["take"] = PERMISSIONS_LOGS_PER_PAGE
			sql_view(src, "log_search", {"
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
			"}, search_args, PROC_REF(sql_rows_arrived))

/// The rows arrive for whoever still has the panel and the rights to see it.
/datum/permissions_panel/proc/sql_rows_arrived(list/result, error, key)
	var/list/rows = sql_view_rows(result, error, key, src)
	if(!holder()?.owner() || !check_rights_for(holder().owner(), R_PERMISSIONS))
		return
	if(error)
		to_chat(holder().owner(), span_danger("A SQL error occurred during this operation, check the server logs."), confidential = TRUE)
	LAZYSET(db_rows, key, rows || list())
	SStgui.update_uis(src)

/datum/permissions_panel/New(datum/admins/owner_holder)
	..()
	rel_set(src, nameof(holder), owner_holder)

// clears its holder's cached panel.

CAPABILITIES(/datum/permissions_panel)
	interface("PermissionsPanel", title = "Permissions", rights = R_PERMISSIONS)
	op("nav_permissions", ui_act("nav_permissions"), then(PROC_REF(ui_act_nav_permissions)))
	op("nav_ranks", ui_act("nav_ranks"), then(PROC_REF(ui_act_nav_ranks)))
	op("nav_logging", ui_act("nav_logging"), then(PROC_REF(ui_act_nav_logging)))
	op("nav_housekeeping", ui_act("nav_housekeeping"), then(PROC_REF(ui_act_nav_housekeeping)))
	op("admin_add", ui_act("admin_add"), then(PROC_REF(ui_act_admin_add)))
	op("admin_remove", ui_act("admin_remove", arg("key", schema_text(4096))), then(PROC_REF(ui_act_admin_remove)))
	op("admin_rank", ui_act("admin_rank", arg("key", schema_text(4096))), then(PROC_REF(ui_act_admin_rank)))
	op("admin_permissions", ui_act("admin_permissions", arg("key", schema_text(4096))), then(PROC_REF(ui_act_admin_permissions)))
	op("admin_activate", ui_act("admin_activate", arg("key", schema_text(4096))), then(PROC_REF(ui_act_admin_activate)))
	op("admin_deactivate", ui_act("admin_deactivate", arg("key", schema_text(4096))), then(PROC_REF(ui_act_admin_deactivate)))
	op("admin_sync", ui_act("admin_sync", arg("key", schema_text(4096))), then(PROC_REF(ui_act_admin_sync)))
	op("ranks_create", ui_act("ranks_create"), then(PROC_REF(ui_act_ranks_create)))
	op("ranks_edit", ui_act("ranks_edit", arg("name", schema_text(4096))), then(PROC_REF(ui_act_ranks_edit)))
	op("ranks_delete", ui_act("ranks_delete", arg("name", schema_text(4096))), then(PROC_REF(ui_act_ranks_delete)))
	op("log_search", ui_act("log_search", arg("actor", schema_text(4096)), arg("operation", schema_text(4096)), arg("target", schema_text(4096))), then(PROC_REF(ui_act_log_search)))
	op("log_page", ui_act("log_page", arg("page", num())), then(PROC_REF(ui_act_log_page)))
	op("housekeep_change", ui_act("housekeep_change", arg("admin", schema_text(4096))), then(PROC_REF(ui_act_housekeep_change)))
	op("housekeep_remove_admin", ui_act("housekeep_remove_admin", arg("admin", schema_text(4096))), then(PROC_REF(ui_act_housekeep_remove_admin)))
	op("housekeep_remove_rank", ui_act("housekeep_remove_rank", arg("name", schema_text(4096))), then(PROC_REF(ui_act_housekeep_remove_rank)))

/datum/permissions_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!holder())
		return FALSE
	return TRUE

/datum/permissions_panel/proc/page_data_permissions()
	var/list/rows = list()
	for(var/admin_ckey in GLOB.admin_datums + GLOB.deadmins)
		var/datum/admins/admin_datum = GLOB.admin_datums[admin_ckey]
		if(!admin_datum)
			admin_datum = GLOB.deadmins[admin_ckey]
			if(!admin_datum)
				continue
		var/display_ckey = admin_ckey
		if(admin_datum.owner())
			display_ckey = admin_datum.owner().key
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
	for(var/list/row as anything in db_rows?["admins"])
		var/admin_rank_text = row[2]
		for(var/datum/admin_rank/composed_rank as anything in ranks_from_rank_name(admin_rank_text))
			admins_by_rank[composed_rank.name] ||= list()
			admins_by_rank[composed_rank.name] |= list(row[1])
	for(var/stored_key in GLOB.admin_datums)
		var/datum/admins/live_holder = GLOB.admin_datums[stored_key]
		for(var/datum/admin_rank/composed_rank as anything in live_holder.ranks)
			admins_by_rank[composed_rank.name] ||= list()
			admins_by_rank[composed_rank.name] |= list(stored_key)

	// Collect rank rows from DB + live datums (DB is source of truth where it has the rank).
	var/list/all_ranks = list()
	for(var/list/row as anything in db_rows?["ranks"])
		all_ranks[row[1]] = list(
			"rank" = row[1],
			"flags" = text2num("[row[2]]"),
			"exclude_flags" = text2num("[row[3]]"),
			"can_edit_flags" = text2num("[row[4]]"),
		)
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
		if((holder().can_edit_rights_flags() & rank_datum.rights) != rank_datum.rights)
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
	data["loading"] = !db_rows || isnull(db_rows["admins"]) || isnull(db_rows["ranks"])
	data["can_create"] = check_rights(R_PERMISSIONS) && holder().can_edit_rights_flags() != NONE
	return data

/datum/permissions_panel/proc/page_data_logging()
	var/list/data = list()
	data["log_target"] = holder().dq_perms_log_target
	data["log_actor"] = holder().dq_perms_log_actor
	data["log_operation"] = holder().dq_perms_log_operation || PERMISSIONS_ACTION_NONE
	data["log_page"] = holder().dq_perms_log_page
	data["action_options"] = GLOB.permission_action_types.Copy()

	var/log_count = 0
	var/list/count_rows = db_rows?["log_count"]
	if(length(count_rows))
		var/list/count_row = count_rows[1]
		log_count = text2num("[count_row[1]]")
	data["log_count"] = log_count
	data["per_page"] = PERMISSIONS_LOGS_PER_PAGE

	var/list/entries = list()
	for(var/list/row as anything in db_rows?["log_search"])
		entries += list(list(
			"datetime" = row[1],
			"round_id" = "[row[2]]",
			"admin_key" = row[3],
			"operation" = row[4],
			"ckey_actioned" = row[5],
			"log" = row[6],
		))
	data["loading"] = !db_rows || isnull(db_rows["log_search"])
	data["entries"] = entries
	return data

/datum/permissions_panel/proc/page_data_housekeeping()
	var/list/data = list()
	var/list/admins_by_rank = list()
	for(var/list/row as anything in db_rows?["admins"])
		var/admin_rank_text = row[2]
		for(var/datum/admin_rank/composed_rank as anything in ranks_from_rank_name(admin_rank_text))
			admins_by_rank[composed_rank.name] += list(row[1])

	var/list/all_db_ranks = list()
	for(var/list/row as anything in db_rows?["ranks"])
		all_db_ranks[row[1]] = list(
			"rank" = row[1],
			"flags" = "[row[2]]",
			"exclude_flags" = "[row[3]]",
			"can_edit_flags" = "[row[4]]",
		)
	data["loading"] = !db_rows || isnull(db_rows["admins"]) || isnull(db_rows["ranks"])

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
		if((holder().can_edit_rights_flags() & rank_datum.rights) == rank_datum.rights)
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

/// /datum/permissions_panel's window data.
/datum/permissions_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(!holder())
		return data
	data["page"] = holder().dq_perms_page || PERMISSIONS_PAGE_PERMISSIONS
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
	forward_holder_topic(holder(), qs)

/datum/permissions_panel/proc/ui_gate(datum/act/op/A)
	if(!holder())
		return FALSE
	return TRUE

/datum/permissions_panel/proc/ui_act_nav_permissions(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	forward_topic("editrightsbrowser=1")
	return TRUE

/datum/permissions_panel/proc/ui_act_nav_ranks(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	forward_topic("editrightsbrowserranks=1")
	return TRUE

/datum/permissions_panel/proc/ui_act_nav_logging(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	forward_topic("editrightsbrowserlogging=1;editrightslogpage=0")
	return TRUE

/datum/permissions_panel/proc/ui_act_nav_housekeeping(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	forward_topic("editrightsbrowserhousekeep=1")
	return TRUE

// Permissions page row actions.

/datum/permissions_panel/proc/ui_act_admin_add(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	forward_topic("editrights=add")
	return TRUE

/datum/permissions_panel/proc/ui_act_admin_remove(datum/act/op/A, key_arg)
	if(!ui_gate(A))
		return FALSE
	var/key = "[key_arg]"
	forward_topic("editrights=remove;key=[key]")
	return TRUE

/datum/permissions_panel/proc/ui_act_admin_rank(datum/act/op/A, key_arg)
	if(!ui_gate(A))
		return FALSE
	var/key = "[key_arg]"
	forward_topic("editrights=rank;key=[key]")
	return TRUE

/datum/permissions_panel/proc/ui_act_admin_permissions(datum/act/op/A, key_arg)
	if(!ui_gate(A))
		return FALSE
	var/key = "[key_arg]"
	forward_topic("editrights=permissions;key=[key]")
	return TRUE

/datum/permissions_panel/proc/ui_act_admin_activate(datum/act/op/A, key_arg)
	if(!ui_gate(A))
		return FALSE
	var/key = "[key_arg]"
	forward_topic("editrights=activate;key=[key]")
	return TRUE

/datum/permissions_panel/proc/ui_act_admin_deactivate(datum/act/op/A, key_arg)
	if(!ui_gate(A))
		return FALSE
	var/key = "[key_arg]"
	forward_topic("editrights=deactivate;key=[key]")
	return TRUE

/datum/permissions_panel/proc/ui_act_admin_sync(datum/act/op/A, key_arg)
	if(!ui_gate(A))
		return FALSE
	var/key = "[key_arg]"
	forward_topic("editrights=sync;key=[key]")
	return TRUE
// Ranks page actions.

/datum/permissions_panel/proc/ui_act_ranks_create(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	forward_topic("editrightsbrowserranks=1;editrightsaddrank=1")
	return TRUE

/datum/permissions_panel/proc/ui_act_ranks_edit(datum/act/op/A, name_arg)
	if(!ui_gate(A))
		return FALSE
	var/name = "[name_arg]"
	forward_topic("editrightsbrowserranks=1;editrightseditrank=[name]")
	return TRUE

/datum/permissions_panel/proc/ui_act_ranks_delete(datum/act/op/A, name_arg)
	if(!ui_gate(A))
		return FALSE
	var/name = "[name_arg]"
	forward_topic("editrightsbrowserranks=1;editrightsremoverank=[name]")
	return TRUE
// Logging page actions.

/datum/permissions_panel/proc/ui_act_log_search(datum/act/op/A, actor, operation, target)
	if(!ui_gate(A))
		return FALSE
	holder().dq_perms_log_target = "[target]"
	holder().dq_perms_log_actor = "[actor]"
	var/op = "[operation]"
	if(op == PERMISSIONS_ACTION_NONE || op == "")
		holder().dq_perms_log_operation = null
	else
		holder().dq_perms_log_operation = op
	holder().dq_perms_log_page = 0
	refresh_db()
	SStgui.update_uis(src)
	return TRUE

/datum/permissions_panel/proc/ui_act_log_page(datum/act/op/A, page)
	if(!ui_gate(A))
		return FALSE
	holder().dq_perms_log_page = page || 0
	refresh_db()
	SStgui.update_uis(src)
	return TRUE
// Housekeeping page actions.

/datum/permissions_panel/proc/ui_act_housekeep_change(datum/act/op/A, admin_arg)
	if(!ui_gate(A))
		return FALSE
	var/admin = "[admin_arg]"
	forward_topic("editrightsbrowserhousekeep=1;editrightschange=[admin]")
	return TRUE

/datum/permissions_panel/proc/ui_act_housekeep_remove_admin(datum/act/op/A, admin_arg)
	if(!ui_gate(A))
		return FALSE
	var/admin = "[admin_arg]"
	forward_topic("editrightsbrowserhousekeep=1;editrightsremove=[admin]")
	return TRUE

/datum/permissions_panel/proc/ui_act_housekeep_remove_rank(datum/act/op/A, name_arg)
	if(!ui_gate(A))
		return FALSE
	var/name = "[name_arg]"
	forward_topic("editrightsbrowserhousekeep=1;editrightsremoverank=[name]")
	return TRUE


/// The holder this refers to (a relation view: null once that is deleted).
/datum/permissions_panel/proc/holder() as /datum/admins
	return holder

// The admin holder owns this panel (dq_permissions_panel); holder is a plain relation back.
