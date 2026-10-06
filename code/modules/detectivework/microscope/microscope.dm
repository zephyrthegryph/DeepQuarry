//microscope code itself
/obj/machinery/microscope
	name = "high powered electron microscope"
	desc = "A highly advanced microscope capable of zooming up to 3000x."
	icon = 'icons/obj/forensics.dmi'
	icon_state = "microscope"
	anchored = TRUE
	density = TRUE

	var/tmp/obj/item/sample
	var/report_num = 0

/obj/machinery/microscope/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/microscope_insert_sample,
		/datum/interaction/machine_hand/ungated/microscope_examine,
		/datum/interaction/machine_alt/microscope_remove_sample,
	)
	..()

/datum/interaction/machine_item/microscope_insert_sample
	id = "microscope_insert_sample"
	name = "Insert sample"
	held_type = /obj/item
	also_requires = list(REQ_FIELD_NOT("sample", "there is already a slide in the microscope"), REQ_TARGET_STATE(/obj/machinery/microscope/proc/can_insert_sample))
	effect = /obj/machinery/microscope/proc/interaction_attackby

/// A microscope sample must be releasable from its current holder before insertion.
/obj/machinery/microscope/proc/can_insert_sample(mob/user, atom/target, obj/item/held)
	var/reason = held?.loc?.release_refusal(held, user)
	if(reason)
		return reason
	return TRUE

/obj/machinery/microscope/proc/interaction_attackby(mob/user, obj/item/held, datum/interaction/interaction)
	if(!istype(held, /obj/item/forensics/swab) && !istype(held, /obj/item/sample/fibers) && !istype(held, /obj/item/sample/print))
		return FALSE

	if(can_insert_sample(user, src, held) != TRUE)
		return FALSE
	if(!held.loc.release_to(held, src, null, user))
		return FALSE
	rel_set(src, nameof(sample), held)
	to_chat(user, span_notice("You insert \the [held] into the microscope."))
	update_icon()
	return TRUE

/datum/interaction/machine_hand/ungated/microscope_examine
	id = "microscope_examine"
	name = "Examine sample"
	also_requires = list(REQ_FIELD("sample", "the microscope has no sample to examine"))
	effect = /obj/machinery/microscope/proc/interaction_examine

/datum/interaction/machine_alt/microscope_remove_sample
	id = "microscope_remove_sample"
	name = "Remove sample"
	consumes_input = FALSE
	effect = /obj/machinery/microscope/proc/interaction_remove_sample

/obj/machinery/microscope/proc/interaction_remove_sample(mob/user, obj/item/held, datum/interaction/interaction)
	remove_sample(user)
	return TRUE

/obj/machinery/microscope/proc/interaction_examine(mob/user, obj/item/held, datum/interaction/interaction)

	to_chat(user, span_notice("The microscope whirrs as you examine \the [sample()]."))

	task_start(/datum/task/timed/microscope_examine, user, sample())
	return TRUE

/obj/machinery/microscope/proc/examine_stopped(datum/task/timed/microscope_examine/task)
	var/mob/user = task.actor
	var/obj/item/examined = task.target
	to_chat(user, span_notice("You stop examining \the [examined]."))

/datum/task/timed/microscope_examine
	duration = 2 SECONDS
	complete_proc = /obj/machinery/microscope/proc/examine_done
	cancel_proc = /obj/machinery/microscope/proc/examine_stopped

/obj/machinery/microscope/proc/examine_done(datum/task/timed/microscope_examine/task)
	var/mob/user = task.actor
	var/obj/item/examined = task.target
	if(sample() != examined)
		return
	to_chat(user, span_notice("Printing findings now..."))
	var/obj/item/paper/report = new(get_turf(src))
	report.stamped = list(/obj/item/stamp)
	report.overlays = list("paper_stamped")
	report_num++

	if(istype(sample(), /obj/item/forensics/swab))
		var/obj/item/forensics/swab/swab = sample()

		report.name = "GSR report #[++report_num]: [swab.name]"
		report.info = span_bold("Scanned item:") + "<br>[swab.name]<br><br>"

		if(swab.gsr)
			report.info += "Residue from a [swab.gsr] bullet detected."
		else
			report.info += "No gunpowder residue found."

	else if(istype(sample(), /obj/item/sample/fibers))
		var/obj/item/sample/fibers/fibers = sample()
		report.name = "Fiber report #[++report_num]: [fibers.name]"
		report.info = span_bold("Scanned item:") + "<br>[fibers.name]<br><br>"
		if(fibers.evidence)
			report.info = "Molecular analysis on provided sample has determined the presence of unique fiber strings.<br><br>"
			for(var/fiber in fibers.evidence)
				report.info += span_notice("Most likely match for fibers: [fiber]") + "<br><br>"
		else
			report.info += "No fibers found."
	else if(istype(sample(), /obj/item/sample/print))
		report.name = "Fingerprint report #[report_num]: [sample().name]"
		report.info = span_bold("Fingerprint analysis report #[report_num]") + ": [sample().name]<br>"
		var/obj/item/sample/print/card = sample()
		if(card.evidence && length(card.evidence))
			report.info += "Surface analysis has determined unique fingerprint strings:<br><br>"
			for(var/prints in card.evidence)
				report.info += span_notice("Fingerprint string: ")
				if(!is_complete_print(LAZYACCESS(card.evidence, prints)))
					report.info += "INCOMPLETE PRINT:[LAZYACCESS(card.evidence, prints)]"
				else
					report.info += "[prints]"
				report.info += "<br>"
		else
			report.info += "No information available."

	if(report)
		report.update_icon()
		if(report.info)
			to_chat(user,report.info)

/obj/machinery/microscope/proc/remove_sample(mob/living/remover)
	if(!istype(remover) || remover.incapacitated() || !Adjacent(remover))
		return
	if(!sample())
		to_chat(remover, span_warning("\The [src] does not have a sample in it."))
		return
	to_chat(remover, span_notice("You remove \the [sample()] from \the [src]."))
	sample().forceMove(get_turf(src))
	remover.put_in_hands(sample())
	rel_clear(src, nameof(sample))
	update_icon()

CAPABILITIES(/obj/machinery/microscope)
	drag_onto(PROC_REF(mousedrop_input))

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/machinery/microscope/proc/mousedrop_input(datum/act/input/A)
	if(!handle_sample_drop(A.actor, A.over))
		return INPUT_FALLTHROUGH

/obj/machinery/microscope/proc/handle_sample_drop(mob/user, atom/other)
	if(user != other)
		return FALSE
	remove_sample(user)
	return TRUE

APPEARANCE_TEMPLATE(/obj/machinery/microscope, "microscope{sample?slide:}")

/// the sample this refers to (a relation view: null once it is deleted).
/obj/machinery/microscope/proc/sample() as /obj/item
	return sample
