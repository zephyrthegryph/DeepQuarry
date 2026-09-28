/obj/structure/displaycase
	name = "display case"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "glassbox1"
	desc = "A display case for prized possessions. It taunts you to kick it."
	density = TRUE
	anchored = TRUE
	unacidable = TRUE//Dissolving the case would also delete the gun.
	max_integrity = 30
	var/occupied = 1
	var/destroyed = 0

// Glass-on-glass hit sound while the case still stands.
/obj/structure/displaycase/play_attack_sound(damage_amount, damage_type, damage_flag)
	play_sfx(src, SFX_EFFECTS_GLASSHIT)

// Reaching 0 integrity shatters the front glass into a passable, looted shell.
/obj/structure/displaycase/atom_destruction(damage_flag)
	SHOULD_CALL_PARENT(FALSE)
	if(!destroyed)
		density = FALSE
		destroyed = 1
		new /obj/item/material/shard( src.loc )
		play_sfx(src, SFX_SHATTER)
		update_icon()

/obj/structure/displaycase/update_icon()
	if(src.destroyed)
		src.icon_state = "glassboxb[src.occupied]"
	else
		src.icon_state = "glassbox[src.occupied]"
	return


/obj/structure/displaycase/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/displaycase_item,
		/datum/interaction/entry_hand/displaycase_hand,
	)
	..()

/// Old attackby: hit the case with a weapon.
/datum/interaction/entry_item/displaycase_item
	id = "displaycase_item"
	name = "Use"
	effect = /obj/structure/displaycase/proc/interaction_item

/obj/structure/displaycase/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	user.setClickCooldown(user.get_attack_speed(W))
	user.do_attack_animation(src)
	play_sfx(src, SFX_EFFECTS_GLASSHIT, volume = 50)
	receive_weapon_hit(W, user)
	return TRUE

/// Old attack_hand: take the gun from a shattered case, or kick it.
/datum/interaction/entry_hand/displaycase_hand
	id = "displaycase_hand"
	name = "Use"
	effect = /obj/structure/displaycase/proc/interaction_hand

/obj/structure/displaycase/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if (src.destroyed && src.occupied)
		new /obj/item/gun/energy/captain( src.loc )
		to_chat(user, span_notice("You deactivate the hover field built into the case."))
		src.occupied = 0
		src.add_fingerprint(user)
		update_icon()
	else
		to_chat(user, span_warning("You kick the display case."))
		for(var/mob/O in oviewers())
			if ((O.client && !( O.blinded )))
				to_chat(O, span_warning("[user] kicks the display case."))
		take_damage(2, BRUTE, MELEE)
	return TRUE
