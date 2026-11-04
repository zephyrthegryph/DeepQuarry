/datum/reagent/nutriment/durian
	name = REAGENT_DURIANPASTE
	id = REAGENT_ID_DURIANPASTE
	description = "A strangely sweet and savory paste."
	taste_description = "sweet and savory"
	color = "#757631"

	glass_name = "durian paste"
	glass_desc = "Durian paste. It smells horrific."

/datum/reagent/nutriment/durian/touch_mob(mob/M, amount)
	..()
	if(iscarbon(M) && !HAS_SYNTHETIC_BIOLOGY(M))
		var/message = pick("Oh god, it smells disgusting here.", "What is that stench?", "That's an awful odor.")
		to_chat(M, span_alien("[message]"))
		if(prob(CLAMP(amount, 5, 90)))
			var/mob/living/L = M
			L.vomit()
	return ..()

/datum/reagent/nutriment/durian/touch_turf(turf/T, amount)
	..()
	if(istype(T))
		var/obj/effect/decal/cleanable/chemcoating/C = new /obj/effect/decal/cleanable/chemcoating(T)
		C.reagents.add_reagent(id, amount)
	return ..()
