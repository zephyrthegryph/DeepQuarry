// DQAdd — Cross-pref invariants. A constraint fires when one of its trigger pref keys
// changes; it may then read and mutate any pref. Constraints replace the ad-hoc cross-pref
// logic that used to live inside sanitize_character() and tgui_act() switches.
//
// Each constraint is a singleton registered in GLOB.preference_constraints. The update
// pipeline indexes them by trigger key and fans out automatically on every accepted update.
//
// Constraints should be small and single-purpose: one rule each. Compose by registering
// multiple constraints on the same trigger.

GLOBAL_LIST_INIT(preference_constraints, init_preference_constraints())
GLOBAL_LIST_INIT(preference_constraints_by_trigger, init_preference_constraints_by_trigger())

/proc/init_preference_constraints()
	var/list/output = list()
	for(var/datum/preference_constraint/constraint_type as anything in subtypesof(/datum/preference_constraint))
		if(is_abstract(constraint_type))
			continue
		output += new constraint_type
	return output

/proc/init_preference_constraints_by_trigger()
	var/list/output = list()
	for(var/datum/preference_constraint/constraint as anything in GLOB.preference_constraints)
		for(var/trigger_key in constraint.triggers)
			if(!output[trigger_key])
				output[trigger_key] = list()
			output[trigger_key] += constraint
	return output

/datum/preference_constraint
	abstract_type = /datum/preference_constraint

	/// Pref keys (each a /datum/preference's savefile_key) that cause this constraint to fire.
	var/list/triggers

	/// Pref keys that this constraint may mutate as a result of firing. Used by the UI to
	/// know which widgets to refresh after a triggering update. Optional but recommended.
	var/list/affects

/// Called whenever a triggering pref is updated. `changed_key` is the key that triggered;
/// `old_value` and `new_value` are the values before/after the change. The constraint
/// should read from / write to the prefs datum directly via read_preference and
/// update_preference_by_type as needed.
///
/// CASCADE BEHAVIOR: writes via update_preference_by_type from inside a constraint DO
/// re-trigger any constraint listening on the written key. The cascade depth is capped at
/// PREF_CONSTRAINT_MAX_DEPTH (see /datum/preferences/proc/update_preference) so a pair of
/// constraints that mutually trigger each other crashes loudly via stack_trace instead of
/// stack-bombing. If you need to write a pref WITHOUT triggering further constraints
/// (e.g. for a simple value clamp), call write_preference_by_type instead — it bypasses
/// the cascade entirely.
/datum/preference_constraint/proc/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	return
