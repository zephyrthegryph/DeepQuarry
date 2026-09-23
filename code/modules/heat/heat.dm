// The heat domain's DM API (doc/rewrite/temperature.md §2.1).
//
// Rust (verdigris/domains/heat, vg-heat) owns every simulated temperature: the
// turf solid heat field (conduction, radiation to space, coupling to turf air)
// and heat bodies, the nodes an atom gets only while it diverges from its
// surroundings. DM reads temperatures, adds heat, declares thermal properties,
// and watches thresholds:
//
//   get_temperature()    the atom's temperature (its body's, or its surroundings')
//   add_heat(joules)     a command; creates the heat body on first divergence
//   thermal_properties() list(capacity J/K, conductance W/K, emissivity)
//
// Turfs push their thermal values with update_heat_cell() (the air ref
// registration paths call it); SSair drives frames through process_turf_heat()
// and dispatches watch wakes to subscribers.

/// The vg-heat body handle while this atom diverges from its surroundings, else
/// null. A dead handle (released at equilibrium) reads as null from Rust and is
/// cleared lazily.
/atom/var/heat_body

// ---------------------------------------------------------------- the API

/// This atom's temperature in kelvin: its heat body's, or, with none, the
/// temperature its surroundings impose.
/atom/proc/get_temperature()
	if(!isnull(heat_body))
		var/temperature = vg_heat_body_temperature(heat_body)
		if(!isnull(temperature))
			return temperature
		heat_body = null
	return get_ambient_temperature()

/// The temperature this atom's surroundings impose on it.
/atom/proc/get_ambient_temperature()
	var/atom/holder = loc
	if(isnull(holder))
		return T20C
	return holder.get_interior_temperature()

/// The temperature something inside this atom sees.
/atom/proc/get_interior_temperature()
	return get_temperature()

/// Adds heat (J; negative removes) to this atom. Creates its heat body on first
/// divergence. Returns the joules accepted.
/atom/proc/add_heat(joules)
	if(!joules || !isnum(joules))
		return 0
	if(!isnull(heat_body))
		if(vg_heat_body_add(heat_body, joules))
			return joules
		heat_body = null
	if(!create_heat_body())
		return 0
	return vg_heat_body_add(heat_body, joules) ? joules : 0

/// list(heat capacity J/K, conductance to the surroundings W/K, emissivity).
/// Items derive a default from their size; H3 derives these from materials.
/atom/proc/thermal_properties()
	return list(THERMAL_CAPACITY_DEFAULT, THERMAL_CONDUCTANCE_DEFAULT, THERMAL_EMISSIVITY_DEFAULT)

/obj/item/thermal_properties()
	var/size = max(w_class, 1)
	return list(size * THERMAL_CAPACITY_PER_W_CLASS, size * THERMAL_CONDUCTANCE_PER_W_CLASS, THERMAL_EMISSIVITY_DEFAULT)

/// Creates this atom's heat body at its surroundings' temperature, coupled to
/// them. Returns TRUE on success.
/atom/proc/create_heat_body(keep = FALSE)
	if(!isnull(heat_body))
		return TRUE
	var/list/properties = thermal_properties()
	var/capacity = properties[THERMAL_CAPACITY]
	if(!(capacity > 0))
		return FALSE
	var/list/coupling = heat_coupling()
	heat_body = vg_heat_body_create(capacity, get_ambient_temperature(), coupling[1], coupling[2], properties[THERMAL_CONDUCTANCE], keep)
	return !isnull(heat_body)

/// list(HEAT_TARGET_*, target) this atom's body couples to: its turf's air (or
/// the turf's solid when it has none), or its container's body, or else the
/// container's own surroundings.
/atom/proc/heat_coupling()
	var/atom/holder = loc
	if(isturf(holder))
		var/turf/T = holder
		return T.heat_has_air() ? list(HEAT_TARGET_TURF_AIR, T) : list(HEAT_TARGET_SOLID, T)
	if(isnull(holder))
		return list(HEAT_TARGET_NONE, 0)
	if(!isnull(holder.heat_body))
		return list(HEAT_TARGET_BODY, holder.heat_body)
	return holder.heat_coupling()

/// Re-couples this atom's body after it moved (a no-op without one).
/atom/proc/heat_recouple()
	if(isnull(heat_body))
		return
	var/list/coupling = heat_coupling()
	var/list/properties = thermal_properties()
	if(!vg_heat_body_couple(heat_body, 0, coupling[1], coupling[2], properties[THERMAL_CONDUCTANCE]))
		heat_body = null

