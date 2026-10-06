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

CAPABILITIES(/datum/private_notes_panel)
	interface("PrivateNotes", state = nameof(GLOB.tgui_default_state))
	op("edit", ui_act("edit"), then(PROC_REF(ui_act_edit)))
	op("save", ui_act("save"), then(PROC_REF(ui_act_save)))

/datum/private_notes_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return FALSE
	return TRUE

/datum/private_notes_panel/ui_title(mob/user)
	return "Private Notes: [host.name]"

/// /datum/private_notes_panel's window data.
/datum/private_notes_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["owner"] = host ? host.name : "(unknown)"
	data["notes"] = host ? html_decode(host.private_notes || "") : ""
	return data

/datum/private_notes_panel/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!host || user != host)
		return FALSE
	return TRUE

/datum/private_notes_panel/proc/ui_act_edit(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	host.set_metainfo_private_notes(host)
	SStgui.update_uis(src)
	return TRUE

/datum/private_notes_panel/proc/ui_act_save(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
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

CAPABILITIES(/datum/ooc_notes_panel)
	interface("OocNotes", state = nameof(GLOB.tgui_default_state))
	op("print", ui_act("print"), then(PROC_REF(ui_act_print)))
	op("save", ui_act("save"), then(PROC_REF(ui_act_save)))
	op("toggle_style", ui_act("toggle_style"), then(PROC_REF(ui_act_toggle_style)))
	op("edit_notes", ui_act("edit_notes"), then(PROC_REF(ui_act_edit_notes)))
	op("edit_favs", ui_act("edit_favs"), then(PROC_REF(ui_act_edit_favs)))
	op("edit_likes", ui_act("edit_likes"), then(PROC_REF(ui_act_edit_likes)))
	op("edit_maybes", ui_act("edit_maybes"), then(PROC_REF(ui_act_edit_maybes)))
	op("edit_dislikes", ui_act("edit_dislikes"), then(PROC_REF(ui_act_edit_dislikes)))

/datum/ooc_notes_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host)
		return FALSE
	return TRUE

/datum/ooc_notes_panel/ui_title(mob/user)
	return "OOC Notes: [host.name]"

/// /datum/ooc_notes_panel's window data.
/datum/ooc_notes_panel/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
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

/datum/ooc_notes_panel/proc/ui_gate(datum/act/op/A)
	if(!host)
		return FALSE
	return TRUE

/datum/ooc_notes_panel/proc/ui_act_print(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	host.print_ooc_notes_chat(user)
	return TRUE

/datum/ooc_notes_panel/proc/ui_act_save(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(user == host)
		host.save_ooc_panel(host)
	return TRUE

/datum/ooc_notes_panel/proc/ui_act_toggle_style(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(user == host)
		host.set_metainfo_ooc_style(host)
		SStgui.update_uis(src)
	return TRUE

/datum/ooc_notes_panel/proc/ui_act_edit_notes(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(user == host)
		host.set_metainfo_panel(host)
		SStgui.update_uis(src)
	return TRUE

/datum/ooc_notes_panel/proc/ui_act_edit_favs(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(user == host)
		host.set_metainfo_favs(host)
		SStgui.update_uis(src)
	return TRUE

/datum/ooc_notes_panel/proc/ui_act_edit_likes(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(user == host)
		host.set_metainfo_likes(host)
		SStgui.update_uis(src)
	return TRUE

/datum/ooc_notes_panel/proc/ui_act_edit_maybes(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(user == host)
		host.set_metainfo_maybes(host)
		SStgui.update_uis(src)
	return TRUE

/datum/ooc_notes_panel/proc/ui_act_edit_dislikes(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(user == host)
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

