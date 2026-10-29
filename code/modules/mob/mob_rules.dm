// Per-type rules of a mob: the mob_rules() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(mob_rules(universal_understand = ...))), read with mob_rules_of(A).universal_understand, written at run time with set_<old var>().
//
//   universal_understand   it understands every language
//   forced_psay   its speech goes to the private channel
//   vent_crawl_time   how long entering a vent takes
//   faction   which side it is on: hostile mobs attack other factions (the standings tables read it)

STATIC_ENTRY(mob_rules)

/proc/mob_rules(universal_understand = null, forced_psay = null, vent_crawl_time = null, faction = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_MOB_RULES, null, list("universal_understand" = universal_understand, "forced_psay" = forced_psay, "vent_crawl_time" = vent_crawl_time, "faction" = faction))

/datum/type_trait/mob_rules
	var/universal_understand = 0
	var/forced_psay = FALSE
	var/vent_crawl_time = 4.5 SECONDS
	var/faction = FACTION_NEUTRAL

/datum/type_trait/mob_rules/copy_values(datum/type_trait/mob_rules/into)
	into.universal_understand = universal_understand
	into.forced_psay = forced_psay
	into.vent_crawl_time = vent_crawl_time
	into.faction = faction

/datum/entry_engine/type_trait/mob_rules
	kind = ENTRY_MOB_RULES
	trait_type = /datum/type_trait/mob_rules
	publish_key = MOB_RULES_KEY
	base_type = /mob
	var_names = list("universal_understand" = "universal_understand", "forced_psay" = "forced_psay", "vent_crawl_time" = "vent_crawl_time", "faction" = "faction")

/// The holder's mob_rules values (its own once one was set at run time). Read only.
READS_AS(/proc/mob_rules_of, MOB_RULES_KEY)
/proc/mob_rules_of(mob/holder) as /datum/type_trait/mob_rules
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_MOB_RULES)

/// What a type declares (no instance): the old initial().
/proc/mob_rules_of_type(type) as /datum/type_trait/mob_rules
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_MOB_RULES)

/mob/proc/set_universal_understand(value)
	return set_trait(src, ENTRY_MOB_RULES, "universal_understand", value)

/mob/proc/set_forced_psay(value)
	return set_trait(src, ENTRY_MOB_RULES, "forced_psay", value)

/// The standings engine reads a subject's faction through standing_faction(); a mob's is its mob_rules faction (no `faction` var is left to read).
/mob/standing_faction()
	var/faction = mob_rules_of(src).faction
	return (istext(faction) && length(faction)) ? faction : null

/mob/proc/set_faction(value)
	return set_trait(src, ENTRY_MOB_RULES, "faction", value)

/mob/proc/set_vent_crawl_time(value)
	return set_trait(src, ENTRY_MOB_RULES, "vent_crawl_time", value)
