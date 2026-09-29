// Structured TGUI replacements for several read-only / list-style admin panels.
//
// Each panel datum is keyed per-host (or per-user for user-owned reports).
// All clicks act() back to the host's existing Topic handler so the legacy
// dispatch logic stays put — we only restructure the rendering.

// ---- Mind: show_memory (player-facing memory viewer) ----------------------

/datum/mind/proc/dq_open_memory_panel(mob/recipient)
	if(!recipient)
		return
	var/datum/mind_memory_panel/panel = new(src, recipient)
	panel.tgui_interact(recipient)

/datum/mind_memory_panel
	var/tmp/source_handle
	var/tmp/recipient_handle

/datum/mind_memory_panel/New(datum/mind/src_mind, mob/recipient_mob)
	..()
	source_handle = om_handle(src_mind)
	recipient_handle = om_handle(recipient_mob)

/datum/mind_memory_panel/tgui_state(mob/user)
	return GLOB.tgui_always_state

DECLARE_UI(/datum/mind_memory_panel, "MindMemory", UI_TITLE("Memory"))

/datum/mind_memory_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(user != recipient())
		return FALSE
	return TRUE

/datum/mind_memory_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!source())
		return data
	data["name"] = source().current ? source().current.real_name : (source().name || "(unknown)")
	data["memory"] = source().memory || ""
	data["ambitions"] = source().ambitions || ""
	var/list/objectives = list()
	for(var/datum/objective/O in source().objectives)
		objectives += list(list("text" = O.explanation_text))
	data["objectives"] = objectives
	return data

/datum/mind/show_memory(mob/recipient)
	dq_open_memory_panel(recipient)

// ---- Tag Menu (admin tagged-datums list) ---------------------------------

/datum/admins/proc/dq_open_tag_menu(mob/user)
	if(!user)
		return
	var/datum/tag_menu_panel/panel = new(src)
	panel.tgui_interact(user)

/datum/tag_menu_panel
	var/tmp/holder_handle

/datum/tag_menu_panel/New(datum/admins/owner_holder)
	..()
	holder_handle = om_handle(owner_holder)

/datum/tag_menu_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN)

DECLARE_UI(/datum/tag_menu_panel, "TagMenu", UI_TITLE("Tag Menu"))

/datum/tag_menu_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!holder())
		return data
	var/list/rows = list()
	var/list/tagged_datums = holder().tagged_datums
	var/datum/marked_datum = holder().marked_datum()
	var/index = 0
	for(var/datum/d as anything in tagged_datums)
		index++
		var/area_coord = ""
		var/health_info = ""
		var/atom/atom_d = istype(d, /atom) ? d : null
		if(atom_d)
			area_coord = "[AREACOORD(atom_d)]"
		if(isliving(d))
			var/mob/living/L = d
			health_info = "Vitality: [round(L.vitality() * 100)]%"
		rows += list(list(
			"index" = index,
			"ref" = REF(d),
			"name" = "[d]",
			"type" = "[d.type]",
			"area_coord" = area_coord,
			"health" = health_info,
			"is_marked" = (d == marked_datum),
		))
	data["entries"] = rows
	return data

/datum/tag_menu_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!holder())
		return FALSE
	return TRUE

UI_ACT(/datum/tag_menu_panel, "refresh", ui_act_refresh)
UI_ACT_PROC(/datum/tag_menu_panel, ui_act_refresh)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/tag_menu_panel, "untag", ui_act_untag, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/tag_menu_panel, ui_act_untag)
	var/ref = "[params["ref"]]"
	holder().topic_internal(ui.user, list("_src_" = "holder", "del_tag" = ref))
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/tag_menu_panel, "mark", ui_act_mark, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/tag_menu_panel, ui_act_mark)
	var/ref = "[params["ref"]]"
	holder().topic_internal(ui.user, list("_src_" = "holder", "mark_datum" = ref))
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/tag_menu_panel, "vv", ui_act_vv, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/tag_menu_panel, ui_act_vv)
	var/ref = "[params["ref"]]"
	ui.user.client?.vv_topic(list("Vars" = ref), TRUE)
	return TRUE

