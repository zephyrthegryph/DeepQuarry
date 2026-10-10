// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/// Fast enough that two loops of station gas meet within a step or two, as the old full mix per air tick did.
#define HEAT_EXCHANGER_CONDUCTANCE 5000

/obj/machinery/atmospherics/unary/heat_exchanger

	icon = 'icons/obj/atmospherics/heat_exchanger.dmi'
	icon_state = "intact"
	pipe_state = "heunary"
	density = TRUE

	name = "Heat Exchanger"
	desc = "Exchanges heat between two input gases. Setup for fast heat transfer"

	var/obj/machinery/atmospherics/unary/heat_exchanger/partner = null
	/// W/K between the two loops' gas (an engineered material's conductance lowers it).
	var/exchange_conductance = HEAT_EXCHANGER_CONDUCTANCE
	/// The first of the pair (by map position): it declares the pair's heat link.
	var/leads_pair = FALSE

TRACKED(/obj/machinery/atmospherics/unary/heat_exchanger, leads_pair)

CAPABILITIES(/obj/machinery/atmospherics/unary/heat_exchanger)
	climb()
	// The pair's loops exchange heat through one link, declared by the first of the two (heat_exchanger_leads()).
	when(nameof(leads_pair), heat_link(HEAT_PORT(1), nameof(partner), nameof(exchange_conductance)))
	links(/obj/machinery/atmospherics/unary/heat_exchanger::partner, /obj/machinery/atmospherics/unary/heat_exchanger::partner)
	pipe_device_unwrench()
	extend("unwrench", needs(req_bool(PROC_REF(floor_clear), because = MSG(air_device/plating))))

/obj/machinery/atmospherics/unary/heat_exchanger/draw(datum/look/look)
	..()
	look.state(node ? "intact" : "exposed")

/obj/machinery/atmospherics/unary/heat_exchanger/atmos_init()
	if(!partner)
		var/partner_connect = turn(dir,180)

		for(var/obj/machinery/atmospherics/unary/heat_exchanger/target in get_step(src,partner_connect))
			if(target.dir & get_dir(src,target))
				rel_set(src, nameof(partner), target)
				break
	update_exchange_conductance()
	set_leads_pair(heat_exchanger_leads())
	partner?.set_leads_pair(partner.heat_exchanger_leads())

	..()

/// Whether this one is the first of its pair (by map position), which declares the pair's heat link.
/// Its floor does not cover it: a pipe-level exchanger under intact tiles cannot be reached.
/obj/machinery/atmospherics/unary/heat_exchanger/proc/floor_clear(datum/act/A)
	var/turf/T = loc // ALLOW(reads): asked when the wrench is used, never from a cached menu; it stays where it was built
	return !(level == 1 && isturf(T) && !T.is_plating()) // ALLOW(reads): the exchanger level is fixed by where it was built; asked when the wrench is used

/obj/machinery/atmospherics/unary/heat_exchanger/proc/heat_exchanger_leads()
	if(!partner)
		return FALSE
	return x + y * world.maxx + z * world.maxx * world.maxy < partner.x + partner.y * world.maxx + partner.z * world.maxx * world.maxy

/// The link's conductance follows an engineered material's: the weaker side's conductance against stock.
/obj/machinery/atmospherics/unary/heat_exchanger/proc/update_exchange_conductance()
	var/datum/material/our_material = engineered_material()
	var/datum/material/their_material = partner?.engineered_material()
	var/fraction = 1
	if(our_material || their_material)
		var/our_conductance = our_material ? our_material.thermal_conductance(1, 0.005, T20C) / 1000 : 50
		var/their_conductance = their_material ? their_material.thermal_conductance(1, 0.005, T20C) / 1000 : 50
		fraction = clamp(min(our_conductance, their_conductance) / 50, 0.02, 1)
	exchange_conductance = HEAT_EXCHANGER_CONDUCTANCE * fraction

/// It comes off its pipe whether or not its loops run (only its gas holds it).
/obj/machinery/atmospherics/unary/heat_exchanger/pipe_device_idle(datum/act/A)
	return TRUE
