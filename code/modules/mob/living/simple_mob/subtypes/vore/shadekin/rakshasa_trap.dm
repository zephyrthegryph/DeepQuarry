/obj/structure/gootrap
	name = "goo"
	throw_speed = 2
	throw_range = 1
	gender = PLURAL
	icon = 'icons/effects/blood.dmi'
	var/base_icon = 'icons/effects/blood.dmi'
	icon_state = "mfloor1"
	var/basecolor="#030303"
	desc = ""
	w_class = ITEMSIZE_NORMAL
	var/deployed = 1
	anchored = 1

/obj/structure/gootrap/proc/can_use(mob/user)
	return (user.IsAdvancedToolUser() && !issilicon(user) && !user.stat && !user.restrained())

/obj/structure/gootrap/draw(datum/look/look)
	..()
	look.set_color(basecolor)


CAPABILITIES(/obj/structure/gootrap)
	op("free", hand(), label("Free the victim"), when(PROC_REF(can_free)), begins(PROC_REF(freeing_text)), wait(0.5 SECONDS), then(PROC_REF(free_victims)), says(PROC_REF(freed_text)))

/// The lines of the freeing name the one who is caught.
/obj/structure/gootrap/proc/freeing_text(datum/act/op/A)
	var/victims = english_list(buckled_mob_list())
	return msg_text(span_notice("You carefully begin to free [victims] from %T%."), span_notice("%U% begins freeing [victims] from %T%."))

/obj/structure/gootrap/proc/freed_text(datum/act/op/A)
	return msg_text(null, span_notice("The one caught has been freed from %T% by %U%."))

/obj/structure/gootrap/proc/can_free(datum/act/op/A)
	return has_buckled_mobs() && can_use(A.actor)

/obj/structure/gootrap/proc/free_victims(datum/act/op/A)
	for(var/mob/victim in src?.buckled_mob_list())
		unbuckle_mob(victim)
	set_anchored(0)

/obj/structure/gootrap/proc/attack_mob(mob/living/L)
	//trap the victim in place
	set_dir(L.dir)
	set_can_buckle(TRUE)
	buckle_mob(L)
	var/goo_sounds = list (
			'sound/rakshasa/Decay1.ogg',
			'sound/rakshasa/Decay2.ogg',
			'sound/rakshasa/Decay3.ogg'
			)
	var/sound = pick(goo_sounds)
	playsound(src, sound, 100, 1)
	L << span_danger("You hear a gooey schlorp as \the [src] ensnares your leg, trapping you in place!")
	deployed = 0
	set_can_buckle(initial(can_buckle))


/obj/structure/gootrap/Crossed(AM as mob|obj)
	if(deployed && isliving(AM))
		var/mob/living/L = AM
		if(L.m_intent == I_RUN)
			act_message(L, src, MSG_SELF(span_danger("You step on %T%!")), MSG_OTHERS(span_danger("%U% steps on %T%.")), MSG_BLIND(span_hear(span_bold("You hear a gooey schlorp as the goo ensnares your leg!"))))
			attack_mob(L)
			if(!has_buckled_mobs())
				set_anchored(0)
			deployed = 0
			message_admins(crossing_admin_message(L))
	..()

/// Format the crossing report from the mob caught by the actual trap callback.
/obj/structure/gootrap/proc/crossing_admin_message(mob/living/victim)
	return "[key_name(victim)] has stepped in the goo trap."
