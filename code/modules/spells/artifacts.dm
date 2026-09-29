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

DECLARE_INTERACTIONS(/obj/item/scrying, INTERACT_USE(null, PROC_REF(interaction_self), REQ_PROC(/proc/dq_actor_is_wizard_or_mindless, "you stare into the orb and see nothing but your own reflection")))

/// Old attack_self.
/obj/item/scrying/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)

	to_chat(user, span_info("You can see... everything!"))
	act_message(user, src, others = span_danger("%U% stares into %T%, %THEIR% eyes glazing over."))

	user.teleop = user.ghostize(1)
	announce_ghost_joinleave(user.teleop, 1, "You feel that they used a powerful artifact to [pick("invade","disturb","disrupt","infest","taint","spoil","blight")] this place with their presence.")
	return TRUE
