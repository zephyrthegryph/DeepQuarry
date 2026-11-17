/*
 * Desk toys
 */
/obj/item/toy/desk
	icon = 'icons/obj/toy.dmi'
	var/on = FALSE
	var/activation_sound = SFX_MACHINES_CLICK

/// The look (the draw sweep: from its template).
/obj/item/toy/desk/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][on ? "-on" : ""]")

/obj/item/toy/desk/proc/activate(mob/user as mob)
	set_on(!on)
	playsound(src.loc, activation_sound, 75, 1)
	return 1

CAPABILITIES(/obj/item/toy/desk)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Alternate use"), then(PROC_REF(interaction_alt)))
	drag_onto(PROC_REF(mousedrop_input))

/// Old attack_self.
/obj/item/toy/desk/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	activate(user)
	return TRUE

/// Old click_alt.
/obj/item/toy/desk/proc/interaction_alt(datum/act/op/A)
	var/mob/user = A.actor
	activate(user)
	return TRUE

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/toy/desk/proc/mousedrop_input(datum/act/input/A)
	return pickup_with_actor(A.actor, A.over)

/obj/item/toy/desk/proc/pickup_with_actor(mob/user, mob/destination)
	if((user && user == destination && (!( user.restrained() ) && (!( user.stat ) && (user.contents.Find(src) || in_range(src, user))))))
		if(ishuman(user))
			if(!user.get_active_hand())		//if active hand is empty
				var/mob/living/carbon/human/H = user
				var/obj/item/organ/external/temp = H.organs_by_name[BP_R_HAND]

				if (H.hand)
					temp = H.organs_by_name[BP_L_HAND]
				if(temp && !temp.is_usable())
					to_chat(user,span_notice("You try to move your [temp.name], but cannot!"))
					return

				to_chat(user,span_notice("You pick up [src]."))
				user.put_in_hands(src)

	return

/obj/item/toy/desk/newtoncradle
	name = "\improper Newton's cradle"
	desc = "A ancient 21th century super-weapon model demonstrating that Sir Isaac Newton is the deadliest sonuvabitch in space."
	icon_state = "newtoncradle"

CAPABILITIES(/obj/item/toy/desk/newtoncradle)
	configure(atom_rules(description_fluff = "Aside from car radios, Eridanian Dregs are reportedly notorious for stealing these things. It is often \
	theorized that the very same ball bearings are used in black-market cybernetics."))
