// Exposure response is type policy; flames/stacks/temperature remain actual status/body state.
STATIC_ENTRY(fire_policy)

/proc/fire_policy(reaction = null, trigger_proc = null, trigger_verb = null, heats_body = null)
	return entry_make(ENTRY_FIRE_POLICY, null, list("reaction" = reaction, "trigger_proc" = trigger_proc, "trigger_verb" = trigger_verb, "heats_body" = heats_body))

/datum/type_trait/fire_policy
	var/reaction = FIRE_REACTION_BURN
	var/trigger_proc = null
	var/trigger_verb = "ignited"
	var/heats_body = FALSE

/datum/type_trait/fire_policy/copy_values(datum/type_trait/fire_policy/into)
	into.reaction = reaction
	into.trigger_proc = trigger_proc
	into.trigger_verb = trigger_verb
	into.heats_body = heats_body

/datum/entry_engine/type_trait/fire_policy
	kind = ENTRY_FIRE_POLICY
	trait_type = /datum/type_trait/fire_policy
	publish_key = FIRE_POLICY_KEY
	base_type = /mob/living
	var_names = list("fire_reaction" = "reaction", "fire_trigger_proc" = "trigger_proc", "fire_trigger_verb" = "trigger_verb", "fire_heats_body" = "heats_body")

READS_AS(/proc/fire_policy_of, FIRE_POLICY_KEY)
/proc/fire_policy_of(mob/living/L) as /datum/type_trait/fire_policy
	READS_FROM(L)
	return type_trait_of(L, ENTRY_FIRE_POLICY)

/proc/fire_policy_of_type(path) as /datum/type_trait/fire_policy
	READS_FROM()
	return type_trait_of_type(path, ENTRY_FIRE_POLICY)
