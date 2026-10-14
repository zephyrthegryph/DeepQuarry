// Concrete listener and garbage diagnostic adapters for collapse accounting.
/datum/state_reference_environment/hook_blockers(list/nodes, list/internal)
	. = list()
	for(var/datum/node as anything in internal)
		for(var/datum/activation/A as anything in node.rx?.sourced)
			if(A.dead || A.def.cap_id != CAP_HOOK || !A.holder || (A.holder in internal))
				continue
			var/datum/capability/hook/def = A.def
			if(def.on_listener)
				. += "[node.type] observes events on [A.holder.type]"
	for(var/datum/node as anything in nodes)
		for(var/datum/activation/A as anything in node.rx?.activations)
			if(A.dead || A.def.cap_id != CAP_HOOK || !isdatum(A.source) || (A.source in internal))
				continue
			var/datum/capability/hook/def = A.def
			if(def.on_listener)
				var/datum/listener = A.source
				. += "[listener.type] observes events on [node.type]"

/datum/state_reference_environment/describe(datum/node, extra, name_holders = FALSE)
	. = "[node.type] has [extra] reference\s from outside its container"
#ifdef UNIT_TESTS
	if(!name_holders)
		return
	// Name the holder. Slow (it walks the world), so test builds only.
	SSgarbage.should_save_refs = TRUE
	node.found_refs = null
	node.find_references()
	SSgarbage.should_save_refs = FALSE
	var/list/names = list()
	for(var/where in node.found_refs)
		if(!islist(where))
			names += "[where]"
	node.found_refs = null
	// The finder cannot name the global a list belongs to, so look there directly.
	for(var/global_name in GLOB.vars)
		var/list/candidate = GLOB.vars[global_name]
		if(islist(candidate) && (node in candidate))
			names += "GLOB.[global_name]"
	if(length(names))
		. += " (found in: [jointext(names, ", ")])"
#endif
