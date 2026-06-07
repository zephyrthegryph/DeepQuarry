// Private Notes / OOC Notes — structured TGUI panels via dedicated panel datums.
// Owner edits gated to user==host; OOC view is open to anyone.

GLOBAL_LIST_EMPTY(dq_private_notes_panels)
GLOBAL_LIST_EMPTY(dq_ooc_notes_panels)

// ---- Private Notes --------------------------------------------------------

/datum/private_notes_panel
	var/mob/living/host

/datum/private_notes_panel/New(mob/living/host_mob)
	host = host_mob

/datum/private_notes_panel/Destroy(force, ...)
	if(host)
		GLOB.dq_private_notes_panels -= "[REF(host)]"
	host = null
	return ..()

/datum/private_notes_panel/tgui_state(mob/user)
	return GLOB.tgui_default_state

/datum/private_notes_panel/tgui_interact(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PrivateNotes", "Private Notes: [host.name]")
		ui.open()

/datum/private_notes_panel/tgui_data(mob/user)
	var/list/data = list()
	data["owner"] = host ? host.name : "(unknown)"
	data["notes"] = host ? html_decode(host.private_notes || "") : ""
	return data

/datum/private_notes_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!host || ui.user != host)
		return
	switch(action)
		if("edit")
			host.set_metainfo_private_notes(host)
			SStgui.update_uis(src)
			return TRUE
		if("save")
			host.save_private_notes(host)
			return TRUE

/mob/living/proc/private_notes_window(mob/user)
	if(user != src)
		return
	if(!private_notes)
		private_notes = " "
		return
	var/key = "[REF(src)]"
	var/datum/private_notes_panel/panel = LAZYACCESS(GLOB.dq_private_notes_panels, key)
	if(!panel)
		panel = new(src)
		GLOB.dq_private_notes_panels[key] = panel
	panel.tgui_interact(user)

// ---- OOC Notes ------------------------------------------------------------

/datum/ooc_notes_panel
	var/mob/living/host

/datum/ooc_notes_panel/New(mob/living/host_mob)
	host = host_mob

/datum/ooc_notes_panel/Destroy(force, ...)
	if(host)
		GLOB.dq_ooc_notes_panels -= "[REF(host)]"
	host = null
	return ..()

/datum/ooc_notes_panel/tgui_state(mob/user)
	return GLOB.tgui_default_state

/datum/ooc_notes_panel/tgui_interact(mob/user, datum/tgui/ui)
	if(!host)
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "OocNotes", "OOC Notes: [host.name]")
		ui.open()

/datum/ooc_notes_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!host)
		return data
	data["owner"] = host.name
	data["is_owner"] = (user == host)
	data["ooc_notes"] = html_decode(host.ooc_notes || "")
	data["ooc_likes"] = html_decode(host.ooc_notes_likes || "")
	data["ooc_dislikes"] = html_decode(host.ooc_notes_dislikes || "")
	data["ooc_favs"] = html_decode(host.ooc_notes_favs || "")
	data["ooc_maybes"] = html_decode(host.ooc_notes_maybes || "")
	data["ooc_style"] = !!host.ooc_notes_style
	return data

/datum/ooc_notes_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!host)
		return
	switch(action)
		if("print")
			host.print_ooc_notes_chat(ui.user)
			return TRUE
		if("save")
			if(ui.user == host)
				host.save_ooc_panel(host)
			return TRUE
		if("toggle_style")
			if(ui.user == host)
				host.set_metainfo_ooc_style(host)
				SStgui.update_uis(src)
			return TRUE
		if("edit_notes")
			if(ui.user == host)
				host.set_metainfo_panel(host)
				SStgui.update_uis(src)
			return TRUE
		if("edit_favs")
			if(ui.user == host)
				host.set_metainfo_favs(host)
				SStgui.update_uis(src)
			return TRUE
		if("edit_likes")
			if(ui.user == host)
				host.set_metainfo_likes(host)
				SStgui.update_uis(src)
			return TRUE
		if("edit_maybes")
			if(ui.user == host)
				host.set_metainfo_maybes(host)
				SStgui.update_uis(src)
			return TRUE
		if("edit_dislikes")
			if(ui.user == host)
				host.set_metainfo_dislikes(host)
				SStgui.update_uis(src)
			return TRUE

/mob/living/proc/ooc_notes_window(mob/user)
	if(!ooc_notes)
		return
	var/key = "[REF(src)]"
	var/datum/ooc_notes_panel/panel = LAZYACCESS(GLOB.dq_ooc_notes_panels, key)
	if(!panel)
		panel = new(src)
		GLOB.dq_ooc_notes_panels[key] = panel
	panel.tgui_interact(user)
