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
	var/datum/mind/source
	var/mob/recipient

/datum/mind_memory_panel/New(datum/mind/src_mind, mob/recipient_mob)
	..()
	source = src_mind
	recipient = recipient_mob

/datum/mind_memory_panel/Destroy(force, ...)
	source = null
	recipient = null
	return ..()

/datum/mind_memory_panel/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/mind_memory_panel/tgui_interact(mob/user, datum/tgui/ui)
	if(user != recipient)
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "MindMemory", "Memory")
		ui.open()

/datum/mind_memory_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!source)
		return data
	data["name"] = source.current ? source.current.real_name : (source.name || "(unknown)")
	data["memory"] = source.memory || ""
	data["ambitions"] = source.ambitions || ""
	var/list/objectives = list()
	for(var/datum/objective/O in source.objectives)
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
	var/datum/admins/holder

/datum/tag_menu_panel/New(datum/admins/owner_holder)
	..()
	holder = owner_holder

/datum/tag_menu_panel/Destroy(force, ...)
	holder = null
	return ..()

/datum/tag_menu_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN)

/datum/tag_menu_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "TagMenu", "Tag Menu")
		ui.open()

/datum/tag_menu_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!holder)
		return data
	var/list/rows = list()
	var/list/tagged_datums = holder.tagged_datums
	var/datum/marked_datum = holder.marked_datum
	var/index = 0
	for(var/datum/d as anything in tagged_datums)
		index++
		var/area_coord = ""
		var/health_info = ""
		var/atom/atom_d = istype(d, /atom) ? d : null
		if(atom_d)
			area_coord = "[AREACOORD(atom_d)]"
		if(iscarbon(d))
			var/mob/living/carbon/c = d
			health_info = "Health: [c.health]"
		else if(isliving(d))
			var/mob/living/L = d
			health_info = "Health: [L.health]"
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

/datum/tag_menu_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(. || !holder)
		return
	var/ref = "[params["ref"]]"
	switch(action)
		if("refresh")
			SStgui.update_uis(src)
			return TRUE
		if("untag")
			holder.Topic("del_tag=[ref]", list("_src_" = "holder", "del_tag" = ref))
			SStgui.update_uis(src)
			return TRUE
		if("mark")
			holder.Topic("mark_datum=[ref]", list("_src_" = "holder", "mark_datum" = ref))
			SStgui.update_uis(src)
			return TRUE
		if("vv")
			holder.Topic("Vars=[ref]", list("_src_" = "vars", "Vars" = ref))
			return TRUE
		if("pp")
			holder.Topic("priv_msg=[ref]", list("_src_" = "holder", "playerpanel" = ref))
			return TRUE
		if("follow")
			holder.Topic("adminmoreinfo=[ref]", list("_src_" = "holder", "adminobs" = ref))
			return TRUE

// ---- ToRban list ---------------------------------------------------------

/datum/dq_torban_panel
	var/list/addresses

/datum/dq_torban_panel/New(list/addr)
	..()
	addresses = addr || list()

/datum/dq_torban_panel/Destroy(force, ...)
	addresses = null
	return ..()

/datum/dq_torban_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_SERVER)

/datum/dq_torban_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "TorbanList", "Torban")
		ui.open()

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

/datum/dq_investigate_panel/Destroy(force, ...)
	subject = null
	log_text = null
	return ..()

/datum/dq_investigate_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_MOD|R_SERVER)

/datum/dq_investigate_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "InvestigateLog", "Investigate: [subject]")
		ui.open()

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
	var/datum/admins/holder
	var/list/cached_rows

/datum/unban_panel/New(datum/admins/owner_holder)
	..()
	holder = owner_holder

/datum/unban_panel/Destroy(force, ...)
	holder = null
	cached_rows = null
	return ..()

/datum/unban_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN)

/datum/unban_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		snapshot_bans()
		ui = new(user, src, "UnbanPanel", "Unban")
		ui.open()

