// The chem vapour layer: boiled-off vapour of a reagent that is not an atmos gas (code/domains/world_model/reagents/vapour.dm sends it here).
//
// Only a tile that holds vapour stores anything: a /datum/vapour_cell (reagent id => units, and a temperature) in this system's sparse table, keyed by the tile's
// coordinates (never a reference to the turf, so a changed turf keeps its place). Every VAPOUR_STEP_SECONDS each cell cools toward the air of its tile, condenses
// (faster the colder it is under the reagent's boiling point), spreads VAPOUR_DIFFUSE of itself to the neighbours the air can reach (atmos adjacency: a wall or an
// airtight door blocks it), may ignite, and is dropped below VAPOUR_EPSILON. Bounds: at most `max_tiles` cells (a new vapour at the cap merges into an adjacent cell or
// is lost), at most VAPOUR_TILE_MAX_UNITS in a tile, and the step yields (STEP_YIELD) when the kernel is over budget and parks while the table is empty.
// Breathers take it in (life_breathing_inhale_vapour()), flammable vapour burns (ignite_at(): turf hotspot_expose() calls it). API: chem_vapour_api.dm.
// Everything is written to the world log under GLOB.chem_trace; the active tile count is the metric chem/vapour/tiles.

/// One tile's vapour.
/datum/vapour_cell
	var/x = 0
	var/y = 0
	var/z = 0
	/// Reagent id => units.
	var/list/units
	/// Kelvin.
	var/kelvin = T20C
	/// TRUE once the cell has had its turn in the current pass (a cell made or fed during a pass is not spread again in it).
	var/stepped = FALSE

SYSTEM_DEF(chem_vapour)
	name = "Chem Vapour"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	/// Tile key ("x,y,z") => /datum/vapour_cell.
	var/list/cells
	/// The most tiles that hold vapour at once.
	var/max_tiles = VAPOUR_MAX_TILES
	/// The most tiles held at one time since boot, and units refused or condensed away by the bounds.
	var/peak_tiles = 0
	var/units_refused = 0
	var/units_condensed = 0
	var/units_burnt = 0
	VAR_PRIVATE/list/pass_keys
	VAR_PRIVATE/pass_index = 1
	VAR_PRIVATE/pass_resuming = FALSE

CAPABILITIES(/datum/system/chem_vapour)
	owns_many(nameof(cells), /datum/vapour_cell)