UI_ACT(/datum/tag_menu_panel, "pp", ui_act_pp, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/tag_menu_panel, ui_act_pp)
	var/ref = "[params["ref"]]"
	holder().topic_internal(ui.user, list("_src_" = "holder", "playerpanel" = ref))
	return TRUE

UI_ACT(/datum/tag_menu_panel, "follow", ui_act_follow, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/tag_menu_panel, ui_act_follow)
	var/ref = "[params["ref"]]"
	holder().topic_internal(ui.user, list("_src_" = "holder", "adminobs" = ref))
	return TRUE

// ---- ToRban list ---------------------------------------------------------

/datum/dq_torban_panel
	var/list/addresses

/datum/dq_torban_panel/New(list/addr)
	..()
	addresses = addr || list()

/datum/dq_torban_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_SERVER)

DECLARE_UI(/datum/dq_torban_panel, "TorbanList", UI_TITLE("Torban"))

/datum/dq_torban_panel/tgui_data(mob/user)
	return list("addresses" = addresses || list())

// ---- Admin Investigate log viewer ----------------------------------------

/datum/dq_investigate_panel
	var/subject = ""
	var/log_text = ""

/datum/dq_investigate_panel/New(subj, text)
	..()
	subject = subj
	log_text = text

/datum/dq_investigate_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_MOD|R_SERVER)

DECLARE_UI(/datum/dq_investigate_panel, "InvestigateLog")

/datum/dq_investigate_panel/ui_title(mob/user)
	return "Investigate: [subject]"

/datum/dq_investigate_panel/tgui_data(mob/user)
	return list(
		"subject" = subject,
		"log_text" = log_text,
	)

// ---- NewBan Unban panel --------------------------------------------------

/datum/admins/proc/dq_open_unban_panel(mob/user)
	if(!user)
		return
	var/datum/unban_panel/panel = new(src)
	panel.tgui_interact(user)

/datum/unban_panel
	var/tmp/holder_handle
	var/list/shown_rows

/datum/unban_panel/New(datum/admins/owner_holder)
	..()
	holder_handle = om_handle(owner_holder)

/datum/unban_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN)

DECLARE_UI(/datum/unban_panel, "UnbanPanel", UI_TITLE("Unban"))

/datum/unban_panel/ui_opening(mob/user, datum/tgui/ui)
	snapshot_bans()

/datum/unban_panel/proc/snapshot_bans()
	shown_rows = list()
	if(!GLOB.banlist)
		return
	// GLOB.banlist is a shared savefile cursor — record the prior cd
	// and restore it after the snapshot so concurrent ban operations
	// don't see a drifted current-directory.
	var/prior_cd = GLOB.banlist.cd
	GLOB.banlist.cd = "/base"
	for(var/A in GLOB.banlist.dir)
		GLOB.banlist.cd = "/base/[A]"
		var/key = GLOB.banlist["key"]
		var/id = GLOB.banlist["id"]
		var/ip = GLOB.banlist["ip"]
		var/reason = GLOB.banlist["reason"]
		var/by = GLOB.banlist["bannedby"]
		var/expiry
		if(GLOB.banlist["temp"])
			var/raw_min = GLOB.banlist["minutes"]
			if(raw_min >= 1440)
				expiry = "[round(raw_min / 1440, 0.1)] Days"
			else if(raw_min >= 60)
				expiry = "[round(raw_min / 60, 0.1)] Hours"
			else
				expiry = "[raw_min] Minutes"
		else
			expiry = "Permaban"
		shown_rows += list(list(
			"key_id" = "[key][id]",
			"key" = "[key]",
			"id" = "[id]",
			"ip" = "[ip]",
			"reason" = "[reason]",
			"by" = "[by]",
			"expiry" = "[expiry]",
		))
	GLOB.banlist.cd = prior_cd

/datum/unban_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!holder())
		return data
	data["bans"] = shown_rows || list()
	data["count"] = length(shown_rows)
	return data

