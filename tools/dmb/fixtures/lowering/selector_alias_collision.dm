/datum/selector_alias_owner
	var/value = 3

/datum/selector_alias_owner/proc/first(dummy = 0)
	set name = "same alias"
	return 1

/datum/selector_alias_owner/proc/second(dummy = 0)
	set name = "same alias"
	return 2

/proc/selector_call_first(datum/selector_alias_owner/owner)
	return owner.first()

/proc/selector_call_second(datum/selector_alias_owner/owner)
	return owner.second()

/proc/selector_cached_first(datum/selector_alias_owner/owner)
	return owner.first(owner.value)

/proc/selector_cached_second(datum/selector_alias_owner/owner)
	return owner.second(owner.value)


