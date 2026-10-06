/obj/aiming_overlay
	name = ""
	desc = "Stick 'em up!"
	icon = 'icons/effects/Targeted.dmi'
	icon_state = "locking"
	anchored = TRUE
	density = FALSE
	opacity = 0
	plane = ABOVE_PLANE
	simulated = FALSE
	mouse_opacity = 0

	var/mob/living/aiming_at   // Who are we currently targeting, if anyone?
	var/tmp/mob/owner	// Who do we belong to?
	var/locked =    0          // Have we locked on?
	EXPIRY_DECLARE(lock_time) // When -will- we lock on?
	var/active =    0          // Is our owner intending to take hostages?
	var/target_permissions = 0 // Permission bitflags.

/// What are we targeting with? Set while aiming; the aim is tracked every slow tick while it is.
OM_FIELD_VIEW(/obj/aiming_overlay, obj/item, aiming_with, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/aiming_overlay, PERIODIC_SLOW, "aiming_with")

/obj/aiming_overlay/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(owner), loc)
	if(!istype(owner(), /mob))
		return INITIALIZE_HINT_QDEL
	moveToNullspace()

/obj/aiming_overlay/proc/toggle_permission(perm)

	if(target_permissions & perm)
		target_permissions &= ~perm
	else
		target_permissions |= perm

	// Update HUD icons.
	if(owner().gun_move_icon)
		if(!(target_permissions & TARGET_CAN_MOVE))
			owner().gun_move_icon.icon_state = "no_walk0"
			owner().gun_move_icon.name = "Allow Movement"
		else
			owner().gun_move_icon.icon_state = "no_walk1"
			owner().gun_move_icon.name = "Disallow Movement"

	if(owner().item_use_icon)
		if(!(target_permissions & TARGET_CAN_CLICK))
			owner().item_use_icon.icon_state = "no_item0"
			owner().item_use_icon.name = "Allow Item Use"
		else
			owner().item_use_icon.icon_state = "no_item1"
			owner().item_use_icon.name = "Disallow Item Use"

	if(owner().radio_use_icon)
		if(!(target_permissions & TARGET_CAN_RADIO))
			owner().radio_use_icon.icon_state = "no_radio0"
			owner().radio_use_icon.name = "Allow Radio Use"
		else
			owner().radio_use_icon.icon_state = "no_radio1"
			owner().radio_use_icon.name = "Disallow Radio Use"

	var/message = "no longer permitted to "
	var/use_span = "warning"
	if(target_permissions & perm)
		message = "now permitted to "
		use_span = "notice"

	switch(perm)
		if(TARGET_CAN_MOVE)
			message += "move"
		if(TARGET_CAN_CLICK)
			message += "use items"
		if(TARGET_CAN_RADIO)
			message += "use a radio"
		else
			return

	to_chat(owner(), "<span class='[use_span]'>[aiming_at ? "The [aiming_at] is" : "Your targets are"] [message].</span>")
	if(aiming_at)
		to_chat(aiming_at, "<span class='[use_span]'>You are [message].</span>")

/obj/aiming_overlay/periodic_step()
	if(!owner())
		consume(src)
		return
	..()
	update_aiming()

/obj/aiming_overlay/relations()
	. = ..()
	. += rel_one(nameof(aiming_at), back = nameof(/mob/living::aimed))
/mob/living/relations()
	. = ..()
	. += rel_many(nameof(aimed), back = nameof(/obj/aiming_overlay::aiming_at))

/obj/aiming_overlay/proc/update_aiming_deferred()
	after(src, 0, PROC_REF(update_aiming))

