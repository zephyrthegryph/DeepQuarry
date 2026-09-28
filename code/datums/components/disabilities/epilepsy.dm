/datum/component/epilepsy_disability

/datum/component/epilepsy_disability/Initialize()
	if (!isliving(parent))
		return COMPONENT_INCOMPATIBLE

	RegisterSignal(owner(), COMSIG_HANDLE_DISABILITIES, PROC_REF(process_component))

/datum/component/epilepsy_disability/proc/process_component()
	SIGNAL_HANDLER

	if (QDELETED(parent))
		return
	if(isbelly(owner().loc))
		return
	if(owner().stat != CONSCIOUS)
		return
	if(owner().transforming)
		return
	if((prob(1) && prob(1) && !owner().has_status(EFFECT_PARALYZED)))
		to_chat(owner(), span_red("You have a seizure!"))
		for(var/mob/O in viewers(owner(), null))
			if(O == owner())
				continue
			O.show_message(span_danger("[owner()] starts having a seizure!"), 1)
		owner().status_at_least(EFFECT_PARALYZED, 10)
		owner().status_at_least(EFFECT_SLEEPING, 10)
		owner().status_adjust(EFFECT_JITTERY, 1000)


/// LC-refs: the afflicted mob (our parent) (was a var copying parent).
/datum/component/epilepsy_disability/proc/owner() as /mob/living
	return parent
