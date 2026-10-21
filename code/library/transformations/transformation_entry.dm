// Transformations as a CAPABILITIES entry (doc/rewrite/proposals/transformations.md section 4).
//
// A rule is a type under /transformation with a transformation(...) entry in its CAPABILITIES block, and nobody makes the type but the compile (which
// makes one instance per rule, the owner of its `then`, `data` and condition procs). The entry is a static kind like loot(): read without an instance,
// compiled once at world setup (static_entries), looked up with xform_of().
//
//   CAPABILITIES(/transformation/chem/instant/carthatoline)
//       transformation(takes = list(reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_PHORON, 0.1)),
//           catalysts = list(reagent(REAGENT_ID_PHORON, 1)), makes = list(reagent(REAGENT_ID_CARTHATOLINE, 2)))
//
//   name, id      display name and id, for the wiki, the handbooks and the logs (the type path is the rule's key; these are for people).   desc: one line about the rule.
//   medium        how the subject stores the terms (MEDIUM_X); inferred from the currency of the first take.
//   regime        which holders run the rule (REGIME_X); a holder declares the regime it runs. Default REGIME_INSTANT.
//   takes         the terms consumed. The first one is the index key (the anchor): the rule is a candidate in a subject holding it.
//   catalysts     present at least this much, not consumed.        blocked_by: present at least this much blocks the rule.
//   holds         the conditions under which the rule holds (code/library/transformations/transformation_conditions.dm); a subtype's `holds` is ANDed over the one
//                 it inherits. (Not `when`: that keyword is the op conditions', and the handler lints read it as one.)
//   rate          how far one step goes, a fraction of the limit: RATE_INSTANT (the default), half_life(n), rate(r).
//   yield         below 1, the rule is inhibited while the product is a large share of the mixture (1: no limit).   floor: a remainder under
//                 this many reaction units completes the rule.
//   makes         the terms produced.   The product of a reagent rule is its first reagent term.
//   made          units per reaction unit that the tail is told were made when the rule has no product term (a rule that spawns things reports how many).
//   data          TYPE_PROC_REF(/type, x): x(holder, extent) returns the data of the product, read before anything is taken.
//   energy        per_step(joules): booked once per step, into the air around the subject (heat_to = XFORM_HEAT_AIR, the default) or its own heat body.
//   takes_ambient list(gas(id, moles)): gas taken from the air around the subject once per step.
//   priority      PRIORITY_X: lower first. Within a priority the rules run in `order`, which is stamped from the declaration order (D5).
//   capacity      CAPACITY_TRUNCATE (the only one built): a product that does not fit is clamped to the free volume, as chemistry always did (D10).
//   says, plays   the message and the sound of a settle in which the rule fired (once per settle). says = "" says nothing.
//   notice        a /datum/notice/transformed subtype to publish instead of the plain one.
//   then          TYPE_PROC_REF(/type, x): the bespoke tail, x(holder, made); counted by the lints. A reagent rule's tail is the legacy on_reaction().
//   important     admin-visible when mixed (the legacy log_is_important).
//   wiki          WIKI_X flags: what the in-game wiki and the handbooks do with the rule (hide it, file it under food or drinks).
//   hotspot       TRUE for a gas rule that makes fires bigger: a hotspot's volume grows by what these rules report in the mixture's reaction_results.
//   cooks_in, cook_time, mix, coating   a kitchen rule's appliance bitfield, cooking time, reagent merge mode and required coating (code/library/transformations/kitchen.dm).
//   energy_in, energy_out, radiation, instability, min_level, min_heat   a fusion rule's numbers per reacting pair (code/modules/power/fusion/fusion_reactions.dm).
//
// A proc named in an entry is TYPE_PROC_REF(/the/rule/type, x), not PROC_REF(x): a static block is read in a global proc, where a bare PROC_REF has no type to
// resolve against. What the compile keeps is the proc's name, called on the rule's one owner instance, so a subtype that overrides x answers for itself.
//
// A subtype changes what it inherits with configure(transformation(...)): the arguments it names (non-null) replace the inherited ones, except
// `holds`, which is ANDed. A plain second transformation() under a type that inherits one is an error. A type whose merged entry has no `takes` is a
// base, not a rule.

