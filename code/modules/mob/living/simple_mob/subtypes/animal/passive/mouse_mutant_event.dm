/mob/living/simple_mob/animal/passive/mouse/event
	desc = "This one looks like it is growing huge!"
	var/amount_grown = 0

/datum/life_system/type_post/simple_mob/animal/passive/mouse/event
	mob_type = /mob/living/simple_mob/animal/passive/mouse/event

/datum/life_system/type_post/simple_mob/animal/passive/mouse/event/tick(mob/living/simple_mob/animal/passive/mouse/event/self, datum/life_context/ctx)
	..()
	if(self.amount_grown >= 0)
		self.amount_grown += rand(0,4)
	if(self.amount_grown >= 100 && self.icon_state != self.icon_dead)
		self.rat()
		return

/mob/living/simple_mob/animal/passive/mouse/event/proc/rat()
	var/mob/bigger = new /mob/living/simple_mob/vore/aggressive/rat/event(get_turf(src))

	if(istype(loc,/obj/belly))
		var/obj/belly/B = loc
		B.owner.visible_message(span_boldwarning("Something grows inside [B.owner]'s [lowertext(B.name)]!"))
		to_chat(B.owner, span_warning("\The [src] suddenly evolves inside your [lowertext(B.name)]!"))
		B.release_specific_contents(src, TRUE)
		B.nom_atom(bigger, null)
		qdel(src)
	else
		visible_message(span_warning("\The [src] suddenly evolves!"))
		qdel(src)
