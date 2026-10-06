// Check Attacks — structured TGUI for default unarmed-attack selection.

GLOBAL_LIST_EMPTY(dq_attacks_panels)

/datum/attacks_panel
	var/mob/living/carbon/human/host

/datum/attacks_panel/New(mob/living/carbon/human/host_mob)
	rel_set(src, nameof(host), host_mob)

/// Phase 2: leaves the per-host panel index.
/datum/attacks_panel/lifecycle_dematerialize()
	. = ..()
	if(host)
		GLOB.dq_attacks_panels -= "[REF(host)]"

CAPABILITIES(/datum/attacks_panel)
	interface("AttacksPanel", title = "Known Attacks", state = nameof(GLOB.tgui_always_state))
	op("set_default", ui_act("set_default", arg("ref", schema_ref(/datum/unarmed_attack))), then(PROC_REF(ui_act_set_default)))
	op("reset_default", ui_act("reset_default"), then(PROC_REF(ui_act_reset_default)))

/datum/attacks_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return FALSE
	return TRUE

/// /datum/attacks_panel's window data.
/datum/attacks_panel/ui_data(datum/act/eval/A)
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

/datum/attacks_panel/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!host || user != host)
		return FALSE
	return TRUE

/datum/attacks_panel/proc/ui_act_set_default(datum/act/op/A, ref)
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in ui_source_host_species_unarmed_attacks()))
		return FALSE
	var/datum/unarmed_attack/u_attack = ref
	if(u_attack)
		host.set_default_attack(u_attack)
		host.check_attacks()
	SStgui.update_uis(src)
	return TRUE

/datum/attacks_panel/proc/ui_act_reset_default(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
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
	set category = VERB_CAT_IC_GAME
	set src = usr
	var/key = "[REF(src)]"
	var/datum/attacks_panel/panel = LAZYACCESS(GLOB.dq_attacks_panels, key)
	if(!panel)
		panel = new(src)
		GLOB.dq_attacks_panels[key] = panel
	panel.tgui_interact(src)

