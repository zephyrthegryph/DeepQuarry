// Phase shifting is the shared shadekin_phase_shift ability
// (code/modules/mob/living/carbon/human/species/shadekin/state/powers/phase_shift.dm); this type
// doesn't need its own version of it.

/mob/living/simple_mob/shadekin/UnarmedAttack()
	if(shadekin.in_phase)
		return FALSE //Nope.

	. = ..()

/mob/living/simple_mob/shadekin/can_fall()
	if(shadekin.in_phase)
		return FALSE //Nope!

	return ..()

/mob/living/simple_mob/shadekin/zMove(direction)
	if(shadekin.in_phase)
		var/turf/destination = (direction == UP) ? GetAbove(src) : GetBelow(src)
		if(destination)
			forceMove(destination)
		return TRUE

	return ..()
