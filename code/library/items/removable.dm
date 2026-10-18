// Whether a thing may leave the slot it is in (admission.md D2l): one requirement for what canremove, NOSTRIP and TRAIT_NODROP spell today.
// A slot or an op takes it on /datum/act/remove: extend(/datum/act/remove, needs(req_removable())). Type- and instance-level: it reads the item.

MSG_DEF_SELF(slot/not_removable, "It can't be taken off.")
MSG_DEF_SELF(slot/not_strippable, "It can't be stripped.")

/// req_removable(strip = FALSE): the held item may be taken out (canremove, no TRAIT_NODROP); with `strip`, it may also be stripped by someone
/// else (no NOSTRIP). Anything that is not an item has no such rule and passes.
/proc/req_removable(strip = FALSE, because = null)
	return part_make(/datum/entry/part/req/removable, list("strip" = strip, "because" = because))

/datum/entry/part/req/removable
	part_name = "req_removable"
	default_reason = /datum/msg/slot/not_removable

/datum/entry/part/req/removable/holds(datum/act/op/A)
	var/obj/item/I = A.held
	if(!istype(I))
		return TRUE
	if(!I.canremove || has_trait(I, TRAIT_NODROP))
		return FALSE
	return !src.args["strip"] || !(I.flags & NOSTRIP)

/datum/entry/part/req/removable/refusal(datum/act/op/A)
	var/obj/item/I = A.held
	if(src.args["because"])
		return req_reason_value(A, src.args["because"], default_reason)
	if(istype(I) && I.canremove && !has_trait(I, TRAIT_NODROP))
		return /datum/msg/slot/not_strippable
	return default_reason
