// The gas domain's heat exchange between a body and a gas (doc/rewrite/final_api.html section 14, "Gas and heat"): what a machine asks of a gas, so
// that no machine edits a mixture's temperature itself. A minimal piece the cryo cell needed; the gas domain's own API file (gas.dm, with gas_release,
// gas_sample and the heater) declares the same call with the same contract and replaces this file when it lands.

/// A body of `body_temperature` (K) and `body_capacity` (J/K) exchanges heat with `air`: `share` (0..1) of the way to the temperature both would
/// settle at. The gas takes exactly what the body gives up. Returns the body's new temperature (the caller sets it); `air` is changed in place.
/proc/gas_body_heat_exchange(datum/gas_mixture/air, body_temperature, body_capacity, share = 1)
	if(!air || body_capacity <= 0 || share <= 0)
		return body_temperature
	var/gas_capacity = air.heat_capacity()
	if(gas_capacity <= 0)
		return body_temperature
	var/gas_temperature = air.return_temperature()
	var/settled = (body_capacity * body_temperature + gas_capacity * gas_temperature) / (body_capacity + gas_capacity)
	var/body_after = body_temperature + min(share, 1) * (settled - body_temperature)
	air.set_temperature(gas_temperature + body_capacity * (body_temperature - body_after) / gas_capacity)
	return body_after
