// Check Attacks — structured TGUI for default unarmed-attack selection.

GLOBAL_LIST_EMPTY(dq_attacks_panels)

/datum/attacks_panel
	var/mob/living/carbon/human/host

/datum/attacks_panel/New(mob/living/carbon/human/host_mob)
	host = host_mob

/datum/attacks_panel/Destroy(force, ...)
	if(host)
		GLOB.dq_attacks_panels -= "[REF(host)]"
	host = null
	return ..()

/datum/attacks_panel/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/attacks_panel/tgui_interact(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AttacksPanel", "Known Attacks")
		ui.open()

/datum/attacks_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!host || !host.species)
		return data
	data["default_name"] = host.default_attack ? host.default_attack.attack_name : null
	var/list/rows = list()
	for(var/datum/unarmed_attack/u_attack in host.species.unarmed_attacks)
		rows += list(list(
			"ref" = "\ref[u_attack]",
			"name" = u_attack.attack_name,
			"is_default" = (u_attack == host.default_attack),
		))
	data["attacks"] = rows
	return data

/datum/attacks_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(. || !host || ui.user != host)
		return
	switch(action)
		if("set_default")
			var/ref = "[params["ref"]]"
			host.Topic("default_attk=[ref]", list("default_attk" = ref))
			SStgui.update_uis(src)
			return TRUE
		if("reset_default")
			host.Topic("default_attk=reset_attk", list("default_attk" = "reset_attk"))
			SStgui.update_uis(src)
			return TRUE

// Check Attacks verb now opens a structured TGUI panel.
/mob/living/carbon/human/verb/check_attacks()
	set name = "Check Attacks"
	set category = "IC.Game"
	set src = usr
	var/key = "[REF(src)]"
	var/datum/attacks_panel/panel = LAZYACCESS(GLOB.dq_attacks_panels, key)
	if(!panel)
		panel = new(src)
		GLOB.dq_attacks_panels[key] = panel
	panel.tgui_interact(src)
