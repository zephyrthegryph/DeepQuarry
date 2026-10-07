// Shared input adapter registry and downstream interaction compatibility protocol.

/datum/input_adapter
	var/name = "abstract"

/// Adapters are singletons; GLOB.input_adapters maps type -> instance.
GLOBAL_LIST_INIT(input_adapters, init_input_adapters())

/proc/init_input_adapters()
	var/list/adapters = list()
	for(var/datum/input_adapter/adapter_type as anything in subtypesof(/datum/input_adapter))
		adapters[adapter_type] = new adapter_type
	return adapters


GLOBAL_DATUM(input_compatibility, /datum/input_adapter)

/mob/proc/input_adapter()
	return input_compatibility()

/datum/input_adapter/proc/drag_legacy(mob/user, atom/dragged, atom/over, list/legacy)
	return

/datum/input_adapter/proc/compatibility_candidates(datum/op_resolution/R)
	return

/datum/input_adapter/proc/compatibility_menu(mob/actor, atom/target, route = null)
	return list()

/datum/input_adapter/proc/compatibility_screentip(mob/actor, atom/target, gesture)
	return null

/datum/input_adapter/proc/compatibility_run(datum/op_cand/C, datum/op_resolution/R, datum/op_result/result)
	return result

/proc/op_run_compatibility(datum/op_cand/C, datum/op_resolution/R, datum/op_result/result)
	return input_compatibility().compatibility_run(C, R, result)

/proc/input_compatibility()
	RETURN_TYPE(/datum/input_adapter)
	if(!GLOB.input_compatibility)
		GLOB.input_compatibility = new /datum/input_adapter
	return GLOB.input_compatibility
