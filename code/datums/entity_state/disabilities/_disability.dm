/// Base for the trait-granted disabilities (were /datum/component/*_disability, then OM behaviours on the disabilities life
/// stage). A disability is a capability the trait grants with itself as the source (trait.dm apply()/unapply()): its every()
/// runs once a Life cycle on the mob's own clock while the trait lasts. State lives on the mob.
/datum/capability/disability
	/// The mob type this disability needs (was the component's COMPONENT_INCOMPATIBLE check).
	var/required_type = /mob/living

/datum/capability/disability/entries()
	return list(every(LIFE_CYCLE, then(CAP_PROC(disability_run))))

/datum/capability/disability/proc/disability_run(datum/act/timer/A)
	if(istype(A.holder, required_type))
		disability_tick(A.holder)

/// One Life cycle of the disability on `owner`.
/datum/capability/disability/proc/disability_tick(mob/living/owner)
	SHOULD_NOT_SLEEP(TRUE)
	return
