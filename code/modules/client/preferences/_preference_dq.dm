// DQAdd — extensions to /datum/preference that bring it in line with the new architecture.
//   Adds:
//   - group (sub-category within a category)
//   - widget hint
//   - depends_on (pref keys that invalidate this one)
//   - runtime metadata procs (get_category, get_group, get_widget, get_widget_props)
//   - get_choices() for choice prefs
//   - validate() / sanitize() / apply() — the unified single-apply hook
//
// Existing /datum/preference subtypes keep working: apply() defaults to dispatch by mob type
// (calling apply_to_human/apply_to_client/etc) so legacy subtypes are unaffected until they
// migrate to overriding apply() directly.

/datum/preference
	/// Fine grouping within `category`. Used by the UI auto-renderer to lay out sections.
	/// Optional — prefs with no group are rendered ungrouped at the top of the category page.
	var/group

	/// Optional human-readable label override for the UI. When null the auto-renderer
	/// title-cases the savefile_key. Use when the savefile_key has historical baggage like
	/// "_vr", abbreviations, or other artifacts that should not show up in the UI.
	var/display_label

	/// Widget hint for the UI auto-renderer. Defaults to PREF_WIDGET_AUTO; subtypes can pin to
	/// a specific widget. Composite prefs that need a registered editor should set
	/// PREF_WIDGET_EDITOR.
	var/widget = PREF_WIDGET_AUTO

	/// List of pref keys (other prefs' `savefile_key`) whose changes invalidate this pref's
	/// cached value or shown choices. The update pipeline uses this to fan out constraint
	/// triggers and refresh the UI.
	var/list/depends_on

/// Runtime category override. Defaults to the static `category` var.
/// Override on subtypes whose category depends on context (e.g., admin-only prefs).
/datum/preference/proc/get_category(datum/preferences/preferences)
	return category

/// Runtime group override.
/datum/preference/proc/get_group(datum/preferences/preferences)
	return group

/// Runtime widget override. When the static `widget` is PREF_WIDGET_AUTO we auto-pick by
/// subtype tree (text → text, numeric → slider/number, toggle → boolean, color → color,
/// choiced → dropdown, composite → editor placeholder, derived → hidden, fallthrough → text).
/// A text pref that overrides get_pref_choices() to return a finite list also gets a dropdown
/// — saves declaring `widget = PREF_WIDGET_DROPDOWN` on every text-with-choices pref.
/datum/preference/proc/get_widget(datum/preferences/preferences)
	if(widget != PREF_WIDGET_AUTO)
		return widget
	if(istype(src, /datum/preference/toggle))
		return PREF_WIDGET_BOOLEAN
	if(istype(src, /datum/preference/color))
		return PREF_WIDGET_COLOR
	if(istype(src, /datum/preference/numeric))
		return PREF_WIDGET_SLIDER
	if(istype(src, /datum/preference/choiced))
		return PREF_WIDGET_DROPDOWN
	if(istype(src, /datum/preference/text))
		if(get_pref_choices(preferences))
			if(get_pref_thumbnails(preferences))
				return PREF_WIDGET_THUMBGRID
			return PREF_WIDGET_DROPDOWN
		return PREF_WIDGET_TEXT
	return PREF_WIDGET_TEXT

/// Returns a list of widget-specific props for the UI (min/max/step for numbers,
/// palette for colors, etc.). Default reads the standard numeric clamp vars if present so
/// PREF_WIDGET_SLIDER renders the right range without extra wiring.
/datum/preference/proc/get_widget_props(datum/preferences/preferences)
	if(istype(src, /datum/preference/numeric))
		var/datum/preference/numeric/n = src
		return list(
			"min" = n.minimum,
			"max" = n.maximum,
			"step" = n.step,
		)
	if(istype(src, /datum/preference/text))
		var/datum/preference/text/t = src
		return list("max_length" = t.maximum_value_length)
	return list()

/// For choice prefs (single or multi), the list of allowed values. Returns either:
///   - a list of strings (each entry both the display label and the saved value)
///   - an assoc list value -> display label
/// Default null = not a choice pref. Named differently from /datum/preference/choiced's
/// existing get_choices() because that one takes no args and we want prefs-aware choices.
/datum/preference/proc/get_pref_choices(datum/preferences/preferences)
	return null

// DQAdd — Auto-validation for any text pref that declares a choice set via
// get_pref_choices(). The text base's is_valid checks only length, so a forged Topic
// could write any short string into h_style / b_type / faction / etc. and pass. With
// this override, the contextual gate (validate()) walks the declared choices for the
// current prefs state and rejects anything not in the set.
//
// Free-text prefs (ooc_notes, vore messages, flavor body) get_pref_choices returns null,
// which means "any value passes" — same as the base, no behaviour change.
//
// Assoc-shaped choice lists (value -> label) are handled by checking against the keys.
/datum/preference/text/validate(datum/preferences/preferences, value)
	if(!is_valid(value))
		return FALSE
	var/list/choices = get_pref_choices(preferences)
	if(isnull(choices))
		return TRUE
	// Choices may be a flat list of allowed values or an assoc value->label. `in` on an
	// assoc list checks keys, which is what we want.
	if(!(value in choices))
		return FALSE
	return TRUE

/// Optional: returns an assoc {value -> list("icon" = REF(dmi), "icon_state" = "...")}
/// matching each entry in get_pref_choices(). When non-null, the auto-renderer picks
/// PREF_WIDGET_THUMBGRID and the React side renders a tinted thumbnail per choice.
/datum/preference/proc/get_pref_thumbnails(datum/preferences/preferences)
	return null

// DQAdd — /datum/preference/choiced already has get_choices() returning either a flat list
// of raw values OR an assoc value->icon/atom (when should_generate_icons). The auto-renderer
// only needs the value strings, so flatten to a JSON-safe list of keys.
/datum/preference/choiced/get_pref_choices(datum/preferences/preferences)
	var/list/raw = get_choices()
	if(!raw)
		return null
	var/list/out = list()
	for(var/choice in raw)
		out += "[choice]"
	return out

/// Coerce a possibly-bad value into the closest valid value. Called on load and on
/// constraint-driven invalidation. Default: pass through if valid, else default.
///
/// The contextual gate `validate(preferences, value)` is defined upstream in
/// /datum/preference/proc/validate (see code/modules/client/preferences/_preference.dm
/// DQAdd block) — this proc just chains through it.
/datum/preference/proc/sanitize(value, datum/preferences/preferences)
	if(validate(preferences, value))
		return value
	return create_informed_default_value(preferences)

/// Single apply entry point. Subtypes should override this directly going forward.
/// Default implementation dispatches by target type for backwards compat with subtypes
/// that still override the per-type apply_to_X procs.
/datum/preference/proc/apply(target, value, datum/preferences/preferences)
	if(isclient(target))
		apply_to_client(target, value)
		return
	if(ishuman(target))
		apply_to_human(target, value)
		return
	if(issilicon(target))
		apply_to_silicon(target, value)
		return
	if(isanimal(target))
		apply_to_animal(target, value)
		return
	if(isliving(target))
		apply_to_living(target, value)
		return
