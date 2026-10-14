// The heat domain's network API (doc/rewrite/final_api.html, section 14 "Gas and heat"; doc/rewrite/temperature.md §2.3).
//
// Rust owns every heat flow. DM never computes a transfer and never writes a temperature: it names reservoirs and declares edges between
// them, and Rust integrates the edges each world step (exactly, for any step length) and books every joule. A reservoir is
//
//   a /datum/gas_mixture              a pipe network, a tank, a canister, a machine's buffer, scratch gas
//   a turf                            its air (its solid when it has none)
//   an atom                           its heat body (made on first use and kept while an edge names it); a mob's body heat
//   HEAT_SPACE                        outer space, an infinite reservoir at TCMB
//   list(HEAT_TARGET_*, ref)          a reservoir already named: HEAT_STORE(h), a heat body a datum keeps (heat_store.dm)
//
// One-off events move heat with heat_move(); persistent flows are the declarative entries of heat_entries.dm (heat_link(), heat_pump(),
// heat_engine()), which live while their scope does.
//
//   heat_move(from, to, joules, source)   moves joules from one reservoir to another in one operation, capped so neither side passes its floor.
//                                          `from` null: the joules come from outside the simulation and `source` (HEAT_SOURCE_*) says what made
//                                          them; `to` null: they leave it. Returns the joules moved. Rust wakes the gas it changed.
//   heat_add(thing, joules, source)        heat_move(null, thing, joules, source)
//   heat_equalize(a, b, fraction = 1)      moves `fraction` of the way to the pair's common temperature, conserved
//   heat_conduct(a, b, conductance, s)     conducts for `s` seconds at `conductance` W/K (the exact pair solution), conserved
//   heat_set(thing, kelvin, source)        an authority write (map load, admin, a test, a spawn-time temperature): the joules it takes, booked
//   heat_set_energy(thing, joules, source)  a thing's end energy after its composition changed, booked
//   gas_react(air, kind, extent, deltas)   a gas reaction: its moles change and Rust settles the energy it releases, booked as a reaction
//   heat_set_solid(turf, kelvin)           a turf's solid temperature (map load, holodeck, admin)
//   heat_reservoir_of(thing)               list(HEAT_TARGET_*, ref) of a reservoir, or null
//   heat_links_text(thing)                 tooling: every edge touching a reservoir with its last step's flows (the "Show Heat Links" verb)
//
// Example (a reaction's enthalpy released into the room it happened in):
//
//	heat_add(loc.return_air(), released_joules, HEAT_SOURCE_REACTION)

/// The reservoir a thing names: list(HEAT_TARGET_*, ref), or null when it holds no heat. An atom gets a heat body on first use.
/proc/heat_reservoir_of(thing)
	if(isnull(thing))
		return null
	if(thing == HEAT_SPACE)
		return list(HEAT_TARGET_SPACE, TCMB)
	if(istype(thing, /datum/gas_mixture))
		return list(HEAT_TARGET_MIXTURE, thing)
	if(islist(thing))
		return thing // already a reservoir: list(HEAT_TARGET_*, ref), such as HEAT_STORE(h)
	if(isturf(thing))
		var/turf/T = thing
		return T.heat_has_air() ? list(HEAT_TARGET_TURF_AIR, T) : list(HEAT_TARGET_SOLID, T)
	if(isatom(thing))
		var/atom/A = thing
		return A.heat_reservoir()
	return null

/// This atom as a heat reservoir: its heat body, made at its surroundings' temperature on first use. null when it holds no heat.
/atom/proc/heat_reservoir()
	if(isnull(heat_body) && !create_heat_body())
		return null
	HEAT_BODY_RESOLVE(src)
	return list(HEAT_TARGET_BODY, heat_body)

