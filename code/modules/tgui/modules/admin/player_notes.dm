#define PLAYER_NOTES_ENTRIES_PER_PAGE 50

/datum/tgui_module/player_notes
	name = "Player Notes"
	tgui_id = "PlayerNotes"

	var/ckeys = list()

	var/current_filter = ""
	var/current_page = 1

	var/number_pages = 0

/datum/tgui_module/player_notes/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		qdel(src)

/datum/tgui_module/player_notes/proc/filter_ckeys(page, filter, mob/user)
	var/savefile/S=new("data/player_notes.sav")
	var/list/note_keys
	S >> note_keys
	if(!note_keys)
		to_chat(user, "No notes found.")
	else
		note_keys = sortList(note_keys)

		if(filter)
			var/list/results = list()
			var/regex/needle = regex(filter, "i")
			for(var/haystack in note_keys)
				if(needle.Find(haystack))
					results += haystack
			note_keys = results

		// Display the notes on the current page
		number_pages = note_keys.len / PLAYER_NOTES_ENTRIES_PER_PAGE
		// Emulate CEILING(why does BYOND not have ceil, 1)
		if(number_pages != round(number_pages))
			number_pages = round(number_pages) + 1
		var/page_index = page - 1

		if(page_index < 0 || page_index >= number_pages)
			to_chat(user, "No keys found.")
		else
			var/lower_bound = page_index * PLAYER_NOTES_ENTRIES_PER_PAGE + 1
			var/upper_bound = (page_index + 1) * PLAYER_NOTES_ENTRIES_PER_PAGE
			upper_bound = min(upper_bound, note_keys.len)
			ckeys = list()
			for(var/index = lower_bound, index <= upper_bound, index++)
				ckeys += note_keys[index]

	current_filter = filter

/datum/tgui_module/player_notes/proc/open_legacy(mob/user)
	var/datum/admins/A = GLOB.admin_datums[user.ckey]
	A.PlayerNotesLegacy(user)

DECLARE_UI_STATE(/datum/tgui_module/player_notes, ADMIN_STATE(R_ADMIN|R_MOD|R_EVENT|R_DEBUG))

/datum/tgui_module/player_notes/tgui_fallback(payload, mob/user)
	if(..())
		return TRUE

	open_legacy(user)

UI_ACT(/datum/tgui_module/player_notes, "show_player_info", ui_act_show_player_info, UI_ARG_TEXT("name"))
UI_ACT_PROC(/datum/tgui_module/player_notes, ui_act_show_player_info)
	var/datum/tgui_module/player_notes_info/A = new(src)
	A.key = params["name"]
	A.tgui_interact(ui.user)

UI_ACT(/datum/tgui_module/player_notes, "filter_player_notes", ui_act_filter_player_notes)
UI_ACT_PROC(/datum/tgui_module/player_notes, ui_act_filter_player_notes)
	var/input = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/text, message = "Filter string (case-insensitive regex)", title = "Player notes filter")
	if(isnull(input))
		return
	current_filter = input

UI_ACT(/datum/tgui_module/player_notes, "set_page", ui_act_set_page, UI_ARG_NUM("index"))
UI_ACT_PROC(/datum/tgui_module/player_notes, ui_act_set_page)
	var/page = params["index"]
	current_page = page

UI_ACT(/datum/tgui_module/player_notes, "clear_player_info_filter", ui_act_clear_player_info_filter)
UI_ACT_PROC(/datum/tgui_module/player_notes, ui_act_clear_player_info_filter)
	current_filter = ""

UI_ACT(/datum/tgui_module/player_notes, "open_legacy_ui", ui_act_open_legacy_ui)
UI_ACT_PROC(/datum/tgui_module/player_notes, ui_act_open_legacy_ui)
	open_legacy(ui.user)

UI_DATA_REPLACE(/datum/tgui_module/player_notes, "filter=current_filter:text", "merge:ui_data_datum_tgui_module_player_notes{ckeys:list,pages:num}")

