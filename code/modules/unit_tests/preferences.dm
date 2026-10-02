/// Requires all preferences to implement required methods, and that each
/// preference's OWN default value passes its OWN is_valid() structural check.
///
/// We deliberately do not construct a /datum/preferences here: on this fork
/// /datum/preferences/New() requires a real client and CRASHes without one (see
/// dq_preferences_tests.dm for the stub used by the architecture tests). The
/// methods exercised here either take no preferences handle (is_valid,
/// init_possible_values) or accept a null one via `preferences?.` null-safe
/// reads (create_informed_default_value), so passing null is safe and keeps the
/// test client-free.
/datum/unit_test/preferences_implement_everything

/datum/unit_test/preferences_implement_everything/Run()
	TEST_ASSERT(length(GLOB.preference_entries) > 0, "preference registry is empty")

	// A unique sentinel guaranteed never to appear in any choiced preference's
	// value set. Used to prove choiced is_valid() actually rejects non-members
	// rather than blindly returning truthy. (Only used against choiced prefs:
	// their is_valid is `value in get_choices()`, which safely handles any type.
	// Other pref shapes—text/color/numeric—run findtext/isnum that would runtime
	// on an arbitrary datum, so we don't feed the sentinel to them.)
	var/datum/garbage_sentinel = new

	for (var/preference_type in GLOB.preference_entries)
		var/datum/preference/preference = GLOB.preference_entries[preference_type]

		// create_default_value / create_informed_default_value must be implemented
		// (the base procs CRASH). A null preferences handle is fine — overrides
		// that consult prefs do so through `preferences?.read_preference(...)`.
		var/default_value = preference.create_informed_default_value(null)

		// The cornerstone invariant: a preference's own default MUST satisfy its
		// own is_valid(). If it doesn't, the preference is broken — its default
		// could never be written to a savefile (write() gates on is_valid()).
		// A null default means "unset / no default" (legitimate for optional text
		// prefs like custom_say), so only a concrete (non-null) default is checked.
		if(!isnull(default_value))
			TEST_ASSERT(preference.is_valid(default_value), \
				"[preference_type]: create_informed_default_value() produced a value its own is_valid() rejects ([default_value]).")

		if (istype(preference, /datum/preference/choiced))
			var/datum/preference/choiced/choiced_preference = preference
			if (choiced_preference.abstract_type == preference_type)
				continue
			// get_choices() asserts non-empty internally and caches; it is the
			// canonical value set is_valid() checks membership against.
			var/list/values = choiced_preference.get_choices()
			TEST_ASSERT(LAZYLEN(values) > 0, \
				"[preference_type]: get_choices() returned an empty list.")
			// The default must be among the offered choices.
			TEST_ASSERT(default_value in values, \
				"[preference_type]: default value [isnull(default_value) ? "null" : default_value] is not one of its own get_choices().")
			// is_valid() must be a real membership check, not a constant truthy
			// stub: a fresh datum never appears in any choice list.
			TEST_ASSERT(!choiced_preference.is_valid(garbage_sentinel), \
				"[preference_type]: choiced is_valid() accepted an arbitrary /datum sentinel — it is not actually checking get_choices() membership.")

/// Requires all preferences to have a valid, unique savefile_identifier.
/datum/unit_test/preferences_valid_savefile_key

/datum/unit_test/preferences_valid_savefile_key/Run()
	var/list/known_savefile_keys = list()

	for (var/preference_type in GLOB.preference_entries)
		var/datum/preference/preference = GLOB.preference_entries[preference_type]
		if (!istext(preference.savefile_key))
			TEST_FAIL("[preference_type] has an invalid savefile_key.")

		if (preference.savefile_key in known_savefile_keys)
			TEST_FAIL("[preference_type] has a non-unique savefile_key `[preference.savefile_key]`!")

		known_savefile_keys += preference.savefile_key

/// Requires all main features have a main_feature_name
/datum/unit_test/preferences_valid_main_feature_name

/datum/unit_test/preferences_valid_main_feature_name/Run()
	for (var/preference_type in GLOB.preference_entries)
		var/datum/preference/choiced/preference = GLOB.preference_entries[preference_type]
		if (!istype(preference))
			continue

		if (preference.category != PREFERENCE_CATEGORY_FEATURES && preference.category != PREFERENCE_CATEGORY_CLOTHING)
			continue

		TEST_ASSERT(!isnull(preference.main_feature_name), "Preference [preference_type] does not have a main_feature_name set!")

/// Validates that every choiced preference with should_generate_icons implements icon_for,
/// and that every one that doesn't, doesn't.
/datum/unit_test/preferences_should_generate_icons_sanity

/datum/unit_test/preferences_should_generate_icons_sanity/Run()
	for (var/preference_type in GLOB.preference_entries)
		var/datum/preference/choiced/choiced_preference = GLOB.preference_entries[preference_type]
		if (!istype(choiced_preference) || choiced_preference.abstract_type == preference_type)
			continue

		var/list/values = choiced_preference.get_choices()

		if (choiced_preference.should_generate_icons)
			for (var/value in values)
				var/icon = choiced_preference.icon_for(value)
				// This fork's icon_for may return a raw /icon instance (e.g. ui_style),
				// a /datum/universal_icon, or an icon type path — all usable.
				TEST_ASSERT(istype(icon, /datum/universal_icon) || istype(icon, /icon) || ispath(icon), "[preference_type] gave [icon] as an icon for [value], which is not a valid value")
		else
			var/errored = FALSE

			try
				choiced_preference.icon_for(values[1])
			catch
				errored = TRUE

			TEST_ASSERT(errored, "[preference_type] implemented icon_for, but does not have should_generate_icons = TRUE")
