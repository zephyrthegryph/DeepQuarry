GLOBAL_DATUM(operation_compatibility, /datum/operation_compatibility)

/// Optional legacy operation transport; input ordering remains owned by the operation engine.
/datum/operation_compatibility
/datum/operation_compatibility/proc/named(mob/actor, datum/target, key)
	return null
/datum/operation_compatibility/proc/perform(mob/actor, datum/target, key, route, obj/held)
	return null
/proc/operation_compatibility()
	RETURN_TYPE(/datum/operation_compatibility)
	if(!GLOB.operation_compatibility)
		GLOB.operation_compatibility = new /datum/operation_compatibility
	return GLOB.operation_compatibility

/datum/proc/op_timer_message(msg)
	return

/// The library defines which declared types are inventory items and how their bindings rank.
/datum/operation_compatibility/proc/item_specificity(type)
	return 0

/datum/operation_compatibility/proc/broad_item_type(type)
	return FALSE

/obj/proc/op_is_item()
	return FALSE

/proc/op_item_like(datum/held)
	var/obj/object = held
	return istype(object) && object.op_is_item()


/// The inventory adapter supplies the transient held provider carried by an action context.
/datum/act/action/proc/held_provider()
	RETURN_TYPE(/obj)
	return null

/datum/act/action/proc/set_held_provider(obj/provider)
	return
