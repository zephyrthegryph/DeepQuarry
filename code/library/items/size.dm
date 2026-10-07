// Item-specific acceptance requirements over the engine's slot parts.

// ---- slot acceptance ----

MSG_DEF_SELF(slot/too_large, "That is too large to fit.")
MSG_DEF_SELF(slot/too_small, "That is too small to fit.")

/// size_is(min, max): the held item's w_class is between min and max (max defaults to min). Refused with "too large" or "too small".
/proc/size_is(min_size, max_size = null)
	return part_make(/datum/entry/part/req/size_is, list("min" = min_size, "max" = isnull(max_size) ? min_size : max_size))

/datum/entry/part/req/size_is
	part_name = "size_is"

/datum/entry/part/req/size_is/holds(datum/act/op/A)
	var/obj/item/held = A.held
	return !istype(held) || (held.w_class >= src.args["min"] && held.w_class <= src.args["max"])

/datum/entry/part/req/size_is/refusal(datum/act/op/A)
	var/obj/item/held = A.held
	return (istype(held) && held.w_class < src.args["min"]) ? /datum/msg/slot/too_small : /datum/msg/slot/too_large
