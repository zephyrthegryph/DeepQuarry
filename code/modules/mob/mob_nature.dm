// What a mob is like: the mob_nature() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(mob_nature(can_pain_emote = FALSE))), read with nature_of(M).can_pain_emote, written at run time with set_<old var>().
//
//   can_pain_emote / pain_1p / pain_3p   whether it cries out in pain, and the first and third person lines
//   death_sound   the sound it dies with, when not the species one
//   name_the_meat / gib_on_butchery / drops_organs   what butchering it gives
//   no_vore / restrict_vore_ventcrawl / faction_bump_vore / belly_size / vore_eyes   its vore leanings

STATIC_ENTRY(mob_nature)

/proc/mob_nature(can_pain_emote = null, pain_1p = null, pain_3p = null, death_sound = null, name_the_meat = null, gib_on_butchery = null, drops_organs = null, no_vore = null, restrict_vore_ventcrawl = null, faction_bump_vore = null, belly_size = null, vore_eyes = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_MOB_NATURE, null, list("can_pain_emote" = can_pain_emote, "pain_1p" = pain_1p, "pain_3p" = pain_3p, "death_sound" = death_sound, "name_the_meat" = name_the_meat, "gib_on_butchery" = gib_on_butchery, "drops_organs" = drops_organs, "no_vore" = no_vore, "restrict_vore_ventcrawl" = restrict_vore_ventcrawl, "faction_bump_vore" = faction_bump_vore, "belly_size" = belly_size, "vore_eyes" = vore_eyes))

/datum/type_trait/mob_nature
	var/can_pain_emote = TRUE
	var/pain_1p = null
	var/pain_3p = null
	var/death_sound = null
	var/name_the_meat = TRUE
	var/gib_on_butchery = FALSE
	var/drops_organs = TRUE
	var/no_vore = FALSE
	var/restrict_vore_ventcrawl = FALSE
	var/faction_bump_vore = FALSE
	var/belly_size = 1
	var/vore_eyes = FALSE

/datum/type_trait/mob_nature/copy_values(datum/type_trait/mob_nature/into)
	into.can_pain_emote = can_pain_emote
	into.pain_1p = pain_1p
	into.pain_3p = pain_3p
	into.death_sound = death_sound
	into.name_the_meat = name_the_meat
	into.gib_on_butchery = gib_on_butchery
	into.drops_organs = drops_organs
	into.no_vore = no_vore
	into.restrict_vore_ventcrawl = restrict_vore_ventcrawl
	into.faction_bump_vore = faction_bump_vore
	into.belly_size = belly_size
	into.vore_eyes = vore_eyes

/datum/entry_engine/type_trait/mob_nature
	kind = ENTRY_MOB_NATURE
	trait_type = /datum/type_trait/mob_nature
	publish_key = MOB_NATURE_KEY
	base_type = /mob
	var_names = list("can_pain_emote" = "can_pain_emote", "pain_emote_1p" = "pain_1p", "pain_emote_3p" = "pain_3p", "death_sound_override" = "death_sound", "name_the_meat" = "name_the_meat", "gib_on_butchery" = "gib_on_butchery", "butchery_drops_organs" = "drops_organs", "no_vore" = "no_vore", "restrict_vore_ventcrawl" = "restrict_vore_ventcrawl", "faction_bump_vore" = "faction_bump_vore", "belly_size_multiplier" = "belly_size", "vore_eyes" = "vore_eyes")

/// The holder's mob_nature values (its own once one was set at run time). Read only.
READS_AS(/proc/nature_of, MOB_NATURE_KEY)
/proc/nature_of(mob/holder) as /datum/type_trait/mob_nature
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_MOB_NATURE)

/// What a type declares (no instance): the old initial().
/proc/nature_of_type(type) as /datum/type_trait/mob_nature
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_MOB_NATURE)

/mob/proc/set_can_pain_emote(value)
	return set_trait(src, ENTRY_MOB_NATURE, "can_pain_emote", value)

/mob/proc/set_pain_emote_1p(value)
	return set_trait(src, ENTRY_MOB_NATURE, "pain_1p", value)

/mob/proc/set_pain_emote_3p(value)
	return set_trait(src, ENTRY_MOB_NATURE, "pain_3p", value)

/mob/proc/set_death_sound_override(value)
	return set_trait(src, ENTRY_MOB_NATURE, "death_sound", value)

/mob/proc/set_name_the_meat(value)
	return set_trait(src, ENTRY_MOB_NATURE, "name_the_meat", value)

/mob/proc/set_gib_on_butchery(value)
	return set_trait(src, ENTRY_MOB_NATURE, "gib_on_butchery", value)

/mob/proc/set_butchery_drops_organs(value)
	return set_trait(src, ENTRY_MOB_NATURE, "drops_organs", value)

/mob/proc/set_no_vore(value)
	return set_trait(src, ENTRY_MOB_NATURE, "no_vore", value)

/mob/proc/set_restrict_vore_ventcrawl(value)
	return set_trait(src, ENTRY_MOB_NATURE, "restrict_vore_ventcrawl", value)

/mob/proc/set_faction_bump_vore(value)
	return set_trait(src, ENTRY_MOB_NATURE, "faction_bump_vore", value)

/mob/proc/set_belly_size_multiplier(value)
	return set_trait(src, ENTRY_MOB_NATURE, "belly_size", value)

/mob/proc/set_vore_eyes(value)
	return set_trait(src, ENTRY_MOB_NATURE, "vore_eyes", value)
