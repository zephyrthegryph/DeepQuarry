// Character setup UI middleware. Walks the /datum/preference registry, groups by
// category + group, and assembles the JSON payload the new TGUI window consumes.
//
// Replaced the old bay_adapter middleware and /datum/category_item/player_setup_item
// framework entirely. All slot/persistence actions (load, save, reload, resetslot,
// copy, game_prefs, refresh_character_preview, cycle_background) are now handled
// directly in tgui_act on /datum/preferences.

/datum/preference_middleware/character_setup
	key = "character_setup"

// explicit category order so the top-tab buttons don't dance every refresh.
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
	"game",
	"misc",
))

// play-mode filter lists.
//
// /datum/preference/text/human/play_mode is one of "human" (default), "robot",
// or "pai" — set by the SpeciesPicker editor when the player selects the
// synthetic "Robot" / "pAI" entries. The middleware filters out groups/keys
// that don't apply to the selected mode:
//   - robot: drop organic-body customization (hair, eyes, skin, tail, wings,
//            blood, markings, organs), drop mind/body/vore/loadout/traits.
//   - pai:   drop everything physical — pAI is a holopad, no body customization
//            at all. Pref names + a slim flavor block is all that matters.
//   - human: drop the chassis group (cyborg-only).

GLOBAL_LIST_INIT(dq_robot_mode_hidden_categories, list(
	"mind_body",
	"loadout",
	"traits",
	"occupation",  // Cyborg job is auto-set when picking Robot species; no need to surface the job priority editor.
))

GLOBAL_LIST_INIT(dq_robot_mode_hidden_groups, list(
	"hair",
	"ears",
	"tail",
	"wings",
	"blood",
	"markings",
	"organs",
	"body",     // All body-group prefs (s_tone, skin_color, eyes_color, digitigrade, synth_color/markings) are organic-only.
	"preview",  // Animations toggle / preview_loadout / preview_job don't apply to chassis-sprite previews.
	"nif",      // Cyborgs don't have NIFs (those are neural interfaces for organic brains).
	"pai",      // Cyborgs aren't pAIs.
	"demographics",  // Age / bday is meaningless for cyborgs.
	"background",    // Birthplace, citizenship, religion etc. don't apply to a cyborg in chargen.
	"records",       // Medical/security records are for organic chars.
	"directory",     // Vore directory ad / sexuality tags — out-of-character for a chassis pick.
	"roleplay",      // Egg type / hot-cold messages / borg petting — RP flavor that doesn't apply to a fresh cyborg.
	// flavor group stays visible — FlavorTextEditor switches to robot flavor inputs in robot mode.
))

GLOBAL_LIST_INIT(dq_robot_mode_hidden_pref_keys, list(
	"s_tone"         = TRUE,
	"skin_color"     = TRUE,
	"eyes_color"     = TRUE,
	"digitigrade"    = TRUE,
	// synth_color / synth_markings live on /mob/living/carbon/human (they
	// color synth limbs on organic bodies or synth species like Protean).
	// Cyborgs are /mob/living/silicon/robot — these vars don't exist there.
	"synth_color"    = TRUE,
	"synth_markings" = TRUE,
))

// pAI: holopad with no body. Strip everything physical and most stat configuration.
GLOBAL_LIST_INIT(dq_pai_mode_hidden_categories, list(
	"appearance",
	"size_voice",
	"mind_body",
	"loadout",
	"traits",
	"antag",
	"occupation",
))

GLOBAL_LIST_INIT(dq_pai_mode_hidden_groups, list(
	"chassis",
	"hair",
	"ears",
	"tail",
	"wings",
	"blood",
	"markings",
	"organs",
	"body",
	"demographics",
	"background",
	"speech_verbs",
	"spawn",
	"records",       // Medical/security records — pAIs aren't on the station roster.
	"persistence",   // Body resleeve / mind scan — pAIs don't have bodies.
	"nif",           // pAIs don't have neural interfaces.
	"directory",     // Vore directory — pAIs aren't on it.
	"roleplay",      // RP flavor tied to physical bodies.
))

GLOBAL_LIST_INIT(dq_pai_mode_hidden_pref_keys, list(
	"s_tone"         = TRUE,
	"skin_color"     = TRUE,
	"eyes_color"     = TRUE,
	"digitigrade"    = TRUE,
	"synth_color"    = TRUE,
	"synth_markings" = TRUE,
))

