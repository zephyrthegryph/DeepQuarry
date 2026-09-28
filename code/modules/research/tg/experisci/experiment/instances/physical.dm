/datum/experiment/physical/arcade_winner
	name = "Playtesting Experiences"
	description = "How do they make these arcade games so fun? Let's play one and win it to find out."

/datum/experiment/physical/arcade_winner/register_events()
	if(!istype(currently_scanned_atom, /obj/machinery/computer/arcade))
		linked_experiment_handler.announce_message("Incorrect object for experiment.")
		return FALSE

	om_hook(currently_scanned_atom, /datum/om/event/arcade_prizevend, src, PROC_REF(win_arcade))
	linked_experiment_handler.announce_message("Experiment ready to start.")
	return TRUE

/datum/experiment/physical/arcade_winner/unregister_events()
	om_unhook(currently_scanned_atom, /datum/om/event/arcade_prizevend, src)

/datum/experiment/physical/arcade_winner/check_progress()
	. += EXPERIMENT_PROG_BOOL("Win an arcade game at a tracked arcade cabinet.", is_complete())

/datum/experiment/physical/arcade_winner/proc/win_arcade(datum/source, datum/om/event/arcade_prizevend/event)
	EVENT_HANDLER
	finish_experiment(linked_experiment_handler)
