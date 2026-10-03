// The gas threshold watch capability (unified plan, live simulation).
//
//	/obj/machinery/air_sensor/valve_control/capabilities()
//		. = ..()
//		. += watches_gas(port = NORTH, when = PRESSURE_ABOVE, level = 4500, hysteresis = 50, callback = PROC_REF(open_relief))
//
// Rust fires open_relief(watch, reason, source, source_kind) on the holder at the exact crossing of
// `level` by the pressure (or temperature) of the mixture at `port`; no step polls it. After a
// crossing the watch fires again only once the value has left the band `hysteresis` wide (-1: the
// channel's own). `port` is the direction of the holder's pipe connection, or null for the holder's
// own air (return_air()).
//
// The watch lives in the holder's cap_data. It follows the port: when the holder's air is pointed
// at another mixture (a pipe network rebuilt, a device joining one) atmos_air_set() re-arms it. A
// port with no mixture yet has no watch until it gets one. Holder deletion cancels it.
//
// The capability finds a device's ports itself (mixture_at(): a binary or unary pipe device's air, else the holder's own
// return_air()); a holder with other ports declares a subtype overriding mixture_at().

/// `when` values for watches_gas().
#define PRESSURE_ABOVE 1
#define PRESSURE_BELOW 2
#define TEMPERATURE_ABOVE 3
#define TEMPERATURE_BELOW 4


/datum/capability/watches_gas
	data_type = /datum/gas_watch_state
	/// The holder's pipe port (a direction), or null for its own air.
	var/port
	/// CH_GAS_* channel watched.
	var/channel = CH_GAS_PRESSURE
	/// WORLD_CMP_ABOVE / WORLD_CMP_BELOW.
	var/cmp = WORLD_CMP_ABOVE
	var/level = 0
	/// In the channel's unit; -1 takes the channel's own.
	var/hysteresis = -1
	/// The holder proc (watch, reason, source, source_kind) to call on a crossing.
	var/callback
	/// The OM lane the wake is delivered on. Urgent: a sensor's crossing is what a valve or an alarm
	/// acts on, and urgent wakes drain in full every pass.
	var/lane = LANE_URGENT

/**
 * A threshold watch on the gas at `port` of the holder. `when` is PRESSURE_ABOVE / PRESSURE_BELOW
 * (kPa) or TEMPERATURE_ABOVE / TEMPERATURE_BELOW (K); `callback` is PROC_REF(proc) on the holder,
 * called (watch, reason, source, source_kind) at the exact crossing of `level`.
 */
/proc/watches_gas(port, when = PRESSURE_ABOVE, level, hysteresis = -1, callback)
	var/datum/capability/watches_gas/C = new
	C.port = port
	C.level = level
	C.hysteresis = hysteresis
	C.callback = callback
	switch(when)
		if(PRESSURE_ABOVE)
			C.channel = CH_GAS_PRESSURE
			C.cmp = WORLD_CMP_ABOVE
		if(PRESSURE_BELOW)
			C.channel = CH_GAS_PRESSURE
			C.cmp = WORLD_CMP_BELOW
		if(TEMPERATURE_ABOVE)
			C.channel = CH_GAS_TEMPERATURE
			C.cmp = WORLD_CMP_ABOVE
		if(TEMPERATURE_BELOW)
			C.channel = CH_GAS_TEMPERATURE
			C.cmp = WORLD_CMP_BELOW
		else
			CRASH("watches_gas: unknown `when` [when]")
	C.key = "watches_gas:[isnull(port) ? "air" : port]:[when]:[level]"
	return C

/// The gas mixture at pipe port `port` (a direction) of holder, or null. With no port: a pipe device's own air, else the
/// holder's return_air().
/datum/capability/watches_gas/proc/mixture_at(atom/holder, port)
	var/obj/machinery/atmospherics/binary/B = holder
	if(istype(B))
		if(isnull(port) || port == turn(B.dir, 180))
			return B.air1
		return port == B.dir ? B.air2 : null
	var/obj/machinery/atmospherics/unary/U = holder
	if(istype(U))
		return (isnull(port) || port == U.dir) ? U.air_contents : null
	return holder.return_air()

/// The per-holder watch: its Rust subscription and the mixture it is armed on.
/datum/gas_watch_state
	/// The world watch on the port's mixture, or null while the port has none.
	var/tmp/datum/native_watch/world/watch
	/// Arena id of the mixture `watch` is on (a number, not a reference to the mixture).
	var/armed_id

/datum/gas_watch_state/relations()
	. = ..()
	. += rel_one(nameof(watch), /datum/native_watch/world, kind = RELK_OWNED, policy = OWN_DELETE)

/// Points the watch at the mixture at the port now: nothing changes when it is the one already
/// watched. A port that lost its mixture drops the watch.
/datum/gas_watch_state/proc/rearm(atom/holder, datum/capability/watches_gas/C)
	var/datum/gas_mixture/mixture = C.mixture_at(holder, C.port)
	var/id = mixture ? mixture.arena_id() : null
	if(id == armed_id && (watch || isnull(id)))
		return
	own_clear(src, nameof(watch), OWN_DELETE)
	armed_id = id
	if(!mixture)
		return
	rel_set(src, nameof(watch), om_watch_gas(holder, mixture, C.channel, C.cmp, C.level, C.callback, C.hysteresis, C.lane))

/datum/capability/watches_gas/on_holder_init(atom/holder, mapload)
	var/datum/gas_watch_state/state = cap_data(holder, src)
	state.rearm(holder, src)

/datum/capability/watches_gas/on_holder_destroy(atom/holder)
	var/datum/gas_watch_state/state = holder.cap_data?[key]
	if(state)
		own_clear(state, nameof(/datum/gas_watch_state::watch), OWN_DELETE)
		state.armed_id = null

/// A holder's gas ports were pointed at other mixtures (atmos_air_set): re-arm each of its gas watches.
/proc/gas_watch_rearm(atom/holder)
	for(var/key in holder.cap_data)
		var/datum/gas_watch_state/state = holder.cap_data[key]
		if(!istype(state))
			continue
		var/datum/capability/watches_gas/C = cap_of(holder, key)
		if(C)
			state.rearm(holder, C)
