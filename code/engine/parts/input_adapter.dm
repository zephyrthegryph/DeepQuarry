// Shared input adapter registry and the downstream topic and drag hooks.

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

/// Delivers a driver-built href that no native topic op answered through the downstream topic table.
/datum/input_adapter/proc/compatibility_topic(datum/holder, mob/actor, list/href_list)
	return

/proc/input_compatibility()
	RETURN_TYPE(/datum/input_adapter)
	if(!GLOB.input_compatibility)
		GLOB.input_compatibility = new /datum/input_adapter
	return GLOB.input_compatibility
