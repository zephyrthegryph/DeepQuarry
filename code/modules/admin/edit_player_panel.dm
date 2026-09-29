// Edit Player ("Show Player Panel") — structured TGUI replacement.
//
// This is the right-click → Show Player Panel admin context menu. The legacy
// panel was ~200 lines of conditional HTML with ~40 distinct byond:// link
// types. All clicks here forward back to /datum/admins.Topic via _src_=holder
// so the existing action handlers stay in place.

GLOBAL_LIST_EMPTY(dq_edit_player_panels)

/datum/admins/proc/dq_open_edit_player_panel(mob/player)
	if(!owner()?.mob || !player)
		return
	var/key = "[REF(src)]-[REF(player)]"
	var/datum/edit_player_panel/panel = LAZYACCESS(GLOB.dq_edit_player_panels, key)
	if(!panel)
		panel = new(src, player)
		GLOB.dq_edit_player_panels[key] = panel
	panel.tgui_interact(owner().mob)

/datum/edit_player_panel
	var/tmp/datum/admins/holder
	var/tmp/mob/target

/datum/edit_player_panel/New(datum/admins/owner_holder, mob/target_mob)
	..()
	rel_set(src, nameof(holder), owner_holder)
	rel_set(src, nameof(target), target_mob)

// leaves the per-admin panel index.
/datum/edit_player_panel/lifecycle_dematerialize()
	..()
	if(holder() && target())
		GLOB.dq_edit_player_panels -= "[REF(holder())]-[REF(target())]"

DECLARE_UI_STATE(/datum/edit_player_panel, ADMIN_STATE(R_HOLDER))

DECLARE_UI(/datum/edit_player_panel, "AdminEditPlayer")

/datum/edit_player_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!holder() || !target())
		return FALSE
	return TRUE

/datum/edit_player_panel/ui_title(mob/user)
	return "Edit Player: [target().key]"

UI_DATA_REPLACE(/datum/edit_player_panel, "merge:ui_data_datum_edit_player_panel{ref:text,name:text,key:bool,mob_type:text,has_client:bool,is_newplayer:bool,is_human:bool,is_ai:bool,is_carbon:bool,is_small:bool,is_corgi:bool,is_animal:bool,client_name:text,client_ref:text,client_ckey:text,player_age:text,account_join_date:text,account_age:text,inactivity_minutes:num,rank_names:unknown,editrights_mode:text,muted:num,can_event:num,special_character:unknown,mute_mask_ic:num,mute_mask_ooc:num,mute_mask_looc:num,mute_mask_pray:num,mute_mask_adminhelp:num,mute_mask_deadchat:num,mute_mask_all:num,dna_cells:list,dna_se_length:num,languages:list}")

/// The computed part of /datum/edit_player_panel's window data (declared on its UI_DATA row).
/datum/edit_player_panel/proc/ui_data_datum_edit_player_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	if(!target())
		return data
	data["ref"] = "[REF(target())]"
	data["name"] = "[target()]"
	data["key"] = target().key || ""
	data["mob_type"] = "[target().type]"
	data["has_client"] = !!target().client
	data["is_newplayer"] = !!isnewplayer(target())
	data["is_human"] = !!ishuman(target())
	data["is_ai"] = !!isAI(target())
	data["is_carbon"] = !!iscarbon(target())
	data["is_small"] = !!issmall(target())
	data["is_corgi"] = !!iscorgi(target())
	data["is_animal"] = !!isanimal(target())
	if(target().client)
		data["client_name"] = "[target().client]"
		data["client_ref"] = "[REF(target().client)]"
		data["client_ckey"] = target().client.ckey
		data["player_age"] = target().client.player_age
		data["account_join_date"] = target().client.account_join_date
		data["account_age"] = target().client.account_age
		data["inactivity_minutes"] = round(target().client.inactivity / 600)
		data["rank_names"] = target().client.holder ? target().client.holder.rank_names() : "Player"
		data["editrights_mode"] = (GLOB.admin_datums[target().client.ckey] || GLOB.deadmins[target().client.ckey]) ? "rank" : "add"
		data["muted"] = target().client.prefs.muted
	else
		data["client_name"] = null
		data["client_ref"] = null
		data["inactivity_minutes"] = -1
		data["muted"] = 0

	data["can_event"] = !!check_rights(R_ADMIN|R_MOD|R_EVENT, 0)
	data["special_character"] = is_special_character(target())

	// Mute mask constants exposed so the React side doesn't hardcode them.
	data["mute_mask_ic"] = MUTE_IC
	data["mute_mask_ooc"] = MUTE_OOC
	data["mute_mask_looc"] = MUTE_LOOC
	data["mute_mask_pray"] = MUTE_PRAY
	data["mute_mask_adminhelp"] = MUTE_ADMINHELP
	data["mute_mask_deadchat"] = MUTE_DEADCHAT
	data["mute_mask_all"] = MUTE_ALL

	// DNA — only meaningful for carbons with a DNA struct.
	if(target().dna && iscarbon(target()))
		var/list/dna_cells = list()
		var/list/gene_lookup = GLOBAL_TABLE_GET(edit_player_gene_lookup)
		for(var/block = 1; block <= DNA_SE_LENGTH; block++)
			var/datum/gene/gene = gene_lookup["[block]"]
			var/cell_state = "empty"
			var/bname = null
			var/tname = null
			if(gene)
				bname = gene.name
				tname = bname
				if(istype(gene, /datum/gene/trait))
					var/datum/gene/trait/T = gene
					tname = T.get_name()
				if(bname in target().active_genes)
					cell_state = "active"
				else if(target().dna.GetSEState(block))
					cell_state = "blocked"
				else
					cell_state = "inactive"
			dna_cells += list(list(
				"block" = block,
				"name" = bname,
				"tname" = tname,
				"state" = cell_state,
			))
		data["dna_cells"] = dna_cells
		data["dna_se_length"] = DNA_SE_LENGTH
	else
		data["dna_cells"] = null

	// Language list.
	var/list/langs = list()
	for(var/k in GLOBAL_TABLE_GET(non_innate_language_keys))
		langs += list(list(
			"key" = k,
			"known" = (GLOB.all_languages[k] in target().languages),
		))
	data["languages"] = langs

	return data

