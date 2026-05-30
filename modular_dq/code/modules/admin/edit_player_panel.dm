// Edit Player ("Show Player Panel") — structured TGUI replacement.
//
// This is the right-click → Show Player Panel admin context menu. The legacy
// panel was ~200 lines of conditional HTML with ~40 distinct byond:// link
// types. All clicks here forward back to /datum/admins.Topic via _src_=holder
// so the existing action handlers stay in place.

GLOBAL_LIST_EMPTY(dq_edit_player_panels)

/datum/admins/proc/dq_open_edit_player_panel(mob/player)
	if(!owner || !player)
		return
	var/key = "[REF(src)]-[REF(player)]"
	var/datum/edit_player_panel/panel = LAZYACCESS(GLOB.dq_edit_player_panels, key)
	if(!panel)
		panel = new(src, player)
		GLOB.dq_edit_player_panels[key] = panel
	panel.tgui_interact(owner)

/datum/edit_player_panel
	var/datum/admins/holder
	var/mob/target

/datum/edit_player_panel/New(datum/admins/owner_holder, mob/target_mob)
	holder = owner_holder
	target = target_mob

/datum/edit_player_panel/Destroy(force, ...)
	if(holder && target)
		GLOB.dq_edit_player_panels -= "[REF(holder)]-[REF(target)]"
	holder = null
	target = null
	return ..()

/datum/edit_player_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_HOLDER)

/datum/edit_player_panel/tgui_interact(mob/user, datum/tgui/ui)
	if(!holder || !target)
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AdminEditPlayer", "Edit Player: [target.key]")
		ui.open()

/datum/edit_player_panel/tgui_data(mob/user)
	var/list/data = list()
	if(!target)
		return data
	data["ref"] = "[REF(target)]"
	data["name"] = "[target]"
	data["key"] = target.key || ""
	data["mob_type"] = "[target.type]"
	data["has_client"] = !!target.client
	data["is_newplayer"] = !!isnewplayer(target)
	data["is_human"] = !!ishuman(target)
	data["is_ai"] = !!isAI(target)
	data["is_carbon"] = !!iscarbon(target)
	data["is_small"] = !!issmall(target)
	data["is_corgi"] = !!iscorgi(target)
	data["is_animal"] = !!isanimal(target)
	if(target.client)
		data["client_name"] = "[target.client]"
		data["client_ref"] = "[REF(target.client)]"
		data["client_ckey"] = target.client.ckey
		data["player_age"] = target.client.player_age
		data["account_join_date"] = target.client.account_join_date
		data["account_age"] = target.client.account_age
		data["inactivity_minutes"] = round(target.client.inactivity / 600)
		data["rank_names"] = target.client.holder ? target.client.holder.rank_names() : "Player"
		data["editrights_mode"] = (GLOB.admin_datums[target.client.ckey] || GLOB.deadmins[target.client.ckey]) ? "rank" : "add"
		data["muted"] = target.client.prefs.muted
	else
		data["client_name"] = null
		data["client_ref"] = null
		data["inactivity_minutes"] = -1
		data["muted"] = 0

	data["can_event"] = !!check_rights(R_ADMIN|R_MOD|R_EVENT, 0)
	data["special_character"] = is_special_character(target)

	// Mute mask constants exposed so the React side doesn't hardcode them.
	data["mute_mask_ic"] = MUTE_IC
	data["mute_mask_ooc"] = MUTE_OOC
	data["mute_mask_looc"] = MUTE_LOOC
	data["mute_mask_pray"] = MUTE_PRAY
	data["mute_mask_adminhelp"] = MUTE_ADMINHELP
	data["mute_mask_deadchat"] = MUTE_DEADCHAT
	data["mute_mask_all"] = MUTE_ALL

	// DNA — only meaningful for carbons with a DNA struct.
	if(target.dna && iscarbon(target))
		var/list/dna_cells = list()
		var/list/gene_lookup = get_gene_lookup()
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
				if(bname in target.active_genes)
					cell_state = "active"
				else if(target.dna.GetSEState(block))
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
	for(var/k in get_non_innate_language_keys())
		langs += list(list(
			"key" = k,
			"known" = (GLOB.all_languages[k] in target.languages),
		))
	data["languages"] = langs

	return data

/datum/edit_player_panel/proc/get_gene_lookup()
	var/static/list/lookup
	if(lookup)
		return lookup
	lookup = list()
	for(var/setup_block = 1; setup_block <= DNA_SE_LENGTH; setup_block++)
		lookup["[setup_block]"] = null
	for(var/datum/gene/gene in GLOB.dna_genes)
		lookup["[gene.block]"] = gene
	return lookup