GLOBAL_LIST_INIT(dq_human_mode_hidden_groups, list(
	"chassis",  // Cyborg chassis editor — humans don't have one.
	"pai",      // pAI card config — humans aren't pAIs.
))

// Nothing pref-level is hidden in human mode at the moment — the chassis
// group filter (above) already takes care of the cyborg-only editor.
GLOBAL_LIST_INIT(dq_human_mode_hidden_pref_keys, list(
))

// Category names are invariant for each play mode. Keep this structural index
// globally instead of making every preferences datum discover it by invoking
// contextual widget/choice providers across the complete preference registry.
/proc/dq_character_category_index(play_mode)
	var/static/list/index_by_mode = list()
	if(islist(index_by_mode[play_mode]))
		return index_by_mode[play_mode].Copy()

	var/playing_as_robot = (play_mode == "robot")
	var/playing_as_pai = (play_mode == "pai")
	var/list/categories = list()
	for(var/pref_type in GLOB.preference_entries)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		if(pref.savefile_identifier != PREFERENCE_CHARACTER || pref.widget == PREF_WIDGET_HIDDEN)
			continue
		var/cat = pref.category || "misc"
		if(cat == PREFERENCE_CATEGORY_MANUALLY_RENDERED || cat == PREFERENCE_CATEGORY_NON_CONTEXTUAL)
			continue
		var/grp = pref.group || ""
		if(playing_as_pai)
			if(cat in GLOB.dq_pai_mode_hidden_categories || grp in GLOB.dq_pai_mode_hidden_groups || GLOB.dq_pai_mode_hidden_pref_keys[pref.savefile_key])
				continue
		else if(playing_as_robot)
			if(cat in GLOB.dq_robot_mode_hidden_categories || grp in GLOB.dq_robot_mode_hidden_groups || GLOB.dq_robot_mode_hidden_pref_keys[pref.savefile_key])
				continue
		else if(grp in GLOB.dq_human_mode_hidden_groups || GLOB.dq_human_mode_hidden_pref_keys[pref.savefile_key])
			continue
		categories[cat] = TRUE

	for(var/datum/preference_editor/editor as anything in GLOB.preference_editors)
		if(editor.hidden)
			continue
		if(editor.key != "species_picker")
			if(playing_as_pai)
				if(editor.category in GLOB.dq_pai_mode_hidden_categories || (editor.group && (editor.group in GLOB.dq_pai_mode_hidden_groups)))
					continue
			else if(playing_as_robot)
				if(editor.category in GLOB.dq_robot_mode_hidden_categories || (editor.group && (editor.group in GLOB.dq_robot_mode_hidden_groups)))
					continue
			else if(editor.group && (editor.group in GLOB.dq_human_mode_hidden_groups))
				continue
		categories[editor.category] = TRUE

	var/list/result = list()
	for(var/ordered_category in GLOB.dq_category_order)
		if(categories[ordered_category])
			result += ordered_category
			categories -= ordered_category
	var/list/remainder = list()
	for(var/category in categories)
		remainder += category
	sortTim(remainder, GLOBAL_PROC_REF(cmp_text_asc))
	result += remainder
	index_by_mode[play_mode] = result
	return result.Copy()

// Reverse-index of editor.static_invalidator_keys: maps a pref
// savefile_key → list(/datum/preference_editor) that should be rebuilt when
// that key changes. Built once at world init from the editors' declarations
// (see /datum/preference_editor.static_invalidator_keys). update_preference
// uses this to do PER-EDITOR cache invalidation instead of nuking the entire
// cache when a structural pref flips — species changes used to invalidate
// every catalog (markings + hair + trait + mind_body + loadout, ~2s rebuild
// total) when only loadout actually depended on species.
GLOBAL_LIST_INIT(dq_editor_static_invalidators_by_key, dq_build_editor_static_invalidator_index())

/proc/dq_build_editor_static_invalidator_index()
	. = list()
	for(var/datum/preference_editor/editor as anything in GLOB.preference_editors)
		if(!islist(editor.static_invalidator_keys))
			continue
		for(var/k in editor.static_invalidator_keys)
			LAZYADD(.[k], editor)

