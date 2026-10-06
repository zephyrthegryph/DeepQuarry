// The power domain's producer and consumer accounting (doc/rewrite/final_api.html section 22: the power system's api lives in its domain).
// Every generator, collector and consumer of the cable network books its watts here; Rust (verdigris/domains/power) settles the network.
//
//   set_power_supply(watts)   a persistent supply rate: it stays until changed, so a steady generator can sleep (PACMANs, solar
//                             controllers, the TEG). Repeating the same rate is free.
//   add_avail(watts)          a supply for the next power step only: a pulse source (radiation collectors, tesla coils, the fusion core, RTGs,
//                             the gas turbine) books it every step it produces.
//   draw_power(watts)         takes what the network can give now, for a machine that draws on its cables directly (an emitter's
//                             capacitor); returns what it got.

/// Supply for the next power step only (pulse sources: coils, collectors,
/// fusion). A producer that runs every tick calls it every tick, as before.
/obj/machinery/power/proc/add_avail(amount)
	if(!power_region || amount <= 0 || !vg_entity)
		return FALSE
	native_write(src, NATIVE_PRODUCER_PULSE, amount)
	return TRUE

/// A persistent supply rate (W): it stays until changed, so a steady
/// generator can sleep. Repeating the same rate is free.
/obj/machinery/power/proc/set_power_supply(amount)
	amount = max(amount, 0)
	if(amount == power_supply_rate)
		return
	power_supply_rate = amount
	if(vg_entity)
		native_write(src, NATIVE_PRODUCER_SUPPLY, amount)

/obj/machinery/power/proc/clear_power_supply()
	set_power_supply(0)

/obj/machinery/power/proc/draw_power(amount)
	return power_draw(power_region, amount, src)

