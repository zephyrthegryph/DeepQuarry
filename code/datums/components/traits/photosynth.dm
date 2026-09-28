// If a mob has this trait state, every life tick it will gain nutrition if it's standing in light up to nutrition_max.
// Extremely good tutorial trait state if you need an example with no special bells and whistles, and no "gotcha" behaviors.
/datum/trait_state/photosynth
	life_stage = /datum/om/stage/life/trait/photosynth
	var/nutrition_max = 1000

/datum/trait_state/photosynth/life_tick()
	if(QDELETED(owner))
		return
	if(owner.stat == DEAD)
		return
	if(owner.is_incorporeal())
		return
	if(owner.inStasisNow())
		return
	if(!isturf(owner.loc))
		return
	if(owner.nutrition >= nutrition_max)
		return
	var/turf/T = owner.loc
	owner.adjust_nutrition(T.get_lumcount() / 10)

/// Trait system: photosynthesis. Was a COMSIG_LIVING_LIFE listener.
/datum/om/stage/life/trait/photosynth
	name = "photosynth"
	state_type = /datum/trait_state/photosynth
