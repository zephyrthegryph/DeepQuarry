// Underwear picker. One pick per underwear category (e.g., "Top", "Bottom"),
// drawn from the global underwear catalog.
//
// Wire actions:
//   "pick"     { category: "Top", item: "Item Name" }
//   "clear"    { category }

/datum/preference_editor/underwear
	key = "underwear"
	category = "loadout"
	group = "underwear"
	sort_order = 20
	display_name = "Underwear"
	hidden = TRUE  // integrated into the loadout editor's panel; actions still dispatch here.
	pref_keys = list("all_underwear", "all_underwear_metadata")

/datum/preference_editor/underwear/build_ui_data(datum/preferences/preferences)
	var/list/all_underwear = preferences.read_preference(/datum/preference/all_underwear) || list()
	var/list/payload = list()
	for(var/datum/category_group/underwear/UWC in GLOB.global_underwear.categories)
		payload[UWC.name] = LAZYACCESS(all_underwear, UWC.name) || "None"
	return list("selections" = payload)

/datum/preference_editor/underwear/build_ui_static_data(datum/preferences/preferences)
	// emit per-item icon refs so the React side can render thumbnails.
	var/list/categories = list()
	for(var/datum/category_group/underwear/UWC in GLOB.global_underwear.categories)
		var/list/items = list()
		for(var/datum/category_item/underwear/UWI in UWC.items)
			items += list(list(
				"name" = UWI.name,
				"icon" = UWI.icon ? "[REF(UWI.icon)]" : null,
				"icon_state" = UWI.icon_state,
			))
		categories[UWC.name] = items
	return list("categories" = categories)

/datum/preference_editor/underwear/proc/ui_act_pick(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/all_underwear = preferences.read_preference(/datum/preference/all_underwear) || list()
	var/datum/category_group/underwear/UWC = LAZYACCESS(GLOB.global_underwear.categories_by_name, params["category"])
	if(!UWC)
		return PREF_UPDATE_REJECTED
	var/datum/category_item/underwear/UWI = UWC.items_by_name[params["item"]]
	if(!UWI)
		return PREF_UPDATE_REJECTED
	all_underwear[UWC.name] = UWI.name
	preferences.update_preference_by_type(/datum/preference/all_underwear, all_underwear)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/underwear/proc/ui_act_clear(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/all_underwear = preferences.read_preference(/datum/preference/all_underwear) || list()
	all_underwear -= params["category"]
	preferences.update_preference_by_type(/datum/preference/all_underwear, all_underwear)
	return PREF_UPDATE_ACCEPTED

/// /datum/preference_editor/underwear's actions (the character setup window's "dq_editor_action" messages): each one's arguments go through their schemas first.
/datum/preference_editor/underwear/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/list/typed
	switch(action)
		if("pick")
			typed = payload_args(src, params, list("category" = null, "item" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_pick(user, typed, preferences, null, action)
		if("clear")
			typed = payload_args(src, params, list("category" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_clear(user, typed, preferences, null, action)
	return ..()
