// Generated routes: the reactions the processes make out of the structures that exist (process.dm, structure.dm).
//
// chem_routes_build() runs every process over every structure. A variant whose end structure is a chemical that exists is a route that makes that chemical; one
// whose end structure nobody has is a route that makes organic residue (or, for neutralisation, salts). Each route is written once per catalyst kind its process
// runs on, and compiled into the one transformation table (xform_compile(): the same compile as every declared recipe, the rule type is /transformation/process_route).
// The route stays what it was generated from: /datum/xform.route_id names it, and the matcher, the temperature gate and the step ask it
// (xform_matches(), reaction_temperature_state(), xform_step()).
//
// What a route does when it runs, besides what any recipe does:
//   * it holds only in a loose container (the same gate as temperature) and, by kind, only with the right catalyst there: a sheet of the right kind lying in the
//     container (solid), an enzyme that has not been poisoned (heavy metals), a dissolved acid or base that is present (the rule's catalysts);
//   * its working band is its process's band, moved down by the catalyst: a dissolved acid or base by CHEM_DISSOLVED_REDUCTION, a solid sheet by its effective
//     catalytic activity times CHEM_SOLID_REDUCTION_PER_POINT, where sulfur and heavy metals in the mixture poison the sheet (chem_catalyst_poison());
//   * a step spends a little of its dissolved catalyst into acid or base residue (an enzyme into endotoxin), makes organic residue from the share of the product
//     the catalyst was not selective for, and leaves the process's own trace-potent contaminants (hydrochloric acid, dioxin, nitrosamine, peroxide, methanol, ...).
//
// Everything is written to the world log under GLOB.chem_trace; the whole generated set is dumped by chem_routes_dump() and pinned by a test.

/// A transformation rule type for the generated routes: no rule is ever declared under it, it is only the key and the owner of the ones the generator writes.
/transformation/process_route

/// A route's id => the route. In generation order.
GLOBAL_LIST_EMPTY(chem_routes)
/// Every compiled route rule (what chem_routes_install() puts into the transformation table).
GLOBAL_LIST_EMPTY(chem_route_rules)

/// A generated route, kept as the generator wrote it.
/datum/chem_route
	var/id
	var/process_id
	var/kind
	/// The reagent the rule is filed under (the first substrate).
	var/substrate_id
	/// The substrates, 1u each (the first is substrate_id).
	var/list/from
	/// reagent id => units taken, in order: the substrates, then what the process adds.
	var/list/takes
	var/list/catalysts
	var/list/blocked
	/// Rows of list(reagent id, units): the product first, then what else it makes.
	var/list/makes
	/// The reagent ids of the products, in order.
	var/list/products
	/// TRUE when the product is a chemical that exists; FALSE: residue.
	var/matched = TRUE
	/// The band the route runs in before a solid catalyst moves it, kelvin.
	var/list/band_base
	var/fixed_band = FALSE
	var/needs_current = FALSE
	var/clean = FALSE
	/// What a dissolved catalyst or an enzyme is spent into, or null.
	var/catalyst_residue

/// The route a compiled rule was generated from, or null for a declared recipe.
/proc/chem_route_of(datum/xform/X)
	RETURN_TYPE(/datum/chem_route)
	return X.route_id ? GLOB.chem_routes[X.route_id] : null

// ---- the generator ----

