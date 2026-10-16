// Final-death destruction policy, not a stat subscription or lifetime condition.
STATIC_ENTRY(death_policy)
/proc/death_policy(delete_on_death = null)
	return entry_make(ENTRY_DEATH_POLICY, null, list("delete_on_death" = delete_on_death))
/datum/type_trait/death_policy
	var/delete_on_death = FALSE
/datum/type_trait/death_policy/copy_values(datum/type_trait/death_policy/into)
	into.delete_on_death = delete_on_death
/datum/entry_engine/type_trait/death_policy
	kind = ENTRY_DEATH_POLICY
	trait_type = /datum/type_trait/death_policy
	publish_key = DEATH_POLICY_KEY
	base_type = /mob/living
	var_names = list("delete_on_death" = "delete_on_death")
READS_AS(/proc/death_policy_of, DEATH_POLICY_KEY)
/proc/death_policy_of(mob/living/L) as /datum/type_trait/death_policy
	READS_FROM(L)
	return type_trait_of(L, ENTRY_DEATH_POLICY)
/proc/death_policy_of_type(path) as /datum/type_trait/death_policy
	READS_FROM()
	return type_trait_of_type(path, ENTRY_DEATH_POLICY)
