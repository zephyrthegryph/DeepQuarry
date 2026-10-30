/datum/system/base
	var/parent_field
/datum/system/base/child
	var/child_field
SYSTEM_DEF(macro_only)
	var/only
SYSTEM_ACCESSOR(base/child, child_ok, nameof(child_field))
SYSTEM_ACCESSOR(base/child, inherited_bad, nameof(parent_field))
SYSTEM_ACCESSOR(macro_only, macro_missing, nameof(only))
SYSTEM_ACCESSOR(power, duplicate, nameof(own), /datum)
SYSTEM_ACCESSOR(power, missing, nameof(absent))
