// What butchering a mob gives: the butchery_rules() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(butchery_rules(meat_amount = ...))), read with butchery_of(A).meat_amount, written at run time with set_<old var>().
//
//   meat_amount   how much meat
//   butchery_loot   extra drops, path = number

STATIC_ENTRY(butchery_rules)

/proc/butchery_rules(meat_amount = null, butchery_loot = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_BUTCHERY_RULES, null, list("meat_amount" = meat_amount, "butchery_loot" = butchery_loot))

/datum/type_trait/butchery_rules
	var/meat_amount = 0
	var/list/butchery_loot = null

/datum/type_trait/butchery_rules/copy_values(datum/type_trait/butchery_rules/into)
	into.meat_amount = meat_amount
	into.butchery_loot = butchery_loot

/datum/entry_engine/type_trait/butchery_rules
	kind = ENTRY_BUTCHERY_RULES
	trait_type = /datum/type_trait/butchery_rules
	publish_key = BUTCHERY_RULES_KEY
	base_type = /mob/living
	var_names = list("meat_amount" = "meat_amount", "butchery_loot" = "butchery_loot")

/// The holder's butchery_rules values (its own once one was set at run time). Read only.
READS_AS(/proc/butchery_of, BUTCHERY_RULES_KEY)
/proc/butchery_of(mob/living/holder) as /datum/type_trait/butchery_rules
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_BUTCHERY_RULES)

/// What a type declares (no instance): the old initial().
/proc/butchery_of_type(type) as /datum/type_trait/butchery_rules
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_BUTCHERY_RULES)

/mob/living/proc/set_meat_amount(value)
	return set_trait(src, ENTRY_BUTCHERY_RULES, "meat_amount", value)

/mob/living/proc/set_butchery_loot(value)
	return set_trait(src, ENTRY_BUTCHERY_RULES, "butchery_loot", value)
