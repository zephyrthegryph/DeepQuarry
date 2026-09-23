/obj/machinery/bunsen_burner
	maintenance_flags = MACHINE_MAINT_PANEL | MACHINE_MAINT_WRENCH
	name = "bunsen burner"
	desc = "A small, self-heating device designed for bringing chemical mixtures to a boil."
	description_info = "Place a beaker into it to begin heating. Reagents will be distilled over time as the mixture heats up. The bunsen burner is only capable of heating reagents up to 600c, and the atmoshere around it will affect what reactions are possible."
	icon = 'icons/obj/device.dmi'
	icon_state = "bunsen0"
	var/heating = FALSE
	/// Heat the flame puts into the burner and what sits on it, W.
	var/heat_power = BUNSEN_HEAT_POWER
	var/obj/item/reagent_containers/held_container

/obj/machinery/bunsen_burner/Initialize(mapload)
	. = ..()
	create_reagents(1, /datum/reagents/distilling) //  resizes based on the boiling container

/obj/machinery/bunsen_burner/attackby(obj/item/W, mob/user)
	add_fingerprint(user)
	// Handle container
	if(!istype(W, /obj/item/reagent_containers))
		to_chat(user, span_notice("You can't put \the [W] onto \the [src]."))
		return
	if(!anchored)
		to_chat(user, span_notice("\The [src] must be secured down with a wrench."))
		return
	if(held_container)
		to_chat(user, span_notice("You must remove \the [held_container] before you can place another container on \the [src]."))
		return
	// A new hand touches the beacon
	user.drop_item(src)
	held_container = W
	held_container.forceMove(src)
	reagents.maximum_volume = held_container.reagents.maximum_volume // Update internal reagent distilling volume
	to_chat(user, span_notice("You put \the [held_container] onto \the [src]."))
	if(held_container.reagents.total_volume > 0)
		start_boiling()
	else
		update_icon()

/obj/machinery/bunsen_burner/wrench_act(mob/user, obj/item/tool)
	. = ..()
	if(. != ITEM_INTERACT_SUCCESS)
		return .
	if(!anchored)
		drop_held_container()
		if(heating)
			end_boil()
	return .

/obj/machinery/bunsen_burner/screwdriver_act(mob/user, obj/item/tool)
	return ..()

/obj/machinery/bunsen_burner/crowbar_act(mob/user, obj/item/tool)
	if(!panel_open || !isturf(loc))
		return ITEM_INTERACT_BLOCKING
	if(!do_after(user, 5 * tool.toolspeed, target = src))
		return ITEM_INTERACT_BLOCKING
	drop_held_container()
	to_chat(user, span_notice("You disassemble \the [src]."))
	new /obj/item/stack/material/steel(get_turf(src), 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/bunsen_burner/attack_hand(mob/user)
	if(..())
		return
	add_fingerprint(user)
	if(!held_container)
		to_chat(user, span_notice("There is nothing on \the [src]."))
		return

	// Take it off
	to_chat(user, span_notice("You remove \the [held_container] from \the [src]."))
	held_container.forceMove(get_turf(src))
	held_container.attack_hand(user) // Pick it up
	held_container = null

	// Removed beaker, so kill processing
	if(heating)
		end_boil()
		return
	update_icon()

/obj/machinery/bunsen_burner/proc/start_boiling()
	if(!held_container)
		return
	if(heating)
		return

	// Begin boiling: the flame is a heat source on the burner's heat body.
	visible_message(span_notice("\The [src] starts to heat \the [held_container]."))
	heating = TRUE
	if(create_heat_body(TRUE))
		vg_heat_body_keep(heat_body, TRUE)
		vg_heat_body_power(heat_body, heat_power)
	update_icon()

/obj/machinery/bunsen_burner/proc/drop_held_container()
	if(!held_container)
		return
	held_container.forceMove(get_turf(src))
	held_container = null

/obj/machinery/bunsen_burner/process()
	if(!heating)
		return

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
	heating = FALSE
	bunsen_last_temp = null
	if(!isnull(heat_body))
		vg_heat_body_power(heat_body, 0)
		vg_heat_body_keep(heat_body, FALSE)
	visible_message(span_notice("\The [src] clicks."))
	update_icon()

/obj/machinery/bunsen_burner/update_icon()
	cut_overlays()
	icon_state = "bunsen0"
	if(held_container)
		var/image/I = image("icon"=held_container)
		add_overlay(I)
	if(heating)
		var/image/I = image(icon, icon_state = "bunsen1", layer = layer+0.1)
		add_overlay(I)

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
