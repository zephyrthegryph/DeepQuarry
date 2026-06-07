// DQAdd — Composite preference editors. Where a single /datum/preference + widget is too
// thin to express the UI (trait picker with conflict detection, marking color/zone matrix,
// loadout slot builder, language pref tied to runechat color, etc.), a /datum/preference_editor
// owns the workflow.
//
// On the DM side, an editor:
//   - declares which prefs it reads and writes (pref_keys)
//   - declares which category/group page it appears on
//   - produces a JSON payload for the UI via build_ui_data()
//   - handles atomic multi-pref actions sent from the UI via handle_action()
//
// On the TGUI side, the auto-renderer looks up a component by editor.key in a static table
// and instantiates it with the data returned from build_ui_data().
//
// Editors are singletons registered in GLOB.preference_editors.

GLOBAL_LIST_INIT(preference_editors, init_preference_editors())
GLOBAL_LIST_INIT(preference_editors_by_key, init_preference_editors_by_key())

/proc/init_preference_editors()
	var/list/output = list()
	for(var/datum/preference_editor/editor_type as anything in subtypesof(/datum/preference_editor))
		if(is_abstract(editor_type))
			continue
		output += new editor_type
	return output

/proc/init_preference_editors_by_key()
	var/list/output = list()
	for(var/datum/preference_editor/editor as anything in GLOB.preference_editors)
		output[editor.key] = editor
	return output

/datum/preference_editor
	abstract_type = /datum/preference_editor

	/// Unique stable identifier. The TGUI side dispatches to a React component by this key.
	var/key

	/// Which prefs this editor reads / writes. The auto-renderer hides individual widgets
	/// for these prefs (they're owned by the editor instead).
	var/list/pref_keys

	/// Category page this editor appears on. Mirrors /datum/preference.category.
	var/category

	/// Group within the category, if the category uses groups. Mirrors /datum/preference.group.
	var/group

	/// Sort order within the group (lower = earlier). Editors and widgets share a single sort
	/// ordering on the page; pick a number that fits.
	var/sort_order = 100

	/// Display name shown above the editor in the UI. If null the UI doesn't render a header.
	var/display_name

	/// If TRUE, the middleware doesn't expose this editor in the per-category page list, but it
	/// stays registered so tgui_act("dq_editor_action") can still dispatch to it. Used when a
	/// larger composite editor (e.g. loadout) integrates several smaller editors into one panel
	/// — the smaller editors keep their action handlers but don't render on their own.
	var/hidden = FALSE

	/// DQAdd — Pref savefile_keys whose change forces this editor's static_data
	/// cache entry to rebuild. Most editors have a constant catalog (markings,
	/// hair, traits, etc.) and don't need invalidation at all; loadout filters
	/// by species/tail, robot_chassis filters by play_mode, etc.
	/// Empty list (default) means "never invalidate after first build".
	var/list/static_invalidator_keys

/// Produce the editor-specific UI payload. Free-form list; the matching React component
/// owns the schema on the other side. Called every time the UI refreshes.
/datum/preference_editor/proc/build_ui_data(datum/preferences/preferences)
	return list()

/// Optional static (per-round constant) UI payload. Cached, not refreshed on every tick.
/datum/preference_editor/proc/build_ui_static_data(datum/preferences/preferences)
	return list()

/// Handle an atomic multi-pref action sent from the UI. Returns one of:
///   PREF_UPDATE_ACCEPTED  — apply preview, persist, refresh UI
///   PREF_UPDATE_REJECTED  — show an error
///   PREF_UPDATE_UNCHANGED — no-op
/datum/preference_editor/proc/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	return PREF_UPDATE_UNCHANGED
