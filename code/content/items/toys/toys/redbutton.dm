/*
 * Big red button
 */
/obj/item/toy/redbutton
	name = "big red button"
	desc = "A big, plastic red button. Reads 'From HonkCo Pranks?' on the back."
	icon = 'icons/obj/toy.dmi'
	icon_state = "bigred"
	w_class = ITEMSIZE_SMALL
	var/cooldown = 0

CAPABILITIES(/obj/item/toy/redbutton)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/redbutton/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 30 SECONDS) // Sets cooldown at 30 seconds
		act_message(user, null, MSG_SELF(span_notice("You press the button, it plays a loud noise!")), MSG_OTHERS(span_warning("%U% presses the big red button.")), MSG_BLIND(span_notice("The button clicks loudly.")))
		play_sfx(src, SFX_EFFECTS_EXPLOSIONFAR)
		for(var/mob/M in range(10, src)) // Checks range
			if(!M.stat && !istype(M, /mob/living/silicon/ai)) // Checks to make sure whoever's getting shaken is alive/not the AI
				after(M, 0.2 SECONDS, GLOBAL_PROC_REF(shake_camera), with = list(M, 2, 1))
	else
		to_chat(user, span_warning("Nothing happens."))
	return TRUE
