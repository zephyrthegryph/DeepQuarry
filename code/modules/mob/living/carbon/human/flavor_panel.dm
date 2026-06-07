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

/datum/flavor_panel/Destroy(force, ...)
	if(host)
		GLOB.dq_flavor_panels -= "[REF(host)]"
	host = null
	return ..()

/datum/flavor_panel/tgui_state(mob/user)
	return GLOB.tgui_default_state

/datum/flavor_panel/tgui_interact(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "FlavorText", "Update Flavour Text")
		ui.open()

/datum/flavor_panel/proc/get_flavor_keys()
	var/static/list/keys = list("general", "head", "face", "eyes", "torso", "arms", "hands", "legs", "feet")
	return keys

/datum/flavor_panel/proc/get_flavor_labels()
	var/static/list/labels = list(
		"general" = "General",
		"head" = "Head",
		"face" = "Face",
		"eyes" = "Eyes",
		"torso" = "Body",
		"arms" = "Arms",
		"hands" = "Hands",
		"legs" = "Legs",
		"feet" = "Feet",
	)
	return labels

/datum/flavor_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!host)
		return data
	var/list/parts = list()
	var/list/labels = get_flavor_labels()
	for(var/k in get_flavor_keys())
		parts += list(list(
			"key" = k,
			"label" = labels[k],
			"preview" = TextPreview(host.flavor_texts[k]),
		))
	data["parts"] = parts
	return data

/datum/flavor_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(. || !host || ui.user != host)
		return
	switch(action)
		if("edit")
			var/key = "[params["key"]]"
			host.Topic("flavor_change=[key]", list("flavor_change" = key))
			SStgui.update_uis(src)
			return TRUE
		if("done")
			host.Topic("flavor_change=done", list("flavor_change" = "done"))
			return TRUE
