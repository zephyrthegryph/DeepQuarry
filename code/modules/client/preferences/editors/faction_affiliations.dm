/datum/preference_editor/faction_affiliations
	key = "faction_affiliations"
	category = "factions"
	group = ""
	sort_order = 10
	display_name = "Faction affiliations"
	pref_keys = list("faction_affiliations")

/datum/preference_editor/faction_affiliations/build_ui_data(datum/preferences/preferences)
	var/list/affiliations = preferences.read_preference(/datum/preference/faction_affiliations)
	return list(
		"affiliations" = affiliations,
		"reputation_total" = reputation_affiliation_total(affiliations),
		"reputation_cap" = REPUTATION_AFFILIATION_NET_CAP,
	)

/datum/preference_editor/faction_affiliations/build_ui_static_data(datum/preferences/preferences)
	var/list/factions = list()
	for(var/faction_id in GLOB.reputation_factions)
		var/datum/reputation_faction/faction = GLOB.reputation_factions[faction_id]
		factions += list(list(
			"id" = faction.id,
			"name" = faction.name,
			"short_name" = faction.short_name,
			"acronym" = faction.acronym,
			"description" = faction.description,
			"color" = faction.color,
			"grid_x" = faction.grid_x,
			"grid_y" = faction.grid_y,
		))
	return list(
		"factions" = factions,
		"choices" = GLOB.reputation_affiliation_choices,
	)

/datum/preference_editor/faction_affiliations/proc/ui_act_set_affiliation(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/faction_id = params["faction"]
	var/affiliation = params["affiliation"]
	if(isnull(faction_id) || isnull(affiliation))
		return PREF_UPDATE_REJECTED
	var/list/current = preferences.read_preference(/datum/preference/faction_affiliations)
	current = islist(current) ? current.Copy() : list()
	if(current[faction_id] == affiliation)
		return PREF_UPDATE_UNCHANGED
	current[faction_id] = affiliation
	var/new_total = reputation_affiliation_total(current)
	if(new_total > REPUTATION_AFFILIATION_NET_CAP)
		to_chat(user, span_warning("Your starting faction reputation cannot total more than [REPUTATION_AFFILIATION_NET_CAP]. Choose a negative affiliation before adding more positive reputation."))
		return PREF_UPDATE_REJECTED
	return preferences.update_preference_by_type(/datum/preference/faction_affiliations, current) ? PREF_UPDATE_ACCEPTED : PREF_UPDATE_REJECTED

/// /datum/preference_editor/faction_affiliations's actions (the character setup window's "dq_editor_action" messages): each one's arguments go through their schemas first.
/datum/preference_editor/faction_affiliations/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/list/typed
	switch(action)
		if("set_affiliation")
			typed = payload_args(src, params, list("faction" = enum(GLOB.reputation_factions), "affiliation" = enum(GLOB.reputation_affiliation_choices)))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_affiliation(user, typed, preferences, null, action)
	return ..()
