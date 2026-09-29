/datum/experiment/physical
	name = "Physical Experiment"
	description = "An experiment requiring a physical reaction to continue"
	exp_tag = EXPERIMENT_TAG_PHYSICAL
	performance_hint = "To perform physical experiments you must use a hand-held scanner unit to track objects in our world relevant to \
		your experiment. Activate the experiment on your scanner, scan the object to track, and then complete the objective."
	/// The atom that is currently being watched by this experiment
	var/atom/currently_scanned_atom
	/// Linked experiment handler
	var/datum/experiment_handler/linked_experiment_handler

// Its hooks on the scanned atom go with the core teardown.

/datum/experiment/physical/is_complete()
	return completed

/datum/experiment/physical/perform_experiment_actions(datum/experiment_handler/experiment_handler, atom/target)
	if(currently_scanned_atom)
		unregister_events()
	rel_set(src, "currently_scanned_atom", target)
	rel_set(src, "linked_experiment_handler", experiment_handler)
	if(register_events())
		return TRUE
	rel_clear(src, "currently_scanned_atom")
	rel_clear(src, "linked_experiment_handler")
	return FALSE

/**
 * Handles registering to events relevant to the experiment
 */
/datum/experiment/physical/proc/register_events()
	return FALSE

/**
 * Handles unregistering to events relevant to the experiment
 */
/datum/experiment/physical/proc/unregister_events()
	return