/// Writes every route. `reagents` is reagent id => prototype (what exists).
/proc/chem_routes_build(list/reagents)
	GLOB.chem_routes = list()
	GLOB.chem_route_rules = list()
	chem_processes_build()
	var/datum/chem_gen/G = new /datum/chem_gen
	G.structures = GLOB.chem_structures
	G.reagents = reagents
	G.condensed = list()
	var/list/ids = list()
	for(var/structure_id in G.structures)
		ids += structure_id
	sortTim(ids, GLOBAL_PROC_REF(cmp_text_asc))
	G.ids = ids
	// The condensations that made a chemical first: hydrolysis is their reverse.
	var/datum/chem_process/condense = chem_process_of(CHEM_PROCESS_CONDENSE)
	if(condense && !condense.reserved)
		for(var/acid_id in ids)
			if(istype(reagents[acid_id], /datum/reagent/contaminant))
				continue
			var/list/joins = condense.chem_variants(acid_id, G.structures[acid_id], G)
			for(var/join in joins)
				var/datum/chem_variant/joined = join
				var/datum/chem_structure/T = joined.to[1]
				if(!chem_structure_match(T))
					continue
				LAZYINITLIST(G.condensed[T.key])
				G.condensed[T.key] += list(list(acid_id, joined.from[2]))
	var/written = 0
	for(var/process_id in GLOB.chem_processes)
		var/datum/chem_process/P = GLOB.chem_processes[process_id]
		if(P.reserved)
			continue
		for(var/substrate_id in ids)
			if(P.id != CHEM_PROCESS_NEUTRALISE && istype(reagents[substrate_id], /datum/reagent/contaminant))
				continue // a contaminant is only ever an acid or a base the neutralisation spends
			var/list/made = P.chem_variants(substrate_id, G.structures[substrate_id], G)
			for(var/variant in made)
				written += chem_route_emit(P, variant, G)
	log_world("Chemistry routes: [written] generated from [length(GLOB.chem_processes)] processes over [length(ids)] structures")

/// Writes the routes of one variant (one per catalyst kind of its process). Returns how many were new.
/proc/chem_route_emit(datum/chem_process/P, datum/chem_variant/V, datum/chem_gen/G)
	var/list/matched_ids = list()
	var/list/residue_ids = list()
	for(var/entry in V.to)
		if(istext(entry))
			matched_ids += entry
			continue
		var/datum/chem_structure/T = entry
		var/found = chem_structure_match(T)
		if(found && !(found in V.from))
			matched_ids += found
		else
			residue_ids += (V.residue || P.residue_id)
	var/matched = length(matched_ids) > 0
	if(!matched && !P.residue_routes)
		return 0
	var/list/makes = list()
	for(var/product in matched_ids + residue_ids)
		makes[product] = (makes[product] || 0) + 1
	for(var/byproduct in V.byproducts)
		makes[byproduct] = (makes[byproduct] || 0) + V.byproducts[byproduct]
	var/list/take_rows = list()
	for(var/substrate in V.from)
		take_rows[substrate] = (take_rows[substrate] || 0) + 1
	for(var/agent in V.agents)
		take_rows[agent] = (take_rows[agent] || 0) + V.agents[agent]
	for(var/taken_id in take_rows)
		if(!G.reagents[taken_id])
			return 0
	for(var/made_id in makes)
		if(!G.reagents[made_id])
			return 0
	var/list/products = matched_ids + residue_ids
	var/written = 0
	for(var/kind in P.kinds)
		var/list/catalysts
		var/residue
		switch(kind)
			if(CHEM_CATALYST_ACID)
				catalysts = list(REAGENT_ID_SACID = 1)
				residue = REAGENT_ID_CONTAMINANT_ACID_RESIDUE
			if(CHEM_CATALYST_BASE)
				catalysts = list(REAGENT_ID_LYE = 1)
				residue = REAGENT_ID_CONTAMINANT_BASE_RESIDUE
			if(CHEM_CATALYST_ENZYME)
				catalysts = list(REAGENT_ID_ENZYME = 1)
				residue = REAGENT_ID_CONTAMINANT_BIOLOGICAL
		var/usable = TRUE
		for(var/catalyst_id in catalysts)
			if(!G.reagents[catalyst_id] || (catalyst_id in take_rows) || (catalyst_id in makes))
				usable = FALSE
		if(!usable)
			continue
		var/route_id = "[P.id]:[jointext(V.from, "+")]:[kind]>[jointext(products, "+")]"
		if(GLOB.chem_routes[route_id])
			continue
		var/datum/chem_route/R = new /datum/chem_route
		R.id = route_id
		R.process_id = P.id
		R.kind = kind
		R.substrate_id = V.from[1]
		R.from = V.from
		R.takes = take_rows
		R.catalysts = catalysts
		if(P.blocked_by_water)
			R.blocked = list(REAGENT_ID_WATER = 1)
		var/list/rows = list()
		for(var/make_id in makes)
			rows += list(list(make_id, makes[make_id]))
		R.makes = rows
		R.products = products
		R.matched = matched
		R.band_base = P.band_for(kind)
		R.fixed_band = P.fixed_band
		R.needs_current = P.needs_current
		R.clean = P.clean
		R.catalyst_residue = residue
		GLOB.chem_routes[route_id] = R
		written++
	return written

