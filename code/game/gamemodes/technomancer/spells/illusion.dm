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
	var/atom/movable/copied
	var/mob/living/simple_mob/illusion/illusion = null

CAPABILITIES(/obj/item/spell/illusion)
	owns_one(nameof(illusion), /mob/living/simple_mob/illusion)

/obj/item/spell/illusion/on_ranged_cast(atom/hit_atom, mob/user)
	if(istype(hit_atom, /atom/movable))
		var/atom/movable/AM = hit_atom
		if(pay_energy(100))
			rel_set(src, nameof(copied), AM)
			to_chat(user, span_notice("You've copied \the [AM]'s appearance."))
			user << 'sound/weapons/flash.ogg'
			return 1
	else if(istype(hit_atom, /turf))
		var/turf/T = hit_atom
		if(!illusion)
			if(!copied())
				rel_set(src, nameof(copied), user)
			if(pay_energy(500))
				rel_set(src, nameof(illusion), new /mob/living/simple_mob/illusion(T))
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
		open_request(src, /datum/prompt/choice, PROC_REF(illusion_action_chosen), answerer = user, title = "Illusion", question = "Would you like to have \the [illusion] speak, or do an emote?", choices = list("Speak","Emote","Cancel"), buttons = TRUE, timeout = 0)

/obj/item/spell/illusion/proc/illusion_action_chosen(datum/act/request/A)
	if(!A.answer)
		return
	switch(A.answer.value)
		if("Speak")
			open_request(src, /datum/prompt/text, PROC_REF(illusion_speak), answerer = A.request.answerer, title = "Illusion Speak", question = "What do you want \the [illusion] to say?", encode = FALSE, timeout = 0)
		if("Emote")
			open_request(src, /datum/prompt/text, PROC_REF(illusion_emote), answerer = A.request.answerer, title = "Illusion Emote", question = "What do you want \the [illusion] to do?", encode = FALSE, timeout = 0)

/obj/item/spell/illusion/proc/illusion_speak(datum/act/request/A)
	if(!A.answer)
		return
	//Sanitize occurs inside say() already.
	if(A.answer.value && illusion)
		illusion.say(A.answer.value)

/obj/item/spell/illusion/proc/illusion_emote(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value && illusion)
		illusion.emote(A.answer.value)


// Makes a tiny overlay of the thing the player has copied, so they can easily tell what they currently have.
/obj/item/spell/illusion/draw(datum/look/look)
	..()
	if(copied())
		var/matrix/M = matrix()
		M.Scale(0.5, 0.5)
		look.overlay(look_overlay_image(of = copied(), transform = M))

/// Copied (a relation view).
/obj/item/spell/illusion/proc/copied() as /atom/movable
	return copied