/datum/system/chem_vapour/reactions()
	. = ..()
	. += every(VAPOUR_STEP_SECONDS SECONDS, PROC_REF(vapour_step), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/chem_vapour/stat_entry(msg)
	return "[..()]Tiles: [length(cells)]/[max_tiles] peak:[peak_tiles] refused:[round(units_refused, 0.1)]u condensed:[round(units_condensed, 0.1)]u burnt:[round(units_burnt, 0.1)]u"

/// The key of a tile in the table.
/proc/vapour_key(turf/T)
	return "[T.x],[T.y],[T.z]"

/datum/system/chem_vapour/proc/cell_at(turf/T)
	return cells?[vapour_key(T)]

/// The tile a cell sits on, or null when it is gone.
/datum/system/chem_vapour/proc/tile_of(datum/vapour_cell/cell)
	var/turf/T = locate(cell.x, cell.y, cell.z)
	return isturf(T) ? T : null

/datum/vapour_cell/proc/total()
	. = 0
	for(var/id in units)
		. += units[id]

/// Adds `amount` units of reagent `id` at `kelvin` to the tile. Returns the units taken (less than asked when the tile is full, none when the layer is at its
/// cap and no adjacent tile holds vapour to merge into).
/datum/system/chem_vapour/proc/add_vapour(turf/T, id, amount, kelvin)
	if(!T || amount <= 0)
		return 0
	var/datum/vapour_cell/cell = cell_at(T)
	if(!cell)
		if(length(cells) >= max_tiles)
			cell = merge_target(T)
			if(!cell)
				units_refused += amount
				if(GLOB.chem_trace)
					log_world("CHEM: vapour layer is full ([length(cells)] tiles): [round(amount, 0.001)]u of [id] at [T] is lost")
				return 0
		else
			cell = new
			cell.x = T.x
			cell.y = T.y
			cell.z = T.z
			cell.kelvin = kelvin
			cell.stepped = !isnull(pass_keys)
			rel_add(src, nameof(cells), cell, vapour_key(T))
			peak_tiles = max(peak_tiles, length(cells))
			wake_work_item(PROC_REF(vapour_step))
	var/room = VAPOUR_TILE_MAX_UNITS - cell.total()
	var/taken = clamp(amount, 0, max(room, 0))
	if(taken < amount)
		units_refused += amount - taken
	if(taken <= 0)
		return 0
	var/before = cell.total()
	// The vapour mixes in by quantity: the cell is warmer when hotter vapour joins.
	cell.kelvin = before > 0 ? (cell.kelvin * before + kelvin * taken) / (before + taken) : kelvin
	LAZYSET(cell.units, id, (cell.units?[id] || 0) + taken)
	if(GLOB.chem_trace)
		log_world("CHEM: [round(taken, 0.001)]u of [id] vapour at [T] at [round(kelvin - T0C, 0.1)] C ([length(cells)] vapour tiles; the tile holds [round(cell.total(), 0.001)]u)")
	return taken

/// At the cap: the vapour of a tile with no cell joins the cell of an adjacent tile, if one holds vapour.
/datum/system/chem_vapour/proc/merge_target(turf/T)
	for(var/turf/N in range(1, T))
		var/datum/vapour_cell/cell = cell_at(N)
		if(cell)
			return cell
	return null

/// Takes up to `fraction` of the tile's vapour (and no more than `most` units in all) out of the layer: reagent id => units, or null when the tile holds none.
/datum/system/chem_vapour/proc/take_vapour(turf/T, fraction, most)
	var/datum/vapour_cell/cell = cell_at(T)
	if(!cell)
		return null
	var/total = cell.total()
	if(total <= 0)
		return null
	var/share = min(fraction, most / total)
	. = list()
	for(var/id in cell.units)
		var/part = cell.units[id] * share
		if(part <= 0)
			continue
		.[id] = part
		cell.units[id] -= part
	tidy(cell)
	if(GLOB.chem_trace && length(.))
		log_world("CHEM: breathed [round(total * share, 0.001)]u of vapour out of [T]")

/// Drops a cell that holds (almost) nothing.
/datum/system/chem_vapour/proc/tidy(datum/vapour_cell/cell)
	for(var/id in cell.units.Copy())
		if(cell.units[id] < VAPOUR_EPSILON * 0.25)
			cell.units -= id
	if(cell.total() < VAPOUR_EPSILON)
		rel_remove(src, nameof(cells), cell)
		return TRUE
	return FALSE

/// Drops every cell (a test's clean-up).
/datum/system/chem_vapour/proc/clear_all()
	rel_clear(src, nameof(cells))
	pass_keys = null
	pass_resuming = FALSE

/// One kernel run: a pass over the table (resumed after a yield), parks when the table is empty.
/datum/system/chem_vapour/proc/vapour_step(dt)
	if(!length(cells))
		pass_resuming = FALSE
		return STEP_PARK
	if(!pass_resuming)
		pass_keys = list()
		for(var/key in cells)
			var/datum/vapour_cell/fresh = cells[key]
			fresh.stepped = FALSE
			pass_keys += key
		pass_index = 1
	pass_resuming = FALSE
	while(pass_index <= length(pass_keys))
		var/key = pass_keys[pass_index++]
		var/datum/vapour_cell/cell = cells?[key]
		if(cell && !cell.stepped)
			step_cell(cell)
		if(KERNEL_OVER_BUDGET)
			pass_resuming = TRUE
			return STEP_YIELD
	pass_keys = null
	return length(cells) ? STEP_DONE : STEP_PARK

/// The boiling point of a reagent id, K.
/proc/vapour_boiling_point(id)
	var/datum/reagent/R = SSchemistry.ready().chemical_reagents[id]
	return R ? R.boiling_point_k() : BOILING_POINT_DEFAULT

/// One cell's turn: cool, condense, ignite, spread.
/datum/system/chem_vapour/proc/step_cell(datum/vapour_cell/cell)
	cell.stepped = TRUE
	var/turf/T = tile_of(cell)
	var/datum/gas_mixture/air = T?.return_air()
	if(!air || T.blocks_air)
		if(GLOB.chem_trace)
			log_world("CHEM: vapour at [cell.x],[cell.y],[cell.z] has no air to live in: [round(cell.total(), 0.001)]u gone")
		rel_remove(src, nameof(cells), cell)
		return
	cell.kelvin += (air.return_temperature() - cell.kelvin) * VAPOUR_COOL_RATE
	for(var/id in cell.units.Copy())
		var/gap = vapour_boiling_point(id) - cell.kelvin
		var/fraction = clamp(VAPOUR_CONDENSE_MIN + gap / 300, VAPOUR_CONDENSE_MIN, VAPOUR_CONDENSE_MAX)
		units_condensed += cell.units[id] * fraction
		cell.units[id] *= 1 - fraction
	if(tidy(cell))
		return
	var/turf/open/O = T
	if(istype(O) && O.active_hotspot && ignite_cell(cell, T))
		return
	spread(cell, T)
	tidy(cell)

/// Spreads VAPOUR_DIFFUSE of the cell to the tiles the air reaches from here, evenly; a tile that cannot take a new cell (the cap) leaves its share here.
/datum/system/chem_vapour/proc/spread(datum/vapour_cell/cell, turf/T)
	var/list/neighbours = vg_atmos_adjacent_turfs(T)
	if(!length(neighbours))
		return
	var/count = length(neighbours)
	for(var/turf/N as anything in neighbours)
		var/datum/vapour_cell/target = cell_at(N)
		if(!target && length(cells) >= max_tiles)
			continue
		for(var/id in cell.units.Copy())
			var/part = cell.units[id] * VAPOUR_DIFFUSE / count
			if(part <= 0)
				continue
			var/moved = add_vapour(N, id, part, cell.kelvin)
			cell.units[id] -= moved
		var/datum/vapour_cell/received = cell_at(N)
		if(received)
			received.stepped = TRUE

/// Flammable vapour in the cell burns: its fuel is used up, its heat goes into the tile's air and a flash fire starts. Needs oxygen. Returns TRUE when it burned.
/datum/system/chem_vapour/proc/ignite_cell(datum/vapour_cell/cell, turf/T)
	var/datum/gas_mixture/air = T.return_air()
	if(!air || air.get_moles(/datum/gas/oxygen) < 0.5)
		return FALSE
	var/fuel = 0
	var/energy = 0
	for(var/id in cell.units)
		var/per_unit = GLOB.reagent_vapour_fuels[id]
		if(per_unit)
			fuel += cell.units[id]
			energy += cell.units[id] * per_unit
	if(fuel < VAPOUR_FLAMMABLE_UNITS)
		return FALSE
	for(var/id in cell.units.Copy())
		if(GLOB.reagent_vapour_fuels[id])
			cell.units -= id
	units_burnt += fuel
	heat_set(air, air.return_temperature() + energy / max(air.heat_capacity(), 1))
	var/turf/open/O = T
	if(istype(O) && !O.active_hotspot)
		new /obj/effect/hotspot(O, 100, VAPOUR_FLASH_TEMPERATURE)
	SSair?.add_to_active(T)
	if(GLOB.chem_trace)
		log_world("CHEM: [round(fuel, 0.001)]u of flammable vapour ignited at [T] and released [round(energy)] J")
	tidy(cell)
	return TRUE

/// A flame or hotspot at `T` at `kelvin`: flammable vapour there ignites when it is hot enough. Returns TRUE when something burned.
/datum/system/chem_vapour/proc/ignite_at(turf/T, kelvin)
	if(kelvin < VAPOUR_IGNITION_TEMPERATURE)
		return FALSE
	var/datum/vapour_cell/cell = cell_at(T)
	return cell ? ignite_cell(cell, T) : FALSE

/// The active vapour tile count, for the metrics line.
/datum/metrics_source/chem_vapour

/datum/metrics_source/chem_vapour/collect(datum/system/server_metrics/M, dt)
	M.gauge("chem/vapour/tiles", chem_vapour_tiles(), METRICS_CAT_SERVICE, "chem_vapour", "tiles")
	M.gauge("chem/vapour/refused", chem_vapour_refused(), METRICS_CAT_SERVICE, "chem_vapour", "units")
