/atom/movable/screen/gun
	name = "gun"
	icon = 'icons/mob/screen1.dmi'
	master_ref = null
	dir = 2

CAPABILITIES(/atom/movable/screen/gun)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/gun/proc/click_input(datum/act/input/A)
	return click_with_actor(A.actor, A.native["location"], A.native["control"], A.params)

/atom/movable/screen/gun/click_with_actor(mob/user, location, control, params)
	if(!user)
		return
	return 1

/atom/movable/screen/gun/move
	name = "Allow Movement"
	icon_state = "no_walk0"
	screen_loc = ui_gun2

/atom/movable/screen/gun/move/click_with_actor(mob/actor, location, control, params)
	if(..())
		var/mob/living/user = actor
		if(istype(user))
			if(!user.aiming) rel_set(user, nameof(user.aiming), new /obj/aiming_overlay(user))
			user.aiming.toggle_permission(TARGET_CAN_MOVE)
		return 1
	return 0

/atom/movable/screen/gun/item
	name = "Allow Item Use"
	icon_state = "no_item0"
	screen_loc = ui_gun1

/atom/movable/screen/gun/item/click_with_actor(mob/actor, location, control, params)
	if(..())
		var/mob/living/user = actor
		if(istype(user))
			if(!user.aiming) rel_set(user, nameof(user.aiming), new /obj/aiming_overlay(user))
			user.aiming.toggle_permission(TARGET_CAN_CLICK)
		return 1
	return 0

/atom/movable/screen/gun/mode
	name = "Toggle Gun Mode"
	icon_state = "gun0"
	screen_loc = ui_gun_select

/atom/movable/screen/gun/mode/click_with_actor(mob/actor, location, control, params)
	if(..())
		var/mob/living/user = actor
		if(istype(user))
			if(!user.aiming) rel_set(user, nameof(user.aiming), new /obj/aiming_overlay(user))
			user.aiming.toggle_active()
		return 1
	return 0

/atom/movable/screen/gun/radio
	name = "Allow Radio Use"
	icon_state = "no_radio0"
	screen_loc = ui_gun4

/atom/movable/screen/gun/radio/click_with_actor(mob/actor, location, control, params)
	if(..())
		var/mob/living/user = actor
		if(istype(user))
			if(!user.aiming) rel_set(user, nameof(user.aiming), new /obj/aiming_overlay(user))
			user.aiming.toggle_permission(TARGET_CAN_RADIO)
		return 1
	return 0
