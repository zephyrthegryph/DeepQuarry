////////////////////////////////////////////////////////////////////////////////
/// FOOD END
////////////////////////////////////////////////////////////////////////////////

/mob/living

///mob/living/simple_mob/adultslime	//The literal only thing in the game that uses this is commented out, so I comment out this too

/mob/living/carbon/alien/diona

/mob/living/simple_mob/slime

/mob/living/simple_mob
	var/kitchen_tag = "animal" //Used for cooking with animals

/// A mindless eater who finished the food asks for more.
/proc/food_finished_emote(mob/user, finished)
	if(finished && !user.client)
		user.automatic_custom_emote(VISIBLE_MESSAGE,"[pick("burps", "cries for more", "burps twice", "looks at the area where the food was")]", check_stat = TRUE)