STATIC_ENTRY(transformation)

/// The root of the declared transformations: each rule is a type under it, never made by anyone but the compile.
/transformation
	abstract_type = /transformation

LIFECYCLE_KEEP_UNLESS_FORCED(/transformation)
LIFECYCLE_KEEP_UNLESS_FORCED(/datum/xform)

/proc/transformation(name = null, id = null, desc = null, medium = null, regime = null, takes = null, catalysts = null, blocked_by = null, holds = null, rate = null, yield = null, floor = null, makes = null, made = null, data = null, energy = null, heat_to = null, takes_ambient = null, priority = null, capacity = null, says = null, plays = null, notice = null, then = null, important = null, wiki = null, hotspot = null, cooks_in = null, cook_time = null, mix = null, coating = null, energy_in = null, energy_out = null, radiation = null, instability = null, min_level = null, min_heat = null, chosen = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_TRANSFORMATION, null, list("name" = name, "id" = id, "desc" = desc, "hotspot" = hotspot, "medium" = medium, "regime" = regime, "takes" = takes, "catalysts" = catalysts, \
		"blocked_by" = blocked_by, "holds" = holds, "rate" = rate, "yield" = yield, "floor" = floor, "makes" = makes, "made" = made, "data" = data, "energy" = energy, \
		"heat_to" = heat_to, "takes_ambient" = takes_ambient, "priority" = priority, "capacity" = capacity, "says" = says, "plays" = plays, \
		"notice" = notice, "then" = then, "important" = important, "wiki" = wiki, "cooks_in" = cooks_in, "cook_time" = cook_time, "mix" = mix, "coating" = coating, \
		"energy_in" = energy_in, "energy_out" = energy_out, "radiation" = radiation, "instability" = instability, "min_level" = min_level, "min_heat" = min_heat, "chosen" = chosen))

/// rate = half_life(n): half the reagents react after n chemistry ticks (0: at once).
/proc/half_life(ticks)
	return ticks ? 1.0 - (0.5) ** (1.0 / (ticks * PROCESS_REACTION_ITER)) : 1.0

/// rate = rate(r): r of the reagents react each chemistry tick.
/proc/rate(fraction)
	return 1.0 - (1.0 - fraction) ** (1.0 / PROCESS_REACTION_ITER)

/// energy = per_step(joules): the joules booked on each step the rule goes (negative: absorbed).
/proc/per_step(joules)
	return joules

/datum/entry_engine/transformation
	kind = ENTRY_TRANSFORMATION
	static_kind = TRUE
	singleton = TRUE

/datum/entry_engine/transformation/merge(datum/entry/old, datum/entry/changes)
	var/list/merged = old.args ? old.args.Copy() : list()
	for(var/name in changes.args)
		var/value = changes.args[name]
		if(isnull(value))
			continue
		if(name == "holds")
			merged[name] = xform_cond_and(merged[name], value)
		else
			merged[name] = value
	return entry_make(ENTRY_TRANSFORMATION, null, merged)

/// type => its /datum/xform, for every rule. Built at world setup (xform_build()), never after.
GLOBAL_LIST_EMPTY(xforms)
/// rule type => the one instance that owns its procs (then, data, PROC_REF conditions).
GLOBAL_LIST_EMPTY(xform_owners)
/// Every rule, sorted by (priority, order).
GLOBAL_LIST_EMPTY(xform_rules)
/// medium => regime => the rules of that medium and regime, sorted (what a consumer walks to list every rule of a family).
GLOBAL_LIST_EMPTY(xform_by_regime)
/// medium => regime => anchor key => the rules that are candidates when a subject holds the key, sorted by (priority, order).
GLOBAL_LIST_EMPTY(xform_index)
/// medium => regime => product key => the rules that make it, in order (the reverse index the wiki, the handbooks and the synthesizer read).
GLOBAL_LIST_EMPTY(xform_by_product)
/// The table of a medium and regime that has no rules.
GLOBAL_LIST_EMPTY(xform_empty_table)

