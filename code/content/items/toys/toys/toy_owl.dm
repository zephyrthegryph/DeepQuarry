/obj/item/toy/owl
	name = "owl action figure"
	desc = "An action figure modeled after 'The Owl', defender of justice."
	icon = 'icons/obj/toy.dmi'
	icon_state = "owlprize"
	w_class = ITEMSIZE_SMALL
	COOLDOWN_DECLARE(cooldown)

CAPABILITIES(/obj/item/toy/owl)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/owl/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown)) //for the sanity of everyone
		var/message = pick("You won't get away this time, Griffin!", "Stop right there, criminal!", "Hoot! Hoot!", "I am the night!")
		to_chat(user, span_notice("You pull the string on the [src]."))
		visible_message(span_danger("[message]"))
		COOLDOWN_START(src, cooldown, 3 SECONDS)
	return TRUE
