/atom/movable/screen/nifsc
	icon = 'icons/mob/screen_nifsc.dmi'

/atom/movable/screen/nifsc/MouseEntered(location,control,params)
	flick(icon_state + "_anim", src)
	openToolTip(usr, src, params, title = name, content = desc)

/atom/movable/screen/nifsc/MouseExited()
	closeToolTip(usr, src)

/atom/movable/screen/nifsc/Click(location, control, params)
	return click_with_actor(usr, location, control, params) // ALLOW(sys_usr_outside_verb): native soulcatcher HUD clicks capture the initiating actor without chaining the atom input router

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
	own_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/nifsc/arproj()
	using.screen_loc = ui_nifsc_arproj
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/nifsc/jumptoowner()
	using.screen_loc = ui_nifsc_jumptoowner
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/nifsc/nme()
	using.screen_loc = ui_nifsc_nme
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)

	using = new /atom/movable/screen/nifsc/nsay()
	using.screen_loc = ui_nifsc_nsay
	rel_set(using, nameof(using.hud), HUD)
	own_add(HUD, nameof(HUD.adding), using)
	if(client && apply_to_client)
		client.screen = list()
		if(length(HUD.adding))
			client.screen += HUD.adding
		client.screen += client.void
