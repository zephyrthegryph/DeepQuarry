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

TRACKED(/obj/structure/displaycase, occupied)
TRACKED(/obj/structure/displaycase, destroyed)

// Glass-on-glass hit sound while the case still stands.
/obj/structure/displaycase/play_attack_sound(damage_amount, damage_type, damage_flag)
	play_sfx(src, SFX_EFFECTS_GLASSHIT)

// Reaching 0 integrity shatters the front glass into a passable, looted shell.
/obj/structure/displaycase/atom_destruction(damage_flag)
	SHOULD_CALL_PARENT(FALSE)
	if(!destroyed)
		set_density(FALSE)
		set_destroyed(1)
		new /obj/item/material/shard( src.loc )
		play_sfx(src, SFX_SHATTER)

/// The look (the draw sweep: from its template).
/obj/structure/displaycase/draw(datum/look/look)
	..()
	look.state("glassbox[destroyed ? "b" : ""][occupied]")


CAPABILITIES(/obj/structure/displaycase)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))

/obj/structure/displaycase/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	user.setClickCooldown(user.get_attack_speed(W))
	user.do_attack_animation(src)
	play_sfx(src, SFX_EFFECTS_GLASSHIT, volume = 50)
	receive_weapon_hit(W, user)
	return TRUE

/obj/structure/displaycase/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if (src.destroyed && src.occupied)
		new /obj/item/gun/energy/captain( src.loc )
		to_chat(user, span_notice("You deactivate the hover field built into the case."))
		set_occupied(0)
		src.add_fingerprint(user)
	else
		to_chat(user, span_warning("You kick the display case."))
		for(var/mob/O in oviewers())
			if ((O.client && !( O.blinded )))
				to_chat(O, span_warning("[user] kicks the display case."))
		take_damage(2, BRUTE, MELEE)
	return TRUE
