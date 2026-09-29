// Private Notes / OOC Notes — structured TGUI panels via dedicated panel datums.
// Owner edits gated to user==host; OOC view is open to anyone.

GLOBAL_LIST_EMPTY(dq_private_notes_panels)
GLOBAL_LIST_EMPTY(dq_ooc_notes_panels)

// ---- Private Notes --------------------------------------------------------

/datum/private_notes_panel
	var/mob/living/host

/datum/private_notes_panel/New(mob/living/host_mob)
	rel_set(src, nameof(host), host_mob)

/// Phase 2: leaves the per-host panel index.
/datum/private_notes_panel/lifecycle_dematerialize()
	. = ..()
	if(host)
		GLOB.dq_private_notes_panels -= "[REF(host)]"

DECLARE_UI_STATE(/datum/private_notes_panel, GLOB.tgui_default_state)

DECLARE_UI(/datum/private_notes_panel, "PrivateNotes")

/datum/private_notes_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return FALSE
	return TRUE

/datum/private_notes_panel/ui_title(mob/user)
	return "Private Notes: [host.name]"

UI_DATA_REPLACE(/datum/private_notes_panel, "merge:ui_data_datum_private_notes_panel{owner:text,notes:unknown}")

/// The computed part of /datum/private_notes_panel's window data (declared on its UI_DATA row).
/datum/private_notes_panel/proc/ui_data_datum_private_notes_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["owner"] = host ? host.name : "(unknown)"
	data["notes"] = host ? html_decode(host.private_notes || "") : ""
	return data

/datum/private_notes_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!host || ui.user != host)
		return FALSE
	return TRUE

UI_ACT(/datum/private_notes_panel, "edit", ui_act_edit)
UI_ACT_PROC(/datum/private_notes_panel, ui_act_edit)
	host.set_metainfo_private_notes(host)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/private_notes_panel, "save", ui_act_save)
UI_ACT_PROC(/datum/private_notes_panel, ui_act_save)
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
	rel_set(src, nameof(host), host_mob)

/// Phase 2: leaves the per-host panel index.
/datum/ooc_notes_panel/lifecycle_dematerialize()
	. = ..()
	if(host)
		GLOB.dq_ooc_notes_panels -= "[REF(host)]"

DECLARE_UI_STATE(/datum/ooc_notes_panel, GLOB.tgui_default_state)

DECLARE_UI(/datum/ooc_notes_panel, "OocNotes")

/datum/ooc_notes_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host)
		return FALSE
	return TRUE

/datum/ooc_notes_panel/ui_title(mob/user)
	return "OOC Notes: [host.name]"

UI_DATA_REPLACE(/datum/ooc_notes_panel, "merge:ui_data_datum_ooc_notes_panel{owner:text,is_owner:bool,ooc_notes:bool,ooc_likes:bool,ooc_dislikes:bool,ooc_favs:bool,ooc_maybes:bool,ooc_style:bool}")

/// The computed part of /datum/ooc_notes_panel's window data (declared on its UI_DATA row).
/datum/ooc_notes_panel/proc/ui_data_datum_ooc_notes_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	if(!host)
		return data
	data["owner"] = host.name
	data["is_owner"] = (user == host)
	data["ooc_notes"] = html_decode(host.identity().ooc_notes || "")
	data["ooc_likes"] = html_decode(host.identity().ooc_notes_likes || "")
	data["ooc_dislikes"] = html_decode(host.identity().ooc_notes_dislikes || "")
	data["ooc_favs"] = html_decode(host.identity().ooc_notes_favs || "")
	data["ooc_maybes"] = html_decode(host.identity().ooc_notes_maybes || "")
	data["ooc_style"] = !!host.identity().ooc_notes_style
	return data

/datum/ooc_notes_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!host)
		return FALSE
	return TRUE

UI_ACT(/datum/ooc_notes_panel, "print", ui_act_print)
UI_ACT_PROC(/datum/ooc_notes_panel, ui_act_print)
	host.print_ooc_notes_chat(ui.user)
	return TRUE

UI_ACT(/datum/ooc_notes_panel, "save", ui_act_save)
UI_ACT_PROC(/datum/ooc_notes_panel, ui_act_save)
	if(ui.user == host)
		host.save_ooc_panel(host)
	return TRUE

UI_ACT(/datum/ooc_notes_panel, "toggle_style", ui_act_toggle_style)
UI_ACT_PROC(/datum/ooc_notes_panel, ui_act_toggle_style)
	if(ui.user == host)
		host.set_metainfo_ooc_style(host)
		SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/ooc_notes_panel, "edit_notes", ui_act_edit_notes)
UI_ACT_PROC(/datum/ooc_notes_panel, ui_act_edit_notes)
	if(ui.user == host)
		host.set_metainfo_panel(host)
		SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/ooc_notes_panel, "edit_favs", ui_act_edit_favs)
UI_ACT_PROC(/datum/ooc_notes_panel, ui_act_edit_favs)
	if(ui.user == host)
		host.set_metainfo_favs(host)
		SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/ooc_notes_panel, "edit_likes", ui_act_edit_likes)
UI_ACT_PROC(/datum/ooc_notes_panel, ui_act_edit_likes)
	if(ui.user == host)
		host.set_metainfo_likes(host)
		SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/ooc_notes_panel, "edit_maybes", ui_act_edit_maybes)
UI_ACT_PROC(/datum/ooc_notes_panel, ui_act_edit_maybes)
	if(ui.user == host)
		host.set_metainfo_maybes(host)
		SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/ooc_notes_panel, "edit_dislikes", ui_act_edit_dislikes)
UI_ACT_PROC(/datum/ooc_notes_panel, ui_act_edit_dislikes)
	if(ui.user == host)
		host.set_metainfo_dislikes(host)
		SStgui.update_uis(src)
	return TRUE

/mob/living/proc/ooc_notes_window(mob/user)
	if(!identity().ooc_notes)
		return
	var/key = "[REF(src)]"
	var/datum/ooc_notes_panel/panel = LAZYACCESS(GLOB.dq_ooc_notes_panels, key)
	if(!panel)
		panel = new(src)
		GLOB.dq_ooc_notes_panels[key] = panel
	panel.tgui_interact(user)

