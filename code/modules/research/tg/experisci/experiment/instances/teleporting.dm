/datum/experiment/physical/teleporting
	name = "Teleportation Basics"
	description = "How does bluespace travel affect mundane materials? Teleport an object from another location to the telescience telepad, and record observations."

/datum/experiment/physical/teleporting/register_events()
	if(!istype(currently_scanned_atom, /obj/machinery/computer/telescience) && !istype(currently_scanned_atom, /obj/machinery/telepad))
		linked_experiment_handler.announce_message("Incorrect object for experiment.")
		return FALSE

	observe(currently_scanned_atom, /datum/notice/telesci_teleport, src, then(PROC_REF(teleported_items)))
	linked_experiment_handler.announce_message("Experiment ready to start.")
	return TRUE

/datum/experiment/physical/teleporting/unregister_events()
	unobserve(currently_scanned_atom, /datum/notice/telesci_teleport, src)

/datum/experiment/physical/teleporting/check_progress()
	. += EXPERIMENT_PROG_BOOL("Teleport an object to the telescience telepad.", is_complete())

/datum/experiment/physical/teleporting/proc/teleported_items(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/telesci_teleport/event = A
	var/list/atom/movable/teleported_things = event.teleported_things
	var/sending = event.sending
	// we must GET an object, not just send one.
	if(!sending && teleported_things.len)
		finish_experiment(linked_experiment_handler)