// Explicit per-category group order. Groups within a category render in
// this order in the React grid; groups not listed fall to the end alphabetically.
// Without this, group order followed first-encounter of GLOB.preference_entries
// which is type-registration order (not file order), so "Name" wasn't reliably
// first in Identity even though the metadata file lists it first.
GLOBAL_LIST_INIT(dq_group_order, list(
	"identity"    = list("name", "gender", "demographics", "species", "spawn", "language", "background", "speech_verbs", "flavor", "directory", "records", "ooc_notes"),
	"appearance"  = list("chassis", "body", "hair", "ears", "tail", "wings", "blood", "markings", "organs", "preview"),
	"size_voice"  = list("size", "voice"),
	"antag"       = list("antag", "be_special"),
	"game"        = list("input", "view", "sound", "ui", "chat", "persistence", "roleplay", "nif", "pai"),
))

/datum/preference_middleware/character_setup/proc/dq_build_category_structure(category_filter, include_details = TRUE)
	// Build the category page list. Each category has zero or more groups; each group has
	// widget items (auto-rendered) and editor items (delegated to a registered editor).
	var/list/categories_data = list()
	var/list/categories_by_name = list() // name -> categories_data entry, for ordering

	// play-mode gating. "robot" collapses organic-only categories /
	// groups / keys; "pai" collapses everything physical; "human" collapses
	// synth-only entries. The species_picker editor (which drives play_mode)
	// is always allowed through so the player has an escape hatch back to
	// human mode.
	var/play_mode = preferences.read_preference(/datum/preference/text/human/play_mode) || "human"
	var/playing_as_robot = (play_mode == "robot")
	var/playing_as_pai = (play_mode == "pai")

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
		// categories the user shouldn't see as a tab. Manually rendered
		// prefs are handled by a specific editor (markings, traits, mind/body…)
		// and either get tag_pref'd to a real category OR should just not surface.
		// Non-contextual prefs (max_traits, starting_trait_points, etc.) are
		// managed-state — never user-editable. Skipping them at the iteration
		// level avoids "Manually Rendered Features" and "Non Contextual" tabs
		// eating column space in the strip.
		if(cat == PREFERENCE_CATEGORY_MANUALLY_RENDERED || cat == PREFERENCE_CATEGORY_NON_CONTEXTUAL)
			continue
		var/grp = pref.get_group(preferences) || ""

		// play-mode gating. play_mode is itself a hidden pref so
		// no escape hatch needed here; the species_picker editor below is
		// always allowed through.
		if(playing_as_pai)
			if(cat in GLOB.dq_pai_mode_hidden_categories)
				continue
			if(grp in GLOB.dq_pai_mode_hidden_groups)
				continue
			if(GLOB.dq_pai_mode_hidden_pref_keys[pref.savefile_key])
				continue
		else if(playing_as_robot)
			if(cat in GLOB.dq_robot_mode_hidden_categories)
				continue
			if(grp in GLOB.dq_robot_mode_hidden_groups)
				continue
			if(GLOB.dq_robot_mode_hidden_pref_keys[pref.savefile_key])
				continue
		else
			if(grp in GLOB.dq_human_mode_hidden_groups)
				continue
			if(GLOB.dq_human_mode_hidden_pref_keys[pref.savefile_key])
				continue
		if(category_filter && cat != category_filter)
			continue

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
			group_entry = list("group" = grp, "items" = list())
			groups += list(group_entry)

		var/list/widget_payload = list(
			"type" = "widget",
			"key" = pref.savefile_key,
			"label" = pref.display_label,
			"widget" = widget_hint,
			"props" = include_details ? pref.get_widget_props(preferences) : list(),
		)
		if(include_details)
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
		// same play-mode gating as for prefs. SpeciesPicker is the
		// always-visible escape hatch (player needs a way to switch modes).
		if(editor.key != "species_picker")
			if(playing_as_pai)
				if(editor.category in GLOB.dq_pai_mode_hidden_categories)
					continue
				if(editor.group && (editor.group in GLOB.dq_pai_mode_hidden_groups))
					continue
			else if(playing_as_robot)
				if(editor.category in GLOB.dq_robot_mode_hidden_categories)
					continue
				if(editor.group && (editor.group in GLOB.dq_robot_mode_hidden_groups))
					continue
			else
				if(editor.group && (editor.group in GLOB.dq_human_mode_hidden_groups))
					continue
		if(category_filter && editor.category != category_filter)
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
		))

	// drop categories whose only contents are empty groups (every pref/editor is
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

	// sort categories by explicit order then alphabetical so the top tabs are
	// stable across refreshes (previously order was first-encounter while iterating
	// preference_entries, which let new entries shove existing tabs around).
	sortTim(categories_data, GLOBAL_PROC_REF(dq_cmp_category_entries))

	// sort groups WITHIN each category by GLOB.dq_group_order. Without
	// this, "Identity" would render whichever group was hit first by the
	// preference_entries iteration, which made "name" fall below "gender" or
	// "species" depending on registration order. sortTim's comparator can't
	// capture state, so we pre-stamp each group with a sort_priority based on
	// its position in dq_group_order and sort by that.
	for(var/list/cat as anything in categories_data)
		var/list/category_order = GLOB.dq_group_order[cat["category"]]
		if(islist(category_order) && length(cat["groups"]) > 1)
			for(var/list/group as anything in cat["groups"])
				var/idx = category_order.Find(group["group"])
				group["sort_priority"] = idx ? idx : 999
			sortTim(cat["groups"], GLOBAL_PROC_REF(dq_cmp_group_by_sort_priority))

	return categories_data