/datum/unban_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!holder())
		return FALSE
	return TRUE

UI_ACT(/datum/unban_panel, "refresh", ui_act_refresh)
UI_ACT_PROC(/datum/unban_panel, ui_act_refresh)
	snapshot_bans()
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/unban_panel, "unban", ui_act_unban, UI_ARG_TEXT("key_id"))
UI_ACT_PROC(/datum/unban_panel, ui_act_unban)
	var/key_id = "[params["key_id"]]"
	holder().topic_internal(ui.user, list("unbanf" = key_id))
	snapshot_bans()
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/unban_panel, "edit", ui_act_edit, UI_ARG_TEXT("key_id"))
UI_ACT_PROC(/datum/unban_panel, ui_act_edit)
	var/key_id = "[params["key_id"]]"
	holder().topic_internal(ui.user, list("unbane" = key_id))
	snapshot_bans()
	SStgui.update_uis(src)
	return TRUE

// (newbanjob unjobbanpanel was dead code — file not in DME; no panel here.)

// ---- Job-Ban Panel (admin) ----------------------------------------------

GLOBAL_LIST_EMPTY(dq_jobban_panels)

/datum/admins/proc/dq_open_jobban_panel(mob/target)
	if(!owner()?.mob || !target)
		return
	var/key = "[REF(src)]-[REF(target)]"
	var/datum/jobban_panel/panel = LAZYACCESS(GLOB.dq_jobban_panels, key)
	if(!panel)
		panel = new(src, target)
		GLOB.dq_jobban_panels[key] = panel
	panel.tgui_interact(owner().mob)

/datum/jobban_panel
	var/tmp/holder_handle
	var/tmp/target_handle

/datum/jobban_panel/New(datum/admins/owner_holder, mob/target_mob)
	..()
	holder_handle = om_handle(owner_holder)
	target_handle = om_handle(target_mob)

// leaves the per-admin panel index.
/datum/jobban_panel/lifecycle_dematerialize()
	..()
	if(holder() && target())
		GLOB.dq_jobban_panels -= "[REF(holder())]-[REF(target())]"

/datum/jobban_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_MOD)

DECLARE_UI(/datum/jobban_panel, "JobBanPanel")

/datum/jobban_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!holder() || !target())
		return FALSE
	return TRUE

/datum/jobban_panel/ui_title(mob/user)
	return "Job-Ban Panel: [target().name]"

/proc/build_jobban_offmap_job_titles()
	var/list/titles = list()
	for(var/dept in GLOB.offmap_departments)
		for(var/jobPos in SSjob.get_job_titles_in_department(dept))
			if(!jobPos)
				continue
			var/datum/job/job = SSjob.get_job(jobPos)
			if(!job)
				continue
			titles += job.title
	return titles

GLOBAL_TABLE(jobban_offmap_job_titles, GLOBAL_PROC_REF(build_jobban_offmap_job_titles))

GLOBAL_LIST_INIT(jobban_dept_layout, list(
	list("title" = "Command Positions",     "color" = "#ccccff", "dept_bantype" = "commanddept",     "dept_const" = DEPARTMENT_COMMAND,     "extra_jobs" = null),
	list("title" = "Security Positions",    "color" = "#ffddf0", "dept_bantype" = "securitydept",    "dept_const" = DEPARTMENT_SECURITY,    "extra_jobs" = null),
	list("title" = "Engineering Positions", "color" = "#fff5cc", "dept_bantype" = "engineeringdept", "dept_const" = DEPARTMENT_ENGINEERING, "extra_jobs" = null),
	list("title" = "Cargo Positions",       "color" = "#fff5cc", "dept_bantype" = "cargodept",       "dept_const" = DEPARTMENT_CARGO,       "extra_jobs" = null),
	list("title" = "Medical Positions",     "color" = "#ffeef0", "dept_bantype" = "medicaldept",     "dept_const" = DEPARTMENT_MEDICAL,     "extra_jobs" = null),
	list("title" = "Science Positions",     "color" = "#e79fff", "dept_bantype" = "sciencedept",     "dept_const" = DEPARTMENT_RESEARCH,    "extra_jobs" = null),
	list("title" = "Exploration Positions", "color" = "#ebb8fc", "dept_bantype" = "explorationdept", "dept_const" = DEPARTMENT_PLANET,      "extra_jobs" = null),
))

