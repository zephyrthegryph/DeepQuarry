// Preset for general and toggled actions: a power the mob has of its own, not through an item.
/datum/action/innate
	check_flags = NONE
	ability_category = ABILITY_CATEGORY_SPECIES
	/// Whether we're active or not, if we're a innate - toggle action.
	var/active = 0

/datum/action/innate/Trigger(trigger_flags)
	if(!..())
		return 0
	if(!active)
		Activate()
	else
		Deactivate()
	ability_changed()
	return 1

/// A toggle shows whether it is on.
/datum/action/innate/ability_toggled()
	return active ? TRUE : null

/datum/action/innate/proc/Activate()
	return

/datum/action/innate/proc/Deactivate()
	return
