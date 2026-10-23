// Per-type rules of an object: the obj_rules() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(obj_rules(tk_reach = FALSE))), read with rules_of(O).tk_reach, written at run time with set_<old var>().
//
//   tk_reach   telekinesis can grab it
//   redgate_allowed   it can be taken through the redgate, in either direction
//   micro_target   micros may be targeted through it
//   surgery_cleanliness   a table or other surface surgery can be done on: how clean it keeps the work
//   show_messages   shown in place of its hit messages
//   sellable_type   the sale kind the sellable capability files it under
//   broken_icon   the icon state it takes when broken

STATIC_ENTRY(obj_rules)

/proc/obj_rules(tk_reach = null, redgate_allowed = null, micro_target = null, surgery_cleanliness = null, show_messages = null, sellable_type = null, broken_icon = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_OBJ_RULES, null, list("tk_reach" = tk_reach, "redgate_allowed" = redgate_allowed, "micro_target" = micro_target, "surgery_cleanliness" = surgery_cleanliness, "show_messages" = show_messages, "sellable_type" = sellable_type, "broken_icon" = broken_icon))

/datum/type_trait/obj_rules
	var/tk_reach = TRUE
	var/redgate_allowed = TRUE
	var/micro_target = FALSE
	var/surgery_cleanliness = 0
	var/show_messages = null
	var/sellable_type = null
	var/broken_icon = null

/datum/type_trait/obj_rules/copy_values(datum/type_trait/obj_rules/into)
	into.tk_reach = tk_reach
	into.redgate_allowed = redgate_allowed
	into.micro_target = micro_target
	into.surgery_cleanliness = surgery_cleanliness
	into.show_messages = show_messages
	into.sellable_type = sellable_type
	into.broken_icon = broken_icon

/datum/entry_engine/type_trait/obj_rules
	kind = ENTRY_OBJ_RULES
	trait_type = /datum/type_trait/obj_rules
	publish_key = OBJ_RULES_KEY
	base_type = /obj
	var_names = list("tk_reach" = "tk_reach", "redgate_allowed" = "redgate_allowed", "micro_target" = "micro_target", "surgery_cleanliness" = "surgery_cleanliness", "show_messages" = "show_messages", "sellable_type" = "sellable_type", "broken_icon_state" = "broken_icon")

/// The holder's obj_rules values (its own once one was set at run time). Read only.
READS_AS(/proc/rules_of, OBJ_RULES_KEY)
/proc/rules_of(obj/holder) as /datum/type_trait/obj_rules
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_OBJ_RULES)

/// What a type declares (no instance): the old initial().
/proc/rules_of_type(type) as /datum/type_trait/obj_rules
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_OBJ_RULES)

/obj/proc/set_tk_reach(value)
	return set_trait(src, ENTRY_OBJ_RULES, "tk_reach", value)

/obj/proc/set_redgate_allowed(value)
	return set_trait(src, ENTRY_OBJ_RULES, "redgate_allowed", value)

/obj/proc/set_micro_target(value)
	return set_trait(src, ENTRY_OBJ_RULES, "micro_target", value)

/obj/proc/set_surgery_cleanliness(value)
	return set_trait(src, ENTRY_OBJ_RULES, "surgery_cleanliness", value)

/obj/proc/set_show_messages(value)
	return set_trait(src, ENTRY_OBJ_RULES, "show_messages", value)

/obj/proc/set_sellable_type(value)
	return set_trait(src, ENTRY_OBJ_RULES, "sellable_type", value)

/obj/proc/set_broken_icon_state(value)
	return set_trait(src, ENTRY_OBJ_RULES, "broken_icon", value)
