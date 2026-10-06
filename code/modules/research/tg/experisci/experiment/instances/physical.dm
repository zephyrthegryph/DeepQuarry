/datum/experiment/physical/arcade_winner
	name = "Playtesting Experiences"
	description = "How do they make these arcade games so fun? Let's play one and win it to find out."

/datum/experiment/physical/arcade_winner/register_events()
	if(!istype(currently_scanned_atom, /obj/machinery/computer/arcade))
		linked_experiment_handler.announce_message("Incorrect object for experiment.")
		return FALSE

	observe(currently_scanned_atom, /datum/notice/arcade_prizevend, src, then(PROC_REF(win_arcade)))
	linked_experiment_handler.announce_message("Experiment ready to start.")
	return TRUE

/datum/experiment/physical/arcade_winner/unregister_events()
	unobserve(currently_scanned_atom, /datum/notice/arcade_prizevend, src)

/datum/experiment/physical/arcade_winner/check_progress()
	. += EXPERIMENT_PROG_BOOL("Win an arcade game at a tracked arcade cabinet.", is_complete())

/datum/experiment/physical/arcade_winner/proc/win_arcade(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	finish_experiment(linked_experiment_handler)
