/datum/operation_compatibility/named(mob/actor, datum/target, key)
	return op_entry_named(actor, target, key)
/datum/operation_compatibility/perform(mob/actor, datum/target, key, route, obj/held)
	return legacy_perform_op(actor, target, key, route, held)

/datum/operation_compatibility/item_specificity(type)
	if(!ispath(type, /obj/item))
		return 0
	if(type == /obj/item)
		return 1
	return length(splittext("[type]", "/"))

/datum/operation_compatibility/broad_item_type(type)
	return type == /obj/item

/obj/item/op_is_item()
	return TRUE

CAPABILITIES(/datum/act/action)
	ref_one(nameof(held))

/datum/act/action/held_provider()
	return held

/datum/act/action/set_held_provider(obj/provider)
	rel_set(src, nameof(held), provider)

/// A released context must not keep a borrowed relation alive when its pool resets the fields.
/datum/act/action/release()
	rel_set(src, nameof(held), null)
	return ..()
