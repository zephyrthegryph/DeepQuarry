/*
 * Chew toys
 */
/obj/item/toy/chewtoy
	name = "chew toy"
	desc = "A red hard-rubber chew toy shaped like a bone. Perfect for your dog! You wouldn't want to chew on it, right?"
	icon = 'icons/obj/toy.dmi'
	icon_state = "dogbone"

/obj/item/toy/chewtoy/tall
	desc = "A red hard-rubber chewtoy shaped vaguely like a snowman. Perfect for your dog! You wouldn't want to chew on it, right?"
	icon_state = "chewtoy"

/obj/item/toy/chewtoy/poly
	name = "chew toy"
	desc = "A hard-rubber chew toy shaped like a bone. Perfect for your dog! You wouldn't want to chew on it, right?"
	icon_state = "dogbone_poly"

/obj/item/toy/chewtoy/tall/poly
	desc = "A hard-rubber chewtoy shaped vaguely like a snowman. Perfect for your dog! You wouldn't want to chew on it, right?"
	icon_state = "chewtoy_poly"

CAPABILITIES(/obj/item/toy/chewtoy)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/chewtoy/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	play_sfx(loc, SFX_ITEMS_DROP_PLUSHIE)
	act_message(user, src, MSG_SELF(span_notice("You gnaw on %T%!")), MSG_OTHERS(span_notice(span_bold("%U%") + " gnaws on %T%!")))
	return TRUE
