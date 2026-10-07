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

TRACKED(/atom, heat_body)

// ---------------------------------------------------------------- the API

/// This atom's temperature in kelvin: its heat body's, or, with none, the
/// temperature its surroundings impose.
/atom/proc/get_temperature()
	if(!isnull(heat_body))
		HEAT_BODY_RESOLVE(src)
		var/temperature = vg_heat_body_temperature(heat_body)
		if(!isnull(temperature))
			return temperature
		set_heat_body(null)
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
		set_heat_body(null)
	if(!create_heat_body())
		return 0
	return vg_heat_body_add(heat_body, joules) ? joules : 0

/// list(heat capacity J/K, conductance to the surroundings W/K, emissivity).
/// Items take theirs from their materials (heat_objects.dm).
/atom/proc/thermal_properties()
	return GLOB.default_thermal_properties

/// The default thermal_properties(). Shared, read-only.
GLOBAL_LIST_INIT(default_thermal_properties, list(THERMAL_CAPACITY_DEFAULT, THERMAL_CONDUCTANCE_DEFAULT, THERMAL_EMISSIVITY_DEFAULT))
/// heat_coupling() of an atom with nothing around it. Shared, read-only.
GLOBAL_LIST_INIT(heat_coupling_none, list(HEAT_TARGET_NONE, 0))


/// This atom's heat capacity changed (reagents added or removed): update its body.
/atom/proc/heat_capacity_changed()
	if(isnull(heat_body))
		return
	HEAT_BODY_RESOLVE(src)
	var/list/properties = thermal_properties()
	if(properties[THERMAL_CAPACITY] > 0)
		vg_heat_body_capacity(heat_body, properties[THERMAL_CAPACITY])

/// Creates this atom's heat body at its surroundings' temperature, coupled to
/// them. Returns TRUE on success.
/atom/proc/create_heat_body(keep = FALSE, start_temperature = null)
	if(!isnull(heat_body))
		return TRUE
	var/list/properties = thermal_properties()
	var/capacity = properties[THERMAL_CAPACITY]
	if(!(capacity > 0))
		return FALSE
	var/list/coupling = heat_coupling()
	var/temperature = isnull(start_temperature) ? get_ambient_temperature() : start_temperature
	var/conductance = heat_path_conductance(properties[THERMAL_CONDUCTANCE])
	// Inside a bind scope (heat_bind_batch.dm) the handle is a pre-reserved body, usable at
	// once; its configuration goes to Rust with the rest of the scope's in one call.
	if(GLOB.dq_heat_bind_depth)
		set_heat_body(dq_heat_body_reserve_for(src, capacity, temperature, coupling[1], coupling[2], conductance, keep))
		if(!isnull(heat_body))
			return TRUE
	set_heat_body(vg_heat_body_create(capacity, temperature, coupling[1], coupling[2], conductance, keep))
	if(isnull(heat_body))
		return FALSE
	heat_body_created()
	return TRUE

/// This atom's heat body now exists in Rust with its real configuration: what follows its
/// arrival (create_heat_body(), or a bind scope's flush for a reserved body).
/atom/proc/heat_body_created()
	// Watches following this object move onto the new body.
	for(var/datum/native_watch/heat/W as anything in heat_watches?.Copy())
		W.relink()
	// Rules watching this object's temperature subscribe to the new body.
	if(dq_rules_for_type(type))
		dq_rules_heat_body_created(src)

/// list(HEAT_TARGET_*, target) this atom's body couples to: its turf's air (or
/// the turf's solid when it has none), or its container's body, or else the
/// container's own surroundings.
/atom/proc/heat_coupling()
	var/atom/holder = loc
	if(isturf(holder))
		var/turf/T = holder
		return T.heat_has_air() ? list(HEAT_TARGET_TURF_AIR, T) : list(HEAT_TARGET_SOLID, T)
	if(isnull(holder))
		return GLOB.heat_coupling_none
	if(!isnull(holder.heat_body))
		return list(HEAT_TARGET_BODY, holder.heat_body)
	return holder.heat_coupling()

/// Re-couples this atom's body after it moved (a no-op without one).
/atom/proc/heat_recouple()
	if(isnull(heat_body))
		return
	HEAT_BODY_RESOLVE(src)
	var/list/coupling = heat_coupling()
	var/list/properties = thermal_properties()
	if(!vg_heat_body_couple(heat_body, 0, coupling[1], coupling[2], heat_path_conductance(properties[THERMAL_CONDUCTANCE])))
		set_heat_body(null)
		return
	// Moving off a burning tile ends the fire coupling.
	var/atom/movable/self = src
	if(istype(self) && !isnull(self.heat_fire_turf) && self.heat_fire_turf != loc)
		self.decouple_from_fire()

/// Releases this atom's heat body: its excess heat goes to its surroundings
/// (in a batched destroy, in the batch's one release call).
/atom/proc/release_heat_body()
	if(isnull(heat_body))
		return
	dq_heat_bind_forget(src)
	dq_heat_body_release(src, heat_body)
	set_heat_body(null)

