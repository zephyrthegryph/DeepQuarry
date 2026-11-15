// Rolled traces (doc/rewrite/proposals/chemistry_redesign.md section 9; the tables: code/content/reagents/trace_sources.dm).
//
// Every source of stock (a material, an ore, a reagent) has a FIXED SIGNATURE of contaminants it always carries and a small POOL OF EXTRAS it may carry. The extras
// are rolled: once per round for station stock (the sheets in the stockroom, each dispenser cartridge, the lab's bottles) and once per lot for an ore vein, a cargo
// shipment or an expedition site. A roll is deterministic for the round seed, the source and the lot key (md5 streams, never rand()), so the same lot always holds
// the same traces, and a new round holds new ones. Nothing is shown until it is assayed (a spectrometer on a stack, a reagent scanner on a beaker).
//
// A roll is a list: contaminant reagent id => strength (a signature contaminant 0.8 to 1.2, an extra 0.3 to 0.8). What a strength means is the consumer's: a stack
// turns it into sheets of the matching material trace (code/content/materials/engineering/material_traces.dm: the same vocabulary, both ways), a cartridge or a bottle
// into units per unit of stock (chem_source_profile()), a ground ore into units of the contaminant reagent.
//
// Each extra shuts or taxes a route, never a chemical: the pool holds only contaminants the standard separations can bring down (their source_weight is above 0:
// nothing trace-potent that only a process makes is ever rolled), so there is always a route round it. Every roll is written to the world log.

/// A source: its fixed signature and its pool of extras.
/datum/trace_source
	/// The material name, ore name or reagent id it is the source of (TRACE_SOURCE_DEFAULT for the fallback).
	var/id
	/// Contaminant reagent id => relative strength (1 when a list is given as plain ids): always carried.
	var/list/signature
	/// Contaminant reagent id => weight: what an extra may be.
	var/list/extras
	/// How many extras a roll picks, station stock; a lot picks one more (never more than the pool).
	var/extras_min = 0
	var/extras_max = 1

/// id => the one instance of each source, built once.
GLOBAL_LIST_INIT(trace_sources, build_trace_sources())

/proc/build_trace_sources()
	var/list/table = list()
	for(var/type in subtypesof(/datum/trace_source))
		var/datum/trace_source/source = new type
		if(source.id)
			table[source.id] = source
	return table

/// The source of `source_id`, or the default source when it has none of its own.
/proc/trace_source_of(source_id)
	RETURN_TYPE(/datum/trace_source)
	return GLOB.trace_sources[source_id] || GLOB.trace_sources[TRACE_SOURCE_DEFAULT]

/// The one place a roll is made. `scope` is TRACE_SCOPE_ROUND (key TRACE_KEY_STATION) or TRACE_SCOPE_LOT (key: the lot: a vein, a shipment, a site). Returns
/// contaminant id => strength, cached for the round seed: asking twice gives the same list (shared, read-only).
/proc/trace_roll(source_id, scope = TRACE_SCOPE_ROUND, key = TRACE_KEY_STATION)
	var/cache_key = "[round_seed()]|[scope]|[source_id]|[key]"
	if(cache_key in GLOB.trace_rolls)
		return GLOB.trace_rolls[cache_key]
	var/datum/trace_source/source = trace_source_of(source_id)
	var/datum/roller/roll = new /datum/roller("[cache_key]|trace")
	var/list/result = list()
	var/list/fixed = list()
	for(var/contaminant_id in source.signature)
		var/weight = source.signature[contaminant_id]
		result[contaminant_id] = (isnum(weight) ? weight : 1) * (0.8 + 0.4 * roll.unit())
		fixed[contaminant_id] = result[contaminant_id]
	var/list/pool = list()
	for(var/extra_id in source.extras)
		if(!(extra_id in result))
			pool[extra_id] = source.extras[extra_id]
	var/count = roll.number(source.extras_min, source.extras_max)
	if(scope == TRACE_SCOPE_LOT)
		count++
	var/list/rolled = list()
	for(var/i in 1 to min(count, length(pool)))
		var/extra_id = roll.weighted(pool)
		if(isnull(extra_id))
			break
		pool -= extra_id
		result[extra_id] = 0.3 + 0.5 * roll.unit()
		rolled[extra_id] = result[extra_id]
	GLOB.trace_rolls[cache_key] = result
	log_world("TRACE: [scope] roll of [source_id] ([key]): signature [contaminants_text(fixed)]; extras [contaminants_text(rolled)]")
	return result

/// Rolls made this round: cache key => the roll.
GLOBAL_LIST_EMPTY(trace_rolls)

/// The lines an assay of a roll prints: "Sulfur compounds 0.8: poisons metal catalysts, ...".
/proc/trace_roll_lines(list/roll)
	var/list/lines = list()
	for(var/contaminant_id in roll)
		var/datum/reagent/contaminant/def = contaminant_def(contaminant_id)
		var/tax = GLOB.trace_route_taxes[contaminant_id]
		lines += "[def ? def.name : contaminant_id] [round(roll[contaminant_id], 0.1)][tax ? ": [tax]" : ""]"
	return lines

// ---- lots: what a thing made now was rolled with ----

/// The shipment being unpacked right now (the supply system sets it around the spawn of a crate's contents), or null.
GLOBAL_VAR(trace_current_lot)

/// A shipment is being unpacked: everything created until trace_lot_end() belongs to the lot `key`.
/proc/trace_lot_begin(key)
	GLOB.trace_current_lot = key

/proc/trace_lot_end()
	GLOB.trace_current_lot = null

/// The lot of something created at `where`: the shipment being unpacked, else the expedition site the level belongs to, else null (station stock, rolled once for the round).
/proc/trace_lot_at(atom/where)
	if(GLOB.trace_current_lot)
		return GLOB.trace_current_lot
	var/turf/here = get_turf(where)
	if(!here || !SSexpedition)
		return null
	var/datum/expedition_site/site = SSexpedition.site_on_level(here.z)
	return site ? "site [site.name] [REF(site)]" : null
