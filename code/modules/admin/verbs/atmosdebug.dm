ADMIN_VERB_VISIBILITY(atmosscan, ADMIN_VERB_VISIBLITY_FLAG_LOCALHOST)
ADMIN_VERB(atmosscan, R_DEBUG, "Check Piping", "Check all pipes in game (Only use on a test server).", ADMIN_CATEGORY_MAPPING)
	set background = 1

	feedback_add_details("admin_verb","CP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_atmos_scan, PROC_REF(scan_confirmed), answerer = answerer)

/datum/admin_verb/atmosscan/proc/scan_confirmed(datum/act/request/context)
	if(!context.answer)
		return
	scan_selected(context)

/datum/admin_verb/atmosscan/proc/scan_selected(datum/act/request/context)
	set background = 1
	var/client/user = context.request.answerer.client
	feedback_add_details("admin_verb","CP")
	if(context.request.value != "Yes")
		return

	to_chat(user, span_debug_info("Checking for disconnected pipes..."))
	//all plumbing - yes, some things might get stated twice, doesn't matter.
	for (var/obj/machinery/atmospherics/plumbing in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if (plumbing.nodealert)
			to_chat(user, span_filter_adminlog(span_warning("Unconnected [plumbing.name] located at [plumbing.x],[plumbing.y],[plumbing.z] ([get_area(plumbing.loc)])")))

	//Manifolds
	for (var/obj/machinery/atmospherics/pipe/manifold/pipe in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if (!pipe.node1 || !pipe.node2 || !pipe.node3)
			to_chat(user, span_filter_adminlog(span_warning("Unconnected [pipe.name] located at [pipe.x],[pipe.y],[pipe.z] ([get_area(pipe.loc)])")))

	//Pipes
	for (var/obj/machinery/atmospherics/pipe/simple/pipe in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if (!pipe.node1 || !pipe.node2)
			to_chat(user, span_filter_adminlog(span_warning("Unconnected [pipe.name] located at [pipe.x],[pipe.y],[pipe.z] ([get_area(pipe.loc)])")))

	to_chat(user, span_debug_info("Checking for overlapping pipes..."))
	next_turf:
		for(var/turf/T in world)
			for(var/dir in GLOB.cardinal)
				var/list/connect_types = list(0, 0, 0)
				for(var/obj/machinery/atmospherics/pipe in contents_of(T))
					if(dir & pipe.initialize_directions)
						for(var/connect_type in pipe.connect_types)
							connect_types[connect_type] += 1
						if(connect_types[1] > 1 || connect_types[2] > 1 || connect_types[3] > 1)
							to_chat(user, span_filter_adminlog(span_warning("Overlapping pipe ([pipe.name]) located at [T.x],[T.y],[T.z] ([get_area(T)])")))
							continue next_turf
	to_chat(user, span_debug_info("Done"))

ADMIN_VERB_VISIBILITY(powerdebug, ADMIN_VERB_VISIBLITY_FLAG_LOCALHOST)
ADMIN_VERB(powerdebug, R_DEBUG, "Check Power", "Checks all powernets (Only use on a test server).", ADMIN_CATEGORY_MAPPING)
	feedback_add_details("admin_verb","CPOW") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

	for(var/id in machines_power_grids())
		if(!length(power_grid_nodes(id)))
			to_chat(user, span_filter_adminlog("Power region [id] has no machines ([power_avail(id)] W available)."))

/datum/prompt/choice/admin_atmos_scan
	rights = R_DEBUG
	timeout = 0
	question = "WARNING: This command should not be run on a live server. Do you want to continue?"
	title = "Check Piping"
	choices = list("No", "Yes")
	buttons = TRUE
	recheck_on_open = TRUE