/// The computed part of /datum/tgui_module/player_notes's window data (declared on its UI_DATA row).
/datum/tgui_module/player_notes/proc/ui_data_datum_tgui_module_player_notes(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	filter_ckeys(current_page, current_filter, user)
	data["ckeys"] = list()
	data["pages"] = number_pages + 1

	for(var/ckey in ckeys)
		data["ckeys"] += list(list(
				"name" = ckey
			))

	return data

// PLAYER NOTES INFO
/datum/tgui_module/player_notes_info
	name = "Player Notes Info"
	tgui_id = "PlayerNotesInfo"

	var/key = null

/datum/tgui_module/player_notes_info/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		qdel(src)

DECLARE_UI_STATE(/datum/tgui_module/player_notes_info, ADMIN_STATE(R_ADMIN|R_MOD|R_EVENT|R_DEBUG))

/datum/tgui_module/player_notes_info/tgui_fallback(payload, mob/user)
	if(..())
		return TRUE

	var/datum/admins/A = GLOB.admin_datums[user.ckey]
	A.show_player_info_legacy(user, key)

UI_ACT(/datum/tgui_module/player_notes_info, "cahngekey", ui_act_cahngekey, UI_ARG_TEXT("ckey"))
UI_ACT_PROC(/datum/tgui_module/player_notes_info, ui_act_cahngekey)
	key = sanitize(params["ckey"])
	return TRUE

UI_ACT(/datum/tgui_module/player_notes_info, "add_player_info", ui_act_add_player_info, UI_ARG_TEXT("ckey"))
UI_ACT_PROC(/datum/tgui_module/player_notes_info, ui_act_add_player_info)
	var/key = params["ckey"]
	var/add = act_ask(ui.user, action, params, ui, "a2", /datum/om/prompt/text, message = "Write your comment below.", title = "Add Player Info", multiline = TRUE, max_length = MAX_TGUI_INPUT)
	if(isnull(add))
		return
	if(!add)
		return FALSE

	notes_add(key,add,ui.user)
	return TRUE

UI_ACT(/datum/tgui_module/player_notes_info, "remove_player_info", ui_act_remove_player_info, UI_ARG_TEXT("ckey"), UI_ARG_NUM("index"))
UI_ACT_PROC(/datum/tgui_module/player_notes_info, ui_act_remove_player_info)
	var/key = params["ckey"]
	var/index = params["index"]

	notes_del(key, index, ui.user)
	return TRUE

UI_DATA_REPLACE(/datum/tgui_module/player_notes_info, "ckey=key:text", "merge:ui_data_datum_tgui_module_player_notes_info{entries:list,age:text}")

/// The computed part of /datum/tgui_module/player_notes_info's window data (declared on its UI_DATA row).
/datum/tgui_module/player_notes_info/proc/ui_data_datum_tgui_module_player_notes_info(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	if(!key)
		return data

	var/p_age = "unknown"
	for(var/client/C in GLOB.clients)
		if(C.ckey == key)
			p_age = C.player_age
			break

	data["entries"] = list()

	var/savefile/info = new("data/player_saves/[copytext(key, 1, 2)]/[key]/info.sav")
	var/list/infos
	info >> infos
	if(infos)
		var/update_file = 0
		var/i = 0
		for(var/datum/player_info/I in infos)
			i += 1
			if(!I.timestamp)
				I.timestamp = "Pre-4/3/2012"
				update_file = 1
			if(!I.rank)
				I.rank = "N/A"
				update_file = 1

			data["entries"] += list(list(
					"comment" = I.content,
					"author" = "[I.author] ([I.rank])",
					"date" = "[I.timestamp]"
				))
		if(update_file) info << infos

	data["age"] = p_age

	return data

// ==== LEGACY UI ====

/datum/admins/proc/PlayerNotesLegacy(mob/user)
	PlayerNotesPageLegacy(1, null, user)

/datum/admins/proc/PlayerNotesFilterLegacy(mob/user)
	var/filter = rerun_ask(user, "a1", PROC_REF(PlayerNotesFilterLegacy), args, /datum/om/prompt/text, message = "Filter string (case-insensitive regex)", title = "Player notes filter")
	if(isnull(filter))
		return
	PlayerNotesPageLegacy(1, filter, user)

/datum/admins/proc/PlayerNotesPageLegacy(page, filter, mob/user)
	var/dat = span_bold("Player notes") + " - <a href='byond://?src=\ref[src];[HrefToken()];notes_legacy=filter'>Apply Filter</a><HR>"
	var/savefile/S=new("data/player_notes.sav")
	var/list/note_keys
	S >> note_keys
	if(!note_keys)
		dat += "No notes found."
	else
		dat += "<table>"
		note_keys = sortList(note_keys)

		if(filter)
			var/list/results = list()
			var/regex/needle = regex(filter, "i")
			for(var/haystack in note_keys)
				if(needle.Find(haystack))
					results += haystack
			note_keys = results

		// Display the notes on the current page
		var/number_pages = note_keys.len / PLAYER_NOTES_ENTRIES_PER_PAGE
		// Emulate CEILING(why does BYOND not have ceil, 1)
		if(number_pages != round(number_pages))
			number_pages = round(number_pages) + 1
		var/page_index = page - 1

		if(page_index < 0 || page_index >= number_pages)
			dat += "<tr><td>No keys found.</td></tr>"
		else
			var/lower_bound = page_index * PLAYER_NOTES_ENTRIES_PER_PAGE + 1
			var/upper_bound = (page_index + 1) * PLAYER_NOTES_ENTRIES_PER_PAGE
			upper_bound = min(upper_bound, note_keys.len)
			for(var/index = lower_bound, index <= upper_bound, index++)
				var/t = note_keys[index]
				dat += "<tr><td><a href='byond://?src=\ref[src];[HrefToken()];notes_legacy=show;ckey=[t]'>[t]</a></td></tr>"

		dat += "</table><hr>"

		// Display a footer to select different pages
		for(var/index = 1, index <= number_pages, index++)
			dat += "<a href='byond://?src=\ref[src];[HrefToken()];notes_legacy=list;index=[index];filter=[filter ? url_encode(filter) : 0]'>[index]</a> "
			if(index == page)
				dat = span_bold(dat)

	// structured TGUI AdminReport.
	dq_admin_report_html(user, "Admin Playernotes", dat, src)

/datum/admins/proc/player_has_info_legacy(key as text)
	var/savefile/info = new("data/player_saves/[copytext(key, 1, 2)]/[key]/info.sav")
	var/list/infos
	info >> infos
	if(!infos || !infos.len) return 0
	else return 1

/datum/admins/proc/show_player_info_legacy(mob/user, key)
	var/dat = ""

	var/p_age = "unknown"
	for(var/client/C in GLOB.clients)
		if(C.ckey == key)
			p_age = C.player_age
			break
	dat += span_black(span_bold("Player age: [p_age]")) + "<br>"

	var/savefile/info = new("data/player_saves/[copytext(key, 1, 2)]/[key]/info.sav")
	var/list/infos
	info >> infos
	if(!infos)
		dat += "No information found on the given key.<br>"
	else
		var/update_file = 0
		var/i = 0
		for(var/datum/player_info/I in infos)
			i += 1
			if(!I.timestamp)
				I.timestamp = "Pre-4/3/2012"
				update_file = 1
			if(!I.rank)
				I.rank = "N/A"
				update_file = 1
			dat += span_green("[I.content]") + " " + span_italics("by [I.author] ([I.rank])") + " on " + span_italics(span_blue("[I.timestamp]")) + " "
			if(I.author == user.key || I.author == "Adminbot" || ishost(user))
				dat += "<A href='byond://?src=\ref[src];[HrefToken()];remove_player_info_legacy=[key];remove_index=[i]'>Remove</A>"
			dat += "<br><br>"
		if(update_file) info << infos

	dat += "<br>"
	dat += "<A href='byond://?src=\ref[src];[HrefToken()];add_player_info_legacy=[key]'>Add Comment</A><br>"

	// structured TGUI AdminReport.
	dq_admin_report_html(user, "Info on [key]", dat, src)

TOPIC_ACTION(/datum/admins, "add_player_info_legacy", PROC_REF(topic_add_player_info_legacy), TOPIC_TEXT("add_player_info_legacy", 64), TOPIC_RIGHTS(R_ADMIN|R_MOD))
TOPIC_ACTION(/datum/admins, "remove_player_info_legacy", PROC_REF(topic_remove_player_info_legacy), TOPIC_TEXT("remove_player_info_legacy", 64), TOPIC_NUM("remove_index"), TOPIC_RIGHTS(R_ADMIN|R_MOD))
TOPIC_ACTION(/datum/admins, "notes_legacy=show", PROC_REF(topic_notes_legacy_show), TOPIC_TEXT("ckey", 64), TOPIC_REF("mob", /mob, TOPIC_IN_MOBS), TOPIC_RIGHTS(R_ADMIN|R_MOD))
TOPIC_ACTION(/datum/admins, "notes_legacy=list", PROC_REF(topic_notes_legacy_list), TOPIC_NUM("index"), TOPIC_TEXT("filter", 256), TOPIC_RIGHTS(R_ADMIN|R_MOD))
TOPIC_ACTION(/datum/admins, "notes_legacy=filter", PROC_REF(topic_notes_legacy_filter), TOPIC_RIGHTS(R_ADMIN|R_MOD))

/datum/admins/proc/topic_add_player_info_legacy(mob/user, list/args)
	var/key = args["add_player_info_legacy"]
	var/add = topic_ask(user, args, "a1", /datum/om/prompt/text, message = "Add Player Info (Legacy)", multiline = TRUE)
	if(isnull(add))
		return
	if(!add)
		return
	notes_add(key, add, user)
	show_player_info_legacy(user, key)
	return TRUE

/datum/admins/proc/topic_remove_player_info_legacy(mob/user, list/args)
	var/key = args["remove_player_info_legacy"]
	notes_del(key, args["remove_index"], user)
	show_player_info_legacy(user, key)
	return TRUE

/datum/admins/proc/topic_notes_legacy_show(mob/user, list/args)
	var/ckey = args["ckey"]
	if(!ckey)
		var/mob/M = args["mob"]
		ckey = M?.ckey
	show_player_info_legacy(user, ckey)
	return TRUE

/datum/admins/proc/topic_notes_legacy_list(mob/user, list/args)
	var/filter
	if(args["filter"] && args["filter"] != "0")
		filter = url_decode(args["filter"])
	PlayerNotesPageLegacy(args["index"], filter, user)
	return TRUE

/datum/admins/proc/topic_notes_legacy_filter(mob/user, list/args)
	PlayerNotesFilterLegacy(user)
	return TRUE

#undef PLAYER_NOTES_ENTRIES_PER_PAGE
