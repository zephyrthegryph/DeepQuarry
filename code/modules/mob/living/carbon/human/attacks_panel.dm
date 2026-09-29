// Check Attacks — structured TGUI for default unarmed-attack selection.

GLOBAL_LIST_EMPTY(dq_attacks_panels)

/datum/attacks_panel
	var/mob/living/carbon/human/host

/datum/attacks_panel/New(mob/living/carbon/human/host_mob)
	rel_set(src, "host", host_mob)

/// Phase 2: leaves the per-host panel index.
/datum/attacks_panel/lifecycle_dematerialize()
	. = ..()
	if(host)
		GLOB.dq_attacks_panels -= "[REF(host)]"

DECLARE_UI_STATE(/datum/attacks_panel, GLOB.tgui_always_state)

DECLARE_UI(/datum/attacks_panel, "AttacksPanel", UI_TITLE("Known Attacks"))

/datum/attacks_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return FALSE
	return TRUE

UI_DATA_REPLACE(/datum/attacks_panel, "merge:ui_data_datum_attacks_panel{default_name:text,attacks:list}")

/// The computed part of /datum/attacks_panel's window data (declared on its UI_DATA row).
/datum/attacks_panel/proc/ui_data_datum_attacks_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/datum/attacks_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!host || ui.user != host)
		return FALSE
	return TRUE

UI_ACT(/datum/attacks_panel, "set_default", ui_act_set_default, UI_ARG_REF("ref", "proc:ui_source_host_species_unarmed_attacks", /datum/unarmed_attack))
UI_ACT_PROC(/datum/attacks_panel, ui_act_set_default)
	var/datum/unarmed_attack/u_attack = params["ref"]
	if(u_attack)
		host.set_default_attack(u_attack)
		host.check_attacks()
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/attacks_panel, "reset_default", ui_act_reset_default)
UI_ACT_PROC(/datum/attacks_panel, ui_act_reset_default)
	host.set_default_attack(null)
	host.check_attacks()
	SStgui.update_uis(src)
	return TRUE

/// The list the UI_ARG_REF rows resolve refs in.
/datum/attacks_panel/proc/ui_source_host_species_unarmed_attacks()
	return host.species?.unarmed_attacks

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

