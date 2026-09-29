/////SINGULARITY SPAWNER
/obj/machinery/the_singularitygen/
	name = "Gravitational Singularity Generator"
	desc = "An Odd Device which produces a Gravitational Singularity when set up."
	icon = 'icons/obj/singularity.dmi'
	icon_state = "TheSingGen"
	anchored = FALSE
	density = TRUE
	use_power = USE_POWER_OFF
	var/energy = 0
	var/creation_type = /obj/singularity

/obj/machinery/the_singularitygen/examine()
	. = ..()
	if(anchored)
		. += span_notice("It has been securely bolted down and is ready for operation.")
	else
		. += span_warning("It is not secured!")

/// Collapses into a singularity once particles have charged it; each hit wakes it to check.
/obj/machinery/the_singularitygen/machine_step()
	var/turf/T = get_turf(src)
	if(src.energy >= 200)
		new creation_type(T, 50)
		if(src) qdel(src)
	return PROCESS_KILL

/obj/machinery/the_singularitygen/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/singularitygen_install_particle_accelerator,
	)
	..()

/datum/interaction/machine_item/singularitygen_install_particle_accelerator
	id = "singularitygen_install_particle_accelerator"
	name = "Install"
	held_type = /obj/item/smes_coil/super_io
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/the_singularitygen/proc/panel_is_open, null))
	effect = /obj/machinery/the_singularitygen/proc/interaction_install

/obj/machinery/the_singularitygen/proc/panel_is_open(mob/actor, atom/target, obj/item/held)
	return panel_open

/// The old attackby always chained to ..() at the end regardless of branch, so this always
/// declines (returns FALSE) after doing its work, letting the base attackby chain still run.
/obj/machinery/the_singularitygen/proc/interaction_install(mob/user, obj/item/W, datum/interaction/interaction)
	visible_message(span_infoplain(span_bold("\The [user]") + " begins to modify \the [src] with \the [W]."))
	om_task_timed(user, 30 SECONDS, src, src, PROC_REF(install_done), list(user, W))
	return FALSE

/obj/machinery/the_singularitygen/proc/install_done(mob/user, obj/item/W)
	user.drop_from_inventory(W)
	visible_message(span_infoplain(span_bold("\The [user]") + " installs \the [W] onto \the [src]."))
	consume(W, user)
	var/turf/T = get_turf(src)
	var/new_machine = /obj/machinery/particle_smasher
	new new_machine(T)
	qdel(src)

/obj/machinery/the_singularitygen/wrench_act(mob/user, obj/item/W)
	set_anchored(!anchored)
	playsound(src, W.usesound, 75, 1)
	user.visible_message("[user.name] [anchored ? "secures" : "unsecures"] [src.name] to the floor.", \
		"You [anchored ? "secure" : "unsecure"] the [src.name] to the floor.", \
		"You hear a ratchet.")
	return ITEM_INTERACT_SUCCESS

/obj/machinery/the_singularitygen/screwdriver_act(mob/user, obj/item/W)
	panel_open = !panel_open
	playsound(src, W.usesound, 50, 1)
	visible_message(span_infoplain(span_bold("\The [user]") + " adjusts \the [src]'s mechanisms."))
	if(panel_open)
		om_task_timed(user, 3 SECONDS, src, src, PROC_REF(inspect_done), list(user, W))
	else
		to_chat(user, span_notice("\The [src]'s mechanisms look secure."))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/the_singularitygen/proc/inspect_done(mob/user, obj/item/W)
	if(!panel_open)
		return
	to_chat(user, span_notice("\The [src] looks like it could be modified."))
	use_tool(user, W, src, delay = 8 SECONDS, volume = 50, receiver = src, on_done = PROC_REF(inspect_done_tool_done), done_args = list(user))

/obj/machinery/the_singularitygen/proc/inspect_done_tool_done(mob/user)
	to_chat(user, span_cult("\The [src] looks like it could be adapted to forge advanced materials via particle acceleration, somehow.."))
