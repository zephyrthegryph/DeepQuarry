// Set Flavour Text — structured TGUI panel replacing the legacy form.

/mob/living/carbon/human/proc/dq_open_flavor_panel(mob/user)
	if(!istype(user))
		return
	var/key = "[REF(src)]"
	var/datum/flavor_panel/panel = LAZYACCESS(GLOB.dq_flavor_panels, key)
	if(!panel)
		panel = new(src)
		GLOB.dq_flavor_panels[key] = panel
	panel.tgui_interact(user)

GLOBAL_LIST_EMPTY(dq_flavor_panels)

/datum/flavor_panel
	var/mob/living/carbon/human/host

/datum/flavor_panel/New(mob/living/carbon/human/host_mob)
	host = host_mob

/// Phase 2: leaves the per-host panel index.
/datum/flavor_panel/lifecycle_dematerialize()
	. = ..()
	if(host)
		GLOB.dq_flavor_panels -= "[REF(host)]"

DECLARE_UI_STATE(/datum/flavor_panel, GLOB.tgui_default_state)

DECLARE_UI(/datum/flavor_panel, "FlavorText", UI_TITLE("Update Flavour Text"))

/datum/flavor_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return FALSE
	return TRUE

TYPE_TABLE_DECLARE(/datum/flavor_panel, get_flavor_keys, list("general", "head", "face", "eyes", "torso", "arms", "hands", "legs", "feet"))

TYPE_TABLE_DECLARE(/datum/flavor_panel, get_flavor_labels, list( \
		"general" = "General", \
		"head" = "Head", \
		"face" = "Face", \
		"eyes" = "Eyes", \
		"torso" = "Body", \
		"arms" = "Arms", \
		"hands" = "Hands", \
		"legs" = "Legs", \
		"feet" = "Feet", \
	))

UI_DATA_REPLACE(/datum/flavor_panel, "merge:ui_data_datum_flavor_panel{parts:list}")

/// The computed part of /datum/flavor_panel's window data (declared on its UI_DATA row).
/datum/flavor_panel/proc/ui_data_datum_flavor_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	if(!host)
		return data
	var/list/parts = list()
	var/list/labels = TYPE_TABLE_GET(src, get_flavor_labels)
	for(var/k in TYPE_TABLE_GET(src, get_flavor_keys))
		parts += list(list(
			"key" = k,
			"label" = labels[k],
			"preview" = TextPreview(LAZYACCESS(host.flavor_texts, k)),
		))
	data["parts"] = parts
	return data

/datum/flavor_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!host || ui.user != host)
		return FALSE
	return TRUE

UI_ACT(/datum/flavor_panel, "edit", ui_act_edit, UI_ARG_TEXT("key"))
UI_ACT_PROC(/datum/flavor_panel, ui_act_edit)
	var/key = "[params["key"]]"
	topic_dispatch(host, ui.user, list("flavor_change" = key))
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/flavor_panel, "done", ui_act_done)
UI_ACT_PROC(/datum/flavor_panel, ui_act_done)
	topic_dispatch(host, ui.user, list("flavor_change" = "done"))
	return TRUE

DECLARE_REF(/datum/flavor_panel, "host", HELD, null)
