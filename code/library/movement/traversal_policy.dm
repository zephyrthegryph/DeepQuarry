// Atom-level policy: click reach, thrown contacts and portal landing share this exact legacy value.
STATIC_ENTRY(traversal_policy)
/proc/traversal_policy(throwpass = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_TRAVERSAL_POLICY, null, list("throwpass" = throwpass))
/datum/type_trait/traversal_policy
	var/throwpass = 0
/datum/type_trait/traversal_policy/copy_values(datum/type_trait/traversal_policy/into)
	into.throwpass = throwpass
/datum/entry_engine/type_trait/traversal_policy
	kind = ENTRY_TRAVERSAL_POLICY
	trait_type = /datum/type_trait/traversal_policy
	publish_key = TRAVERSAL_POLICY_KEY
	base_type = /atom
	var_names = list("throwpass" = "throwpass")
READS_AS(/proc/traversal_policy_of, TRAVERSAL_POLICY_KEY)
/proc/traversal_policy_of(atom/A) as /datum/type_trait/traversal_policy
	READS_FROM(A)
	return type_trait_of(A, ENTRY_TRAVERSAL_POLICY)
/proc/traversal_policy_of_type(type) as /datum/type_trait/traversal_policy
	READS_FROM()
	return type_trait_of_type(type, ENTRY_TRAVERSAL_POLICY)
/atom/proc/set_throwpass(value)
	return set_trait(src, ENTRY_TRAVERSAL_POLICY, "throwpass", value)
