/obj/machinery/feeder
	name = "\improper Feeder"
	icon = 'icons/obj/feeder.dmi'
	desc = "This is a feeder. Put in a reagent container, then click and drag the feeder to someone!"
	anchored = FALSE
	density = FALSE

OM_FIELD_VIEW(/obj/machinery/feeder, mob/living/carbon/human, attached, CHANGE_MACHINE_OCCUPANT)
OM_FIELD_VIEW(/obj/machinery/feeder, obj/item/reagent_containers, beaker, CHANGE_MACHINE_OCCUPANT)
/// Feeds while a patient and a container are attached.
DECLARE_APPEARANCE_PROC(/obj/machinery/feeder, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/feeder/appearance_overlays()
	. = list()
	if(attached())
		icon_state = "feeding"
	else
		icon_state = ""


	if(beaker)
		var/datum/reagents/reagents = beaker.reagents
		if(reagents.total_volume)
			var/image/filling = image('icons/obj/feeder.dmi', src, "reagent")

			var/percent = round((reagents.total_volume / beaker.volume) * 100)
			switch(percent)
				if(0 to 9)		filling.icon_state = "reagent0"
				if(10 to 19) 	filling.icon_state = "reagent10"
				if(20 to 44)	filling.icon_state = "reagent20"
				if(45 to 59)	filling.icon_state = "reagent45"
				if(60 to 74)	filling.icon_state = "reagent60"
				if(75 to 89)	filling.icon_state = "reagent75"
				if(90 to 94)	filling.icon_state = "reagent90"
				if(95 to INFINITY)	filling.icon_state = "reagent100"

			filling.icon += reagents.get_color()
			. += filling

CAPABILITIES(/obj/machinery/feeder)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = cond_all(nameof(attached), nameof(beaker)), wakes_on = list(nameof(attached), nameof(beaker)))
	drag_onto(PROC_REF(drop_input))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("insert_beaker", item(/obj/item/reagent_containers), priority(OP_PRIORITY_DEFAULT - 1), label("Insert container"), needs(req_is(nameof(beaker), FALSE, because = MSG(feeder/beaker))), then(PROC_REF(interaction_insert_beaker)))
	op("reject", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_reject)))
	op("take_beaker", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Take out container"), then(PROC_REF(interaction_take_beaker)))

/// The native drop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm). A drop onto a patient attaches them,
/// then the native drop goes on.
/obj/machinery/feeder/proc/drop_input(datum/act/input/A)
	drop_patient_with_actor(A.actor, A.over)
	return INPUT_FALLTHROUGH

/obj/machinery/feeder/proc/drop_patient_with_actor(mob/user, atom/over_object)
	if(!isliving(user))
		return

	if(attached())
		visible_message("The feeding tube is pulled out of [attached()].")
		rel_clear(src, nameof(attached))
		update_icon()
		return

	if(in_range(src, user) && ishuman(over_object) && get_dist(over_object, src) <= 1)
		act_message(user, null, others = "%U% inserts the feeding tube into \the [over_object].")
		rel_set(src, nameof(attached), over_object)
		update_icon()


MSG_DEF_SELF(feeder/beaker, "There is already a reagent container inserted.")

/obj/machinery/feeder/proc/interaction_insert_beaker(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!move_into(src, nameof(src.beaker), W, user))
		return TRUE
	to_chat(user, span_notice("You insert \the [W] into \the [src]."))
	update_icon()
	return TRUE

/obj/machinery/feeder/proc/interaction_reject(datum/act/op/A)
	return TRUE

/obj/machinery/feeder/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	playsound(src, tool.usesound, 50, TRUE)
	set_panel_open(!panel_open)
	to_chat(user, span_notice("You [panel_open ? "open" : "close"] the maintenance hatch of [src]."))
	update_icon()
	task_timed(user, 1.5 SECONDS, target = src, receiver = src, on_done = PROC_REF(screwdriver_act_timed_done), done_args = list(user))
	return OP_OK

/obj/machinery/feeder/proc/screwdriver_act_timed_done(mob/user)
	to_chat(user, "You deconstruct the feeder.")
	new /obj/item/stack/material/plastic(loc, 4)
	if(beaker)
		beaker.forceMove(get_turf(src))
		rel_take(src, nameof(beaker))
	destroyed(src, user, "deconstructed")

/// Feeds while a patient and a container are attached; otherwise it sleeps until one is.
/obj/machinery/feeder/proc/work_step(datum/act/timer/A)
	if(attached())
		if(!(get_dist(src, attached()) <= 1 && isturf(attached().loc)))
			visible_message("The tube is pulled out of [attached()].")
			rel_clear(src, nameof(attached))
			update_icon()
			return
	// Give food
	if(beaker && beaker.volume > 0)
		var/transfer_amount = 2
		beaker.reagents.trans_to_mob(attached(), transfer_amount, CHEM_INGEST)
		update_icon()

/obj/machinery/feeder/proc/interaction_take_beaker(datum/act/op/A)
	if(!beaker)
		return OP_DECLINE
	beaker.forceMove(get_turf(src))
	rel_take(src, nameof(beaker))
	update_icon()
	return TRUE

/obj/machinery/feeder/examine(mob/user)
	.=..()
	if(!(user in view(2)) && user != src.loc) return

	if(beaker)
		if(beaker.reagents && beaker.reagents.reagent_list.len)
			. += span_notice("Inserted is \a [beaker] with [beaker.reagents.total_volume] units of liquid.")
		else
			. += span_notice("Inserted is an empty [beaker].")
	else
		. += span_notice("No container is inserted.")

	. += span_notice("[attached() ? attached() : "No one"] is being fed by it.")

/obj/machinery/feeder/CanPass(atom/movable/mover, turf/target, height = 0, air_group = 0)
	if(height && istype(mover) && mover.checkpass(PASSTABLE)) //allow bullets, beams, thrown objects, mice, drones, and the like through.
		return 1
	return ..()

/obj/machinery/feeder/ownership()
	. = ..()
	. += owns(nameof(beaker), policy = OWN_CONTAINED)

/// attached (a relation view: it reads null once the target is deleted).
/obj/machinery/feeder/proc/attached() as /mob/living/carbon/human
	return attached