// ------------------------------------------------------------------ turfs

/// A turf's temperature is its solid's (the heat field), or its seed while it is not in the field yet.
/turf/get_temperature()
	var/live = vg_heat_turf_temperature(src)
	return isnull(live) ? initial_temperature : live

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

/turf/thermal_properties()
	return list(heat_capacity, thermal_conductivity, THERMAL_EMISSIVITY_DEFAULT)

/turf/create_heat_body(keep = FALSE, start_temperature = null)
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
/// the turf's seed (initial_temperature); an existing one keeps its temperature.
/turf/proc/update_heat_cell()
	var/list/properties = thermal_properties()
	return vg_heat_set_turf(src, heat_cell_kind(), properties[THERMAL_CAPACITY], properties[THERMAL_CONDUCTANCE], properties[THERMAL_EMISSIVITY], initial_temperature, heat_has_air())

/// Bulk form of update_heat_cell for round-start setup: one FFI call.
/proc/heat_register_turfs(list/turfs)
	var/list/records = list()
	for(var/turf/T as anything in turfs)
		var/list/properties = T.thermal_properties()
		records += list(T, T.heat_cell_kind(), properties[THERMAL_CAPACITY], properties[THERMAL_CONDUCTANCE], properties[THERMAL_EMISSIVITY], T.initial_temperature, T.heat_has_air())
	return vg_heat_set_turfs_bulk(records)

// ------------------------------------------------------ gas containers

/// Something inside a tank sees its gas.
/obj/item/tank/get_interior_temperature()
	return air_contents ? air_contents.return_temperature() : ..()

/// Something inside a canister sees its gas.
/obj/machinery/portable_atmospherics/canister/get_interior_temperature()
	return air_contents ? air_contents.return_temperature() : ..()

// ---------------------------------------------------------------- watches

/// Native heat watches on this atom (relinked when it gets a new body).
/atom/var/tmp/list/heat_watches

/**
 * A heat watch (code/datums/om/native.dm): a threshold, band or ThresholdSet
 * on a turf's solid or an atom's heat body. Threshold and band watches call
 * `callback` on the owner as (watch, reason, source); a set calls it once
 * per crossed entry as (watch, payload, entered, generation).
 *
 * `keep_body`: the target gets a body now and keeps it while watched. Without
 * it the watch follows whatever body the target has, and waits while it is at
 * rest (reading its surroundings, unwatched).
 */
/datum/native_watch/heat
	delivery_source = NATIVE_SRC_HEAT
	var/atom/target
	var/kind
	var/level
	var/both_edges = FALSE
	var/lane = HEAT_LANE_NORMAL
	var/keep_body = TRUE
	/// The Rust subscription (a world watch token, vg_world_cancel()): non-null while registered.
	var/token
	/// The body the watch is on.
	var/body
	/// ThresholdSet entries: payload -> list(generation, limit, above, both_edges).
	var/list/entries

/datum/native_watch/heat/proc/start(atom/target, kind, level, both_edges, lane, keep_body)
	rel_set(src, nameof(target), target)
	src.kind = kind
	src.level = level
	src.both_edges = both_edges
	src.lane = lane
	src.keep_body = keep_body
	if(!register() && keep_body)
		spent(src)
		return null
	return src

/// `target` and the atom's heat_watches name each other (setting `target` lists the watch there).
CAPABILITIES(/datum/native_watch/heat)
	links(/datum/native_watch/heat::target, /atom::heat_watches, b_many = TRUE)

/// The watch port and cell of this watch's target: a body's world kind and entity, or the turf solid
/// (VG_HEAT_CELLS) and the turf.
/datum/native_watch/heat/proc/port_code()
	return isturf(target) ? VG_HEAT_CELLS : VG_KIND_HEATBODY

/datum/native_watch/heat/proc/port_cell()
	return isturf(target) ? target : body

/// The temperature channel of `port_code()` (a channel index Rust owns).
/proc/heat_temperature_channel(code)
	var/static/list/channels
	if(!channels)
		channels = list()
	var/found = channels["[code]"]
	if(isnull(found))
		found = vg_world_channel(code, "temperature")
		channels["[code]"] = found
	return found

