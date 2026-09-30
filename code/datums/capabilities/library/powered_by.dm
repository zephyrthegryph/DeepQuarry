// powered_by(system, role): membership of a /datum/cap_system, with a role (doc/rewrite/dx_conventions.md
// §6). The holder joins `system` while it exists; a role-indexed system lists its members by role, so
// the power system finds every area supply without scanning atoms:
//	cap_system_members(/datum/cap_system/power, POWER_ROLE_AREA_SUPPLY)
//
//	. += powered_by(/datum/cap_system/power, role = POWER_ROLE_AREA_SUPPLY)

/datum/capability/powered_by
	layer_name = CAP_NO_LAYER
	var/role

/proc/powered_by(system, role)
	var/datum/capability/powered_by/C = new
	C.joins = list(system)
	C.role = role
	C.key = "powered_by:[system]"
	return list(C)

/// The role A holds in `system` (its powered_by() capability), or null.
/proc/cap_system_role(atom/A, system)
	for(var/datum/capability/powered_by/C in caps_all(A))
		if(system in C.joins)
			return C.role
	return null

/// The role this capability plays in its system.
/datum/capability/powered_by/system_role()
	return role

/// A system whose members are indexed by role (powered_by()). The index is the membership store's (membership.dm).
/datum/cap_system/roles

/// The members of `system` holding `role` (a copy).
/proc/cap_system_members(system, role)
	return members_of(system, role).Copy()

/// The power system: area supplies (APCs); producers and storage later.
/datum/cap_system/power
	parent_type = /datum/cap_system/roles
