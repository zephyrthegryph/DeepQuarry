/obj/item/toy/griffin
	name = "griffin action figure"
	desc = "An action figure modeled after 'The Griffin', criminal mastermind."
	icon = 'icons/obj/toy.dmi'
	icon_state = "griffinprize"
	w_class = ITEMSIZE_SMALL
	COOLDOWN_DECLARE(cooldown)

CAPABILITIES(/obj/item/toy/griffin)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/griffin/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown)) //for the sanity of everyone
		var/message = pick("You can't stop me, Owl!", "My plan is flawless! The vault is mine!", "Caaaawwww!", "You will never catch me!")
		to_chat(user, span_notice("You pull the string on the [src]."))
		visible_message(span_danger("[message]"))
		COOLDOWN_START(src, cooldown, 3 SECONDS)
	return TRUE
