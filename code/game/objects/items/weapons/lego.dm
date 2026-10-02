/obj/item/lego
	name = "Lego of Doom"
	throw_speed = 5
	throw_range = 4
	gender = PLURAL
	icon = 'icons/obj/items_ch.dmi'
	icon_state = "lego"
	desc = "An absolutely horrifying mechanical trap, banned in most sectors across the universe. Placing one is considered a major war crime."
	randpixel = 0
	center_of_mass_x = 0
	center_of_mass_y = 0
	throwforce = 0
	w_class = ITEMSIZE_SMALL

/obj/item/lego/Crossed(atom/movable/AM as mob|obj)
	if(AM.is_incorporeal())
		return
	if(isliving(AM))
		var/mob/living/L = AM
		if(L.m_intent == I_RUN)
			act_message(L, src, MSG_SELF(span_danger("You step on %T%, you poor bastard!")), \
				MSG_OTHERS(span_danger("%U% steps on %T%.")), \
				MSG_BLIND(span_hear(span_bold("You hear the sound of immeasurable suffering!"))))
			L.injure(INJURY_PAIN, 100, source = src)
			play_sfx(src, SFX_MISC_LEGODEATH)
			consume(src, L)
	..()

/obj/item/lego/gib
	name = "Lego of Doom"
	throw_speed = 5
	throw_range = 4
	gender = PLURAL
	icon = 'icons/obj/items_ch.dmi'
	icon_state = "lego"
	desc = "An absolutely horrifying mechanical trap, banned in most sectors across the universe. Placing one is considered a major war crime."
	randpixel = 0
	center_of_mass_x = 0
	center_of_mass_y = 0
	throwforce = 0
	w_class = ITEMSIZE_SMALL

/obj/item/lego/gib/Crossed(atom/movable/AM as mob|obj)
	if(AM.is_incorporeal())
		return
	if(isliving(AM))
		var/mob/living/L = AM
		if(L.m_intent == I_RUN)
			act_message(L, src, MSG_SELF(span_danger("You step on %T%, you poor bastard!")), \
				MSG_OTHERS(span_danger("%U% steps on %T%.")), \
				MSG_BLIND(span_hear(span_bold("You hear the sound of immeasurable suffering!"))))
			L.gib()
			play_sfx(src, SFX_MISC_LEGODEATH)
			qdel(src)
	..()
