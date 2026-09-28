/mob/living/carbon/alien/diona/MouseDrop(atom/over_object)
	var/mob/living/carbon/human/H = over_object
	if(!istype(H) || !Adjacent(H))
		return ..()
	if(H.attack_variant == ATTACK_VARIANT_GRAB && hat && !H.hands_are_full())
		hat.forceMove(get_turf(src))
		H.put_in_hands(hat)
		H.visible_message(span_danger("\The [H] removes \the [src]'s [hat]."))
		hat = null
		update_icon()
	else
		return ..()

EXTEND_INTERACTIONS(/mob/living/carbon/alien/diona, INTERACT_ITEM_AS(I_HELP, "Put on hat", PROC_REF(diona_interaction_hat)))

/// Old attackby, in help: a hat goes on the nymph. Anything else reaches the attack.
/mob/living/carbon/alien/diona/proc/diona_interaction_hat(mob/user, obj/item/held, datum/interaction/interaction)
	if(!istype(held, /obj/item/clothing/head))
		return FALSE
	if(hat)
		to_chat(user, span_warning("\The [src] is already wearing \the [hat]."))
		return TRUE
	user.unEquip(held)
	wear_hat(held)
	user.visible_message(span_infoplain(span_bold("\The [user]") + " puts \the [held] on \the [src]."))
	return TRUE
