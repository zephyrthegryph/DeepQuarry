// powered_by(system, role): a MEMBER relation to a /datum/system (or to the holder's area), with a role
// (doc/rewrite/dx_conventions.md §6). The holder joins `system` while it exists, through the one membership
// store (controllers/kernel/membership.dm); members are listed by role, so the power system finds every area
// supply without scanning atoms:
//	system(/datum/system/power).members_with_role(POWER_ROLE_AREA_SUPPLY)
//
//	. += powered_by(/datum/system/power, role = POWER_ROLE_AREA_SUPPLY)

/datum/capability/powered_by
	layer_name = CAP_NO_LAYER
	var/role
	/// powered_by(POWERED_BY_AREA, ...): the holder is a MEMBER of the area it stands in (join(area, holder,
	/// source = this capability, role)), not of a system. members_of(area, role) lists them.
	var/of_area = FALSE

/// `system`: a /datum/system type the holder joins, or POWERED_BY_AREA to be a member of its area.
/proc/legacy_powered_by(system, role)
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
/proc/caps_area_changed(atom/holder, area/old_area, area/new_area)
	for(var/datum/capability/powered_by/C in caps_all(holder))
		C.area_changed(holder, old_area, new_area)

/// The members of `area` holding `role` (a copy: a caller that yields may see members leave meanwhile).
/proc/area_members(area/A, role)
	var/list/found = A ? members_of(A, role) : null
	return found ? found.Copy() : list()

/// The role this capability plays in its system.
/datum/capability/powered_by/system_role()
	return role
