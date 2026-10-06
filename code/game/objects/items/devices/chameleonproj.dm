/obj/item/chameleon
	name = "chameleon projector"
	icon = 'icons/obj/device.dmi'
	icon_state = "shield0"
	slot_flags = SLOT_BELT
	item_state = "electronic"
	throwforce = 5.0
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_SMALL
	var/can_use = 1
	var/obj/effect/dummy/chameleon/active_dummy = null
	var/saved_item = /obj/item/trash/cigbutt
	var/saved_icon = 'icons/inventory/face/item.dmi'
	var/saved_icon_state = "cigbutt"
	var/saved_overlays

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

CAPABILITIES(/obj/item/chameleon)
	owns_one(nameof(active_dummy), /obj/effect/dummy/chameleon)
	op("disguise", in_hand(), label("Toggle chameleon disguise"), then(PROC_REF(projector_activation_requested)))

/obj/item/chameleon/dropped(mob/user, equipping, slot)
	if(equipping)
		return ..()
	disrupt()
	..()

/obj/item/chameleon/equipped()
	..()
	disrupt()
	..()

/obj/item/chameleon/proc/projector_activation_requested(datum/act/op/A)
	toggle(A.actor)
	return OP_OK

/obj/item/chameleon/afterattack(atom/target, mob/user, proximity)
	if(!proximity) return
	if(!active_dummy)
		if(istype(target,/obj/item) && !istype(target, /obj/item/disk/nuclear))
			play_sfx(src, SFX_WEAPONS_FLASH, extrarange = -6)
			to_chat(user, span_notice("Scanned [target]."))
			saved_item = target.type
			saved_icon = target.icon
			saved_icon_state = target.icon_state
			saved_overlays = target.overlays

/obj/item/chameleon/proc/toggle(mob/user)
	if(!can_use || !saved_item) return
	if(active_dummy)
		eject_all()
		play_sfx(src, SFX_EFFECTS_POP, 2, vary = TRUE, extrarange = -6)
		own_clear(src, nameof(active_dummy), OWN_DELETE)
		to_chat(user, span_notice("You deactivate the [src]."))
		var/obj/effect/overlay/T = new /obj/effect/overlay(get_turf(src))
		T.icon = 'icons/effects/effects.dmi'
		flick("emppulse",T)
		T.expire(0.8 SECONDS)
	else
		play_sfx(src, SFX_EFFECTS_POP, 2, vary = TRUE, extrarange = -6)
		if(istype(user.loc, /obj/item/holder)) // This doesn't go well...
			return
		var/obj/O = new saved_item(src)
		if(!O) return
		var/obj/effect/dummy/chameleon/C = new /obj/effect/dummy/chameleon(user.loc)
		C.activate(O, user, saved_icon, saved_icon_state, saved_overlays, src)
		spent(O, user)
		to_chat(user, span_notice("You activate the [src]."))
		var/obj/effect/overlay/T = new/obj/effect/overlay(get_turf(src))
		T.icon = 'icons/effects/effects.dmi'
		flick("emppulse",T)
		T.expire(0.8 SECONDS)

/obj/item/chameleon/proc/disrupt(delete_dummy = 1)
	if(active_dummy)
		fx_sparks(src, 5, FALSE)
		eject_all()
		if(delete_dummy)
			own_clear(src, nameof(active_dummy), OWN_DELETE)
		else
			own_take(src, nameof(active_dummy)) // the dummy is already being destroyed
		can_use = 0
		after(src, 5 SECONDS, PROC_REF(allow_use))

/obj/item/chameleon/proc/allow_use()
	can_use = 1

/obj/item/chameleon/proc/eject_all()
	for(var/atom/movable/A in active_dummy)
		A.forceMove(get_turf(active_dummy))

/obj/effect/dummy/chameleon
	name = ""
	desc = ""
	density = FALSE
	anchored = TRUE
	flags = REMOTEVIEW_ON_ENTER
	var/can_move = 1
	var/obj/item/chameleon/master = null

/obj/effect/dummy/chameleon/proc/activate(obj/O, mob/M, new_icon, new_iconstate, new_overlays, obj/item/chameleon/C)
	name = O.name
	desc = O.desc
	icon = new_icon
	icon_state = new_iconstate
	overlays = new_overlays
	set_dir(O.dir)
	M.forceMove(src)
	rel_set(src, nameof(master), C)
	rel_set(master, nameof(master.active_dummy), src)

/obj/effect/dummy/chameleon/proc/interaction_disrupt(datum/act/op/A)
	for(var/mob/M in contents_of(src))
		to_chat(M, span_warning("Your chameleon-projector deactivates."))
	master.disrupt()
	return TRUE

CAPABILITIES(/obj/effect/dummy/chameleon)
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(chameleon_disrupted))))
	extend(/datum/act/hit/projectile, instead(then(PROC_REF(chameleon_disrupted))))
	op("disrupt", inputs(item(/obj/item), hand()), label("Disrupt"), then(PROC_REF(interaction_disrupt)))

/// A blast or a round drops the disguise, and the hit stops there.
/obj/effect/dummy/chameleon/proc/chameleon_disrupted(datum/act/A)
	for(var/mob/M in contents_of(src))
		to_chat(M, span_warning("Your chameleon-projector deactivates."))
	master.disrupt()
	return OP_OK

/obj/effect/dummy/chameleon/proc/allow_move()
	can_move = 1

/obj/effect/dummy/chameleon/relaymove(mob/user, direction)
	if(istype(loc, /turf/space)) return //No magical space movement!

	if(can_move)
		can_move = 0
		switch(user.body_temperature())
			if(300 to INFINITY)
				after(src, 1 SECOND, PROC_REF(allow_move))
			if(295 to 300)
				after(src, 1.3 SECONDS, PROC_REF(allow_move))
			if(280 to 295)
				after(src, 1.6 SECONDS, PROC_REF(allow_move))
			if(260 to 280)
				after(src, 2 SECONDS, PROC_REF(allow_move))
			else
				after(src, 2.5 SECONDS, PROC_REF(allow_move))
		step(src, direction)
	return

// the projector's disguise is disrupted.
/obj/effect/dummy/chameleon/lifecycle_prerelease()
	..()
	master?.disrupt(0)

// The projector owns its dummy (implicit OWN); the dummy names the projector (one-sided REL).
