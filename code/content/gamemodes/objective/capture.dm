/datum/objective/capture/proc/gen_amount_goal()
	target_amount = rand(5,10)
	set_explanation_text("Accumulate [target_amount] capture points.")
	return target_amount

/datum/objective/capture/check_completion()//Basically runs through all the mobs in the area to determine how much they are worth.
	var/captured_amount = 0
	var/area/centcom/holding/A = locate()

	for(var/mob/living/carbon/human/M in area_contents_of_type(A, /mob/living/carbon/human)) // Humans (and subtypes).
		var/worth = M.species.rarity_value
		if(M.stat==2)//Dead folks are worth less.
			worth*=0.5
			continue
		captured_amount += worth

	for(var/mob/living/carbon/alien/larva/M in area_contents_of_type(A, /mob/living/carbon/alien/larva))//Larva are important for research.
		if(M.stat==2)
			captured_amount+=0.5
			continue
		captured_amount+=1

	if(captured_amount<target_amount)
		return 0
	return 1
