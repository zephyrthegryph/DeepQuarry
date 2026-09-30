// powered_by(system, role): membership of a /datum/cap_system, with a role (doc/rewrite/dx_conventions.md
// §6). The holder joins `system` while it exists; a role-indexed system lists its members by role, so
// the power system finds every area supply without scanning atoms:
//	cap_system_members(/datum/cap_system/power, POWER_ROLE_AREA_SUPPLY)
//
//	. += powered_by(/datum/cap_system/power, role = POWER_ROLE_AREA_SUPPLY)

/datum/capability/powered_by
	layer_name = CAP_NO_LAYER
	var/role
	/// powered_by(POWERED_BY_AREA, ...): the holder is a MEMBER of the area it stands in (join(area, holder,
	/// source = this capability, role)), not of a cap_system. members_of(area, role) lists them.
	var/of_area = FALSE

/// `system`: a /datum/cap_system type the holder joins, or POWERED_BY_AREA to be a member of its area.
/proc/powered_by(system, role)
	var/datum/capability/powered_by/C = new
	if(system == POWERED_BY_AREA)
		C.of_area = TRUE
	else
		C.joins = list(system)
	C.role = role
	C.key = "powered_by:[system]"
	return list(C)

/datum/capability/powered_by/on_holder_init(atom/holder, mapload)
	if(of_area)
		join(get_area(holder), holder, src, role)

/datum/capability/powered_by/on_holder_destroy(atom/holder)
	if(of_area)
		leave(get_area(holder), holder, src, all = TRUE)

/// The holder moved to another area: its membership follows.
/datum/capability/powered_by/proc/area_changed(atom/holder, area/old_area, area/new_area)
	if(!of_area)
		return
	if(old_area)
		leave(old_area, holder, src, all = TRUE)
	if(new_area)
		join(new_area, holder, src, role)

/// A holder's powered_by(POWERED_BY_AREA) memberships follow it into another area.
/atom/proc/caps_area_changed(area/old_area, area/new_area)
	for(var/datum/capability/powered_by/C in caps_all(src))
		C.area_changed(src, old_area, new_area)

/// The members of `area` holding `role` (a copy: a caller that yields may see members leave meanwhile).
/proc/area_members(area/A, role)
	var/list/found = A ? members_of(A, role) : null
	return found ? found.Copy() : list()

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
