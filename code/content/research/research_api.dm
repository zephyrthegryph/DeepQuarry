// The research system's API (code/modules/research/research_service.dm declares the system).
//
//   SSresearch.techweb_node_by_id(id) / techweb_design_by_id(id)   a node or design by id (the error placeholder when unknown)
//   SSresearch.register_techweb(web)                                a techweb joins the round's shared webs
//   SSresearch.autounlock_techweb(path)                             the round's autounlock web of a type, made on first use
//   SSresearch.get_available_servers(turf) / find_valid_servers(turf, web)   the research servers a location can reach
//
// The node and design tables, the point types and the registered techwebs are read as vars.

/datum/system/research/proc/techweb_node_by_id(id)
	return techweb_nodes[id] || error_node

/datum/system/research/proc/techweb_design_by_id(id)
	return techweb_designs[id] || error_design

/// Registers one of the round's techwebs (science, admin, an autounlock web): it becomes a shared
/// registry instance (registry_techweb()). Scratch webs (disks) are never registered.
/datum/system/research/proc/register_techweb(datum/techweb/web)
	if(web && !(web in techwebs))
		techwebs += web
	return web

/// The round's autounlock techweb of `path`, made and registered on first use.
/datum/system/research/proc/autounlock_techweb(path)
	var/datum/techweb/web = GLOB.autounlock_techwebs[path]
	if(!web)
		web = new path
		GLOB.autounlock_techwebs[path] = web
	return register_techweb(web)

/datum/system/research/proc/get_available_servers(turf/location)
	var/list/local_servers = list()
	if(!location)
		return local_servers
	for (var/datum/techweb/individual_techweb as anything in techwebs)
		var/list/servers = find_valid_servers(location, individual_techweb)
		if(length(servers))
			local_servers += servers
	return local_servers

/datum/system/research/proc/find_valid_servers(turf/location, datum/techweb/checking_web)
	var/list/valid_servers = list()
	for(var/obj/machinery/rnd/server/server as anything in checking_web.techweb_servers)
		if(!is_valid_z_level(get_turf(server), location))
			continue
		valid_servers += server
	return valid_servers
