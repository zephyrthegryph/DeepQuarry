/mob/living/carbon/alien/diona/MouseDrop(atom/over_object)
	var/mob/living/carbon/human/H = over_object
	if(!istype(H) || !Adjacent(H))
		return ..()
	if(H.attack_variant == ATTACK_VARIANT_GRAB && hat && !H.hands_are_full())
		var/obj/item/removed_hat = rel_take(src, nameof(hat))
		removed_hat.forceMove(get_turf(src))
		H.put_in_hands(removed_hat)
		act_message(H, src, others = span_danger("%U% removes %T%'s [removed_hat]."))
	else
		return ..()

EXTEND_INTERACTIONS(/mob/living/carbon/alien/diona, INTERACT_INSERT_AS(I_HELP, /obj/item/clothing/head, PROC_REF(diona_interaction_hat), "Put on hat", REQ_FIELD_NOT("hat")))

/// Old attackby, in help: a hat goes on the nymph. Anything else reaches the attack.
/mob/living/carbon/alien/diona/proc/diona_interaction_hat(mob/user, obj/item/held, datum/interaction/interaction)
	user.unEquip(held)
	wear_hat(held)
	act_message(user, src, others = span_infoplain(span_bold("%U%") + " puts %I% on %T%."), item = held)
	return TRUE
