/mob/living/simple_mob/animal/passive/lizard/event
	desc = "This one looks like it is growing huge!"
	var/amount_grown = 0
	faction = "lizard"

/mob/living/simple_mob/animal/passive/lizard/event/life_type_post_due()
	return TRUE

/mob/living/simple_mob/animal/passive/lizard/event/life_type_post(datum/seq_frame/life/F)
	..()
	if(src.amount_grown >= 0)
		src.amount_grown += rand(0,4)
	if(src.amount_grown >= 100 && src.icon_state != src.icon_dead)
		src.man()
		return

/mob/living/simple_mob/animal/passive/lizard/event/proc/man()
	if(loc?.release_refusal(src))
		return
	var/mob/bigger = new /mob/living/simple_mob/vore/aggressive/lizardman(get_turf(src))

	if(istype(loc,/obj/belly))
		var/obj/belly/B = loc
		B.owner.visible_message(span_boldwarning("Something grows inside [B.owner]'s [lowertext(B.name)]!"))
		to_chat(B.owner, span_warning("\The [src] suddenly evolves inside your [lowertext(B.name)]!"))
		B.release_specific_contents(src, TRUE)
		B.nom_atom(bigger, null)
		consume(src)
	else
		act_message(src, null, null, MSG_OTHERS(span_warning("%U% suddenly evolves!")))
		consume(src)
