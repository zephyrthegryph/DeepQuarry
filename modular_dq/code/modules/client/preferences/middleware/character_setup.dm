// DQAdd — Character setup UI middleware. Walks the /datum/preference registry, groups by
// category + group, and assembles the JSON payload the new TGUI window consumes.
//
// Replaces bay_adapter for the character-prefs window. bay_adapter stays (for now) to keep
// the legacy /datum/category_item/player_setup_item rendering working alongside; the
// demolition pass will delete bay_adapter entirely.

/datum/preference_middleware/character_setup
	key = "character_setup"

// DQAdd — explicit category order so the top-tab buttons don't dance every refresh.
// Categories not listed here fall to the end in alphabetical order. Names must match the
// `category` field tag_pref writes onto singletons (see _pref_metadata.dm).
GLOBAL_LIST_INIT(dq_category_order, list(
	"identity",
	"appearance",
	"size_voice",
	"loadout",
	"occupation",
	"traits",
	"mind_body",
	"antag",
	"vore",
	"game",
	"misc",
))

// DQAdd — Groups in this set start collapsed on the React side. Use for niche / long-form
// content where the default-expanded state would dominate the page visually.
GLOBAL_LIST_INIT(dq_collapsed_groups, list(
	"records"      = TRUE,
	"ooc_notes"    = TRUE,
	"flavor"       = TRUE,
	"speech_verbs" = TRUE,
	"pai"          = TRUE,
	"nif"          = TRUE,
	"persistence"  = TRUE,
))

/datum/preference_middleware/character_setup/get_ui_data(mob/user)
	var/list/data = ..()

	if(preferences.current_window != PREFERENCE_TAB_CHARACTER_PREFERENCES)
		return data

	// Build the category page list. Each category has zero or more groups; each group has
	// widget items (auto-rendered) and editor items (delegated to a registered editor).
	var/list/categories_data = list()
	var/list/categories_by_name = list() // name -> categories_data entry, for ordering

	for(var/pref_type in GLOB.preference_entries)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		if(pref.savefile_identifier != PREFERENCE_CHARACTER)
			continue
		var/widget_hint = pref.get_widget(preferences)
		if(widget_hint == PREF_WIDGET_HIDDEN)
			continue
		var/cat = pref.get_category(preferences)
		if(!cat)
			cat = "misc"
		var/grp = pref.get_group(preferences) || ""

		var/list/category_entry = categories_by_name[cat]
		if(!category_entry)
			category_entry = list("category" = cat, "groups" = list())
			categories_by_name[cat] = category_entry
			categories_data += list(category_entry)

		var/list/groups = category_entry["groups"]
		var/list/group_entry
		for(var/list/g as anything in groups)
			if(g["group"] == grp)
				group_entry = g
				break
		if(!group_entry)
			group_entry = list("group" = grp, "items" = list(), "collapsed" = LAZYACCESS(GLOB.dq_collapsed_groups, grp) ? TRUE : FALSE)
			groups += list(group_entry)

		var/list/widget_payload = list(
			"type" = "widget",
			"key" = pref.savefile_key,
			"label" = pref.display_label,
			"widget" = widget_hint,
			"value" = preferences.read_preference(pref_type),
			"props" = pref.get_widget_props(preferences),
		)
		var/list/choices = pref.get_pref_choices(preferences)
		if(choices)
			widget_payload["choices"] = choices
		var/list/thumbnails = pref.get_pref_thumbnails(preferences)
		if(thumbnails)
			widget_payload["thumbnails"] = thumbnails

		group_entry["items"] += list(widget_payload)

	// Mix editors into their categories/groups.
	for(var/datum/preference_editor/editor as anything in GLOB.preference_editors)
		if(editor.hidden)
			continue
		var/list/category_entry = categories_by_name[editor.category]
		if(!category_entry)
			category_entry = list("category" = editor.category, "groups" = list())
			categories_by_name[editor.category] = category_entry
			categories_data += list(category_entry)

		var/list/groups = category_entry["groups"]
		var/list/group_entry
		for(var/list/g as anything in groups)
			if(g["group"] == (editor.group || ""))
				group_entry = g
				break
		if(!group_entry)
			group_entry = list("group" = editor.group || "", "items" = list())
			groups += list(group_entry)

		group_entry["items"] += list(list(
			"type" = "editor",
			"key" = editor.key,
			"sort_order" = editor.sort_order,
			"display_name" = editor.display_name,
			"data" = editor.build_ui_data(preferences),
		))

	// DQEdit — drop categories whose only contents are empty groups (every pref/editor is
	// HIDDEN or the category had only hidden composite items). Prevents the top tabs from
	// rendering "Occupation" / "Persistence" buttons that open to a blank page.
	var/list/non_empty = list()
	for(var/list/cat as anything in categories_data)
		var/has_items = FALSE
		for(var/list/grp as anything in cat["groups"])
			if(length(grp["items"]))
				has_items = TRUE
				break
		if(has_items)
			non_empty += list(cat)
	categories_data = non_empty

	// DQEdit — sort categories by explicit order then alphabetical so the top tabs are
	// stable across refreshes (previously order was first-encounter while iterating
	// preference_entries, which let new entries shove existing tabs around).
	sortTim(categories_data, GLOBAL_PROC_REF(dq_cmp_category_entries))

	data["dq_categories"] = categories_data
	return data