/// The title of a route's rule: "Condense: Kelotane + Ethanol -> Dermaline".
/datum/chem_route/proc/title()
	var/datum/chem_process/P = chem_process_of(process_id)
	var/list/from_names = list()
	for(var/from_id in from)
		var/datum/reagent/from_reagent = SSchemistry.ready().chemical_reagents[from_id]
		from_names += from_reagent ? from_reagent.name : from_id
	var/list/to_names = list()
	for(var/product_id in products)
		var/datum/reagent/product_reagent = SSchemistry.ready().chemical_reagents[product_id]
		to_names += product_reagent ? product_reagent.name : product_id
	return "[P?.name]: [jointext(from_names, " + ")] -> [jointext(to_names, " + ")]"

// ---- compile and install ----

/// Compiles every route into a rule and puts the rules into the transformation table. Idempotent: a rule already in the table is left; the table being rebuilt
/// (xform_build()) puts the same rules back.
/proc/chem_routes_install()
	if(!length(GLOB.chem_routes) || !length(GLOB.xform_rules))
		return // nothing generated yet, or the transformations are not compiled yet: xform_build() calls this when they are
	if(!length(GLOB.chem_route_rules))
		var/order = CHEM_ROUTE_ORDER_BASE
		for(var/route_id in GLOB.chem_routes)
			var/datum/chem_route/R = GLOB.chem_routes[route_id]
			var/datum/xform/X = chem_route_compile(R, ++order)
			if(X)
				GLOB.chem_route_rules += X
	var/touched = list()
	var/added = 0
	for(var/datum/xform/X as anything in GLOB.chem_route_rules)
		if(X in GLOB.xform_rules)
			continue
		GLOB.xform_rules += X
		xform_index_rule(X, touched)
		added++
	if(!added)
		return
	sortTim(GLOB.xform_rules, GLOBAL_PROC_REF(cmp_xform_asc))
	for(var/list/bucket in touched)
		sortTim(bucket, GLOBAL_PROC_REF(cmp_xform_asc))
	if(!GLOB.xform_owners[/transformation/process_route])
		GLOB.xform_owners[/transformation/process_route] = new /transformation/process_route
	log_world("Chemistry routes: [added] rule(s) installed in the transformation table")

/// One route's rule, compiled like any recipe.
/proc/chem_route_compile(datum/chem_route/R, order)
	RETURN_TYPE(/datum/xform)
	var/list/take_terms = list()
	for(var/take_id in R.takes)
		take_terms += reagent(take_id, R.takes[take_id])
	var/list/catalyst_terms = list()
	for(var/catalyst_id in R.catalysts)
		catalyst_terms += reagent(catalyst_id, R.catalysts[catalyst_id])
	var/list/blocked_terms = list()
	for(var/blocked_id in R.blocked)
		blocked_terms += reagent(blocked_id, R.blocked[blocked_id])
	var/list/make_terms = list()
	for(var/list/row as anything in R.makes)
		make_terms += reagent(row[1], row[2])
	var/datum/entry/E = transformation(name = R.title(), id = R.id, takes = take_terms, catalysts = length(catalyst_terms) ? catalyst_terms : null, \
		blocked_by = length(blocked_terms) ? blocked_terms : null, makes = make_terms)
	var/datum/xform/X = xform_compile(/transformation/process_route, E, order, "chem route [R.id]")
	if(!X)
		return null
	X.route_id = R.id
	return X

