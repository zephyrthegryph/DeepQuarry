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

CAPABILITIES(/datum/edit_player_panel)
	ref_one(nameof(holder), /datum/admins)
	ref_one(nameof(target), /mob)
	extend(TAG_UI, needs(req(PROC_REF(ui_gate), silent = TRUE)))
	interface("AdminEditPlayer", rights = R_HOLDER)

	section(admin, "The admin actions of the Edit Player panel: rights, messages, moving, banning, muting")
	op("editrights", ui_act("editrights", arg("mode", schema_text(4096))), then(PROC_REF(ui_act_editrights)))
	op("revive", ui_act("revive"), then(PROC_REF(ui_act_revive)))
	op("vv", ui_act("vv"), then(PROC_REF(ui_act_vv)))
	op("traitor", ui_act("traitor"), then(PROC_REF(ui_act_traitor)))
	op("priv_msg", ui_act("priv_msg"), then(PROC_REF(ui_act_priv_msg)))
	op("subtlemessage", ui_act("subtlemessage"), then(PROC_REF(ui_act_subtlemessage)))
	op("jumpto", ui_act("jumpto"), then(PROC_REF(ui_act_jumpto)))
	op("getmob", ui_act("getmob"), then(PROC_REF(ui_act_getmob)))
	op("sendmob", ui_act("sendmob"), then(PROC_REF(ui_act_sendmob)))
	op("narrateto", ui_act("narrateto"), then(PROC_REF(ui_act_narrateto)))
	op("boot2", ui_act("boot2"), then(PROC_REF(ui_act_boot2)))
	op("warn", ui_act("warn"), then(PROC_REF(ui_act_warn)))
	op("newban", ui_act("newban"), then(PROC_REF(ui_act_newban)))
	op("jobban2", ui_act("jobban2"), then(PROC_REF(ui_act_jobban2)))
	op("notes", ui_act("notes"), then(PROC_REF(ui_act_notes)))
	op("sendtoprison", ui_act("sendtoprison"), then(PROC_REF(ui_act_sendtoprison)))
	op("sendbacktolobby", ui_act("sendbacktolobby"), then(PROC_REF(ui_act_sendbacktolobby)))
	op("forcespeech", ui_act("forcespeech"), then(PROC_REF(ui_act_forcespeech)))
	op("mute", ui_act("mute", arg("mute_type", schema_text(4096))), then(PROC_REF(ui_act_mute)))

	section(transform, "The transformations and thunderdome sends of the Edit Player panel")
	op("turn_monkey", ui_act("turn_monkey"), then(PROC_REF(ui_act_turn_monkey)))
	op("corgione", ui_act("corgione"), then(PROC_REF(ui_act_corgione)))
	op("turn_ai", ui_act("turn_ai"), then(PROC_REF(ui_act_turn_ai)))
	op("turn_robot", ui_act("turn_robot"), then(PROC_REF(ui_act_turn_robot)))
	op("turn_alien", ui_act("turn_alien"), then(PROC_REF(ui_act_turn_alien)))
	op("makeanimal", ui_act("makeanimal"), then(PROC_REF(ui_act_makeanimal)))
	op("respawn", ui_act("respawn"), then(PROC_REF(ui_act_respawn)))
	op("togmutate", ui_act("togmutate", arg("block", schema_text(4096))), then(PROC_REF(ui_act_togmutate)))
	op("simplemake", ui_act("simplemake", arg("kind", schema_text(4096)), arg("species", schema_text(4096))), then(PROC_REF(ui_act_simplemake)))
	op("tdome1", ui_act("tdome1"), then(PROC_REF(ui_act_tdome1)))
	op("tdome2", ui_act("tdome2"), then(PROC_REF(ui_act_tdome2)))
	op("tdomeadmin", ui_act("tdomeadmin"), then(PROC_REF(ui_act_tdomeadmin)))
	op("tdomeobserve", ui_act("tdomeobserve"), then(PROC_REF(ui_act_tdomeobserve)))
	op("toglang", ui_act("toglang", arg("lang", schema_text(4096))), then(PROC_REF(ui_act_toglang)))

