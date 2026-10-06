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
	rel_set(src, nameof(host), host_mob)

/// Phase 2: leaves the per-host panel index.
/datum/flavor_panel/lifecycle_dematerialize()
	. = ..()
	if(host)
		GLOB.dq_flavor_panels -= "[REF(host)]"

CAPABILITIES(/datum/flavor_panel)
	interface("FlavorText", title = "Update Flavour Text", state = nameof(GLOB.tgui_default_state))
	op("edit", ui_act("edit", arg("key", schema_text(4096))), then(PROC_REF(ui_act_edit)))
	op("done", ui_act("done"), then(PROC_REF(ui_act_done)))

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

/// /datum/flavor_panel's window data.
/datum/flavor_panel/ui_data(datum/act/eval/A)
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

