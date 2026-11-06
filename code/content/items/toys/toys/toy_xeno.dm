/*
 * Toy xeno
 */
/obj/item/toy/toy_xeno
	icon = 'icons/obj/toy.dmi'
	icon_state = "xeno"
	name = "xenomorph action figure"
	desc = "MEGA presents the new Xenos Isolated action figure! Comes complete with realistic sounds! Pull back string to use."
	var/cooldown = 0

/obj/item/toy/toy_xeno/proc/hiss()
	atom_say("Hiss!")
	play_sfx(get_turf(src), SFX_HISS, volume = 50, vary = TRUE)
	after(src, 4.5 SECONDS, PROC_REF(hiss_rewound))

/obj/item/toy/toy_xeno/proc/hiss_rewound()
	set_icon_state("[initial(icon_state)]")

CAPABILITIES(/obj/item/toy/toy_xeno)
	configure(atom_rules(bubble_icon = "alien"))
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/toy_xeno/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 5 SECONDS) //5 second cooldown
		act_message(user, src, others = span_notice("%U% pulls back the string on %T%."))
		set_icon_state("[initial(icon_state)]cool")
		after(src, 0.5 SECONDS, PROC_REF(hiss))
	else
		to_chat(user, span_warning("The string on [src] hasn't rewound all the way!"))
		return TRUE
	return TRUE
