/obj/machinery/bunsen_burner
	maintenance_flags = MACHINE_MAINT_PANEL | MACHINE_MAINT_WRENCH
	name = "bunsen burner"
	desc = "A small, self-heating device designed for bringing chemical mixtures to a boil."
	icon = 'icons/obj/device.dmi'
	icon_state = "bunsen0"
	/// Heat the flame puts into the burner and what sits on it, W.
	var/heat_power = BUNSEN_HEAT_POWER
	var/obj/item/reagent_containers/held_container

/obj/machinery/bunsen_burner/var/heating = FALSE
TRACKED_BRIDGED(/obj/machinery/bunsen_burner, heating, CHANGE_MACHINE_SETTINGS)
/// Boils its container while heating (start_boiling() .. end_boil()).
// The holder resizes to match the boiling container.

/obj/machinery/bunsen_burner/proc/interaction_place_container(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	add_fingerprint(user)
	// Handle container
	if(!istype(W, /obj/item/reagent_containers))
		to_chat(user, span_notice("You can't put \the [W] onto \the [src]."))
		return TRUE
	if(!anchored)
		to_chat(user, span_notice("\The [src] must be secured down with a wrench."))
		return TRUE
	if(held_container)
		to_chat(user, span_notice("You must remove \the [held_container] before you can place another container on \the [src]."))
		return TRUE
	// A new hand touches the beacon
	if(!move_into(src, nameof(src.held_container), W, user))
		return TRUE
	reagents.maximum_volume = held_container.reagents.maximum_volume // Update internal reagent distilling volume
	to_chat(user, span_notice("You put \the [held_container] onto \the [src]."))
	if(held_container.reagents.total_volume > 0)
		start_boiling()
	else
		update_icon()
	return TRUE

/obj/machinery/bunsen_burner/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!panel_open || !isturf(loc))
		return OP_OK
	use_tool(user, tool, src, delay = 5, receiver = src, on_done = PROC_REF(crowbar_act_tool_done), done_args = list(user))
	return OP_OK

/obj/machinery/bunsen_burner/proc/crowbar_act_tool_done(mob/user)
	drop_held_container()
	to_chat(user, span_notice("You disassemble \the [src]."))
	replace_with(src, /obj/item/stack/material/steel, 1)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/bunsen_burner/proc/interaction_remove_container(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!held_container)
		to_chat(user, span_notice("There is nothing on \the [src]."))
		return TRUE

	// Take it off
	to_chat(user, span_notice("You remove \the [held_container] from \the [src]."))
	held_container.forceMove(get_turf(src))
	held_container.attack_hand(user) // Pick it up
	rel_take(src, nameof(held_container))

	// Removed beaker, so kill processing
	if(heating)
		end_boil()
		return TRUE
	update_icon()
	return TRUE

/obj/machinery/bunsen_burner/proc/start_boiling()
	if(!held_container)
		return
	if(heating)
		return

	// Begin boiling: the flame is a heat source on the burner's heat body.
	visible_message(span_notice("\The [src] starts to heat \the [held_container]."))
	set_heating(TRUE)
	if(create_heat_body(TRUE))
		vg_heat_body_keep(heat_body, TRUE)
		vg_heat_body_power(heat_body, heat_power)
	update_icon()

/obj/machinery/bunsen_burner/proc/drop_held_container()
	if(!held_container)
		return
	held_container.forceMove(get_turf(src))
	rel_take(src, nameof(held_container))

/// Boils its container; runs while heating (declared).
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/bunsen_burner)
	owns_one(nameof(held_container), /obj/item/reagent_containers)
	op("place_container", item(/obj/item), label("Place container"), then(PROC_REF(interaction_place_container)))
	op("remove_container", hand(), label("Remove container"), then(PROC_REF(interaction_remove_container)))
	reagents(1, holder = /datum/reagents/distilling)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(heating), wakes_on = list(nameof(heating)))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(crowbar_used)))
	extend("machine_anchor", then(PROC_REF(rewrenched)))
	extend("machine_unanchor", then(PROC_REF(rewrenched)))

/obj/machinery/bunsen_burner/proc/work_step(datum/act/timer/A)
	if(held_container && !anchored)
		drop_held_container()
		end_boil()
		return

	if(!LAZYLEN(held_container?.reagents?.reagent_list))
		end_boil()
		return

	// The flame heats the body; read where it is now.
	var/previous_temp = bunsen_last_temp || get_temperature()
	var/current_temp = get_temperature()
	bunsen_last_temp = current_temp

	// Slosh and toss. We use an internal distilling container, react it in there, then pass it back.
	held_container.reagents.trans_to_obj(src, held_container.reagents.total_volume)
	if(reagents.handle_reactions())
		held_container.update_icon()
		update_icon()
	reagents.trans_to_obj(held_container, reagents.total_volume)

	// every 25 degree step, do a message to show we are working
	if(FLOOR(previous_temp / 40, 1) != FLOOR(current_temp / 40, 1))
		// Open flame
		var/turf/location = get_turf(src)
		if(isturf(location))
			location.hotspot_expose(1000, 500, 1)
		// Messages and temp limit
		if(current_temp < T0C + 50)
			visible_message(span_notice("\The [src] sloshes."))
		else if(current_temp <  T0C + 100)
			visible_message(span_notice("\The [src] hisses."))
		else if(current_temp <  T0C + 200)
			visible_message(span_notice("\The [src] boils."))
		else if(current_temp <  T0C + 400)
			visible_message(span_notice("\The [src] bubbles aggressively."))
		else if(current_temp <  T0C + 600)
			visible_message(span_notice("\The [src] rumbles intensely."))
		else
			// finished boiling
			end_boil()

/obj/machinery/bunsen_burner/proc/end_boil()
	set_heating(FALSE)
	bunsen_last_temp = null
	if(!isnull(heat_body))
		vg_heat_body_power(heat_body, 0)
		vg_heat_body_keep(heat_body, FALSE)
	visible_message(span_notice("\The [src] clicks."))
	update_icon()

/// The burner, what sits on it, and the flame while it heats.
/obj/machinery/bunsen_burner/draw(datum/look/look)
	..()
	look.state("bunsen0")
	if(held_container)
		look.overlay(image("icon" = held_container))
	if(heating)
		look.overlay(image(icon, icon_state = "bunsen1", layer = layer + 0.1))

/obj/machinery/bunsen_burner/examine(mob/user, infix, suffix)
	. = ..()
	if(heating)
		. += span_notice("It's current temperature is [round(get_temperature() - T0C, 0.1)]c")


/obj/machinery/bunsen_burner
	/// Temperature at the last process(), for the progress messages.
	var/tmp/bunsen_last_temp

/// The burner heats what sits on it: its body carries the held reagents' heat capacity.
/obj/machinery/bunsen_burner/thermal_properties()
	. = ..()
	if(held_container?.reagents)
		.[THERMAL_CAPACITY] += held_container.reagents.heat_capacity()

/// After the base wrench: an unsecured burner lets go of its container and stops boiling.
/obj/machinery/bunsen_burner/proc/rewrenched(datum/act/op/A)
	if(!anchored)
		drop_held_container()
		if(heating)
			end_boil()