/// Releases this atom's heat body: its excess heat goes to its surroundings.
/atom/proc/release_heat_body()
	if(isnull(heat_body))
		return
	vg_heat_body_release(heat_body)
	heat_body = null

// ------------------------------------------------------------------ turfs

/// A turf's temperature is its solid's (the heat field), or its temperature
/// var when it is not in the field.
/turf/get_temperature()
	var/temperature = vg_heat_turf_temperature(src)
	return isnull(temperature) ? src.temperature : temperature

/// Something on a turf sees the turf's air, or its solid when it has none.
/turf/get_interior_temperature()
	var/datum/gas_mixture/air = heat_has_air() ? return_air() : null
	if(air && air.heat_capacity() > 0)
		return air.return_temperature()
	return get_temperature()

/turf/add_heat(joules)
	if(!joules || !isnum(joules))
		return 0
	return vg_heat_add_turf(src, joules) ? joules : 0

/// Sets the solid temperature (DM authority: map load, holodeck programs, admin).
/turf/proc/set_temperature(new_temperature)
	temperature = new_temperature
	return vg_heat_set_turf_temperature(src, new_temperature)

/turf/thermal_properties()
	return list(heat_capacity, thermal_conductivity, THERMAL_EMISSIVITY_DEFAULT)

/turf/heat_coupling()
	return list(HEAT_TARGET_NONE, 0)

/turf/create_heat_body(keep = FALSE)
	return FALSE

/// HEAT_CELL_* kind of this turf's solid.
/turf/proc/heat_cell_kind()
	return HEAT_CELL_SOLID

/turf/open/heat_cell_kind()
	// Immutable air on a non-space turf is a planet surface: a reservoir.
	return immutable_atmos ? HEAT_CELL_PLANET : HEAT_CELL_SOLID

/turf/space/heat_cell_kind()
	return HEAT_CELL_SPACE

/// Whether this turf's solid couples to air on it.
/turf/proc/heat_has_air()
	return FALSE

/turf/open/heat_has_air()
	return !blocks_air && !isnull(air)

/// Pushes this turf's thermal values into the heat field. A new cell starts at
/// the turf's temperature var; an existing one keeps its temperature.
/turf/proc/update_heat_cell()
	var/list/properties = thermal_properties()
	return vg_heat_set_turf(src, heat_cell_kind(), properties[THERMAL_CAPACITY], properties[THERMAL_CONDUCTANCE], properties[THERMAL_EMISSIVITY], temperature, heat_has_air())

/// Bulk form of update_heat_cell for round-start setup: one FFI call.
/proc/heat_register_turfs(list/turfs)
	var/list/records = list()
	for(var/turf/T as anything in turfs)
		var/list/properties = T.thermal_properties()
		records += list(T, T.heat_cell_kind(), properties[THERMAL_CAPACITY], properties[THERMAL_CONDUCTANCE], properties[THERMAL_EMISSIVITY], T.temperature, T.heat_has_air())
	return vg_heat_set_turfs_bulk(records)

// ------------------------------------------------------ gas containers

/// Something inside a tank sees its gas.
/obj/item/tank/get_interior_temperature()
	return air_contents ? air_contents.return_temperature() : ..()

/// Something inside a canister sees its gas.
/obj/machinery/portable_atmospherics/canister/get_interior_temperature()
	return air_contents ? air_contents.return_temperature() : ..()

// ---------------------------------------------------------------- watches

/// Subscriber index -> datum, for heat watch wakes.
GLOBAL_LIST_EMPTY(heat_subscribers)
/// Free subscriber indices.
GLOBAL_LIST_EMPTY(heat_subscriber_free)
/// "[watch handle]" -> subscriber index, for ThresholdSet crossings.
GLOBAL_LIST_EMPTY(heat_watch_owners)

/// This datum's heat subscriber index (0: none).
/datum/var/heat_subscriber = 0

/// The datum's subscriber index, allocated on first use.
/datum/proc/heat_subscriber_index()
	if(heat_subscriber)
		return heat_subscriber
	var/index
	if(length(GLOB.heat_subscriber_free))
		index = GLOB.heat_subscriber_free[length(GLOB.heat_subscriber_free)]
		GLOB.heat_subscriber_free.len--
		GLOB.heat_subscribers[index] = src
	else
		GLOB.heat_subscribers += src
		index = length(GLOB.heat_subscribers)
	heat_subscriber = index
	return index