/// Sorts rules by priority, then by their stamped order.
/proc/cmp_xform_asc(datum/xform/a, datum/xform/b)
	if(a.priority != b.priority)
		return a.priority - b.priority
	return a.order - b.order

/// A compiled rule: the flat, read-only form the matcher uses. Built from the merged entry of a rule type; never written after the build.
/datum/xform
	var/rule_type
	var/name
	var/id
	var/desc
	var/medium
	var/regime = REGIME_INSTANT
	/// Rows of list(currency, key, amount, into).
	var/list/takes
	var/list/catalysts
	var/list/blocked_by
	var/list/makes
	/// The reagent terms as key => amount (the shape holders are asked in), or null.
	var/list/reagent_takes
	var/list/reagent_catalysts
	var/list/reagent_blocked
	/// The gas terms of a gas rule as gas type => minimum moles (the shape the dispatcher reads the mixture's readings in), or null.
	var/list/gas_takes
	/// A gas rule's temperature window (null: open), read from its temperature_in() condition.
	var/min_temp
	var/max_temp
	/// A gas rule that makes fires bigger (hotspot = TRUE).
	var/expands_hotspot = FALSE
	/// A kitchen rule's ingredients: the item types in order (one entry per term, duplicates kept) and the grown items by kitchen tag.
	var/list/cook_items
	var/list/fruit_takes
	var/cooks_in = 0
	var/cook_time = 0
	var/mix = 0
	/// The coating the items must carry: null for none, -1 for any, or a type.
	var/coating
	/// A fusion rule: its two reactants (the first two reagent terms of `takes`), the energy it consumes and releases, the radiation and instability it adds per pair,
	/// the field energy and temperature it needs, and what it makes (reagent id => amount per pair).
	var/reactant_a
	var/reactant_b
	var/energy_in = 0
	var/energy_out = 0
	var/radiation = 0
	var/instability = 0
	var/min_level = 0
	var/min_heat = 0
	var/list/field_products
	/// A stack recipe (chosen mode, code/library/transformations/stack_recipes.dm): its title, who it is for, what it costs and makes, and how it is built.
	var/title
	var/subject
	var/cost = 1
	var/max_made = 1
	var/build_time = 0
	var/one_per_turf = 0
	var/on_floor = 0
	var/use_material
	var/pass_color
	var/matter_material
	var/group
	var/replaces = FALSE
	var/list/drops
	/// Gas taken from the air around the subject once per step, gas => moles, or null.
	var/list/takes_ambient
	var/holds
	var/rate = RATE_INSTANT
	var/yield = 1
	var/floor = 2
	var/data_proc
	var/energy = 0
	var/heat_to = XFORM_HEAT_AIR
	var/priority = PRIORITY_DEFAULT
	/// The declaration order of the type (its place in subtypesof(/transformation)), stamped at compile: what decides between rules of one priority.
	var/order = 0
	var/capacity = CAPACITY_TRUNCATE
	var/says
	var/plays
	var/wiki = 0
	var/notice_type = /datum/notice/transformed
	var/then_proc
	var/important = FALSE
	// ---- derived at compile ----
	/// The first take's key: the index key.
	var/anchor
	/// The reagent a reagent rule makes and how much per reaction unit.
	var/result
	var/result_amount = 0
	/// The number of terms taken: the specificity of the rule.
	var/specificity = 0
	/// The type a subject_is() condition pins, or null.
	var/subject_type
	/// Rows of list(lo, hi): the temperature bounds of the rule's conditions, registered as watch bands.
	var/list/bands
	/// TRUE when nothing but data decides the rule: no `then`, no `data`, no PROC_REF condition.
	var/plain = TRUE

