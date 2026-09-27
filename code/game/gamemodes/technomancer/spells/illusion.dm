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
	var/atom/movable/copied = null
	var/mob/living/simple_mob/illusion/illusion = null

/obj/item/spell/illusion/on_ranged_cast(atom/hit_atom, mob/user)
	if(istype(hit_atom, /atom/movable))
		var/atom/movable/AM = hit_atom
		if(pay_energy(100))
			copied = AM
			update_icon()
			to_chat(user, span_notice("You've copied \the [AM]'s appearance."))
			user << 'sound/weapons/flash.ogg'
			return 1
	else if(istype(hit_atom, /turf))
		var/turf/T = hit_atom
		if(!illusion)
			if(!copied)
				copied = user
			if(pay_energy(500))
				illusion = new(T)
				illusion.copy_appearance(copied)
				illusion.copy_overlays(copied, TRUE)
				to_chat(user, span_notice("An illusion of \the [copied] is made on \the [T]."))
				user << 'sound/effects/pop.ogg'
				return 1
		else
			if(pay_energy(100))
				illusion.ai_brain?.give_destination(T)
/obj/item/spell/illusion/on_use_cast(mob/user)
	if(illusion)
		om_prompt(src, user, list("message" = "Would you like to have \the [illusion] speak, or do an emote?", "title" = "Illusion", "choices" = list("Speak","Emote","Cancel")), PROC_REF(illusion_action_chosen))

/obj/item/spell/illusion/proc/illusion_action_chosen(mob/user, choice, datum/om/prompt/ask)
	switch(choice)
		if("Speak")
			om_prompt_chain(ask, list("kind" = "text", "message" = "What do you want \the [illusion] to say?", "title" = "Illusion Speak", "encode" = FALSE), PROC_REF(illusion_speak))
		if("Emote")
			om_prompt_chain(ask, list("kind" = "text", "message" = "What do you want \the [illusion] to do?", "title" = "Illusion Emote", "encode" = FALSE), PROC_REF(illusion_emote))

/obj/item/spell/illusion/proc/illusion_speak(mob/user, what_to_say, datum/om/prompt/ask)
	//Sanitize occurs inside say() already.
	if(what_to_say && illusion)
		illusion.say(what_to_say)

/obj/item/spell/illusion/proc/illusion_emote(mob/user, what_to_emote, datum/om/prompt/ask)
	if(what_to_emote && illusion)
		illusion.emote(what_to_emote)

/obj/item/spell/illusion/Destroy()
	QDEL_NULL(illusion)
	copied = null
	return ..()

// Makes a tiny overlay of the thing the player has copied, so they can easily tell what they currently have.
/obj/item/spell/illusion/update_icon()
	cut_overlays()
	if(copied)
		var/image/temp_image = image(copied)
		var/matrix/M = matrix()
		M.Scale(0.5, 0.5)
		temp_image.transform = M
//		temp_image.pixel_y = 8
		add_overlay(temp_image)
