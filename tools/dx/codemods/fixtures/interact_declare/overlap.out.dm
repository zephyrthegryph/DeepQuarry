DECLARE_INTERACTIONS(/obj/item/gap_twice, \
	INTERACT_HAND("Poke", PROC_REF(interaction_poke)), \
	INTERACT_HAND_AS(I_HURT, "Punch", PROC_REF(interaction_punch)), \
)

/obj/item/gap_twice/proc/interaction_poke(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

/obj/item/gap_twice/proc/interaction_punch(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE
