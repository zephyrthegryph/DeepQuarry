/mob/held_for_ops()
	return get_active_hand()
/mob/op_input_stance()
	return input_stance()
/obj/item/op_tool_quality(quality)
	return has_tool_quality(quality)

/obj/item/can_carry(obj/thing, mob/actor)
	return FALSE

/obj/item/carry(obj/thing, mob/actor)
	return FALSE
