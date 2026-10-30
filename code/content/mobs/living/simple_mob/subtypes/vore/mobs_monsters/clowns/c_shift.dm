/mob/living/simple_mob/clowns/big/c_shift
	var/shadekin_type = /datum/shadekin/phase_only //Type of the shadekin datum that holds all the shadekin vars.

/mob/living/simple_mob/clowns/big/c_shift/UnarmedAttack()
	if(shadekin.in_phase)
		return FALSE //Nope.

	. = ..()

/mob/living/simple_mob/clowns/big/c_shift/can_fall()
	if(shadekin.in_phase)
		return FALSE //Nope!

	return ..()

/mob/living/simple_mob/clowns/big/c_shift/zMove(direction)
	if(shadekin.in_phase)
		var/turf/destination = (direction == UP) ? GetAbove(src) : GetBelow(src)
		if(destination)
			forceMove(destination)
		return TRUE

	return ..()