/datum/unban_panel/proc/snapshot_bans()
	cached_rows = list()
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
		cached_rows += list(list(
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
	if(!holder)
		return data
	data["bans"] = cached_rows || list()
	data["count"] = length(cached_rows)
	return data

/datum/unban_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(. || !holder)
		return
	var/key_id = "[params["key_id"]]"
	switch(action)
		if("refresh")
			snapshot_bans()
			SStgui.update_uis(src)
			return TRUE
		if("unban")
			holder.Topic("unbanf=[key_id]", list("unbanf" = key_id))
			snapshot_bans()
			SStgui.update_uis(src)
			return TRUE
		if("edit")
			holder.Topic("unbane=[key_id]", list("unbane" = key_id))
			snapshot_bans()
			SStgui.update_uis(src)
			return TRUE

// (newbanjob unjobbanpanel was dead code — file not in DME; no panel here.)

// ---- Job-Ban Panel (admin) ----------------------------------------------

GLOBAL_LIST_EMPTY(dq_jobban_panels)

/datum/admins/proc/dq_open_jobban_panel(mob/target)
	if(!owner || !target)
		return
	var/key = "[REF(src)]-[REF(target)]"
	var/datum/jobban_panel/panel = LAZYACCESS(GLOB.dq_jobban_panels, key)
	if(!panel)
		panel = new(src, target)
		GLOB.dq_jobban_panels[key] = panel
	panel.tgui_interact(owner)

/datum/jobban_panel
	var/datum/admins/holder
	var/mob/target

/datum/jobban_panel/New(datum/admins/owner_holder, mob/target_mob)
	..()
	holder = owner_holder
	target = target_mob

/datum/jobban_panel/Destroy(force, ...)
	if(holder && target)
		GLOB.dq_jobban_panels -= "[REF(holder)]-[REF(target)]"
	holder = null
	target = null
	return ..()

/datum/jobban_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_MOD)

/datum/jobban_panel/tgui_interact(mob/user, datum/tgui/ui)
	if(!holder || !target)
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "JobBanPanel", "Job-Ban Panel: [target.name]")
		ui.open()

/datum/jobban_panel/proc/get_offmap_job_titles()
	var/static/list/titles
	if(titles)
		return titles
	titles = list()
	for(var/dept in GLOB.offmap_departments)
		for(var/jobPos in SSjob.get_job_titles_in_department(dept))
			if(!jobPos)
				continue
			var/datum/job/job = SSjob.get_job(jobPos)
			if(!job)
				continue
			titles += job.title
	return titles

/datum/jobban_panel/proc/get_dept_layout()
	var/static/list/layout
	if(layout)
		return layout
	layout = list(
		list("title" = "Command Positions",     "color" = "#ccccff", "dept_bantype" = "commanddept",     "dept_const" = DEPARTMENT_COMMAND,     "extra_jobs" = null),
		list("title" = "Security Positions",    "color" = "#ffddf0", "dept_bantype" = "securitydept",    "dept_const" = DEPARTMENT_SECURITY,    "extra_jobs" = null),
		list("title" = "Engineering Positions", "color" = "#fff5cc", "dept_bantype" = "engineeringdept", "dept_const" = DEPARTMENT_ENGINEERING, "extra_jobs" = null),
		list("title" = "Cargo Positions",       "color" = "#fff5cc", "dept_bantype" = "cargodept",       "dept_const" = DEPARTMENT_CARGO,       "extra_jobs" = null),
		list("title" = "Medical Positions",     "color" = "#ffeef0", "dept_bantype" = "medicaldept",     "dept_const" = DEPARTMENT_MEDICAL,     "extra_jobs" = null),
		list("title" = "Science Positions",     "color" = "#e79fff", "dept_bantype" = "sciencedept",     "dept_const" = DEPARTMENT_RESEARCH,    "extra_jobs" = null),
		list("title" = "Exploration Positions", "color" = "#ebb8fc", "dept_bantype" = "explorationdept", "dept_const" = DEPARTMENT_PLANET,      "extra_jobs" = null),
	)
	return layout

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
			"is_banned" = !!jobban_isbanned(target, title),
		))
	return list(
		"title" = dept_title,
		"color" = color,
		"dept_bantype" = dept_bantype,
		"is_dept_banned" = dept_bantype ? !!jobban_isbanned(target, dept_bantype) : FALSE,
		"jobs" = jobs,
	)

