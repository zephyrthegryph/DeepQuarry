// DQAdd — Post-apply orchestration hooks. Where a Bay copy_to_mob did cross-pref work that
// touches the character mob (re-sanitize the real name using species rules, run the species
// produceCopy() pipeline with the trait list, spawn-time body backup, etc.), the new
// architecture expresses that as a /datum/preference_apply_hook subtype.
//
// Hooks fire AFTER all individual /datum/preference.apply() calls during character spawn.
// They have access to the full prefs datum and the target mob.
//
// Each hook is a singleton in GLOB.preference_apply_hooks, ordered by `priority` (lower =
// earlier). They're walked once per character spawn from /datum/preferences/proc/copy_to().

// Priority constants. Hooks ordered by these execute earlier-to-later. Defined at the top
// so the class declaration below can reference APPLY_HOOK_PRIORITY_DEFAULT.
#define APPLY_HOOK_PRIORITY_NAME            10  // name sanitization (depends on species)
#define APPLY_HOOK_PRIORITY_SPECIES         20  // species/trait synthesis (produceCopy + traits)
#define APPLY_HOOK_PRIORITY_DEFAULT        100
#define APPLY_HOOK_PRIORITY_ORGANS         200  // organ/limb application
#define APPLY_HOOK_PRIORITY_ACCESSORIES    300  // markings, ear styles, etc. that depend on species
#define APPLY_HOOK_PRIORITY_EQUIPMENT      400  // gear/loadout/underwear
#define APPLY_HOOK_PRIORITY_LATE           900  // anything that must run after everything else

GLOBAL_LIST_INIT(preference_apply_hooks, init_preference_apply_hooks())

/proc/init_preference_apply_hooks()
	var/list/output = list()
	for(var/datum/preference_apply_hook/hook_type as anything in subtypesof(/datum/preference_apply_hook))
		if(is_abstract(hook_type))
			continue
		output += new hook_type
	sortTim(output, GLOBAL_PROC_REF(cmp_preference_apply_hook_priority))
	return output

/proc/cmp_preference_apply_hook_priority(datum/preference_apply_hook/a, datum/preference_apply_hook/b)
	return a.priority - b.priority

/datum/preference_apply_hook
	abstract_type = /datum/preference_apply_hook

	/// Order in the apply pipeline. Lower runs earlier. Use these named constants when possible.
	var/priority = APPLY_HOOK_PRIORITY_DEFAULT

	/// If TRUE, the hook is skipped when the target is a preview mannequin (no client, no
	/// real-character state to apply). Hooks that should always run on the preview leave this
	/// as FALSE.
	var/skip_on_preview = FALSE

/// Run this hook against the character. Read prefs through the passed preferences datum.
/datum/preference_apply_hook/proc/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	return