/// A pipe machine as a reservoir is the gas of the pipeline its first port is in (followed through merges and splits).
/obj/machinery/atmospherics/heat_reservoir()
	if(length(rust_pipe_port_ids) && rust_pipe_port_ids[1])
		return list(HEAT_TARGET_PIPE_PORT, rust_pipe_port_ids[1])
	return null

/// Moves `joules` from `source_thing` into `into` (see the header). Returns the joules moved.
/proc/heat_move(source_thing, into, joules, source = HEAT_SOURCE_NONE)
	if(!isnum(joules) || !joules)
		return 0
	var/list/a = heat_reservoir_of(source_thing)
	var/list/b = heat_reservoir_of(into)
	if(!isnull(source_thing) && !a || !isnull(into) && !b)
		return 0
	. = vg_heat_move(a ? a[1] : HEAT_TARGET_NONE, a ? a[2] : null, b ? b[1] : HEAT_TARGET_NONE, b ? b[2] : null, joules, source) || 0

/// Adds `joules` (negative removes) to a reservoir from outside the simulation, booked under `source`.
/proc/heat_add(thing, joules, source = HEAT_SOURCE_OTHER)
	return heat_move(null, thing, joules, source)

/// Moves `fraction` (0..1) of the way to two reservoirs' common temperature in one conserved operation (1: both end at the mixed
/// temperature). Returns the joules moved from `a` to `b`.
/proc/heat_equalize(a, b, fraction = 1)
	var/list/ra = heat_reservoir_of(a)
	var/list/rb = heat_reservoir_of(b)
	if(!ra || !rb)
		return 0
	. = vg_heat_equalize(ra[1], ra[2], rb[1], rb[2], fraction) || 0

/// Conducts between two reservoirs for `seconds` at `conductance` W/K in one conserved operation (the exact pair solution, never past
/// equilibrium): a sample that covers a stretch of time. Returns the joules moved from `a` to `b`.
/proc/heat_conduct(a, b, conductance, seconds)
	var/list/ra = heat_reservoir_of(a)
	var/list/rb = heat_reservoir_of(b)
	if(!ra || !rb || !(conductance > 0) || !(seconds > 0))
		return 0
	. = vg_heat_conduct(ra[1], ra[2], rb[1], rb[2], conductance, seconds) || 0

/// One heat-engine pass between two reservoirs: the equalizing heat flows hot to cold and `efficiency` of it (capped at Carnot) leaves as
/// electricity. Returns the electrical work, J.
/proc/heat_engine_once(a, b, efficiency)
	var/list/ra = heat_reservoir_of(a)
	var/list/rb = heat_reservoir_of(b)
	if(!ra || !rb)
		return 0
	. = vg_heat_engine_once(ra[1], ra[2], rb[1], rb[2], efficiency) || 0

/// Brings a reservoir to `kelvin` by a booked external source (an authority write). Returns the joules it took.
/proc/heat_set(thing, kelvin, source = HEAT_SOURCE_AUTHORITY)
	if(!isnum(kelvin))
		return 0
	var/list/r = heat_reservoir_of(thing)
	if(!r)
		return 0
	. = vg_heat_move_to_temperature(r[1], r[2], kelvin, source) || 0

/// Sets a reservoir's thermal energy to `joules` (never below its floor) by a booked external source: a gas reaction that changed
/// the mixture's composition reports the energy it ends with, `temperature * old_heat_capacity + released`. Returns the joules added.
/proc/heat_set_energy(thing, joules, source = HEAT_SOURCE_REACTION)
	if(!isnum(joules))
		return 0
	var/list/r = heat_reservoir_of(thing)
	if(!r)
		return 0
	. = vg_heat_set_energy(r[1], r[2], joules, source) || 0

