// The stat panel system's API (code/modules/client/statpanel_service.dm declares the system).
//
//   SSstatpanels.immediate_send_stat_data(client)   refresh the client's active tab at once
//   SSstatpanels.set_examine_tab(client)            fill the client's Examine tab

///immediately update the active statpanel tab of the target client
/datum/system/statpanels/proc/immediate_send_stat_data(client/target)
	if(!target.stat_panel.is_ready())
		return FALSE

	if(target.stat_tab == "Examine")
		set_examine_tab(target)
		return TRUE

	if(target.stat_tab == "Status")
		set_status_tab(target)
		return TRUE

	var/mob/target_mob = target.mob

	// Handle actions

	var/update_actions = FALSE
	if(target.stat_tab in target.spell_tabs)
		update_actions = TRUE


	if(update_actions)
		set_action_tabs(target, target_mob)
		return TRUE

	if(!target.holder)
		return FALSE

	if(target.stat_tab == "MC")
		set_MC_tab(target)
		return TRUE

	if(target.stat_tab == "Tickets")
		set_tickets_tab(target)
		return TRUE

	if(!REGISTRY_COUNT(REGISTRY_SDQL2_QUERIES) && ("SDQL2" in target.panel_tabs))
		target.stat_panel.send_message("remove_sdql2")

	else if(REGISTRY_COUNT(REGISTRY_SDQL2_QUERIES) && target.stat_tab == "SDQL2")
		set_SDQL2_tab(target)

/datum/system/statpanels/proc/set_examine_tab(client/target)
	var/description_holders = target.description_holders
	var/list/examine_update = list()

	var/atom/atom_icon = description_holders["icon"]
	var/shown_icon = target.examine_icon()
	if(!shown_icon && atom_icon)
		if(ismob(atom_icon))
			// Flattening a human's dozens of overlays synchronously took 0.8-1.0s
			// per examine and froze the entire BYOND thread. Use an already-cached
			// composite when one exists; otherwise the base mob appearance is a
			// deliberately cheap portrait fallback.
			var/icon/cached_mob_icon = get_cached_examine_icon(atom_icon)
			shown_icon = cached_mob_icon \
				? icon2html(cached_mob_icon, target, sourceonly = TRUE) \
				: icon2html(atom_icon, target, sourceonly = TRUE)
		else if(length(atom_icon.overlays) > 0)
			var/force_south = FALSE
			if(isliving(atom_icon))
				force_south = TRUE
			shown_icon = costly_icon2html(atom_icon, target, sourceonly=TRUE, force_south = force_south)
		else
			shown_icon = icon2html(atom_icon, target, sourceonly=TRUE)
		target.examine_icon = shown_icon
	examine_update += "<img src=\"[shown_icon]\" />&emsp;" + span_giant("[description_holders["name"]]") //The name, written in big letters.
	examine_update += "[description_holders["desc"]]" //the default examine text.
	if(description_holders["info"])
		examine_update += span_blue(span_bold("[replacetext(description_holders["info"], "\n", "<BR>")]")) + "<br />" //Blue, informative text.
	if(description_holders["interactions"])
		for(var/line in description_holders["interactions"])
			examine_update += span_blue(span_bold("[line]")) + "<br />"
	if(description_holders["fluff"])
		examine_update += span_green(span_bold("[replacetext(description_holders["fluff"], "\n", "<BR>")]")) + "<br />" //Green, fluff-related text.
	if(description_holders["antag"])
		examine_update += span_red(span_bold("[description_holders["antag"]]")) + "<br />" //Red, malicious antag-related text

	var/update_panel = FALSE
	if(target.prefs?.read_preference(/datum/preference/choiced/examine_mode) == EXAMINE_MODE_SWITCH_TO_PANEL)
		update_panel = TRUE

	target.stat_panel.send_message("update_examine", list("EX" = examine_update, "UPD" = update_panel))