/datum/native_watch/heat/register()
	if(!isturf(target))
		HEAT_BODY_RESOLVE(target)
		if(keep_body)
			if(!target.create_heat_body(TRUE))
				return FALSE
			vg_heat_body_keep(target.heat_body, TRUE)
		else if(!isnull(target.heat_body) && isnull(vg_heat_body_temperature(target.heat_body)))
			target.set_heat_body(null)
		body = target.heat_body
		if(isnull(body))
			return TRUE // at rest: relinked when the target gets a body
	var/code = port_code()
	var/channel = heat_temperature_channel(code)
	var/rust_lane = lane
	switch(kind)
		if(HEAT_WATCH_ABOVE)
			// ALLOW(api): the heat port is the one place that binds heat channels to the Rust world watch
			token = vg_world_watch_threshold(code, handle, rust_lane, port_cell(), channel, WORLD_CMP_ABOVE, level, -1, both_edges)
		if(HEAT_WATCH_BELOW)
			// ALLOW(api): the heat port is the one place that binds heat channels to the Rust world watch
			token = vg_world_watch_threshold(code, handle, rust_lane, port_cell(), channel, WORLD_CMP_BELOW, level, -1, both_edges)
		if(HEAT_WATCH_BAND)
			// ALLOW(api): the heat port is the one place that binds heat channels to the Rust world watch
			token = vg_world_watch_band(code, handle, rust_lane, port_cell(), channel, level, -1)
		if(HEAT_WATCH_SET)
			// ALLOW(api): the heat port is the one place that binds heat channels to the Rust world watch
			token = vg_world_watch_set(code, handle, rust_lane, port_cell(), channel)
	if(isnull(token))
		body = null
		return FALSE
	for(var/payload in entries)
		var/list/entry = entries[payload]
		// ALLOW(api): the heat port is the one place that binds heat channels to the Rust world watch
		vg_world_watch_set_add(token, channel, text2num(payload), entry[1], entry[3] ? WORLD_CMP_ABOVE : WORLD_CMP_BELOW, entry[2], entry[4])
	return TRUE

/datum/native_watch/heat/unregister()
	if(!isnull(token))
		// ALLOW(api): the heat port is the one place that binds heat channels to the Rust world watch
		vg_world_cancel(token)
	token = null
	body = null
	rel_clear(src, nameof(target)) // two-sided: the target's heat_watches lets go too

/// The target's body changed (created, or released at rest): follow it.
/datum/native_watch/heat/proc/relink()
	if(isturf(target) || QDELETED(target) || (!isnull(token) && body == target.heat_body))
		return
	if(!isnull(token))
		// ALLOW(api): the heat port is the one place that binds heat channels to the Rust world watch
		vg_world_cancel(token)
		token = null
		body = null
	register()

/// Adds (or replaces) a ThresholdSet entry: crossing `limit` upwards (`above`) or downwards.
/datum/native_watch/heat/proc/add_entry(payload, generation, limit, above = TRUE, both_edges = FALSE)
	LAZYSET(entries, "[payload]", list(generation, limit, above, both_edges))
	if(!isnull(token))
		// ALLOW(api): the heat port is the one place that binds heat channels to the Rust world watch
		vg_world_watch_set_add(token, heat_temperature_channel(port_code()), payload, generation, above ? WORLD_CMP_ABOVE : WORLD_CMP_BELOW, limit, both_edges)

/datum/native_watch/heat/proc/remove_entry(payload)
	LAZYREMOVE(entries, "[payload]")
	if(!isnull(token))
		// ALLOW(api): the heat port is the one place that binds heat channels to the Rust world watch
		vg_world_watch_set_remove(token, payload)

/// Whether the watch is registered with Rust right now (tests).
/datum/native_watch/heat/proc/is_live()
	return !isnull(token)

/// The frame's record for this watch. A threshold or band wake calls the owner as (reason, source); a
/// ThresholdSet's crossing calls it as (payload, entered, generation), and its plain wakes (every
/// crossing also wakes the watch) are dropped.
/datum/native_watch/heat/crossed(band, list/detail)
	if(length(detail) == NATIVE_CROSSED_SET_DETAIL)
		fire(list(band, detail[1], detail[2]))
		return TRUE
	if(kind == HEAT_WATCH_SET)
		return FALSE
	fire(list(detail[2], detail[3]))
	return TRUE

/// Watches `target`'s temperature for crossing `limit` (upwards if `above`);
/// `callback` runs on `owner` as (watch, reason, source). A turf watches its
/// solid; any other atom its heat body. Returns the watch, or null.
/proc/heat_watch_threshold(datum/owner, atom/target, limit, above, callback, both_edges = FALSE, lane = HEAT_LANE_NORMAL, keep_body = TRUE)
	var/datum/native_watch/heat/W = new(owner, callback)
	return W.start(target, above ? HEAT_WATCH_ABOVE : HEAT_WATCH_BELOW, limit, both_edges, lane, keep_body)

/// Watches `target`'s temperature band over ascending `levels`: fires on every
/// band change, and once at registration.
/proc/heat_watch_band(datum/owner, atom/target, list/levels, callback, lane = HEAT_LANE_NORMAL, keep_body = TRUE)
	var/datum/native_watch/heat/W = new(owner, callback)
	return W.start(target, HEAT_WATCH_BAND, levels, FALSE, lane, keep_body)

/// A ThresholdSet on `target` (add entries with add_entry()); `callback` runs
/// on `owner` as (watch, payload, entered, generation) per crossing.
/proc/heat_watch_set(datum/owner, atom/target, callback, lane = HEAT_LANE_NORMAL)
	var/datum/native_watch/heat/W = new(owner, callback)
	return W.start(target, HEAT_WATCH_SET, 0, FALSE, lane, TRUE)
