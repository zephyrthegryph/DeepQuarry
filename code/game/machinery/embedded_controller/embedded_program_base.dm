/datum/embedded_program
	var/name
	var/list/memory = list() // ALLOW(instance_list): d: every embedded program keeps its state in memory
	var/obj/machinery/embedded_controller/master

	var/id_tag

/datum/embedded_program/New(obj/machinery/embedded_controller/M)
	rel_set(src, nameof(master), M)
	if (istype(M, /obj/machinery/embedded_controller/radio))
		var/obj/machinery/embedded_controller/radio/R = M
		id_tag = R.id_tag

// The controller owns its program (embedded_controller.program); the program names it back.
/datum/embedded_program/declare_ownership(decl)
	..()
	rel(decl, nameof(master))

// Return TRUE if was a command for us, otherwise return FALSE (so controllers with multiple programs can try each in turn until one accepts)
/datum/embedded_program/proc/receive_user_command(command)
	return FALSE

/datum/embedded_program/proc/receive_signal(datum/signal/signal, receive_method, receive_param)
	return

/// Whether receiving this signal can require the sleeping controller to process.
/datum/embedded_program/proc/signal_requires_processing(datum/signal/signal, receive_method, receive_param)
	return TRUE

/datum/embedded_program/proc/post_signal(datum/signal/signal, comm_line)
	if(master)
		master.post_signal(signal, comm_line)
	else
		qdel(signal)
