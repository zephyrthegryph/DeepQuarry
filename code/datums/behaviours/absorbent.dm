/// Absorbent (was /datum/component/absorbent): cleans what the barefoot mob walks over and
/// feeds on it. A shared OM behaviour on the moved event; attached by the Absorbent trait.
/datum/om/behaviour/absorbent
	handles = list(/datum/om/event/moved)

/datum/om/behaviour/absorbent/on_moved(mob/living/carbon/human/H, datum/om/event/moved/event)
	if(!istype(H))
		return
	var/turf/T = get_turf(H)
	if(istype(T))
		if(!(H.get_equipped_item(SLOT_ID_SHOES) || (H.get_equipped_item(SLOT_ID_SUIT) && (H.get_equipped_item(SLOT_ID_SUIT).body_parts_covered & FEET))))
			//We do this first as it gives nutrition for each item on the turf.
			for(var/obj/O in turf_contents_of_type(T, /obj))
				if(O.wash(CLEAN_WASH))
					H.adjust_nutrition(rand(5, 15))

			//Secondly, we check if the turf is a sim turf. If it's dirty, we get nutrition.
			//The T.wash() below will clean it and set the dirt to 0.
			if(istype(T, /turf/simulated))
				var/turf/simulated/turf_to_clean = T
				if(turf_to_clean.dirt >= 50)
					H.adjust_nutrition(rand(10, 20))
			//Third, we clean the turf itself.
			if(T.wash(CLEAN_WASH))
				H.adjust_nutrition(rand(10, 20))

	//Lastly, we clean ourself and all the items on us.
	if(H.wash(CLEAN_WASH))
		H.adjust_nutrition(rand(5, 15))