/// The instance that owns the rule's procs.
/datum/xform/proc/owner_of()
	RETURN_TYPE(/transformation)
	return GLOB.xform_owners[rule_type]

/// How far one step of the rule goes in `holder`, in reaction units, given its stoichiometric `reaction_limit` (react still caps it at the limit).
/// The maths is Rust's (verdigris/domains/chem/src/reaction.rs); DM gathers the numbers.
/datum/xform/proc/progress(datum/reagents/holder, reaction_limit)
	var/list/reactants = list()
	for(var/reactant in reagent_takes)
		reactants += holder.get_reagent_amount(reactant)
		reactants += LAZYACCESS(reagent_takes, reactant)
	// Catalytic material surfaces alter the ordinary reaction rate; no recipe knows an alloy name.
	var/multiplier = holder.my_atom?.material_reaction_rate_multiplier() || 1
	return vg_chem_reaction_progress(reaction_limit, rate, multiplier, yield, result_amount, result ? holder.get_reagent_amount(result) : 0, floor, reactants)

/// The rule of this type, or null when it is not one (a base, or not a transformation).
/proc/xform_of(rule_type)
	RETURN_TYPE(/datum/xform)
	static_entries_ensure("xform_of([rule_type])")
	return GLOB.xforms[rule_type]

/// The rules that are candidates for subjects holding `key` (its anchor bucket), sorted, or null.
/proc/xform_candidates(medium, regime, key)
	static_entries_ensure("xform_candidates([key])")
	var/list/by_regime = GLOB.xform_index[medium]
	var/list/by_key = by_regime?[regime]
	return by_key?[key]

/// The whole anchor table of a medium and regime: key => rules. The settle reads one entry per reagent of the subject.
/proc/xform_bucket_table(medium, regime)
	static_entries_ensure("xform_bucket_table([medium])")
	var/list/by_regime = GLOB.xform_index[medium]
	return by_regime?[regime] || GLOB.xform_empty_table

/// Every rule of a medium and regime, sorted. The list is shared: read it, never write it.
/proc/xform_rules_in(medium, regime)
	RETURN_TYPE(/list)
	static_entries_ensure("xform_rules_in([medium])")
	var/list/by_regime = GLOB.xform_by_regime[medium]
	return by_regime?[regime] || GLOB.xform_empty_table

/// The rules that make `key`, in order (the reverse index).
/proc/xform_makers_of(medium, regime, key)
	static_entries_ensure("xform_makers_of([key])")
	var/list/by_regime = GLOB.xform_by_product[medium]
	var/list/by_key = by_regime?[regime]
	return by_key?[key]

/datum/entry_engine/transformation/static_built(list/by_type)
	xform_build(by_type)

