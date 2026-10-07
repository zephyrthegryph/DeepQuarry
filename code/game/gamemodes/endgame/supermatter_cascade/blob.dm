// QUALITY COPYPASTA
/turf/unsimulated/wall/supermatter
	name = "Bluespace"
	desc = "THE END IS right now actually."

	icon = 'icons/turf/space.dmi'
	icon_state = "bluespace"

	plane = PLANE_LIGHTING_ABOVE
	resistance_flags = BOMB_PROOF

/turf/unsimulated/wall/supermatter/conversion_cascade_act(list/already_marked_turfs)
	// Do pretty fadeout animation for the new turf
	. = ..()
	for(var/turf/valid_turf in .)
		new /obj/effect/overlay/bluespacify(valid_turf)
	// Consume everything in our turf
	for(var/atom/movable/A in turf_contents_of_type(src, /atom/movable))
		if(isliving(A))
			spent(A)
			continue
		if(istype(A,/mob)) // Observers, AI cameras.
			continue
		spent(A)

/turf/unsimulated/wall/supermatter/attack_generic(mob/user as mob)
	return attack_hand(user)

CAPABILITIES(/turf/unsimulated/wall/supermatter)
	op("supermatter_wall_robot", remote(), when(req_actor_kind(/mob/living/silicon/robot)), priority(OP_PRIORITY_DEFAULT - 1), label("Touch"), then(PROC_REF(supermatter_wall_robot)))
	op("supermatter_wall_silicon_examine", remote(), priority(OP_PRIORITY_DEFAULT - 2), label("Examine"), then(PROC_REF(supermatter_wall_examine)))
	op("supermatter_wall_ghost_examine", observer(), label("Examine"), then(PROC_REF(supermatter_wall_examine)))
	// The item op is declared first: a held item answers before the bare-hand touch (which would dust the player), and a click that is not on harm intent is refused.
	op("supermatter_wall_item", item(/obj/item), needs(req(TYPE_PROC_REF(/atom, harm_click_only), because = MSG(harm_click_only))), priority(OP_PRIORITY_DEFAULT - 1), label("Touch with"), then(PROC_REF(supermatter_wall_item)))
	op("supermatter_wall_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Touch"), then(PROC_REF(supermatter_wall_hand)))

/// Old attack_robot: a cyborg touches it only from next to it.
/turf/unsimulated/wall/supermatter/proc/supermatter_wall_robot(datum/act/op/A)
	var/mob/user = A.actor
	if(Adjacent(user))
		attack_hand(user)
	else
		to_chat(user, span_warning("What the fuck are you doing?"))
	return OP_OK

/// Old attack_ai and attack_ghost (/vg/: don't let ghosts fuck with this): just examine it.
/turf/unsimulated/wall/supermatter/proc/supermatter_wall_examine(datum/act/op/A)
	var/mob/user = A.actor
	user.examinate(src)
	return OP_OK

/// Old attack_hand.
/turf/unsimulated/wall/supermatter/proc/supermatter_wall_hand(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, MSG_SELF(span_danger("You reach out and touch %T%. Everything immediately goes quiet. Your last thought is \"That was not a wise decision.\"")), \
		MSG_OTHERS(span_warning("%U% reaches out and touches %T%... And then blinks out of existance.")), \
		MSG_BLIND(span_warning("You hear an unearthly noise.")))

	play_sfx(src, SFX_EFFECTS_SUPERMATTER)

	Consume(user)
	return OP_OK

/// Old attackby: a harm-intent touch with an item turns the item to dust; any other click with an item leaves it alone.
/turf/unsimulated/wall/supermatter/proc/supermatter_wall_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	act_message(user, src, MSG_SELF(span_danger("You touch %I% to %T% when everything suddenly goes silent.\"") + "\n" + span_notice("%I% flashes into dust as you flinch away from %T%.")), \
		MSG_OTHERS(span_warning("%U% touches \a [W] to %T% as a silence fills the room...")), \
		MSG_BLIND(span_warning("Everything suddenly goes silent.")), \
		item = W)

	play_sfx(src, SFX_EFFECTS_SUPERMATTER)

	user.drop_from_inventory(W)
	Consume(W)
	return OP_OK


/turf/unsimulated/wall/supermatter/Bumped(atom/AM as mob|obj)
	if(isliving(AM))
		var/mob/living/M = AM
		AM.visible_message(span_warning("\The [AM] slams into \the [src] inducing a resonance... [M.p_Their()] body starts to glow and catch flame before flashing into ash."),\
		span_danger("You slam into \the [src] as your ears are filled with unearthly ringing. Your last thought is \"Oh, fuck.\""),\
		span_warning("You hear an unearthly noise as a wave of heat washes over you."))
	else
		AM.visible_message(span_warning("\The [AM] smacks into \the [src] and rapidly flashes to ash."),\
		span_warning("You hear a loud crack as you are washed with a wave of heat."))

	play_sfx(src, SFX_EFFECTS_SUPERMATTER)

	Consume(AM)


/turf/unsimulated/wall/supermatter/proc/Consume(mob/living/user)
	if(istype(user,/mob/observer))
		return

	consumed(user, src)