/datum/edit_player_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!holder() || !target())
		return FALSE
	return TRUE

/datum/edit_player_panel/ui_title(mob/user)
	return "Edit Player: [target().key]"

/datum/edit_player_panel/ui_data(datum/act/eval/A)
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

/// The answer to a question a button asked still counts (its window is still open and interactive for the one who answers).
/datum/edit_player_panel/proc/request_usable(datum/request/R)
	return window_request_usable(src, R)

/// A panel whose admin or player is gone answers nothing (silently).
/datum/edit_player_panel/proc/ui_gate(datum/act/op/A)
	return holder() && target()

/datum/edit_player_panel/proc/ui_act_editrights(datum/act/op/A, mode_arg)
	var/mode = "[mode_arg]"
	forward_topic("editrights=[mode];key=[target().key]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_revive(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("revive=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_vv(datum/act/op/A)
	var/mob/user = A.actor
	var/tref = "[REF(target())]"
	user.client?.vv_topic(list("Vars" = tref), TRUE)
	return TRUE

/datum/edit_player_panel/proc/ui_act_traitor(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("traitor=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_priv_msg(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("priv_msg=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_subtlemessage(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("subtlemessage=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_jumpto(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("jumpto=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_getmob(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("getmob=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_sendmob(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("sendmob=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_narrateto(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("narrateto=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_boot2(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("boot2=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_warn(datum/act/op/A)
	forward_topic("warn=[target().ckey]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_newban(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("newban=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_jobban2(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("jobban2=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_notes(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("notes=show;mob=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_sendtoprison(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("sendtoprison=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_sendbacktolobby(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("sendbacktolobby=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_forcespeech(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("forcespeech=[tref]")
	return TRUE

// Mute toggles

/datum/edit_player_panel/proc/ui_act_mute(datum/act/op/A, mute_type_arg)
	var/tref = "[REF(target())]"
	var/mute_type = "[mute_type_arg]"
	forward_topic("mute=[tref];mute_type=[mute_type]")
	return TRUE
// Transformation

/datum/edit_player_panel/proc/ui_act_turn_monkey(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("turn_monkey=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_corgione(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("corgione=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_turn_ai(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("turn_ai=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_turn_robot(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("turn_robot=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_turn_alien(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("turn_alien=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_makeanimal(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("makeanimal=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_respawn(datum/act/op/A)
	var/cref = target().client ? "[REF(target().client)]" : null
	if(cref)
		forward_topic("respawn=[cref]")
	return TRUE

// DNA gene toggle

/datum/edit_player_panel/proc/ui_act_togmutate(datum/act/op/A, block_arg)
	var/tref = "[REF(target())]"
	var/block = "[block_arg]"
	forward_topic("togmutate=[tref];block=[block]")
	return TRUE
// simplemake

/datum/edit_player_panel/proc/ui_act_simplemake(datum/act/op/A, kind_arg, species_arg)
	var/tref = "[REF(target())]"
	var/kind = "[kind_arg]"
	var/species = "[species_arg]"
	var/qs = "simplemake=[kind];mob=[tref]"
	if(length(species))
		qs += ";species=[species]"
	forward_topic(qs)
	return TRUE
// Thunderdome

/datum/edit_player_panel/proc/ui_act_tdome1(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("tdome1=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_tdome2(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("tdome2=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_tdomeadmin(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("tdomeadmin=[tref]")
	return TRUE

/datum/edit_player_panel/proc/ui_act_tdomeobserve(datum/act/op/A)
	var/tref = "[REF(target())]"
	forward_topic("tdomeobserve=[tref]")
	return TRUE

// Language

/datum/edit_player_panel/proc/ui_act_toglang(datum/act/op/A, lang_arg)
	var/tref = "[REF(target())]"
	var/lang = "[lang_arg]"
	forward_topic("toglang=[tref];lang=[lang]")
	return TRUE

/// The holder this refers to (a relation view: null once that is deleted).
/datum/edit_player_panel/proc/holder() as /datum/admins
	return holder

/// The target this refers to (a relation view: null once that is deleted).
/datum/edit_player_panel/proc/target() as /mob
	return target