/// Applies a gas reaction in one step: `deltas` (gas type path = moles, signed) change the mixture, and Rust computes what the reaction of
/// `kind` (GAS_REACTION_*) releases for its `extent` (with `aux`, the value a kind names: BZ formation's decomposed fraction, noblium's BZ)
/// and settles the mixture's temperature: its thermal energy before, plus the release, over its new heat capacity. Booked under
/// HEAT_SOURCE_REACTION. Returns the joules released (negative: absorbed). DM decides a reaction's rate and stoichiometry, never its heat.
/proc/gas_react(datum/gas_mixture/air, kind, extent, list/deltas, aux = 0)
	var/list/flat = list()
	for(var/gas in deltas)
		flat += GAS_IDX(gas)
		flat += deltas[gas]
	. = vg_gas_reaction_apply(air, kind, extent, aux, flat) || 0
	gas_touched(air)

/// Sets a turf's solid temperature (DM authority: map load, holodeck programs, admin). The seed follows, so a turf registered after this starts
/// there.
/proc/heat_set_solid(turf/T, kelvin)
	if(!T || !isnum(kelvin))
		return FALSE
	if(kelvin == T.get_temperature())
		return FALSE
	T.initial_temperature = kelvin
	. = vg_heat_set_turf_temperature(T, kelvin)
	T.solid_temperature_set()

/// A turf's solid temperature was set by heat_set_solid() (a planet wall re-evaluates its neighbours).
/turf/proc/solid_temperature_set()
	return

/// The electrical power of an edge's last step, W: positive for an engine's output, negative for a pump's draw.
/proc/heat_edge_power(edge)
	return edge ? (vg_heat_edge_power(edge) || 0) : 0

// ---- tooling ----

GLOBAL_LIST_INIT(heat_edge_names, list("link", "pump", "engine"))
GLOBAL_LIST_INIT(heat_target_names, list("solid", "turf air", "mixture", "body", "pipe port", "space"))

/// Every edge touching `thing` with its parameters and its last step's flows, one line each.
/proc/heat_links_text(thing)
	var/list/r = heat_reservoir_of(thing)
	if(!r)
		return "[thing] is not a heat reservoir."
	var/list/state = vg_heat_reservoir_state(r[1], r[2])
	var/list/lines = list("[thing]: [state ? "[round(state[1], 0.01)] K, [state[2] < 0 ? "infinite" : "[round(state[2])] J/K"]" : "gone"]")
	var/list/ids = vg_heat_reservoir_links(r[1], r[2])
	for(var/id in ids)
		var/list/row = vg_heat_edge_info(id)
		if(!row)
			continue
		lines += "  edge [id] [GLOB.heat_edge_names[row[1]]]: [GLOB.heat_target_names[row[2]]] [row[3]] -> [GLOB.heat_target_names[row[4]]] [row[5]] \
			params [row[6]], [row[7]], [row[8]]; last step [round(row[9], 0.1)] W out of a, [round(row[10], 0.1)] W into b, \
			work in [round(row[11], 0.1)] W, work out [round(row[12], 0.1)] W"
	if(!length(ids))
		lines += "  no edges"
	var/list/books = vg_heat_books()
	if(books)
		lines += "network: [books[1]] edges; last step moved [round(books[2])] J, work in [round(books[3])] J, work out [round(books[4])] J, \
			in [round(books[5])] J, out [round(books[6])] J; [books[12]] unbalanced steps"
	return jointext(lines, "\n")

/// The admin verb "Show Heat Links": a reservoir's edges and their last step's flows (and those of the thing's own air, when it has one).
ADMIN_VERB_AND_CONTEXT_MENU(heat_show_links, R_DEBUG, "Show Heat Links", "Every heat edge touching a thing, with its last step's flows.", ADMIN_CATEGORY_DEBUG, atom/target in world)
	var/text = heat_links_text(target)
	var/datum/gas_mixture/air = isturf(target) ? null : target.return_air()
	if(air && air != target.loc?.return_air())
		text += "\n" + heat_links_text(air)
	to_chat(user, "<b>Heat links of [target]</b><br>[replacetext(html_encode(text), "\n", "<br>")]")
