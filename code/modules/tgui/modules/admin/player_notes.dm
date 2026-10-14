#define PLAYER_NOTES_ENTRIES_PER_PAGE 50

/datum/tgui_module/player_notes
	name = "Player Notes"

	var/list/ckeys

	var/current_filter = ""
	var/current_page = 1

	var/number_pages = 0

/datum/tgui_module/player_notes/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		spent(src, user)

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
			ckeys = null
			for(var/index = lower_bound, index <= upper_bound, index++)
				LAZYADD(ckeys, note_keys[index])

	current_filter = filter

/datum/tgui_module/player_notes/proc/open_legacy(mob/user)
	var/datum/admins/A = GLOB.admin_datums[user.ckey]
	A.PlayerNotesLegacy(user)

CAPABILITIES(/datum/tgui_module/player_notes)
	interface("PlayerNotes", rights = R_ADMIN|R_MOD|R_EVENT|R_DEBUG)
	op("show_player_info", ui_act("show_player_info", arg("name", schema_text(4096))), then(PROC_REF(ui_act_show_player_info)))
	op("filter_player_notes", ui_act("filter_player_notes"), then(PROC_REF(ui_act_filter_player_notes)))
	op("set_page", ui_act("set_page", arg("index", num())), then(PROC_REF(ui_act_set_page)))
	op("clear_player_info_filter", ui_act("clear_player_info_filter"), then(PROC_REF(ui_act_clear_player_info_filter)))
	op("open_legacy_ui", ui_act("open_legacy_ui"), then(PROC_REF(ui_act_open_legacy_ui)))

/datum/tgui_module/player_notes/tgui_fallback(payload, mob/user)
	if(..())
		return TRUE

	open_legacy(user)

/datum/tgui_module/player_notes/proc/ui_act_show_player_info(datum/act/op/A, name)
	var/mob/user = A.actor
	var/datum/tgui_module/player_notes_info/A2 = new(src)
	A2.key = name
	A2.tgui_interact(user)

/datum/tgui_module/player_notes/proc/ui_act_filter_player_notes(datum/act/op/A)
	open_request(src, /datum/prompt/text, PROC_REF(filter_player_notes_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Filter string (case-insensitive regex)", title = "Player notes filter", timeout = 0)

/datum/tgui_module/player_notes/proc/filter_player_notes_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/input = A.answer.value
	current_filter = input

/datum/tgui_module/player_notes/proc/ui_act_set_page(datum/act/op/A, index)
	var/page = index
	current_page = page

/datum/tgui_module/player_notes/proc/ui_act_clear_player_info_filter(datum/act/op/A)
	current_filter = ""

/datum/tgui_module/player_notes/proc/ui_act_open_legacy_ui(datum/act/op/A)
	var/mob/user = A.actor
	open_legacy(user)

/datum/tgui_module/player_notes/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	data["filter"] = current_filter

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

	var/key = null

/datum/tgui_module/player_notes_info/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		spent(src, user)

CAPABILITIES(/datum/tgui_module/player_notes_info)
	interface("PlayerNotesInfo", rights = R_ADMIN|R_MOD|R_EVENT|R_DEBUG)
	op("cahngekey", ui_act("cahngekey", arg("ckey", schema_text(4096))), then(PROC_REF(ui_act_cahngekey)))
	op("add_player_info", ui_act("add_player_info", arg("ckey", schema_text(4096))), asks(/datum/prompt/text, fields = list("title" = "Add Player Info", "question" = "Write your comment below.", "multiline" = TRUE, "max_len" = MAX_TGUI_INPUT)), then(PROC_REF(ui_act_add_player_info)))
	op("remove_player_info", ui_act("remove_player_info", arg("ckey", schema_text(4096)), arg("index", num())), then(PROC_REF(ui_act_remove_player_info)))

/datum/tgui_module/player_notes_info/tgui_fallback(payload, mob/user)
	if(..())
		return TRUE

	var/datum/admins/A = GLOB.admin_datums[user.ckey]
	A.show_player_info_legacy(user, key)

/datum/tgui_module/player_notes_info/proc/ui_act_cahngekey(datum/act/op/A, ckey)
	key = sanitize(ckey)
	return TRUE

/datum/tgui_module/player_notes_info/proc/ui_act_add_player_info(datum/act/op/A, ckey)
	var/mob/user = A.actor
	var/datum/prompt/P = A.answer
	var/add = P?.value
	if(!add)
		return FALSE
	notes_add(ckey, add, user)
	return TRUE

/datum/tgui_module/player_notes_info/proc/ui_act_remove_player_info(datum/act/op/A, ckey, index_arg)
	var/mob/user = A.actor
	var/key = ckey
	var/index = index_arg

	notes_del(key, index, user)
	return TRUE

/datum/tgui_module/player_notes_info/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["ckey"] = key

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
	open_request(src, /datum/prompt/text/player_notes_legacy_filter, PROC_REF(player_notes_filter_entered), answerer = user)

/datum/admins/proc/player_notes_filter_entered(datum/act/request/A)
	if(!A.answer)
		return
	PlayerNotesPageLegacy(1, A.answer.value, A.request.answerer)

/datum/prompt/text/player_notes_legacy_filter
	question = "Filter string (case-insensitive regex)"
	title = "Player notes filter"
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/player_notes_legacy_filter/normalize(given)
	return istext(given) ? given : null

/datum/prompt/text/player_notes_legacy_filter/recheck_extra()
	return QDELETED(owner) || QDELETED(answerer) ? "gone" : null

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


/datum/admins/proc/topic_add_player_info_legacy(datum/act/op/A, href_add_player_info_legacy)
	var/mob/user = A.actor
	var/key = href_add_player_info_legacy
	var/add = A.step_value("info")
	if(isnull(add))
		return
	if(!add)
		return
	notes_add(key, add, user)
	show_player_info_legacy(user, key)
	return TRUE

/datum/admins/proc/topic_remove_player_info_legacy(datum/act/op/A, href_remove_player_info_legacy, href_remove_index)
	var/mob/user = A.actor
	var/key = href_remove_player_info_legacy
	notes_del(key, href_remove_index, user)
	show_player_info_legacy(user, key)
	return TRUE

/datum/admins/proc/topic_notes_legacy_show(datum/act/op/A, href_ckey, href_mob)
	var/mob/user = A.actor
	var/ckey = href_ckey
	if(!ckey)
		var/mob/M = href_mob
		ckey = M?.ckey
	show_player_info_legacy(user, ckey)
	return TRUE

/datum/admins/proc/topic_notes_legacy_list(datum/act/op/A, href_index, href_filter)
	var/mob/user = A.actor
	var/filter
	if(href_filter && href_filter != "0")
		filter = url_decode(href_filter)
	PlayerNotesPageLegacy(href_index, filter, user)
	return TRUE

/datum/admins/proc/topic_notes_legacy_filter(datum/act/op/A)
	var/mob/user = A.actor
	PlayerNotesFilterLegacy(user)
	return TRUE

#undef PLAYER_NOTES_ENTRIES_PER_PAGE