/datum/preference_middleware/character_setup/proc/dq_ensure_category_cache(category_key)
	if(!islist(preferences.dq_category_static_cache))
		preferences.dq_category_static_cache = list()
	if(!islist(preferences.dq_category_index))
		var/play_mode = preferences.read_preference(/datum/preference/text/human/play_mode) || "human"
		preferences.dq_category_index = dq_character_category_index(play_mode)
	if(!category_key || (category_key in preferences.dq_category_static_cache))
		return
	var/list/categories_data = dq_build_category_structure(category_key, TRUE)
	for(var/list/category as anything in categories_data)
		for(var/list/group as anything in category["groups"])
			for(var/list/item as anything in group["items"])
				if(item["type"] == "widget")
					item -= "value"
				else if(item["type"] == "editor")
					item -= "data"
		var/built_category_key = category["category"]
		preferences.dq_category_static_cache[built_category_key] = category

/datum/preference_middleware/character_setup/proc/dq_editor_version(editor_key)
	LAZYINITLIST(preferences.dq_editor_static_versions)
	if(!preferences.dq_editor_static_versions[editor_key])
		preferences.dq_editor_static_versions[editor_key] = 1
	return preferences.dq_editor_static_versions[editor_key]

/datum/preferences/proc/dq_invalidate_category_cache()
	dq_category_static_cache = null
	dq_category_index = null
	dq_category_structure_version++

/datum/preferences/proc/dq_invalidate_all_catalogs()
	dq_editor_static_cache = null
	LAZYINITLIST(dq_editor_static_versions)
	for(var/datum/preference_editor/editor as anything in GLOB.preference_editors)
		if(editor.hidden)
			continue
		dq_editor_static_versions[editor.key] = (dq_editor_static_versions[editor.key] || 1) + 1
	dq_invalidate_category_cache()