/datum/jobban_panel/proc/get_dept_job_titles(dept_const)
	var/static/list/titles_by_dept
	if(!titles_by_dept)
		titles_by_dept = list()
	var/key = "[dept_const]"
	if(!titles_by_dept[key])
		var/list/cached = list()
		for(var/jobPos in SSjob.get_job_titles_in_department(dept_const))
			if(!jobPos)
				continue
			var/datum/job/job = SSjob.get_job(jobPos)
			if(!job)
				continue
			cached += job.title
		titles_by_dept[key] = cached
	return titles_by_dept[key]

/datum/jobban_panel/proc/build_dept_block(dept_const, dept_title, dept_bantype, color)
	var/list/jobs = list()
	for(var/title in get_dept_job_titles(dept_const))
		jobs += list(list(
			"title" = title,
			"is_banned" = !!jobban_isbanned(target(), title),
		))
	return list(
		"title" = dept_title,
		"color" = color,
		"dept_bantype" = dept_bantype,
		"is_dept_banned" = dept_bantype ? !!jobban_isbanned(target(), dept_bantype) : FALSE,
		"jobs" = jobs,
	)

/datum/jobban_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!target())
		return data
	data["target_name"] = target().name
	data["target_ref"] = "\ref[target()]"
	var/list/departments = list()
	for(var/list/layout_entry in GLOB.jobban_dept_layout)
		departments += list(build_dept_block(layout_entry["dept_const"], layout_entry["title"], layout_entry["dept_bantype"], layout_entry["color"]))

	// Offmap is the union of multiple departments.
	var/list/offmap_block_jobs = list()
	for(var/title in GLOBAL_TABLE_GET(jobban_offmap_job_titles))
		offmap_block_jobs += list(list(
			"title" = title,
			"is_banned" = !!jobban_isbanned(target(), title),
		))
	departments += list(list(
		"title" = "Offmap Positions",
		"color" = "#00ffff",
		"dept_bantype" = "offmapdept",
		"is_dept_banned" = !!jobban_isbanned(target(), "offmapdept"),
		"jobs" = offmap_block_jobs,
	))

	// Civilian block; the upstream panel also appended Internal Affairs Agent here.
	var/list/civilian = build_dept_block(DEPARTMENT_CIVILIAN, "Civilian Positions", "civiliandept", "#dddddd")
	var/list/civ_jobs = civilian["jobs"]
	civ_jobs += list(list(
		"title" = JOB_INTERNAL_AFFAIRS_AGENT,
		"is_banned" = !!jobban_isbanned(target(), JOB_INTERNAL_AFFAIRS_AGENT),
	))
	civilian["jobs"] = civ_jobs
	departments += list(civilian)
	departments += list(build_dept_block(DEPARTMENT_SYNTHETIC, "Synthetic Positions", "nonhumandept", "#ccffcc"))

	// Antagonist block — driven by the antag service, not by SSjob department.
	var/list/antag_jobs = list()
	var/dept_antag_ban = !!jobban_isbanned(target(), JOB_SYNDICATE)
	for(var/antag_type in GLOB.antag_service.all_antag_types)
		var/datum/antagonist/antag = GLOB.antag_service.all_antag_types[antag_type]
		if(!antag || !antag.bantype)
			continue
		antag_jobs += list(list(
			"title" = "[antag.bantype]",
			"display" = "[antag.role_text]",
			"is_banned" = !!jobban_isbanned(target(), "[antag.bantype]") || dept_antag_ban,
		))
	departments += list(list(
		"title" = "Antagonist Positions",
		"color" = "#ffeeaa",
		"dept_bantype" = "Syndicate",
		"is_dept_banned" = dept_antag_ban,
		"jobs" = antag_jobs,
	))

	// Misc roles.
	var/static/list/misc_roles = list(JOB_DIONAEA, JOB_GRAFFITI, JOB_CUSTOM_LOADOUT, JOB_PAI, JOB_GHOSTROLES, JOB_ANTAGHUD)
	var/list/misc_jobs = list()
	for(var/entry in misc_roles)
		misc_jobs += list(list(
			"title" = entry,
			"is_banned" = !!jobban_isbanned(target(), entry),
		))
	departments += list(list(
		"title" = "Other Roles",
		"color" = "#ccccff",
		"dept_bantype" = null,
		"is_dept_banned" = FALSE,
		"jobs" = misc_jobs,
	))

	data["departments"] = departments
	return data

