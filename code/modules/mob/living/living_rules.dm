// Per-type rules of a living mob: the living_rules() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(living_rules(use_modern_ai = ...))), read with living_rules_of(A).use_modern_ai, written at run time with set_<old var>().
//
//   use_modern_ai / has_huds   which brain and HUD set it has
//   max_nutrition / force_max_speed   its food cap and speed lock
//   fire_*   how it reacts to being set alight
//   adminbus_trash / parasitic / appendage_color / vore_shred_time   vore leanings
//   composition_reagent   what it is made of when eaten
//   low_sorting_priority   sorted last in lists

STATIC_ENTRY(living_rules)

/proc/living_rules(use_modern_ai = null, has_huds = null, max_nutrition = null, fire_reaction = null, fire_trigger_proc = null, fire_trigger_verb = null, fire_heats_body = null, force_max_speed = null, adminbus_trash = null, parasitic = null, appendage_color = null, vore_shred_time = null, composition_reagent = null, low_sorting_priority = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_LIVING_RULES, null, list("use_modern_ai" = use_modern_ai, "has_huds" = has_huds, "max_nutrition" = max_nutrition, "fire_reaction" = fire_reaction, "fire_trigger_proc" = fire_trigger_proc, "fire_trigger_verb" = fire_trigger_verb, "fire_heats_body" = fire_heats_body, "force_max_speed" = force_max_speed, "adminbus_trash" = adminbus_trash, "parasitic" = parasitic, "appendage_color" = appendage_color, "vore_shred_time" = vore_shred_time, "composition_reagent" = composition_reagent, "low_sorting_priority" = low_sorting_priority))

/datum/type_trait/living_rules
	var/use_modern_ai = FALSE
	var/has_huds = FALSE
	var/max_nutrition = MAX_NUTRITION
	var/fire_reaction = FIRE_REACTION_BURN
	var/fire_trigger_proc = null
	var/fire_trigger_verb = "ignited"
	var/fire_heats_body = FALSE
	var/force_max_speed = 0
	var/adminbus_trash = FALSE
	var/parasitic = FALSE
	var/appendage_color = "#e03997"
	var/vore_shred_time = 45 SECONDS
	var/composition_reagent = null
	var/low_sorting_priority = FALSE

/datum/type_trait/living_rules/copy_values(datum/type_trait/living_rules/into)
	into.use_modern_ai = use_modern_ai
	into.has_huds = has_huds
	into.max_nutrition = max_nutrition
	into.fire_reaction = fire_reaction
	into.fire_trigger_proc = fire_trigger_proc
	into.fire_trigger_verb = fire_trigger_verb
	into.fire_heats_body = fire_heats_body
	into.force_max_speed = force_max_speed
	into.adminbus_trash = adminbus_trash
	into.parasitic = parasitic
	into.appendage_color = appendage_color
	into.vore_shred_time = vore_shred_time
	into.composition_reagent = composition_reagent
	into.low_sorting_priority = low_sorting_priority

/datum/entry_engine/type_trait/living_rules
	kind = ENTRY_LIVING_RULES
	trait_type = /datum/type_trait/living_rules
	publish_key = LIVING_RULES_KEY
	base_type = /mob/living
	var_names = list("use_modern_ai" = "use_modern_ai", "has_huds" = "has_huds", "max_nutrition" = "max_nutrition", "fire_reaction" = "fire_reaction", "fire_trigger_proc" = "fire_trigger_proc", "fire_trigger_verb" = "fire_trigger_verb", "fire_heats_body" = "fire_heats_body", "force_max_speed" = "force_max_speed", "adminbus_trash" = "adminbus_trash", "parasitic" = "parasitic", "appendage_color" = "appendage_color", "vore_shred_time" = "vore_shred_time", "composition_reagent" = "composition_reagent", "low_sorting_priority" = "low_sorting_priority")

/// The holder's living_rules values (its own once one was set at run time). Read only.
READS_AS(/proc/living_rules_of, LIVING_RULES_KEY)
/proc/living_rules_of(mob/living/holder) as /datum/type_trait/living_rules
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_LIVING_RULES)

/// What a type declares (no instance): the old initial().
/proc/living_rules_of_type(type) as /datum/type_trait/living_rules
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_LIVING_RULES)

/mob/living/proc/set_use_modern_ai(value)
	return set_trait(src, ENTRY_LIVING_RULES, "use_modern_ai", value)

/mob/living/proc/set_has_huds(value)
	return set_trait(src, ENTRY_LIVING_RULES, "has_huds", value)

/mob/living/proc/set_max_nutrition(value)
	return set_trait(src, ENTRY_LIVING_RULES, "max_nutrition", value)

/mob/living/proc/set_fire_reaction(value)
	return set_trait(src, ENTRY_LIVING_RULES, "fire_reaction", value)

/mob/living/proc/set_fire_trigger_proc(value)
	return set_trait(src, ENTRY_LIVING_RULES, "fire_trigger_proc", value)

/mob/living/proc/set_fire_trigger_verb(value)
	return set_trait(src, ENTRY_LIVING_RULES, "fire_trigger_verb", value)

/mob/living/proc/set_fire_heats_body(value)
	return set_trait(src, ENTRY_LIVING_RULES, "fire_heats_body", value)

/mob/living/proc/set_force_max_speed(value)
	return set_trait(src, ENTRY_LIVING_RULES, "force_max_speed", value)

/mob/living/proc/set_adminbus_trash(value)
	return set_trait(src, ENTRY_LIVING_RULES, "adminbus_trash", value)

/mob/living/proc/set_parasitic(value)
	return set_trait(src, ENTRY_LIVING_RULES, "parasitic", value)

/mob/living/proc/set_appendage_color(value)
	return set_trait(src, ENTRY_LIVING_RULES, "appendage_color", value)

/mob/living/proc/set_vore_shred_time(value)
	return set_trait(src, ENTRY_LIVING_RULES, "vore_shred_time", value)

/mob/living/proc/set_composition_reagent(value)
	return set_trait(src, ENTRY_LIVING_RULES, "composition_reagent", value)

/mob/living/proc/set_low_sorting_priority(value)
	return set_trait(src, ENTRY_LIVING_RULES, "low_sorting_priority", value)
