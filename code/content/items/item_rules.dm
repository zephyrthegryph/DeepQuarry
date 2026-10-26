// Per-type rules of an item: the item_rules() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(item_rules(sprite_sheets_obj = ...))), read with item_rules_of(A).sprite_sheets_obj, written at run time with set_<old var>().
//
//   sprite_sheets_obj   its per-species object sprite sheets
//   actions_types   the action buttons it grants

STATIC_ENTRY(item_rules)

/proc/item_rules(sprite_sheets_obj = null, actions_types = null, storage_cost = null, climbing_delay = null, abstract = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_ITEM_RULES, null, list("sprite_sheets_obj" = sprite_sheets_obj, "actions_types" = actions_types, "storage_cost" = storage_cost, "climbing_delay" = climbing_delay, "abstract" = abstract))

/datum/type_trait/item_rules
	var/list/sprite_sheets_obj = null
	var/list/actions_types = null
	var/storage_cost = null
	var/climbing_delay = 1
	var/abstract = FALSE

/datum/type_trait/item_rules/copy_values(datum/type_trait/item_rules/into)
	into.sprite_sheets_obj = sprite_sheets_obj
	into.actions_types = actions_types
	into.storage_cost = storage_cost
	into.climbing_delay = climbing_delay
	into.abstract = abstract

/datum/entry_engine/type_trait/item_rules
	kind = ENTRY_ITEM_RULES
	trait_type = /datum/type_trait/item_rules
	publish_key = ITEM_RULES_KEY
	base_type = /obj/item
	var_names = list("sprite_sheets_obj" = "sprite_sheets_obj", "actions_types" = "actions_types", "storage_cost" = "storage_cost", "climbing_delay" = "climbing_delay", "abstract" = "abstract")

/// The holder's item_rules values (its own once one was set at run time). Read only.
READS_AS(/proc/item_rules_of, ITEM_RULES_KEY)
/proc/item_rules_of(obj/item/holder) as /datum/type_trait/item_rules
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_ITEM_RULES)

/// What a type declares (no instance): the old initial().
/proc/item_rules_of_type(type) as /datum/type_trait/item_rules
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_ITEM_RULES)

/obj/item/proc/set_sprite_sheets_obj(value)
	return set_trait(src, ENTRY_ITEM_RULES, "sprite_sheets_obj", value)

/obj/item/proc/set_actions_types(value)
	return set_trait(src, ENTRY_ITEM_RULES, "actions_types", value)

/obj/item/proc/set_storage_cost(value)
	return set_trait(src, ENTRY_ITEM_RULES, "storage_cost", value)

/obj/item/proc/set_climbing_delay(value)
	return set_trait(src, ENTRY_ITEM_RULES, "climbing_delay", value)

/obj/item/proc/set_abstract(value)
	return set_trait(src, ENTRY_ITEM_RULES, "abstract", value)