/// The generated routes as one sorted text line each: what the pin test compares. A route is its id, what it takes (with catalysts and blockers) and what it makes.
/proc/chem_routes_dump()
	var/list/lines = list()
	for(var/route_id in GLOB.chem_routes)
		var/datum/chem_route/R = GLOB.chem_routes[route_id]
		var/list/takes = list()
		for(var/take_id in R.takes)
			takes += "[take_id] [R.takes[take_id]]"
		var/list/catalysts = list()
		for(var/catalyst_id in R.catalysts)
			catalysts += "[catalyst_id] [R.catalysts[catalyst_id]]"
		var/list/blocked = list()
		for(var/blocked_id in R.blocked)
			blocked += "[blocked_id]"
		var/list/makes = list()
		for(var/list/row as anything in R.makes)
			makes += "[row[1]] [row[2]]"
		var/list/band = R.band_base
		lines[route_id] = "takes [jointext(takes, ", ")] | catalysts [jointext(catalysts, ", ") || "none"] | blocked by [jointext(blocked, ", ") || "none"] | makes [jointext(makes, ", ")] | [R.matched ? "product" : "residue"] | band [round(band[1] - T0C)]..[round(band[2] - T0C)]..[round(band[3] - T0C)]..[round(band[4] - T0C)] C"
	return lines

// ---- the matcher, the gate and the step ask the route ----

/// Does this route hold in `holder` now: a loose container, the catalyst kind there, a current if it needs one.
/datum/chem_route/proc/can_run(datum/reagents/holder)
	if(!holder.temperature_gated())
		return FALSE
	if(needs_current && !holder.current_flows())
		return FALSE
	switch(kind)
		if(CHEM_CATALYST_SOLID_METAL, CHEM_CATALYST_SOLID_ACID)
			var/list/solid = holder.solid_catalyst()
			if(!solid || solid[1] != kind || solid[2] < CHEM_SOLID_MIN_ACTIVITY)
				return FALSE
		if(CHEM_CATALYST_ENZYME)
			if(holder.heavy_metal_share() > CHEM_ENZYME_POISON_SHARE)
				if(GLOB.chem_trace)
					log_world("CHEM: route [id] refused in [holder.my_atom]: heavy metals poison the enzyme")
				return FALSE
	return TRUE

/// The band the route runs in in `holder`, kelvin: its process's, moved down by a solid catalyst's effective activity.
/datum/chem_route/proc/band_in(datum/reagents/holder)
	if(fixed_band || (kind != CHEM_CATALYST_SOLID_METAL && kind != CHEM_CATALYST_SOLID_ACID))
		return band_base
	var/list/solid = holder.solid_catalyst()
	if(!solid || solid[1] != kind)
		return band_base
	var/shift = solid[2] * CHEM_SOLID_REDUCTION_PER_POINT
	return list(band_base[1] - shift, band_base[2] - shift, band_base[3] - shift, band_base[4] - shift)

/// The share (0..1) of a step's product that is clean: what ran it decides.
/datum/chem_route/proc/selectivity(datum/reagents/holder)
	if(clean)
		return 1
	switch(kind)
		if(CHEM_CATALYST_ACID, CHEM_CATALYST_BASE)
			return CHEM_SELECTIVITY_DISSOLVED
		if(CHEM_CATALYST_ENZYME)
			return CHEM_SELECTIVITY_ENZYME
		if(CHEM_CATALYST_SOLID_METAL, CHEM_CATALYST_SOLID_ACID)
			var/list/solid = holder.solid_catalyst()
			var/activity = (solid && solid[1] == kind) ? solid[2] : 0
			return clamp(CHEM_SELECTIVITY_NONE + (1 - CHEM_SELECTIVITY_NONE) * activity / 100, CHEM_SELECTIVITY_NONE, 1)
	return CHEM_SELECTIVITY_NONE