/// Compiles every rule: one /datum/xform per type that declares a transformation() with takes, its owner instance, the index and the product index.
/// Reports a rule that cannot compile (an unknown medium, a capacity not built, takes with no key) and leaves it out.
/proc/xform_build(list/by_type)
	var/started = REALTIMEOFDAY
	GLOB.xforms = list()
	GLOB.xform_owners = list()
	GLOB.xform_rules = list()
	GLOB.xform_index = list()
	GLOB.xform_by_product = list()
	GLOB.xform_by_regime = list()
	var/list/order_of = list()
	var/place = 0
	for(var/type in typesof(/transformation))
		order_of[type] = ++place
	var/list/declaring = list()
	for(var/type in by_type)
		var/datum/type_table/T = by_type[type]
		if(T.owner_type == type)
			declaring += type
	sortTim(declaring, GLOBAL_PROC_REF(cmp_type_text_asc))
	for(var/type in declaring)
		var/datum/type_table/T = by_type[type]
		var/datum/centry/C = static_find(T, ENTRY_TRANSFORMATION)
		var/datum/entry/E = C?.item
		if(!E || (!length(E.args?["takes"]) && !E.args?["chosen"]))
			continue // a base: defaults for the rules under it
		var/datum/xform/X = xform_compile(type, E, order_of[type], C.origin)
		if(!X)
			continue
		GLOB.xforms[type] = X
		GLOB.xform_rules += X
	sortTim(GLOB.xform_rules, GLOBAL_PROC_REF(cmp_xform_asc))
	for(var/datum/xform/X as anything in GLOB.xform_rules)
		GLOB.xform_owners[X.rule_type] = new X.rule_type
		var/list/by_regime = GLOB.xform_index[X.medium]
		if(!by_regime)
			by_regime = list()
			GLOB.xform_index[X.medium] = by_regime
		var/list/by_key = by_regime[X.regime]
		if(!by_key)
			by_key = list()
			by_regime[X.regime] = by_key
		LAZYINITLIST(by_key[X.anchor])
		by_key[X.anchor] += X
		var/list/listed_by_regime = GLOB.xform_by_regime[X.medium]
		if(!listed_by_regime)
			listed_by_regime = list()
			GLOB.xform_by_regime[X.medium] = listed_by_regime
		LAZYINITLIST(listed_by_regime[X.regime])
		listed_by_regime[X.regime] += X
		if(X.result)
			var/list/products_by_regime = GLOB.xform_by_product[X.medium]
			if(!products_by_regime)
				products_by_regime = list()
				GLOB.xform_by_product[X.medium] = products_by_regime
			var/list/by_product = products_by_regime[X.regime]
			if(!by_product)
				by_product = list()
				products_by_regime[X.regime] = by_product
			LAZYINITLIST(by_product[X.result])
			by_product[X.result] += X
	log_world("Transformations compiled: [length(GLOB.xform_rules)] rule(s) in [(REALTIMEOFDAY - started) / 10] s")

