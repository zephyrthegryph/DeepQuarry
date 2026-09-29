// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/obj/machinery/atmospherics/unary/heat_exchanger

	icon = 'icons/obj/atmospherics/heat_exchanger.dmi'
	icon_state = "intact"
	pipe_state = "heunary"
	density = TRUE

	name = "Heat Exchanger"
	desc = "Exchanges heat between two input gases. Setup for fast heat transfer"

	var/obj/machinery/atmospherics/unary/heat_exchanger/partner = null
	var/update_cycle
	gas_dependency_mask = GAS_DEPENDENCY_ALL

/obj/machinery/atmospherics/unary/heat_exchanger/Initialize(mapload)
	. = ..()
	make_climbable()

/obj/machinery/atmospherics/unary/heat_exchanger/update_icon()
	if(node)
		icon_state = "intact"
	else
		icon_state = "exposed"

	return

/obj/machinery/atmospherics/unary/heat_exchanger/atmos_init()
	if(!partner)
		var/partner_connect = turn(dir,180)

		for(var/obj/machinery/atmospherics/unary/heat_exchanger/target in get_step(src,partner_connect))
			if(target.dir & get_dir(src,target))
				rel_set(src, "partner", target)
				break

	..()

/obj/machinery/atmospherics/unary/heat_exchanger/machine_step()
	..()
	if(!partner)
		return 0

	if(!SSair || SSair.times_fired <= update_cycle)
		return 0

	update_cycle = SSair.times_fired
	partner.update_cycle = SSair.times_fired

	var/air_heat_capacity = air_contents.heat_capacity()
	var/other_air_heat_capacity = partner.air_contents.heat_capacity()
	var/combined_heat_capacity = other_air_heat_capacity + air_heat_capacity

	var/old_temperature = air_contents.return_temperature()
	var/other_old_temperature = partner.air_contents.return_temperature()
	if(combined_heat_capacity <= 0 || abs(old_temperature - other_old_temperature) <= 0.1)
		register_gas_dependencies()
		return PROCESS_KILL

	if(combined_heat_capacity > 0)
		var/combined_energy = other_old_temperature*other_air_heat_capacity + air_heat_capacity*old_temperature

		var/new_temperature = combined_energy/combined_heat_capacity
		var/datum/material/our_material = engineered_material()
		var/datum/material/their_material = partner.engineered_material()
		var/transfer_fraction = 1
		if(our_material || their_material)
			var/our_conductance = our_material ? our_material.thermal_conductance(1, 0.005, old_temperature) / 1000 : 50
			var/their_conductance = their_material ? their_material.thermal_conductance(1, 0.005, other_old_temperature) / 1000 : 50
			transfer_fraction = clamp(min(our_conductance, their_conductance) / 50, 0.02, 1)
		air_contents.set_temperature(old_temperature + (new_temperature - old_temperature) * transfer_fraction)
		partner.air_contents.set_temperature(other_old_temperature + (new_temperature - other_old_temperature) * transfer_fraction)

	if(network)
		if(abs(old_temperature-air_contents.return_temperature()) > 1)
			network.mark_dirty()

	if(partner.network)
		if(abs(other_old_temperature-partner.air_contents.return_temperature()) > 1)
			partner.network.mark_dirty()

	if(abs(air_contents.return_temperature() - partner.air_contents.return_temperature()) <= 0.1)
		register_gas_dependencies()
		return PROCESS_KILL

	return 1

/// Wakes on either side of the exchange: its own contents or its partner's.
/obj/machinery/atmospherics/unary/heat_exchanger/gas_wake_mixtures()
	return partner ? list(air_contents, partner.air_contents) : list(air_contents)

/// The same test process() makes before it exchanges heat: both sides can hold heat and differ
/// by more than the settle margin it hibernates under.
/obj/machinery/atmospherics/unary/heat_exchanger/gas_wake_condition()
	if(!partner || air_contents.heat_capacity() <= 0 || partner.air_contents.heat_capacity() <= 0)
		return FALSE
	return abs(air_contents.return_temperature() - partner.air_contents.return_temperature()) > 0.1

/obj/machinery/atmospherics/unary/heat_exchanger/wrench_act(mob/user, obj/item/W)
	var/turf/T = src.loc
	if (level==1 && isturf(T) && !T.is_plating())
		to_chat(user, span_warning("You must remove the plating first."))
		return ITEM_INTERACT_BLOCKING
	if (!can_unwrench())
		to_chat(user, span_warning("You cannot unwrench \the [src], it is too exerted due to internal pressure."))
		add_fingerprint(user)
		return ITEM_INTERACT_BLOCKING
	use_tool(user, W, src, delay = 40, volume = 50, start_self = "You begin to unfasten \the [src]...", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/unary/heat_exchanger/proc/wrench_act_tool_done(mob/user)
	act_message(user, src, MSG_SELF(span_notice("You have unfastened %T%.")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " unfastens %T%.")), \
		MSG_BLIND("You hear a ratchet."))
	atom_deconstruct()

REL_PAIR(/obj/machinery/atmospherics/unary/heat_exchanger, partner, partner)
