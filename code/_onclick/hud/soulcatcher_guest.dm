/atom/movable/screen/nifsc
	icon = 'icons/mob/screen_nifsc.dmi'

/// The tooltip the hovering mob sees (tooltip(), code/engine/lifeforms/input.dm).
/atom/movable/screen/nifsc/proc/input_tooltip(mob/user)
	return list(name, desc)

/// Plays its hover animation when the mouse enters (hover(), code/engine/lifeforms/input.dm).
/atom/movable/screen/nifsc/proc/input_hovered(datum/act/input/A)
	if(A.entered)
		flick(icon_state + "_anim", src)

CAPABILITIES(/atom/movable/screen/nifsc)
	click_on(PROC_REF(click_input))
	tooltip(PROC_REF(input_tooltip))
	hover(PROC_REF(input_hovered))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/nifsc/proc/click_input(datum/act/input/A)
	return click_with_actor(A.actor, A.native["location"], A.native["control"], A.params)

/atom/movable/screen/nifsc/click_with_actor(mob/user, location, control, params)
	closeToolTip(user, src)

/atom/movable/screen/nifsc/reenter
	name = "Re-enter NIF"
	desc = "Return into the NIF"
	icon_state = "reenter"

/atom/movable/screen/nifsc/reenter/click_with_actor(mob/user, location, control, params)
	..()
	var/mob/living/carbon/brain/caught_soul/CS = user
	if(!istype(CS))
		return
	CS.reenter_soulcatcher()

/atom/movable/screen/nifsc/arproj
	name = "AR project"
	desc = "Project your form into Augmented Reality for those around your predator with the appearance of your loaded character."
	icon_state = "arproj"

/atom/movable/screen/nifsc/arproj/click_with_actor(mob/user, location, control, params)
	..()
	var/mob/living/carbon/brain/caught_soul/CS = user
	if(!istype(CS))
		return
	CS.ar_project()

/atom/movable/screen/nifsc/jumptoowner
	name = "Jump back to host"
	desc = "Jumb back to the Soulcather host"
	icon_state = "jump"

/atom/movable/screen/nifsc/jumptoowner/click_with_actor(mob/user, location, control, params)
	..()
	var/mob/living/carbon/brain/caught_soul/CS = user
	if(!istype(CS))
		return
	CS.jump_to_owner()

/atom/movable/screen/nifsc/nme
	name = "Emote into Soulcatcher"
	desc = "Emote into the NIF's Soulcatcher (circumventing AR emoting)"
	icon_state = "nme"

/atom/movable/screen/nifsc/nme/click_with_actor(mob/user, location, control, params)
	..()
	var/mob/living/carbon/brain/caught_soul/CS = user
	if(!istype(CS))
		return
	CS.nme_brain()

/atom/movable/screen/nifsc/nsay
	name = "Speak into Soulcatcher"
	desc = "Speak into the NIF's Soulcatcher (circumventing AR speaking)"
	icon_state = "nsay"

/atom/movable/screen/nifsc/nsay/click_with_actor(mob/user, location, control, params)
	..()
	var/mob/living/carbon/brain/caught_soul/CS = user
	if(!istype(CS))
		return
	CS.nsay_brain()


/mob/living/carbon/brain/caught_soul/create_mob_hud(datum/hud/HUD, apply_to_client = TRUE)
	..()

	var/atom/movable/screen/using

	using = new /atom/movable/screen/nifsc/reenter()
	using.screen_loc = ui_nifsc_reenter
	rel_set(using, nameof(using.hud), HUD)
	rel_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/nifsc/arproj()
	using.screen_loc = ui_nifsc_arproj
	rel_set(using, nameof(using.hud), HUD)
	rel_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/nifsc/jumptoowner()
	using.screen_loc = ui_nifsc_jumptoowner
	rel_set(using, nameof(using.hud), HUD)
	rel_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/nifsc/nme()
	using.screen_loc = ui_nifsc_nme
	rel_set(using, nameof(using.hud), HUD)
	rel_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/nifsc/nsay()
	using.screen_loc = ui_nifsc_nsay
	rel_set(using, nameof(using.hud), HUD)
	rel_add(HUD, nameof(HUD.adding), using)
	if(client && apply_to_client)
		client.screen = list()
		if(length(HUD.adding))
			client.screen += HUD.adding
		client.screen += client.void
