/*
 * Party popper
 */
/obj/item/toy/partypopper
	name = "party popper"
	desc = "Instructions : Aim away from face. Wait for appropriate timing. Pull cord, enjoy confetti."
	icon = 'icons/obj/toy.dmi'
	icon_state = "partypopper"
	w_class = ITEMSIZE_TINY

CAPABILITIES(/obj/item/toy/partypopper)
	configure(item_sounds(drop = SFX_ITEMS_DROP_CARDBOARDBOX, pickup = SFX_ITEMS_PICKUP_CARDBOARDBOX))
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/partypopper/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(icon_state == "partypopper")
		act_message(user, null, MSG_SELF(span_notice("You pull on the string, releasing a burst of confetti!")), MSG_OTHERS(span_notice("%U% pulls on the string, releasing a burst of confetti!")))
		play_sfx(src, SFX_EFFECTS_SNAP)
		var/datum/effect/effect/system/confetti_spread/s = new /datum/effect/effect/system/confetti_spread
		s.set_up(5, 1, src)
		s.start()
		set_icon_state("partypopper_e")
		var/turf/T = get_step(src, user.dir)
		if(!turf_clear(T))
			T = get_turf(src)
		new /obj/effect/decal/cleanable/confetti(T)
	else
		to_chat(user, span_notice("The [src] is already spent!"))
	return TRUE