/proc/dq_cmp_category_entries(list/a, list/b)
	var/aidx = GLOB.dq_category_order.Find(a["category"])
	var/bidx = GLOB.dq_category_order.Find(b["category"])
	if(aidx && bidx)
		return aidx - bidx
	if(aidx)
		return -1
	if(bidx)
		return 1
	return cmptext(a["category"], b["category"])

/datum/preference_middleware/character_setup/get_ui_static_data(mob/user)
	var/list/data = ..()

	if(preferences.current_window != PREFERENCE_TAB_CHARACTER_PREFERENCES)
		return data

	var/list/static_editors = list()
	for(var/datum/preference_editor/editor as anything in GLOB.preference_editors)
		var/list/static_payload = editor.build_ui_static_data(preferences)
		if(static_payload && static_payload.len)
			static_editors[editor.key] = static_payload
	if(static_editors.len)
		data["dq_editor_static"] = static_editors

	return data

/datum/preference_middleware/character_setup/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		// Single-pref update from the auto-renderer.
		if("dq_update_preference")
			var/key = params["key"]
			var/value = params["value"]
			var/datum/preference/pref = GLOB.preference_entries_by_key[key]
			if(!pref)
				return FALSE
			preferences.update_preference(pref, value)
			return TRUE

		// Color picker for /datum/preference/color/* widgets. The React side has no
		// reliable native color input, so it asks BYOND to open tgui_color_picker; the
		// chosen value is written through the same update_preference path so constraints
		// and apply-hooks fire identically to a typed write.
		if("dq_pick_color")
			var/key = params["key"]
			var/datum/preference/pref = GLOB.preference_entries_by_key[key]
			if(!pref)
				return FALSE
			var/current = preferences.read_preference(pref.type)
			var/new_color = tgui_color_picker(ui.user, "Pick a color", "Color", current || "#000000")
			if(!new_color)
				return TRUE  // user cancelled; nothing to write
			// tgui_color_picker sleeps — the player can move, log off, swap characters, or
			// have their prefs torn down while it's open. Re-verify before writing.
			if(!ui.user?.client?.prefs || ui.user.client.prefs != preferences)
				return TRUE
			if(!pref.is_accessible(preferences))
				return TRUE
			preferences.update_preference(pref, new_color)
			return TRUE

		// Atomic multi-pref operation handled by a registered editor.
		if("dq_editor_action")
			var/editor_key = params["editor"]
			var/datum/preference_editor/editor = GLOB.preference_editors_by_key[editor_key]
			if(!editor)
				return FALSE
			var/result = editor.handle_action(preferences, params["action"], params["params"], ui.user)
			return (result == PREF_UPDATE_ACCEPTED)
