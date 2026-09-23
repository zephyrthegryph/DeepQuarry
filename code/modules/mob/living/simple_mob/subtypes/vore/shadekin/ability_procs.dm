// Phase shifting is the shared shadekin_phase_shift ability
// (code/datums/components/species/shadekin/powers/phase_shift.dm); this type
// doesn't need its own version of it.

/mob/living/simple_mob/shadekin/UnarmedAttack()
	if(comp.in_phase)
		return FALSE //Nope.

	. = ..()

/mob/living/simple_mob/shadekin/can_fall()
	if(comp.in_phase)
		return FALSE //Nope!

	return ..()

/mob/living/simple_mob/shadekin/zMove(direction)
	if(comp.in_phase)
		var/turf/destination = (direction == UP) ? GetAbove(src) : GetBelow(src)
		if(destination)
			forceMove(destination)
		return TRUE

	return ..()
