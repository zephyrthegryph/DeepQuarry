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
/// null. A dead handle (dropped) reads as null from Rust and is
/// cleared lazily.
/atom/var/heat_body
/// Written only through set_heat_body(): reactive code reads the temperature as a band (watched()), not the handle, so nothing generates it.


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
	// Sensings following this object move onto the new body.
	for(var/datum/sense_sub/heat/sub as anything in heat_subs?.Copy())
		sub.rearm()
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

/// Logs bodies dropped on deletion (`report` is Rust's line per body that held heat over its surroundings, null when none did).
/proc/heat_drop_log(report)
	if(istext(report) && length(report))
		log_world("HEAT DROPPED on deletion (nothing transferred): [report]")

/// Drops this atom's heat body. DELETION IS NOT A PHYSICAL EVENT: whatever the body holds over its surroundings is discarded, never deposited
/// into the tile, the floor or a container (only the exchange a relaxing body had already made is booked). A real transformation that leaves
/// remains (gibs, ash, melt) carries the heat on explicitly with inherit_heat() before the source goes. In a batched destroy the drop is the
/// batch's one call.
/atom/proc/drop_heat_body()
	if(isnull(heat_body))
		return
	dq_heat_bind_forget(src)
	dq_heat_body_drop(src, heat_body)
	set_heat_body(null)

/// This atom starts at `temperature` K: the product of a real transformation (gibs, ash, a melt) inheriting its source's temperature. The
/// heat it needs comes with the transformation, not from the surroundings. Does nothing for a null temperature or one it is already at.
/atom/proc/inherit_heat(temperature)
	if(!isnum(temperature) || QDELETED(src))
		return
	var/delta = temperature - get_temperature()
	if(abs(delta) < 0.05)
		return
	var/list/properties = thermal_properties()
	var/capacity = properties[THERMAL_CAPACITY]
	if(!(capacity > 0))
		return
	add_heat(capacity * delta)
	log_world("HEAT INHERITED: [type] started at [round(temperature, 0.1)] K ([round(capacity * delta)] J) from its source")

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

// ---------------------------------------------------------------- sensing
// A heat body's temperature is sensed with sense_heat() (heat_sense.dm).

/// The temperature channel of a heat world kind (a channel index Rust owns).
/proc/heat_temperature_channel(code)
	var/static/list/channels
	if(!channels)
		channels = list()
	var/found = channels["[code]"]
	if(isnull(found))
		found = vg_world_channel(code, "temperature")
		channels["[code]"] = found
	return found
