DECLARE_INTERACTIONS(/obj/item/gated, INTERACT_USE(null, PROC_REF(interaction_self), REQ_BECAUSE(REQ_FIELD("held"), "empty")))

/obj/item/gated/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

DECLARE_INTERACTIONS(/obj/item/falls, INTERACT_HAND(null, PROC_REF(interaction_hand)))

/obj/item/falls/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(!user)
		return FALSE
	user.visible_message("falls off the end")

DECLARE_INTERACTIONS(/obj/item/stancy, INTERACT_OBSERVER(null, PROC_REF(interaction_alt)))

/obj/item/stancy/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

DECLARE_INTERACTIONS(/obj/item/reads, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/reads/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	return interaction.stance

DECLARE_INTERACTIONS(/obj/item/parent, INTERACT_USE(null, PROC_REF(interaction_self)))
DECLARE_INTERACTIONS(/obj/item/parent/child, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/parent/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

/obj/item/parent/child/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

EXTEND_INTERACTIONS(/obj/item/extends, INTERACT_USE(null, PROC_REF(interaction_self)))
