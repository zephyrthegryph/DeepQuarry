#define REACTOR_MODE_INTAKE 0
#define REACTOR_MODE_OUTPUT 1

/obj/machinery/reagent_refinery/reactor
	name = "Industrial Chemical Reactor"
	desc = "A reinforced chamber for high temperature distillation. Can be connected to a pipe network to change the interior atmosphere. It outputs chemicals on a timer, to allow for distillation."
	icon_state = "reactor"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 0
	active_power_usage = 500
	circuit = /obj/item/circuitboard/industrial_reagent_reactor
	default_max_vol = REAGENT_VAT_VOLUME
	reagent_type = /datum/reagents/distilling

	VAR_PRIVATE/obj/machinery/portable_atmospherics/canister/internal_tank
	VAR_PRIVATE/toggle_mode = REACTOR_MODE_INTAKE
	VAR_PRIVATE/next_mode_toggle = 0

	VAR_PRIVATE/dis_time = 30
	VAR_PRIVATE/drain_time = 10

CAPABILITIES(/obj/machinery/reagent_refinery/reactor)
	default_parts()
	owns_one(nameof(internal_tank), /obj/machinery/portable_atmospherics/canister)
	climb()

/obj/machinery/reagent_refinery/reactor/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(internal_tank), new /obj/machinery/portable_atmospherics/canister/empty())
	update_gas_network()
	COOLDOWN_START(src, next_mode_toggle, dis_time SECONDS)

/obj/machinery/reagent_refinery/reactor/refinery_step()
	if(!anchored)
		return

	power_change()
	if(!operable())
		return

	if(COOLDOWN_FINISHED(src, next_mode_toggle))
		if(toggle_mode == REACTOR_MODE_INTAKE)
			if(reagents && reagents.total_volume > 0 && amount_per_transfer_from_this > 0)
				set_toggle_mode(REACTOR_MODE_OUTPUT) // Only drain if anything in it!
			COOLDOWN_START(src, next_mode_toggle, drain_time SECONDS)
		else
			set_toggle_mode(REACTOR_MODE_INTAKE)
			COOLDOWN_START(src, next_mode_toggle, dis_time SECONDS)

	if(amount_per_transfer_from_this <= 0 || reagents.total_volume <= 0)
		return

	if(toggle_mode == REACTOR_MODE_INTAKE)
		// perform reactions
		reagents.handle_reactions()
	else
		// dump reagents to next refinery machine
		var/obj/machinery/reagent_refinery/target = locate_within(get_step(loc,dir), /obj/machinery/reagent_refinery)
		if(target)
			transfer_tank( reagents, target, dir)

TRACKED(/obj/machinery/reagent_refinery/reactor, toggle_mode)

/obj/machinery/reagent_refinery/reactor/draw(datum/look/look)
	..()
	// Get main dir pipe
	var/image/pipe = image(icon, icon_state = "reactor_cons", dir = dir)
	look.overlay(pipe)
	if(anchored)
		if(operable())
			var/image/dot = image(icon, icon_state = "vat_dot_[ toggle_mode > REACTOR_MODE_INTAKE ? "on" : "off" ]") // Show refinery output mode
			look.overlay(dot)
		look.overlay(update_input_connection_overlays(look, "reactor_intakes"))

/obj/machinery/reagent_refinery/reactor/handle_transfer(atom/origin_machine, datum/reagents/RT, source_forward_dir, transfer_rate, filter_id = "")
	// no back/forth, filters don't use just their forward, they send the side too!
	if(dir == GLOB.reverse_dir[source_forward_dir])
		return 0
	// locked until distilling mode
	if(toggle_mode == REACTOR_MODE_OUTPUT)
		return 0
	. = ..(origin_machine, RT, source_forward_dir, transfer_rate, filter_id)

/obj/machinery/reagent_refinery/reactor/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u. It is pumping chemicals at a rate of [amount_per_transfer_from_this]u."
	var/datum/gas_mixture/GM = internal_tank.return_air()
	. += "The internal temperature is [GM.return_temperature()]k at [GM.return_pressure()]kpa. It is currently in a [toggle_mode ? "pumping cycle, outputting stored chemicals" : "distilling cycle, accepting input chemicals"]."
	tutorial(REFINERY_TUTORIAL_SINGLEOUTPUT, .)

/obj/machinery/reagent_refinery/reactor/rewrenched()
	update_gas_network()
	set_toggle_mode(REACTOR_MODE_INTAKE)
	COOLDOWN_START(src, next_mode_toggle, dis_time SECONDS)

/obj/machinery/reagent_refinery/reactor/proc/update_gas_network()
	if(!internal_tank)
		return
	// think of this as we JUST anchored/deanchored
	var/obj/machinery/atmospherics/portables_connector/pad = locate_within(get_turf(src), /obj/machinery/atmospherics/portables_connector)
	if(pad && !pad.connected_device)
		if(anchored)
			// Perform the connection, forcibly... we're ignoring adjacency checks with this
			rel_set(internal_tank, nameof(internal_tank.connected_port), pad)
			rel_set(pad, nameof(pad.connected_device), internal_tank)
			pad.set_on(1) //Activate port updates
			// Actually enforce the air sharing
			pad.rust_attach_external_device(internal_tank)
			// Sfx
			play_sfx(src, SFX_MECHA_GASCONNECTED)
		else
			internal_tank.disconnect()
			play_sfx(src, SFX_MECHA_GASDISCONNECTED)
	else if(internal_tank.connected_port())
		internal_tank.disconnect() // How did we get here? qdelled pad?
		play_sfx(src, SFX_MECHA_GASDISCONNECTED)

/obj/machinery/reagent_refinery/reactor/return_air()
	if(internal_tank)
		return internal_tank.return_air()
	. = ..()

#undef REACTOR_MODE_INTAKE
#undef REACTOR_MODE_OUTPUT

/// Busy while it holds reagents: it cycles between reacting and draining on its own timer.
/obj/machinery/reagent_refinery/reactor/refinery_busy()
	return reagents.total_volume > 0
