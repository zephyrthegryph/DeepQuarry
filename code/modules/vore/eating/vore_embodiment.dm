STATIC_ENTRY(vore_embodiment)
/proc/vore_embodiment(no_vore = null, restrict_vore_ventcrawl = null, parasitic = null, belly_size_multiplier = null, vore_eyes = null, faction_bump_vore = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_VORE_EMBODIMENT, null, list("no_vore" = no_vore, "restrict_vore_ventcrawl" = restrict_vore_ventcrawl, "parasitic" = parasitic, "belly_size_multiplier" = belly_size_multiplier, "vore_eyes" = vore_eyes, "faction_bump_vore" = faction_bump_vore))
/datum/type_trait/vore_embodiment
	var/no_vore = FALSE
	var/restrict_vore_ventcrawl = FALSE
	var/parasitic = FALSE
	var/belly_size_multiplier = 1
	var/vore_eyes = FALSE
	var/faction_bump_vore = FALSE
/datum/type_trait/vore_embodiment/copy_values(datum/type_trait/vore_embodiment/into)
	into.no_vore = no_vore
	into.restrict_vore_ventcrawl = restrict_vore_ventcrawl
	into.parasitic = parasitic
	into.belly_size_multiplier = belly_size_multiplier
	into.vore_eyes = vore_eyes
	into.faction_bump_vore = faction_bump_vore
/datum/entry_engine/type_trait/vore_embodiment
	kind = ENTRY_VORE_EMBODIMENT
	trait_type = /datum/type_trait/vore_embodiment
	publish_key = VORE_EMBODIMENT_KEY
	base_type = /mob
	var_names = list("no_vore" = "no_vore", "restrict_vore_ventcrawl" = "restrict_vore_ventcrawl", "parasitic" = "parasitic", "belly_size_multiplier" = "belly_size_multiplier", "vore_eyes" = "vore_eyes", "faction_bump_vore" = "faction_bump_vore")
READS_AS(/proc/vore_embodiment_of, VORE_EMBODIMENT_KEY)
/proc/vore_embodiment_of(mob/M) as /datum/type_trait/vore_embodiment
	READS_FROM(M)
	return type_trait_of(M, ENTRY_VORE_EMBODIMENT)
/proc/vore_embodiment_of_type(type) as /datum/type_trait/vore_embodiment
	READS_FROM()
	return type_trait_of_type(type, ENTRY_VORE_EMBODIMENT)

/mob/proc/set_no_vore(value)
	return set_trait(src, ENTRY_VORE_EMBODIMENT, "no_vore", value)

/mob/proc/set_restrict_vore_ventcrawl(value)
	return set_trait(src, ENTRY_VORE_EMBODIMENT, "restrict_vore_ventcrawl", value)

/mob/proc/set_parasitic(value)
	return set_trait(src, ENTRY_VORE_EMBODIMENT, "parasitic", value)

/mob/proc/set_belly_size_multiplier(value)
	return set_trait(src, ENTRY_VORE_EMBODIMENT, "belly_size_multiplier", value)

/mob/proc/set_vore_eyes(value)
	return set_trait(src, ENTRY_VORE_EMBODIMENT, "vore_eyes", value)

/mob/proc/set_faction_bump_vore(value)
	return set_trait(src, ENTRY_VORE_EMBODIMENT, "faction_bump_vore", value)