/// One rule's flyweight from its merged entry, or null (and a report) when it cannot compile.
/proc/xform_compile(type, datum/entry/E, order, origin)
	RETURN_TYPE(/datum/xform)
	var/list/arguments = E.args
	var/datum/xform/X = new
	X.rule_type = type
	X.order = order
	X.takes = xform_rows(arguments["takes"])
	X.catalysts = xform_rows(arguments["catalysts"])
	X.blocked_by = xform_rows(arguments["blocked_by"])
	X.makes = xform_rows(arguments["makes"])
	if(!length(X.takes) && !arguments["chosen"])
		declare_report("[origin]: [type]: transformation() takes no terms -- a rule takes at least one")
		return null
	X.anchor = length(X.takes) ? X.takes[1][2] : type
	X.specificity = length(X.takes)
	X.medium = arguments["medium"] || (length(X.takes) ? xform_medium_of(X.takes[1][1]) : null)
	if(!X.medium)
		declare_report("[origin]: [type]: no medium for currency [X.takes[1][1]] -- name it with medium =")
		return null
	X.regime = arguments["regime"] || REGIME_INSTANT
	X.name = arguments["name"]
	X.id = arguments["id"]
	X.desc = arguments["desc"]
	X.expands_hotspot = !!arguments["hotspot"]
	X.holds = arguments["holds"]
	if(!isnull(arguments["rate"]))
		X.rate = arguments["rate"]
	if(!isnull(arguments["yield"]))
		X.yield = arguments["yield"]
	if(!isnull(arguments["floor"]))
		X.floor = arguments["floor"]
	X.data_proc = "[xform_proc_name(arguments["data"])]" // a proc name (text): "" when there is none
	if(!isnull(arguments["energy"]))
		X.energy = arguments["energy"]
	if(arguments["heat_to"])
		X.heat_to = arguments["heat_to"]
	if(!isnull(arguments["priority"]))
		X.priority = arguments["priority"]
	var/capacity = arguments["capacity"] || CAPACITY_TRUNCATE
	if(capacity != CAPACITY_TRUNCATE)
		declare_report("[origin]: [type]: capacity = [capacity] is not built -- only CAPACITY_TRUNCATE is (D10: a family flips through intended_changes.md)")
		return null
	X.capacity = capacity
	X.says = arguments["says"]
	X.plays = arguments["plays"]
	if(arguments["notice"])
		X.notice_type = arguments["notice"]
	X.then_proc = "[xform_proc_name(arguments["then"])]" // a proc name (text): "" when there is none
	X.important = !!arguments["important"]
	X.wiki = arguments["wiki"] || 0
	if(X.medium == MEDIUM_FIELD)
		if(length(X.takes) >= 2)
			X.reactant_a = X.takes[1][2]
			X.reactant_b = X.takes[2][2]
		X.field_products = xform_assoc(X.makes, XCUR_REAGENT)
		X.energy_in = arguments["energy_in"] || 0
		X.energy_out = arguments["energy_out"] || 0
		X.radiation = arguments["radiation"] || 0
		X.instability = arguments["instability"] || 0
		X.min_level = arguments["min_level"] || 0
		X.min_heat = arguments["min_heat"] || 0
	if(X.medium == MEDIUM_CONTENTS)
		X.reagent_takes = xform_assoc(X.takes, XCUR_REAGENT)
		X.fruit_takes = xform_assoc(X.takes, XCUR_FRUIT)
		for(var/list/row as anything in X.takes)
			if(row[1] == XCUR_ITEM)
				LAZYADD(X.cook_items, row[2])
		for(var/list/row as anything in X.makes)
			if(row[1] == XCUR_ITEM)
				X.result = row[2]
				X.result_amount = row[3]
				break
		X.cooks_in = arguments["cooks_in"] || 0
		X.cook_time = arguments["cook_time"] || 0
		X.mix = arguments["mix"] || 0
		X.coating = arguments["coating"]
	if(arguments["chosen"])
		xform_compile_chosen(X, arguments["chosen"])
	if(X.medium == MEDIUM_REAGENTS)
		X.reagent_takes = xform_assoc(X.takes, XCUR_REAGENT)
		X.reagent_catalysts = xform_assoc(X.catalysts, XCUR_REAGENT)
		X.reagent_blocked = xform_assoc(X.blocked_by, XCUR_REAGENT)
		for(var/list/row as anything in X.makes)
			if(row[1] == XCUR_REAGENT)
				X.result = row[2]
				X.result_amount = row[3]
				break
		if(!X.result && !isnull(arguments["made"]))
			X.result_amount = arguments["made"]
	if(X.medium == MEDIUM_GAS)
		X.gas_takes = xform_assoc(X.takes, XCUR_GAS)
	for(var/list/row as anything in xform_rows(arguments["takes_ambient"]))
		LAZYSET(X.takes_ambient, row[2], row[3])
	X.bands = xform_cond_bands(X.holds)
	if(X.medium == MEDIUM_GAS && length(X.bands))
		X.min_temp = X.bands[1][1]
		X.max_temp = X.bands[1][2]
	X.subject_type = text2path("[xform_cond_subject_type(X.holds)]") // a type path, or null
	X.plain = !X.then_proc && !X.data_proc && !xform_cond_calls_proc(X.holds)
	return X

/// The medium a currency lives in, when a rule does not name one.
/proc/xform_medium_of(currency)
	switch(currency)
		if(XCUR_REAGENT)
			return MEDIUM_REAGENTS
		if(XCUR_GAS)
			return MEDIUM_GAS
		if(XCUR_ITEM, XCUR_STACK, XCUR_FRUIT)
			return MEDIUM_CONTENTS
		if(XCUR_ORE)
			return MEDIUM_ORE_STOCK
	return null