/proc/build_edit_player_gene_lookup()
	var/list/lookup = list()
	for(var/setup_block = 1; setup_block <= DNA_SE_LENGTH; setup_block++)
		lookup["[setup_block]"] = null
	for(var/datum/gene/gene in GLOB.dna_genes)
		lookup["[gene.block]"] = gene
	return lookup

GLOBAL_TABLE(edit_player_gene_lookup, GLOBAL_PROC_REF(build_edit_player_gene_lookup))

/proc/build_non_innate_language_keys()
	var/list/keys = list()
	for(var/k in GLOB.all_languages)
		var/datum/language/L = GLOB.all_languages[k]
		if(L.flags & INNATE)
			continue
		keys += k
	return keys

GLOBAL_TABLE(non_innate_language_keys, GLOBAL_PROC_REF(build_non_innate_language_keys))

/datum/edit_player_panel/proc/forward_topic(qs, list/extra_params = null)
	forward_holder_topic(holder(), qs, extra_params)

/datum/edit_player_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!holder() || !target())
		return FALSE
	return TRUE

UI_ACT(/datum/edit_player_panel, "editrights", ui_act_editrights, UI_ARG_TEXT("mode"))
UI_ACT_PROC(/datum/edit_player_panel, ui_act_editrights)
	var/mode = "[params["mode"]]"
	forward_topic("editrights=[mode];key=[target().key]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "revive", ui_act_revive)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_revive)
	var/tref = "[REF(target())]"
	forward_topic("revive=[tref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "vv", ui_act_vv)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_vv)
	var/tref = "[REF(target())]"
	ui.user.client?.vv_topic(list("Vars" = tref), TRUE)
	return TRUE

UI_ACT(/datum/edit_player_panel, "traitor", ui_act_traitor)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_traitor)
	var/tref = "[REF(target())]"
	forward_topic("traitor=[tref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "priv_msg", ui_act_priv_msg)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_priv_msg)
	var/tref = "[REF(target())]"
	forward_topic("priv_msg=[tref]")
	return TRUE

UI_ACT(/datum/edit_player_panel, "subtlemessage", ui_act_subtlemessage)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_subtlemessage)
	var/tref = "[REF(target())]"
	forward_topic("subtlemessage=[tref]")
	return TRUE

UI_ACT(/datum/edit_player_panel, "jumpto", ui_act_jumpto)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_jumpto)
	var/tref = "[REF(target())]"
	forward_topic("jumpto=[tref]")
	return TRUE

UI_ACT(/datum/edit_player_panel, "getmob", ui_act_getmob)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_getmob)
	var/tref = "[REF(target())]"
	forward_topic("getmob=[tref]")
	return TRUE

UI_ACT(/datum/edit_player_panel, "sendmob", ui_act_sendmob)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_sendmob)
	var/tref = "[REF(target())]"
	forward_topic("sendmob=[tref]")
	return TRUE

UI_ACT(/datum/edit_player_panel, "narrateto", ui_act_narrateto)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_narrateto)
	var/tref = "[REF(target())]"
	forward_topic("narrateto=[tref]")
	return TRUE

UI_ACT(/datum/edit_player_panel, "boot2", ui_act_boot2)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_boot2)
	var/tref = "[REF(target())]"
	forward_topic("boot2=[tref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "warn", ui_act_warn)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_warn)
	forward_topic("warn=[target().ckey]")
	return TRUE

UI_ACT(/datum/edit_player_panel, "newban", ui_act_newban)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_newban)
	var/tref = "[REF(target())]"
	forward_topic("newban=[tref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "jobban2", ui_act_jobban2)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_jobban2)
	var/tref = "[REF(target())]"
	forward_topic("jobban2=[tref]")
	return TRUE

UI_ACT(/datum/edit_player_panel, "notes", ui_act_notes)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_notes)
	var/tref = "[REF(target())]"
	forward_topic("notes=show;mob=[tref]")
	return TRUE

