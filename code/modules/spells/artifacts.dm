//////////////////////Scrying orb//////////////////////

/obj/item/scrying
	name = "scrying orb"
	desc = "An incandescent orb of otherworldly energy, staring into it gives you vision beyond mortal means."
	icon = 'icons/obj/projectiles.dmi'
	icon_state = "bluespace"
	throw_speed = 3
	throw_range = 7
	throwforce = 10
	injury_kind = INJURY_BURN
	force = 10
	hitsound = SFX_ITEMS_WELDER2

CAPABILITIES(/obj/item/scrying)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))

/// Old attack_self.

/obj/item/scrying/proc/interaction_self(datum/act/op/A)
	var/refusal = dq_actor_is_wizard_or_mindless(A.actor, src, A.held)
	if(refusal != TRUE)
		if(istext(refusal))
			to_chat(A.actor, span_warning(refusal))
		return OP_DECLINE
	var/mob/user = A.actor

	to_chat(user, span_info("You can see... everything!"))
	act_message(user, src, others = span_danger("%U% stares into %T%, %THEIR% eyes glazing over."))

	rel_set(user, nameof(/mob::teleop), user.ghostize(1))
	announce_ghost_joinleave(user.teleop, 1, "You feel that they used a powerful artifact to [pick("invade","disturb","disrupt","infest","taint","spoil","blight")] this place with their presence.")
	return TRUE