/datum/preference_middleware/character_setup/get_ui_data(mob/user, datum/tgui/ui)
	var/list/data = ..()

	if(preferences.current_window != PREFERENCE_TAB_CHARACTER_PREFERENCES)
		return data

	var/catalog_started = TICK_USAGE_REAL
	dq_ensure_category_cache()
	if(!(preferences.dq_active_category in preferences.dq_category_static_cache))
		if(!(preferences.dq_active_category in preferences.dq_category_index))
			preferences.dq_active_category = preferences.dq_category_index?[1]
		dq_ensure_category_cache(preferences.dq_active_category)

	data["dq_cache_key"] = "[REF(preferences)]-[preferences.default_slot]"
	data["dq_active_category"] = preferences.dq_active_category
	data["dq_category_index"] = preferences.dq_category_index
	data["dq_structure_version"] = preferences.dq_category_structure_version

	var/window_id = ui?.window?.id || "unpooled"
	var/force_catalogs = !!preferences.dq_force_catalogs_by_window?[window_id]
	if(force_catalogs)
		preferences.dq_force_catalogs_by_window -= window_id
	LAZYINITLIST(preferences.dq_window_category_versions)
	if(!islist(preferences.dq_window_category_versions[window_id]))
		preferences.dq_window_category_versions[window_id] = list()
	var/list/window_category_versions = preferences.dq_window_category_versions[window_id]
	if(window_category_versions[preferences.dq_active_category] != preferences.dq_category_structure_version)
		var/list/category_patch = list()
		category_patch[preferences.dq_active_category] = preferences.dq_category_static_cache[preferences.dq_active_category]
		data["dq_category_patch"] = category_patch
		window_category_versions[preferences.dq_active_category] = preferences.dq_category_structure_version

	// Values are small and allow a cached category to display current state
	// immediately. Large editor state and catalogs are restricted to the active
	// category so unopened tabs cost nothing.
	var/list/widget_values = list()
	var/list/active_category = preferences.dq_category_static_cache[preferences.dq_active_category]
	for(var/list/group as anything in active_category?["groups"])
		for(var/list/item as anything in group["items"])
			if(item["type"] != "widget")
				continue
			var/datum/preference/pref = GLOB.preference_entries_by_key[item["key"]]
			if(pref)
				widget_values[pref.savefile_key] = preferences.read_preference(pref.type)
	data["dq_values"] = widget_values

	var/list/editor_data = list()
	var/list/editor_versions = list()
	var/list/editor_static_patch = list()
	LAZYINITLIST(preferences.dq_window_editor_versions)
	if(!islist(preferences.dq_window_editor_versions[window_id]))
		preferences.dq_window_editor_versions[window_id] = list()
	var/list/window_editor_versions = preferences.dq_window_editor_versions[window_id]
	for(var/datum/preference_editor/editor as anything in GLOB.preference_editors)
		if(editor.hidden || editor.category != preferences.dq_active_category)
			continue
		editor_data[editor.key] = editor.build_ui_data(preferences)
		var/editor_version = dq_editor_version(editor.key)
		editor_versions[editor.key] = editor_version
		if(window_editor_versions[editor.key] == editor_version)
			continue
		// Let the first payload reveal the already-warm generic shell. React sees
		// the version mismatch and requests catalogs immediately afterward, moving
		// editor-specific construction off the window-opening critical path.
		if(!force_catalogs)
			continue
		if(!islist(preferences.dq_editor_static_cache) || !(editor.key in preferences.dq_editor_static_cache))
			preferences.dq_rebuild_editor_static_entry(editor)
		editor_static_patch[editor.key] = preferences.dq_editor_static_cache?[editor.key] || list()
		window_editor_versions[editor.key] = editor_version
	data["dq_editor_data"] = editor_data
	data["dq_editor_versions"] = editor_versions
	if(length(editor_static_patch))
		data["dq_editor_static_patch"] = editor_static_patch
	data["dq_catalog_build_ms"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - catalog_started)

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

/proc/dq_cmp_group_by_sort_priority(list/a, list/b)
	return a["sort_priority"] - b["sort_priority"]

// Rebuild a single editor catalog on demand when the active browser slot has
// not received its current version.
/datum/preferences/proc/dq_rebuild_editor_static_entry(datum/preference_editor/editor)
	if(!editor)
		return
	if(!islist(dq_editor_static_cache))
		dq_editor_static_cache = list()
	var/list/static_payload = editor.build_ui_static_data(src)
	if(static_payload && static_payload.len)
		dq_editor_static_cache[editor.key] = static_payload
	else
		dq_editor_static_cache -= editor.key
/datum/preference_middleware/character_setup/get_ui_static_data(mob/user)
	var/list/data = ..()
	return data

/datum/preference_middleware/character_setup/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		if("dq_select_category")
			dq_ensure_category_cache()
			var/category_key = params["category"]
			if(!(category_key in preferences.dq_category_index))
				return FALSE
			preferences.dq_active_category = category_key
			if(params["force_catalogs"])
				var/window_id = ui?.window?.id || "unpooled"
				LAZYINITLIST(preferences.dq_force_catalogs_by_window)
				preferences.dq_force_catalogs_by_window[window_id] = TRUE
				if(islist(preferences.dq_window_category_versions?[window_id]))
					preferences.dq_window_category_versions[window_id] -= category_key
				if(islist(preferences.dq_window_editor_versions?[window_id]))
					for(var/datum/preference_editor/editor as anything in GLOB.preference_editors)
						if(!editor.hidden && editor.category == category_key)
							preferences.dq_window_editor_versions[window_id] -= editor.key
			return TRUE

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
			// Switching human/robot/pAI mode changes which category groups exist.
			// Drop the structure cache and bump its version; each pooled browser
			// receives the new active-category patch on its next update.
			if(result == PREF_UPDATE_ACCEPTED && editor_key == "species_picker")
				preferences.dq_invalidate_category_cache()
			return (result == PREF_UPDATE_ACCEPTED)
