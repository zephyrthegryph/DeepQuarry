// Heat stores: a Rust heat body kept by a datum that is not an atom (a material batch, an assembly's material service) by its handle, a plain
// number (doc/rewrite/temperature.md §7). Rust holds its energy and integrates the heat links it makes each world step; the owner reads and
// changes it only through these procs, which book every joule.
//
//   heat_store_create(capacity, kelvin, phase_kelvin = 0, latent = 0)  a body of `capacity` J/K at `kelvin`, with an optional phase plateau:
//                                                                       its handle, or null
//   heat_store_temperature(h)  heat_store_latent(h)  heat_store_energy(h)   reads: K, the latent heat its plateau holds (J), energy (J)
//   heat_store_add(h, joules, source)                                    booked heat in (negative: out); returns the joules applied
//   heat_store_set_temperature(h, kelvin, source)                        an authority write, booked
//   heat_store_set_capacity(h, capacity)  heat_store_set_phase(h, k, J)  a material change: the temperature is kept
//   heat_store_set_power(h, watts)                                       a sustained source (an exothermic material)
//   heat_store_link(h, thing, conductance, emissivity, area)            a heat link to a reservoir: its edge id
//   heat_store_engine(h, thing, efficiency, conductance)                a heat engine to a reservoir: its edge id (vg_heat_edge_take_work())
//   heat_store_release(h)                                                drops the body; its heat leaves with it (call at equilibrium)
//
// As an endpoint of heat_move(), heat_equalize() or heat_conduct() a store is HEAT_STORE(h). Edge ids are removed with vg_heat_edge_remove().

/proc/heat_store_create(capacity, kelvin, phase_kelvin = 0, latent = 0)
	var/h = vg_heat_body_create(max(capacity, 0.0001), max(kelvin, TCMB), HEAT_TARGET_NONE, null, 0, TRUE)
	if(h && phase_kelvin > 0 && latent > 0)
		vg_heat_body_phase(h, phase_kelvin, latent)
	return h

/// list(temperature K, latent heat stored J, energy J), or null when the store does not exist.
/proc/heat_store_state(h)
	return h ? vg_heat_body_state(h) : null

/proc/heat_store_temperature(h, default = T20C)
	var/list/s = heat_store_state(h)
	return s ? s[1] : default

/// The heat held in the phase plateau, J: none below it, all of its latent heat above it.
/proc/heat_store_latent(h)
	var/list/s = heat_store_state(h)
	return s ? s[2] : 0

/proc/heat_store_energy(h)
	var/list/s = heat_store_state(h)
	return s ? s[3] : 0

/// Adds `joules` from outside the simulation (negative removes), booked under `source`. Returns the joules applied.
/proc/heat_store_add(h, joules, source = HEAT_SOURCE_OTHER)
	if(!h || !isnum(joules) || !joules)
		return 0
	return vg_heat_move(HEAT_TARGET_NONE, null, HEAT_TARGET_BODY, h, joules, source) || 0

/// Brings the store to `kelvin`, booked under `source`. Returns the joules it took.
/proc/heat_store_set_temperature(h, kelvin, source = HEAT_SOURCE_AUTHORITY)
	if(!h || !isnum(kelvin))
		return 0
	return vg_heat_move_to_temperature(HEAT_TARGET_BODY, h, max(kelvin, TCMB), source) || 0

/// A new heat capacity, J/K, keeping the temperature (and the plateau's state).
/proc/heat_store_set_capacity(h, capacity)
	if(!h || !(capacity > 0))
		return
	var/list/s = vg_heat_body_state(h)
	vg_heat_body_capacity(h, capacity)
	if(s && s[2] > 0)
		vg_heat_body_set_temperature(h, s[1]) // re-derives the energy with the plateau held

/// The phase plateau (0 K: none), keeping the temperature: above the plateau its latent heat is held, below it it is not.
/proc/heat_store_set_phase(h, kelvin, latent)
	if(h)
		vg_heat_body_phase(h, max(kelvin, 0), max(latent, 0))

/proc/heat_store_set_power(h, watts)
	if(h)
		vg_heat_body_power(h, watts || 0)

/// A heat link from the store to `thing` (a gas mixture, a turf's air, an atom, HEAT_SPACE, or list(HEAT_TARGET_*, ref)). Returns its id.
/proc/heat_store_link(h, thing, conductance, emissivity = 0, area = 0)
	var/list/r = islist(thing) ? thing : heat_reservoir_of(thing)
	if(!h || !r)
		return null
	return vg_heat_link_create(HEAT_TARGET_BODY, h, r[1], r[2], max(conductance, 0), emissivity, area)

/// A heat engine from the store to `thing`: heat flows hot to cold through `conductance` and `efficiency` of it (capped at Carnot) leaves as
/// work, taken with vg_heat_edge_take_work(id) (negative: work made). Returns its id.
/proc/heat_store_engine(h, thing, efficiency, conductance)
	var/list/r = islist(thing) ? thing : heat_reservoir_of(thing)
	if(!h || !r)
		return null
	return vg_heat_engine_create(HEAT_TARGET_BODY, h, r[1], r[2], clamp(efficiency, 0, 1), max(conductance, 0))

/// Drops the store's body. What it holds leaves the simulation with it: release it at equilibrium, or move its heat out first.
/proc/heat_store_release(h)
	if(h)
		vg_heat_body_release(h)