/// Frees the datum's subscriber index (its watches must be removed first).
/datum/proc/heat_unsubscribe()
	if(!heat_subscriber)
		return
	GLOB.heat_subscribers[heat_subscriber] = null
	GLOB.heat_subscriber_free += heat_subscriber
	heat_subscriber = 0

/// Watches `target`'s temperature for crossing `limit` (upwards if `above`).
/// A turf watches its solid; any other atom its heat body (kept while watched).
/// Returns the watch handle. on_heat_wake(watch, reason, source) is called.
/datum/proc/heat_watch_threshold(atom/target, limit, above = TRUE, both_edges = FALSE, lane = HEAT_LANE_NORMAL)
	return heat_watch(target, above ? HEAT_WATCH_ABOVE : HEAT_WATCH_BELOW, limit, both_edges, lane)

/// Watches `target`'s temperature band over ascending `levels`: wakes on every
/// band change, and once at registration.
/datum/proc/heat_watch_band(atom/target, list/levels, lane = HEAT_LANE_NORMAL)
	return heat_watch(target, HEAT_WATCH_BAND, levels, FALSE, lane)

/// A ThresholdSet on `target`: add entries with heat_watch_set_add(); crossings
/// call on_heat_crossing(watch, payload, entered, generation).
/datum/proc/heat_watch_set(atom/target, lane = HEAT_LANE_NORMAL)
	return heat_watch(target, HEAT_WATCH_SET, 0, FALSE, lane)

/datum/proc/heat_watch(atom/target, kind, level, both_edges, lane)
	var/subscriber = heat_subscriber_index()
	var/watch
	if(isturf(target))
		watch = vg_heat_watch(FALSE, target, subscriber, lane, kind, level, both_edges)
	else
		if(!target.create_heat_body(TRUE))
			return null
		vg_heat_body_keep(target.heat_body, TRUE)
		watch = vg_heat_watch(TRUE, target.heat_body, subscriber, lane, kind, level, both_edges)
	if(!isnull(watch))
		GLOB.heat_watch_owners["[watch]"] = subscriber
	return watch

/proc/heat_watch_set_add(watch, payload, generation, limit, above = TRUE, both_edges = FALSE)
	return vg_heat_watch_set_add(watch, payload, generation, above ? HEAT_WATCH_ABOVE : HEAT_WATCH_BELOW, limit, both_edges)

/proc/heat_unwatch(watch)
	GLOB.heat_watch_owners -= "[watch]"
	return vg_heat_unwatch(watch)

/// A heat watch fired. `reason` is the vg-core reason mask, `source` the cell
/// or body slot.
/datum/proc/on_heat_wake(watch, reason, source)
	return

/// A ThresholdSet entry was crossed (`entered`: TRUE entering, FALSE leaving).
/datum/proc/on_heat_crossing(watch, payload, entered, generation)
	return

// ------------------------------------------------------------------ ticks

/datum/controller/subsystem/air/var/heat_last_tick = 0

/// Advances the heat domain by the game time since the last call, then hands
/// any watch wakes to their subscribers.
/datum/controller/subsystem/air/proc/process_turf_heat()
	var/now = world.time
	var/elapsed = heat_last_tick ? (now - heat_last_tick) / (1 SECONDS) : wait / (1 SECONDS)
	heat_last_tick = now
	if(vg_heat_tick(elapsed) > 0)
		dispatch_heat_wakes()

/// Delivers collected heat wakes and ThresholdSet crossings.
/datum/controller/subsystem/air/proc/dispatch_heat_wakes()
	var/list/flat = vg_heat_take_wakes()
	var/wakes = length(flat) ? flat[1] : 0
	var/i = 2
	for(var/n in 1 to wakes)
		var/datum/subscriber = GLOB.heat_subscribers.len >= flat[i] ? GLOB.heat_subscribers[flat[i]] : null
		if(subscriber && !QDELETED(subscriber))
			subscriber.on_heat_wake(flat[i + 1], flat[i + 2], flat[i + 3])
		i += 4
	while(i + 3 <= length(flat))
		var/index = GLOB.heat_watch_owners["[flat[i]]"]
		var/datum/subscriber = index && GLOB.heat_subscribers.len >= index ? GLOB.heat_subscribers[index] : null
		if(subscriber && !QDELETED(subscriber))
			subscriber.on_heat_crossing(flat[i], flat[i + 1], flat[i + 2], flat[i + 3])
		i += 4