/datum/jobban_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!holder() || !target())
		return FALSE
	return TRUE

UI_ACT(/datum/jobban_panel, "toggle_job", ui_act_toggle_job, UI_ARG_TEXT("title"))
UI_ACT_PROC(/datum/jobban_panel, ui_act_toggle_job)
	var/title = "[params["title"]]"
	// use REF() macro (canonical form) instead of legacy \ref[target] interpolation.
	holder().topic_internal(ui.user, list("_src_" = "holder", "jobban3" = title, "jobban4" = REF(target())))
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/jobban_panel, "toggle_dept", ui_act_toggle_dept, UI_ARG_TEXT("bantype"))
UI_ACT_PROC(/datum/jobban_panel, ui_act_toggle_dept)
	var/bantype = "[params["bantype"]]"
	holder().topic_internal(ui.user, list("_src_" = "holder", "jobban3" = bantype, "jobban4" = REF(target())))
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/jobban_panel, "refresh", ui_act_refresh)
UI_ACT_PROC(/datum/jobban_panel, ui_act_refresh)
	SStgui.update_uis(src)
	return TRUE

// ---- Vending log viewer --------------------------------------------------

/datum/dq_vending_log_panel
	var/machine_name = ""
	var/user_name = ""
	var/list/entries

/datum/dq_vending_log_panel/New(mach_name, viewer_name, list/log_entries)
	..()
	machine_name = mach_name
	user_name = viewer_name
	entries = log_entries || list()

/datum/dq_vending_log_panel/tgui_state(mob/user)
	return GLOB.tgui_default_state

DECLARE_UI(/datum/dq_vending_log_panel, "VendingLog")

/datum/dq_vending_log_panel/ui_title(mob/user)
	return "[machine_name] Vending Log"

/datum/dq_vending_log_panel/tgui_data(mob/user)
	return list(
		"machine_name" = machine_name,
		"user_name" = user_name,
		"entries" = entries,
	)

// ZAS Variable Settings panel (/datum/vs_control + VsSettings.tsx) was the
// admin UI for the ZAS atmos engine's tunable knobs. The atmos engine moved
// from ZAS to LINDA, those knobs no longer exist, and the panel's data
// source (settings, plc.settings, plc.vars) is gone. Block removed.

// ---- admin_verbs Delete Book (library admin) -----------------------------

/datum/dq_delete_book_panel
	var/tmp/our_comp_handle
	var/list/books
	var/error_msg = ""

/datum/dq_delete_book_panel/New(obj/machinery/librarycomp/comp, list/book_rows, error)
	..()
	our_comp_handle = om_handle(comp)
	books = book_rows || list()
	error_msg = error || ""

/datum/dq_delete_book_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN)

DECLARE_UI(/datum/dq_delete_book_panel, "DeleteBookPanel", UI_TITLE("Delete Book"))

/datum/dq_delete_book_panel/tgui_data(mob/user)
	return list(
		"books" = books,
		"error" = error_msg,
		"sort_by" = our_comp() ? our_comp().sortby : "",
	)

/datum/dq_delete_book_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!our_comp())
		return FALSE
	return TRUE