UI_ACT(/datum/edit_player_panel, "sendtoprison", ui_act_sendtoprison)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_sendtoprison)
	var/tref = "[REF(target())]"
	forward_topic("sendtoprison=[tref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "sendbacktolobby", ui_act_sendbacktolobby)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_sendbacktolobby)
	var/tref = "[REF(target())]"
	forward_topic("sendbacktolobby=[tref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "forcespeech", ui_act_forcespeech)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_forcespeech)
	var/tref = "[REF(target())]"
	forward_topic("forcespeech=[tref]")
	return TRUE
// Mute toggles

UI_ACT(/datum/edit_player_panel, "mute", ui_act_mute, UI_ARG_TEXT("mute_type"))
UI_ACT_PROC(/datum/edit_player_panel, ui_act_mute)
	var/tref = "[REF(target())]"
	var/mute_type = "[params["mute_type"]]"
	forward_topic("mute=[tref];mute_type=[mute_type]")
	SStgui.update_uis(src)
	return TRUE
// Transformation

UI_ACT(/datum/edit_player_panel, "turn_monkey", ui_act_turn_monkey)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_turn_monkey)
	var/tref = "[REF(target())]"
	forward_topic("turn_monkey=[tref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "corgione", ui_act_corgione)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_corgione)
	var/tref = "[REF(target())]"
	forward_topic("corgione=[tref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "turn_ai", ui_act_turn_ai)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_turn_ai)
	var/tref = "[REF(target())]"
	forward_topic("turn_ai=[tref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "turn_robot", ui_act_turn_robot)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_turn_robot)
	var/tref = "[REF(target())]"
	forward_topic("turn_robot=[tref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "turn_alien", ui_act_turn_alien)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_turn_alien)
	var/tref = "[REF(target())]"
	forward_topic("turn_alien=[tref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "makeanimal", ui_act_makeanimal)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_makeanimal)
	var/tref = "[REF(target())]"
	forward_topic("makeanimal=[tref]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_player_panel, "respawn", ui_act_respawn)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_respawn)
	var/cref = target().client ? "[REF(target().client)]" : null
	if(cref)
		forward_topic("respawn=[cref]")
		SStgui.update_uis(src)
	return TRUE
// DNA gene toggle

UI_ACT(/datum/edit_player_panel, "togmutate", ui_act_togmutate, UI_ARG_TEXT("block"))
UI_ACT_PROC(/datum/edit_player_panel, ui_act_togmutate)
	var/tref = "[REF(target())]"
	var/block = "[params["block"]]"
	forward_topic("togmutate=[tref];block=[block]")
	SStgui.update_uis(src)
	return TRUE
// simplemake

UI_ACT(/datum/edit_player_panel, "simplemake", ui_act_simplemake, UI_ARG_TEXT("kind"), UI_ARG_TEXT("species"))
UI_ACT_PROC(/datum/edit_player_panel, ui_act_simplemake)
	var/tref = "[REF(target())]"
	var/kind = "[params["kind"]]"
	var/species = "[params["species"]]"
	var/qs = "simplemake=[kind];mob=[tref]"
	if(length(species))
		qs += ";species=[species]"
	forward_topic(qs)
	SStgui.update_uis(src)
	return TRUE
// Thunderdome

UI_ACT(/datum/edit_player_panel, "tdome1", ui_act_tdome1)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_tdome1)
	var/tref = "[REF(target())]"
	forward_topic("tdome1=[tref]")
	return TRUE

UI_ACT(/datum/edit_player_panel, "tdome2", ui_act_tdome2)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_tdome2)
	var/tref = "[REF(target())]"
	forward_topic("tdome2=[tref]")
	return TRUE

UI_ACT(/datum/edit_player_panel, "tdomeadmin", ui_act_tdomeadmin)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_tdomeadmin)
	var/tref = "[REF(target())]"
	forward_topic("tdomeadmin=[tref]")
	return TRUE

UI_ACT(/datum/edit_player_panel, "tdomeobserve", ui_act_tdomeobserve)
UI_ACT_PROC(/datum/edit_player_panel, ui_act_tdomeobserve)
	var/tref = "[REF(target())]"
	forward_topic("tdomeobserve=[tref]")
	return TRUE
// Language

UI_ACT(/datum/edit_player_panel, "toglang", ui_act_toglang, UI_ARG_TEXT("lang"))
UI_ACT_PROC(/datum/edit_player_panel, ui_act_toglang)
	var/tref = "[REF(target())]"
	var/lang = "[params["lang"]]"
	forward_topic("toglang=[tref];lang=[lang]")
	SStgui.update_uis(src)
	return TRUE

/// The holder this refers to (a relation view: null once that is deleted).
/datum/edit_player_panel/proc/holder() as /datum/admins
	return holder

/// The target this refers to (a relation view: null once that is deleted).
/datum/edit_player_panel/proc/target() as /mob
	return target