/// A step of this route made `produced` units: the catalyst is spent, the share that was not selective is residue, the process leaves its trace-potent contaminants.
/datum/chem_route/proc/after_step(datum/reagents/holder, produced)
	if(produced <= 0)
		return
	var/datum/chem_process/P = chem_process_of(process_id)
	var/temperature = holder.reaction_temperature()
	var/list/parts = list()
	if(catalyst_residue)
		for(var/catalyst_id in catalysts)
			var/spent = min(produced * CHEM_CATALYST_RESIDUE_RATE, holder.get_reagent_amount(catalyst_id))
			if(spent <= 0)
				continue
			holder.remove_reagent(catalyst_id, spent, safety = 1)
			holder.add_reagent(catalyst_residue, spent, safety = 1)
			parts += "[round(spent, 0.001)]u [catalyst_id] spent into [catalyst_residue]"
	var/residue = produced * (1 - selectivity(holder)) * CHEM_RESIDUE_PER_LOST
	if(residue > 0)
		holder.add_reagent(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE, residue, safety = 1)
		parts += "[round(residue, 0.001)]u organic residue from what the [kind] route was not selective for"
	var/datum/chem_structure/S = chem_structure_of(substrate_id)
	var/list/traces = P?.fallout(kind, S, temperature)
	for(var/trace_id in traces)
		var/units = produced * traces[trace_id]
		if(units <= 0)
			continue
		holder.add_reagent(trace_id, units, safety = 1)
		parts += "[round(units, 0.0001)]u [trace_id]"
	if(GLOB.chem_trace)
		log_world("CHEM: route [id] made [round(produced, 0.001)]u in [holder.my_atom] at [round(temperature - T0C, 0.1)] C: [jointext(parts, "; ") || "clean"]")

// ---- the holder's side ----

/// The share (0..1) of the poison sulfur and the heavy metals make of the mixture, times CHEM_POISON_SCALE: the share of a metal catalyst's activity they take.
/datum/reagents/proc/catalyst_poison()
	if(total_volume <= 0)
		return 0
	var/poisons = get_reagent_amount(REAGENT_ID_CONTAMINANT_SULFUR) + get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL) + get_reagent_amount(REAGENT_ID_SULFUR) \
		+ get_reagent_amount(REAGENT_ID_MERCURY) + get_reagent_amount(REAGENT_ID_LEAD)
	return clamp(poisons / total_volume * CHEM_POISON_SCALE, 0, 1)

/// The share of the mixture that is heavy metal (the contaminant, mercury, lead): what an enzyme is poisoned by.
/datum/reagents/proc/heavy_metal_share()
	if(total_volume <= 0)
		return 0
	return (get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL) + get_reagent_amount(REAGENT_ID_MERCURY) + get_reagent_amount(REAGENT_ID_LEAD)) / total_volume

/// The solid catalyst in the container: list(its kind, its effective catalytic activity after poisoning), or null with none.
/datum/reagents/proc/solid_catalyst()
	var/obj/item/reagent_containers/glass/vessel = my_atom
	if(!istype(vessel))
		return null
	var/kind = vessel.catalyst_kind()
	if(!kind)
		return null
	return list(kind, vessel.catalyst_activity() * (1 - catalyst_poison()))

/// A current flows through the mixture: the container stands on a hot plate whose element is on (the plate's leads are the electrodes).
/datum/reagents/proc/current_flows()
	var/obj/machinery/chem_hot_plate/plate = my_atom?.loc
	return istype(plate) && plate.heating

// ---- peroxide ----

/// The units of peroxide that would go off now: a loose container, hot enough, enough of it. 0 when none.
/datum/reagents/proc/peroxide_hazard()
	if(!temperature_gated())
		return 0
	var/units = get_reagent_amount(REAGENT_ID_CONTAMINANT_PEROXIDE)
	if(units < PEROXIDE_MIN_UNITS || reaction_temperature() < PEROXIDE_DETONATION_TEMP)
		return 0
	return units

/// Peroxide in a container that is heated goes off: an explosion of PEROXIDE_BLAST_PER_UNIT per unit (two or less is a pop), and the container's contents with it.
/// Returns TRUE when it did.
/datum/reagents/proc/detonate_peroxide()
	var/units = peroxide_hazard()
	if(units <= 0)
		return FALSE
	var/atom/container = my_atom
	log_world("CHEM: [units]u of peroxide in [container] at [round(reaction_temperature() - T0C, 0.1)] C detonates")
	clear_reagents()
	var/datum/effect/effect/system/reagents_explosion/blast = new /datum/effect/effect/system/reagents_explosion
	blast.set_up(units * PEROXIDE_BLAST_PER_UNIT, container, 0, 0)
	blast.start()
	return TRUE
