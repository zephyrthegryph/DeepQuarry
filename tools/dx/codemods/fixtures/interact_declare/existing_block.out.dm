CAPABILITIES(/obj/item/blocked)
	examine_line("It is blocked.")
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))

/obj/item/blocked/proc/interaction_self(datum/act/op/A)
	return TRUE
