/// The power system (a /datum/system): who plays which part of the power network, as MEMBER relations held by
/// powered_by(/datum/system/power, role = ...) capabilities. An APC joins as POWER_ROLE_AREA_SUPPLY; producers and
/// storage join under their own roles, so the power code lists them by role instead of scanning atoms.
/datum/system/power
	name = "power"

/// The members holding `role` (a copy: a caller that yields may see members leave meanwhile).
/datum/system/power/proc/members_with_role(role)
	return members_of(type, role).Copy()

/// The role `A` holds here, or null.
/datum/system/power/proc/role_of(atom/A)
	return member_role(type, A)