/obj/aiming_overlay/proc/update_aiming()

	if(!owner())
		consume(src)
		return

	if(QDELETED(aiming_at))
		cancel_aiming()
		return

	if(!locked && EXPIRY_EXPIRED(src, lock_time, CLOCK_WORLD))
		locked = 1
		to_chat(owner(), span_notice("You are locked onto your target."))
		to_chat(aiming_at, span_danger("The gun is trained on you!"))
		changed(src)

	var/cancel_aim = 1

	var/mob/living/carbon/human/H = owner()
	if(!(aiming_with() in owner()) || (istype(H) && !H.item_is_in_hands(aiming_with())))
		to_chat(owner(), span_warning("You must keep hold of your weapon!"))
	else if(owner().has_status(STAT_BLINDED))
		to_chat(owner(), span_warning("You are blind and cannot see your target!"))
	else if(!aiming_at || !istype(aiming_at.loc, /turf))
		to_chat(owner(), span_warning("You have lost sight of your target!"))
	else if(owner().incapacitated() || owner().lying || owner().restrained())
		to_chat(owner(), span_warning("You must be conscious and standing to keep track of your target!"))
	else if(aiming_at.alpha <= 50 || (aiming_at.invisibility > owner().see_invisible))
		to_chat(owner(), span_warning("Your target has become invisible!"))
	else if(get_dist(get_turf(owner()), get_turf(aiming_at)) > 7) // !(owner in viewers(aiming_at, 7))
		to_chat(owner(), span_warning("Your target is too far away to track!"))
	else
		cancel_aim = 0

	forceMove(get_turf(aiming_at))

	if(cancel_aim)
		cancel_aiming()
		return

	if(!owner().incapacitated() && owner().client)
		owner().set_dir(get_dir(get_turf(owner()), get_turf(src)))

/obj/aiming_overlay/proc/aim_at(mob/target, obj/thing)

	if(!owner())
		return

	if(owner().incapacitated())
		to_chat(owner(), span_warning("You cannot aim a gun in your current state."))
		return
	if(owner().lying)
		to_chat(owner(), span_warning("You cannot aim a gun while prone."))
		return
	if(owner().restrained())
		to_chat(owner(), span_warning("You cannot aim a gun while handcuffed."))
		return
	if(target.alpha <= 50)
		to_chat(owner(), span_warning("You cannot aim at something you cannot see."))
		return

	if(aiming_at)
		if(aiming_at == target)
			return
		rel_remove(aiming_at, nameof(aiming_at.aimed), src)
		owner().visible_message(span_danger("\The [owner()] turns \the [thing] on \the [target]!"))
	else
		owner().visible_message(span_danger("\The [owner()] aims \the [thing] at \the [target]!"))
	log_and_message_admins("aimed \a [thing] at [key_name(target)].")

	if(owner().client)
		owner().client.add_gun_icons()
	to_chat(target, span_danger("You now have a gun pointed at you. No sudden moves!"))
	to_chat(target, span_critical("If you fail to comply with your assailant, you accept the consequences of your actions."))
	rel_set(src, nameof(aiming_with), thing)
	rel_set(src, nameof(aiming_at), target)
	if(istype(aiming_with(), /obj/item/gun))
		play_sfx(owner(), SFX_WEAPONS_TARGETON)
	forceMove(get_turf(target))

	rel_add(aiming_at, nameof(aiming_at.aimed), src)
	toggle_active(1)
	locked = 0
	changed(src)
	EXPIRY_SET(src, lock_time, 25, CLOCK_WORLD)

/// The look (the draw sweep: from its template).
/obj/aiming_overlay/draw(datum/look/look)
	..()
	look.state("[locked ? "locked" : "locking"]")

/obj/aiming_overlay/proc/toggle_active(force_state = null)
	if(!isnull(force_state))
		if(active == force_state)
			return
		active = force_state
	else
		active = !active

	if(!active)
		cancel_aiming()

	if(owner().client)
		if(active)
			to_chat(owner(), span_notice("You will now aim rather than fire."))
			owner().client.add_gun_icons()
		else
			to_chat(owner(), span_notice("You will no longer aim rather than fire."))
			owner().client.remove_gun_icons()
		owner().gun_setting_icon?.icon_state = "gun[active]"

/obj/aiming_overlay/proc/cancel_aiming(no_message = 0)
	if(!aiming_with() || !aiming_at)
		return
	if(istype(aiming_with(), /obj/item/gun))
		play_sfx(owner(), SFX_WEAPONS_TARGETOFF)
	if(!no_message)
		owner().visible_message(span_infoplain(span_bold("\The [owner()]") + " lowers \the [aiming_with()]."))

	rel_clear(src, nameof(aiming_with))
	rel_remove(aiming_at, nameof(aiming_at.aimed), src)
	rel_clear(src, nameof(aiming_at))
	moveToNullspace()

/// What are we targeting with? (a relation view: null once it is deleted).
/obj/aiming_overlay/proc/aiming_with() as /obj/item
	return aiming_with

/// Who do we belong to? (a relation view: null once it is deleted).
/obj/aiming_overlay/proc/owner() as /mob
	return owner
