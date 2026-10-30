/datum/system/power
	var/own
SYSTEM_DEF(power)
	var
		grouped
#if 0
/datum/system/power
	var/inactive
#endif
SYSTEM_ACCESSOR(power, alpha, nameof(own))
SYSTEM_ACCESSOR(power, typed, nameof(grouped), /datum/unknown)
SYSTEM_ACCESSOR(power, inactive, nameof(inactive))
SYSTEM_ACCESSOR(power, duplicate, nameof(own))
SYSTEM_ACCESSOR(power)
SYSTEM_ACCESSOR(power, bad_key, own)
SYSTEM_ACCESSOR(power, bad_type, nameof(own), datum)
