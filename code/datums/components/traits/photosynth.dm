// If a mob has this component, every life tick it will gain nutrition if it's standing in light up to nutrition_max.
// Extremely good tutorial component if you need an example with no special bells and whistles, and no "gotcha" behaviors.
/datum/component/photosynth
	var/nutrition_max = 1000

/datum/component/photosynth/Initialize()
	if(!isliving(parent))
		return COMPONENT_INCOMPATIBLE

/datum/component/photosynth/RegisterWithParent()
	om_stage_add(parent, /datum/om/stage/life/trait/photosynth)

/datum/component/photosynth/UnregisterFromParent()
	om_stage_remove(parent, /datum/om/stage/life/trait/photosynth)

/datum/component/photosynth/proc/process_component()
	SIGNAL_HANDLER
	var/mob/living/owner = parent
	if(QDELETED(parent))
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
	component_type = /datum/component/photosynth

/datum/om/stage/life/trait/photosynth/tick_component(mob/living/self, datum/component/photosynth/component)
	component.process_component()