UI_ACT(/datum/dq_delete_book_panel, "sort", ui_act_sort, UI_ARG_TEXT("by"))
UI_ACT_PROC(/datum/dq_delete_book_panel, ui_act_sort)
	var/by = "[params["by"]]"
	our_comp().tgui_act("sort", list("field" = by), ui, ui.state())
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/dq_delete_book_panel, "order_by_id", ui_act_order_by_id)
UI_ACT_PROC(/datum/dq_delete_book_panel, ui_act_order_by_id)
	our_comp().tgui_act("orderbyid", list(), ui, ui.state())
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/dq_delete_book_panel, "delete", ui_act_delete, UI_ARG_TEXT("id"))
UI_ACT_PROC(/datum/dq_delete_book_panel, ui_act_delete)
	var/id = "[params["id"]]"
	our_comp().tgui_act("delid", list("id" = id), ui, ui.state())
	SStgui.update_uis(src)
	return TRUE

// ---- Syndicate beacon (Virgo) --------------------------------------------

/obj/machinery/syndicate_beacon/virgo/tgui_state(mob/user)
	return GLOB.tgui_default_state

DECLARE_UI(/obj/machinery/syndicate_beacon/virgo, "SyndicateBeacon", UI_TITLE("Ominous Beacon"))

/obj/machinery/syndicate_beacon/virgo/tgui_data(mob/user)
	var/list/data = list()
	data["temp"] = temptext || ""
	data["selfdestructing"] = !!selfdestructing
	data["charges"] = charges
	if(ishuman(user) || isAI(user))
		data["recognized"] = !!is_special_character(user)
		data["connection_severed"] = (charges < 1) && !is_special_character(user)
		data["user_ref"] = "\ref[user]"
		data["user_name"] = user.name
		var/honorific = "Mr."
		if(user.gender == FEMALE)
			honorific = "Ms."
		data["honorific"] = honorific
	else
		data["recognized"] = FALSE
		data["connection_severed"] = TRUE
		data["user_ref"] = ""
		data["user_name"] = ""
		data["honorific"] = ""
	return data

UI_ACT(/obj/machinery/syndicate_beacon/virgo, "transfer_supplies", ui_act_transfer_supplies, UI_ARG_REF("mob_ref", "proc:ui_source_registry_members_registry_mobs", /mob))
UI_ACT_PROC(/obj/machinery/syndicate_beacon/virgo, ui_act_transfer_supplies)
	var/mob/M = params["mob_ref"]
	betraitor(ui.user, M)
	SStgui.update_uis(src)
	return TRUE

/// The list the UI_ARG_REF rows resolve refs in.
/obj/machinery/syndicate_beacon/virgo/proc/ui_source_registry_members_registry_mobs()
	return REGISTRY_MEMBERS(REGISTRY_MOBS)

/obj/machinery/syndicate_beacon/virgo/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/syndicate_beacon_virgo_use,
	)
	..()

/datum/interaction/machine_hand/ungated/syndicate_beacon_virgo_use
	id = "syndicate_beacon_virgo_use"
	name = "Use"
	effect = /obj/machinery/syndicate_beacon/virgo/proc/interaction_use

/obj/machinery/syndicate_beacon/virgo/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

/// LC-refs: the source this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/mind_memory_panel/proc/source() as /datum/mind
	return om_resolve(source_handle)

/// LC-refs: the recipient this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/mind_memory_panel/proc/recipient() as /mob
	return om_resolve(recipient_handle)

/// LC-refs: the our_comp this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/dq_delete_book_panel/proc/our_comp() as /obj/machinery/librarycomp
	return om_resolve(our_comp_handle)

/// LC-refs: the holder this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/tag_menu_panel/proc/holder() as /datum/admins
	return om_resolve(holder_handle)

/// LC-refs: the holder this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/unban_panel/proc/holder() as /datum/admins
	return om_resolve(holder_handle)

/// LC-refs: the holder this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/jobban_panel/proc/holder() as /datum/admins
	return om_resolve(holder_handle)

/// LC-refs: the target this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/jobban_panel/proc/target() as /mob
	return om_resolve(target_handle)
