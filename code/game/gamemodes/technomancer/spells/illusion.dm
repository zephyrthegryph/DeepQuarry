/datum/technomancer/spell/illusion
	name = "Illusion"
	desc = "Allows you to create and control a holographic illusion, that can take the form of most object or entities."
	enhancement_desc = "Illusions will be made of hard light, allowing the interception of attacks, appearing more realistic."
	cost = 25
	obj_path = /obj/item/spell/illusion
	ability_icon_state = "tech_illusion"
	category = UTILITY_SPELLS

/obj/item/spell/illusion
	name = "illusion"
	icon_state = "illusion"
	desc = "Now you can toy with the minds of the whole colony."
	aspect = ASPECT_LIGHT
	cast_methods = CAST_RANGED | CAST_USE
	var/copied_handle
	var/mob/living/simple_mob/illusion/illusion = null

/obj/item/spell/illusion/on_ranged_cast(atom/hit_atom, mob/user)
	if(istype(hit_atom, /atom/movable))
		var/atom/movable/AM = hit_atom
		if(pay_energy(100))
			copied_handle = om_handle(AM)
			update_icon()
			to_chat(user, span_notice("You've copied \the [AM]'s appearance."))
			user << 'sound/weapons/flash.ogg'
			return 1
	else if(istype(hit_atom, /turf))
		var/turf/T = hit_atom
		if(!illusion)
			if(!copied())
				copied_handle = om_handle(user)
			if(pay_energy(500))
				illusion = new(T)
				illusion.copy_appearance(copied())
				illusion.copy_overlays(copied(), TRUE)
				to_chat(user, span_notice("An illusion of \the [copied()] is made on \the [T]."))
				user << 'sound/effects/pop.ogg'
				return 1
		else
			if(pay_energy(100))
				illusion.ai_brain?.give_destination(T)
/obj/item/spell/illusion/on_use_cast(mob/user)
	if(illusion)
		om_ask(user, /datum/om/prompt/choice, PROC_REF(illusion_action_chosen), title = "Illusion", message = "Would you like to have \the [illusion] speak, or do an emote?", choices = list("Speak","Emote","Cancel"), buttons = TRUE)

/obj/item/spell/illusion/proc/illusion_action_chosen(datum/om/prompt/choice/ask)
	switch(ask.choice)
		if("Speak")
			om_ask(ask.answerer, /datum/om/prompt/text, PROC_REF(illusion_speak), title = "Illusion Speak", message = "What do you want \the [illusion] to say?", encode = FALSE)
		if("Emote")
			om_ask(ask.answerer, /datum/om/prompt/text, PROC_REF(illusion_emote), title = "Illusion Emote", message = "What do you want \the [illusion] to do?", encode = FALSE)

/obj/item/spell/illusion/proc/illusion_speak(datum/om/prompt/text/ask)
	//Sanitize occurs inside say() already.
	if(ask.text && illusion)
		illusion.say(ask.text)

/obj/item/spell/illusion/proc/illusion_emote(datum/om/prompt/text/ask)
	if(ask.text && illusion)
		illusion.emote(ask.text)

DECLARE_REF(/obj/item/spell/illusion, "illusion", OWNED, null)

// Makes a tiny overlay of the thing the player has copied, so they can easily tell what they currently have.
DECLARE_APPEARANCE_PROC(/obj/item/spell/illusion, PROC_REF(appearance_overlays), list())
/obj/item/spell/illusion/appearance_overlays()
	. = list()
	if(copied())
		var/image/temp_image = image(copied())
		var/matrix/M = matrix()
		M.Scale(0.5, 0.5)
		temp_image.transform = M
		. += temp_image

/// LC-refs: copied -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/spell/illusion/proc/copied() as /atom/movable
	return om_resolve(copied_handle)