/datum/jobban_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!target)
		return data
	data["target_name"] = target.name
	data["target_ref"] = "\ref[target]"
	var/list/departments = list()
	for(var/list/layout_entry in get_dept_layout())
		departments += list(build_dept_block(layout_entry["dept_const"], layout_entry["title"], layout_entry["dept_bantype"], layout_entry["color"]))

	// Offmap is the union of multiple departments.
	var/list/offmap_block_jobs = list()
	for(var/title in get_offmap_job_titles())
		offmap_block_jobs += list(list(
			"title" = title,
			"is_banned" = !!jobban_isbanned(target, title),
		))
	departments += list(list(
		"title" = "Offmap Positions",
		"color" = "#00ffff",
		"dept_bantype" = "offmapdept",
		"is_dept_banned" = !!jobban_isbanned(target, "offmapdept"),
		"jobs" = offmap_block_jobs,
	))

	// Civilian block; the upstream panel also appended Internal Affairs Agent here.
	var/list/civilian = build_dept_block(DEPARTMENT_CIVILIAN, "Civilian Positions", "civiliandept", "#dddddd")
	var/list/civ_jobs = civilian["jobs"]
	civ_jobs += list(list(
		"title" = JOB_INTERNAL_AFFAIRS_AGENT,
		"is_banned" = !!jobban_isbanned(target, JOB_INTERNAL_AFFAIRS_AGENT),
	))
	civilian["jobs"] = civ_jobs
	departments += list(civilian)
	departments += list(build_dept_block(DEPARTMENT_SYNTHETIC, "Synthetic Positions", "nonhumandept", "#ccffcc"))

	// Antagonist block — driven by SSantag_job, not by SSjob department.
	var/list/antag_jobs = list()
	var/dept_antag_ban = !!jobban_isbanned(target, JOB_SYNDICATE)
	for(var/antag_type in SSantag_job.all_antag_types)
		var/datum/antagonist/antag = SSantag_job.all_antag_types[antag_type]
		if(!antag || !antag.bantype)
			continue
		antag_jobs += list(list(
			"title" = "[antag.bantype]",
			"display" = "[antag.role_text]",
			"is_banned" = !!jobban_isbanned(target, "[antag.bantype]") || dept_antag_ban,
		))
	departments += list(list(
		"title" = "Antagonist Positions",
		"color" = "#ffeeaa",
		"dept_bantype" = "Syndicate",
		"is_dept_banned" = dept_antag_ban,
		"jobs" = antag_jobs,
	))

	// Misc roles.
	var/list/misc_roles = list(JOB_DIONAEA, JOB_GRAFFITI, JOB_CUSTOM_LOADOUT, JOB_PAI, JOB_GHOSTROLES, JOB_ANTAGHUD)
	var/list/misc_jobs = list()
	for(var/entry in misc_roles)
		misc_jobs += list(list(
			"title" = entry,
			"is_banned" = !!jobban_isbanned(target, entry),
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

/datum/jobban_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(. || !holder || !target)
		return
	switch(action)
		if("toggle_job")
			var/title = "[params["title"]]"
			// use REF() macro (canonical form) instead of legacy \ref[target] interpolation.
			holder.Topic("jobban3=[title];jobban4=[REF(target)]", list("_src_" = "holder", "jobban3" = title, "jobban4" = REF(target)))
			SStgui.update_uis(src)
			return TRUE
		if("toggle_dept")
			var/bantype = "[params["bantype"]]"
			holder.Topic("jobban3=[bantype];jobban4=[REF(target)]", list("_src_" = "holder", "jobban3" = bantype, "jobban4" = REF(target)))
			SStgui.update_uis(src)
			return TRUE
		if("refresh")
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

/datum/dq_vending_log_panel/Destroy(force, ...)
	entries = null
	return ..()

/datum/dq_vending_log_panel/tgui_state(mob/user)
	return GLOB.tgui_default_state

/datum/dq_vending_log_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "VendingLog", "[machine_name] Vending Log")
		ui.open()

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
	var/obj/machinery/librarycomp/our_comp
	var/list/books
	var/error_msg = ""

/datum/dq_delete_book_panel/New(obj/machinery/librarycomp/comp, list/book_rows, error)
	..()
	our_comp = comp
	books = book_rows || list()
	error_msg = error || ""

/datum/dq_delete_book_panel/Destroy(force, ...)
	our_comp = null
	books = null
	return ..()

/datum/dq_delete_book_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN)

/datum/dq_delete_book_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "DeleteBookPanel", "Delete Book")
		ui.open()

/datum/dq_delete_book_panel/tgui_data(mob/user)
	return list(
		"books" = books,
		"error" = error_msg,
		"sort_by" = our_comp ? our_comp.sortby : "",
	)

/datum/dq_delete_book_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(. || !our_comp)
		return
	switch(action)
		if("sort")
			var/by = "[params["by"]]"
			our_comp.Topic("sort=[by]", list("our_comp" = "\ref[our_comp]", "sort" = by))
			SStgui.update_uis(src)
			return TRUE
		if("order_by_id")
			our_comp.Topic("orderbyid=1", list("our_comp" = "\ref[our_comp]", "orderbyid" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("delete")
			var/id = "[params["id"]]"
			our_comp.Topic("delid=[id]", list("our_comp" = "\ref[our_comp]", "delid" = id))
			SStgui.update_uis(src)
			return TRUE

// ---- Syndicate beacon (Virgo) --------------------------------------------

/obj/machinery/syndicate_beacon/virgo/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/machinery/syndicate_beacon/virgo/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "SyndicateBeacon", "Ominous Beacon")
		ui.open()

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

/obj/machinery/syndicate_beacon/virgo/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(action == "transfer_supplies")
		var/ref = "[params["mob_ref"]]"
		Topic("betraitor=1;traitormob=[ref]", list("betraitor" = "1", "traitormob" = ref))
		SStgui.update_uis(src)
		return TRUE

/obj/machinery/syndicate_beacon/virgo/attack_hand(mob/user)
	user.set_machine(src)
	tgui_interact(user)