/datum/edit_player_panel/proc/get_non_innate_language_keys()
	var/static/list/keys
	if(keys)
		return keys
	keys = list()
	for(var/k in GLOB.all_languages)
		var/datum/language/L = GLOB.all_languages[k]
		if(L.flags & INNATE)
			continue
		keys += k
	return keys

/datum/edit_player_panel/proc/forward_topic(qs, list/extra_params = null)
	forward_holder_topic(holder, qs, extra_params)

/datum/edit_player_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(. || !holder || !target)
		return
	// Most actions take action=<x>=REF(target) form. Build the ref once.
	var/tref = "[REF(target)]"
	var/cref = target.client ? "[REF(target.client)]" : null
	switch(action)
		// Header actions
		if("editrights")
			var/mode = "[params["mode"]]"
			forward_topic("editrights=[mode];key=[target.key]")
			SStgui.update_uis(src)
			return TRUE
		if("revive")
			forward_topic("revive=[tref]")
			SStgui.update_uis(src)
			return TRUE
		if("vv")
			holder.Topic("Vars=[tref]", list("_src_" = "vars", "Vars" = tref))
			return TRUE
		if("traitor")
			forward_topic("traitor=[tref]")
			SStgui.update_uis(src)
			return TRUE
		if("priv_msg")
			forward_topic("priv_msg=[tref]")
			return TRUE
		if("subtlemessage")
			forward_topic("subtlemessage=[tref]")
			return TRUE
		if("jumpto")
			forward_topic("jumpto=[tref]")
			return TRUE
		if("getmob")
			forward_topic("getmob=[tref]")
			return TRUE
		if("sendmob")
			forward_topic("sendmob=[tref]")
			return TRUE
		if("narrateto")
			forward_topic("narrateto=[tref]")
			return TRUE
		if("boot2")
			forward_topic("boot2=[tref]")
			SStgui.update_uis(src)
			return TRUE
		if("warn")
			forward_topic("warn=[target.ckey]")
			return TRUE
		if("newban")
			forward_topic("newban=[tref]")
			SStgui.update_uis(src)
			return TRUE
		if("jobban2")
			forward_topic("jobban2=[tref]")
			return TRUE
		if("notes")
			forward_topic("notes=show;mob=[tref]")
			return TRUE
		if("sendtoprison")
			forward_topic("sendtoprison=[tref]")
			SStgui.update_uis(src)
			return TRUE
		if("sendbacktolobby")
			forward_topic("sendbacktolobby=[tref]")
			SStgui.update_uis(src)
			return TRUE
		if("forcespeech")
			forward_topic("forcespeech=[tref]")
			return TRUE
		// Mute toggles
		if("mute")
			var/mute_type = "[params["mute_type"]]"
			forward_topic("mute=[tref];mute_type=[mute_type]")
			SStgui.update_uis(src)
			return TRUE
		// Transformation
		if("turn_monkey")
			forward_topic("turn_monkey=[tref]")
			SStgui.update_uis(src)
			return TRUE
		if("corgione")
			forward_topic("corgione=[tref]")
			SStgui.update_uis(src)
			return TRUE
		if("turn_ai")
			forward_topic("turn_ai=[tref]")
			SStgui.update_uis(src)
			return TRUE
		if("turn_robot")
			forward_topic("turn_robot=[tref]")
			SStgui.update_uis(src)
			return TRUE
		if("turn_alien")
			forward_topic("turn_alien=[tref]")
			SStgui.update_uis(src)
			return TRUE
		if("makeanimal")
			forward_topic("makeanimal=[tref]")
			SStgui.update_uis(src)
			return TRUE
		if("respawn")
			if(cref)
				forward_topic("respawn=[cref]")
				SStgui.update_uis(src)
			return TRUE
		// DNA gene toggle
		if("togmutate")
			var/block = "[params["block"]]"
			forward_topic("togmutate=[tref];block=[block]")
			SStgui.update_uis(src)
			return TRUE
		// simplemake
		if("simplemake")
			var/kind = "[params["kind"]]"
			var/species = "[params["species"]]"
			var/qs = "simplemake=[kind];mob=[tref]"
			if(length(species))
				qs += ";species=[species]"
			forward_topic(qs)
			SStgui.update_uis(src)
			return TRUE
		// Thunderdome
		if("tdome1")
			forward_topic("tdome1=[tref]")
			return TRUE
		if("tdome2")
			forward_topic("tdome2=[tref]")
			return TRUE
		if("tdomeadmin")
			forward_topic("tdomeadmin=[tref]")
			return TRUE
		if("tdomeobserve")
			forward_topic("tdomeobserve=[tref]")
			return TRUE
		// Language
		if("toglang")
			var/lang = "[params["lang"]]"
			forward_topic("toglang=[tref];lang=[lang]")
			SStgui.update_uis(src)
			return TRUE
