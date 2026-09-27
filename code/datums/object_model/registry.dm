// Sparse declared membership using the same storage as materialization
// registries. Runtime activation and teardown control membership here.
/datum/object_model/registry
	parent_type = /datum/registry
	var/accepts = /datum

/datum/object_model/registry/om_kind()
	return OM_KIND_SERVICE

/datum/object_model/registry/Destroy(force = FALSE)
	var/list/services = om_registry_services()
	if(services[type] == src)
		services -= type
	return ..()

/proc/om_registry_services()
	var/static/list/services = list()
	return services

/proc/om_registry(path) as /datum/object_model/registry
	if(!ispath(path, /datum/object_model/registry) || path == /datum/object_model/registry)
		return null
	var/list/services = om_registry_services()
	var/datum/object_model/registry/R = services[path]
	if(!R || QDELETED(R))
		R = new path
		services[path] = R
	return R

/// A detached snapshot; callers can filter or remove entries locally.
/proc/om_registry_members(path, member_type = null)
	var/list/result = list()
	var/datum/object_model/registry/R = om_registry(path)
	if(!R || (member_type && !ispath(member_type, /datum)))
		return result
	for(var/datum/member as anything in R.members)
		if(!QDELETED(member) && (!member_type || istype(member, member_type)))
			result += member
	return result

/proc/om_registry_has(path, datum/member)
	var/datum/object_model/registry/R = om_registry(path)
	return !!(R && member && !QDELETED(member) && (member in R.members))
