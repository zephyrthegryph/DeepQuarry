// Configuration only: changing it after initialization never re-arms a timer. expire() owns runtime scheduling.
STATIC_ENTRY(expiry_policy)
/proc/expiry_policy(delay = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_EXPIRY_POLICY, null, list("delay" = delay))
/datum/type_trait/expiry_policy
	var/delay = 0
/datum/type_trait/expiry_policy/copy_values(datum/type_trait/expiry_policy/into)
	into.delay = delay
/datum/entry_engine/type_trait/expiry_policy
	kind = ENTRY_EXPIRY_POLICY
	trait_type = /datum/type_trait/expiry_policy
	publish_key = EXPIRY_POLICY_KEY
	base_type = /atom/movable
	var_names = list("lifecycle_lifetime" = "delay")
READS_AS(/proc/expiry_policy_of, EXPIRY_POLICY_KEY)
/proc/expiry_policy_of(atom/movable/A) as /datum/type_trait/expiry_policy
	READS_FROM(A)
	return type_trait_of(A, ENTRY_EXPIRY_POLICY)
/proc/expiry_policy_of_type(type) as /datum/type_trait/expiry_policy
	READS_FROM()
	return type_trait_of_type(type, ENTRY_EXPIRY_POLICY)
/atom/movable/proc/set_lifecycle_lifetime(value)
	return set_trait(src, ENTRY_EXPIRY_POLICY, "delay", value)
