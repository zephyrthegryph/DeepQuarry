/// Base for the perk-granted disabilities (were /datum/component/*_disability). Each reacts to the
/// handle_disabilities event the disabilities life stage emits on the mob; state lives on the mob.
/datum/om/behaviour/disability
	handles = list(/datum/om/event/handle_disabilities)
	/// The mob type this disability needs (was the component's COMPONENT_INCOMPATIBLE check).
	var/required_type = /mob/living

/datum/om/behaviour/disability/on_event(datum/E, datum/om/event/event)
	if(!istype(event, /datum/om/event/handle_disabilities))
		return
	if(!istype(E, required_type))
		return
	disability_tick(E)

/// One disabilities life-stage tick for `owner`.
/datum/om/behaviour/disability/proc/disability_tick(mob/living/owner)
	SHOULD_NOT_SLEEP(TRUE)
	return

