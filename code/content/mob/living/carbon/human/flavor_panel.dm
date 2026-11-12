// Set Flavour Text — structured TGUI panel replacing the legacy form.

/mob/living/carbon/human/proc/dq_open_flavor_panel(mob/user)
	if(!istype(user))
		return
	var/key = handle_of(src)
	var/datum/flavor_panel/panel = handle_get(ALAZYACCESS(GLOB.dq_flavor_panels, key))
	if(!panel)
		panel = new(src)
		GLOB.dq_flavor_panels[key] = handle_of(panel)
	panel.tgui_interact(user)

/// Open panels: host key -> the panel's handle_of (a deleted panel stops resolving).
GLOBAL_ALIST_EMPTY(dq_flavor_panels)

/datum/flavor_panel
	var/mob/living/carbon/human/host

/datum/flavor_panel/New(mob/living/carbon/human/host_mob)
	rel_set(src, nameof(host), host_mob)

/// Phase 2: leaves the per-host panel index.
/datum/flavor_panel/lifecycle_dematerialize()
	. = ..()
	if(host)
		GLOB.dq_flavor_panels -= handle_of(host)

CAPABILITIES(/datum/flavor_panel)
	ref_one(nameof(host), /mob/living/carbon/human)
	interface("FlavorText", title = "Update Flavour Text", state = nameof(GLOB.tgui_default_state))
	ui_shape(parts = list_of(row(key = schema_text(), label = schema_text(), preview = schema_text())))
	op("edit", ui_act("edit", arg("key", schema_text(4096))), then(PROC_REF(ui_act_edit)))
	op("done", ui_act("done"), then(PROC_REF(ui_act_done)))

/datum/flavor_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return FALSE
	return TRUE

TYPE_TABLE_DECLARE(/datum/flavor_panel, get_flavor_keys, list("general", "face", "body"))

TYPE_TABLE_DECLARE(/datum/flavor_panel, get_flavor_labels, list( \
		"general" = "General", \
		"face" = "Face", \
		"body" = "Body", \
	))

/// /datum/flavor_panel's window data.
/datum/flavor_panel/ui_data(datum/act/eval/A)
	var/list/data = list("parts" = list())
	if(!host)
		return data
	var/list/parts = list()
	var/list/labels = TYPE_TABLE_GET(src, get_flavor_labels)
	for(var/k in TYPE_TABLE_GET(src, get_flavor_keys))
		parts += list(list(
			"key" = k,
			"label" = labels[k],
			"preview" = TextPreview(LAZYACCESS(host.bio.flavor_texts, k)) || "",
		))
	data["parts"] = parts
	return data

/datum/flavor_panel/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!host || user != host)
		return FALSE
	return TRUE

/datum/flavor_panel/proc/ui_act_edit(datum/act/op/A, key_arg)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/key = "[key_arg]"
	topic_dispatch(host, user, list("flavor_change" = key))
	SStgui.update_uis(src)
	return TRUE

/datum/flavor_panel/proc/ui_act_done(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	topic_dispatch(host, user, list("flavor_change" = "done"))
	return TRUE

