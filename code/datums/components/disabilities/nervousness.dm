/datum/component/nervousness_disability
	var/mob/owner

/datum/component/nervousness_disability/Initialize()
	if (!ishuman(parent))
		return COMPONENT_INCOMPATIBLE

	owner = parent
	RegisterSignal(owner, COMSIG_HANDLE_DISABILITIES, PROC_REF(process_component))

/datum/component/nervousness_disability/proc/process_component()
	SIGNAL_HANDLER

	if(QDELETED(parent))
		return
	if(isbelly(owner.loc))
		return
	if(owner.stat != CONSCIOUS)
		return
	if(owner.transforming)
		return
	if(prob(5) && prob(7))
		owner.status_at_least(EFFECT_STUTTERING, 15)
		if(owner.status_units(EFFECT_JITTERY) < 50)
			owner.status_adjust(EFFECT_JITTERY, 65)

/datum/component/nervousness_disability/Destroy(force = FALSE)
	UnregisterSignal(owner, COMSIG_HANDLE_DISABILITIES)
	owner = null
	. = ..()
