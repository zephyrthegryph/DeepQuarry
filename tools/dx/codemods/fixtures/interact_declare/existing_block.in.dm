CAPABILITIES(/obj/item/blocked)
	examine_line("It is blocked.")

DECLARE_INTERACTIONS(/obj/item/blocked, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/blocked/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE
