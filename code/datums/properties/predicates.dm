// Predicates (doc/rewrite/rules.md ยง2): a small compiled language over
// properties and the (actor, target, held) context, with reasons.
//
// Declaring. A predicate is a list of clause specs built with the REQ_* macros
// (code/__defines/predicates.dm). Either subclass /datum/predicate and set
// `spec`, or hand a spec and a stable key to dq_predicate_for() (interaction
// and ability definitions use their type as the key).
//
// Compiling. Each declaration compiles once, against the property registry,
// into a tree of shared /datum/pred_node singletons. Compilation checks every
// property id, kind and unit; a kelvin property compared with kilograms is an
// error. SSproperties compiles every /datum/predicate subtype at boot and
// fails on any error. NOT is pushed into the leaves (De Morgan), so evaluation
// never has a negation node and comparison nodes hold their effective operator.
//
// Evaluating. check() and why_not() walk the tree, short-circuit, and allocate
// nothing on success. On failure the first failing leaf (or the innermost
// REQ_BECAUSE / OR node) generates the reason text, only then.
//
// Watches (for P4). Comparison and band nodes over channel-backed properties
// (a PROP_SOURCE_DOMAIN base provider) get `watch_kind` set and are listed in
// the predicate's `watchable`. P4 maps them to reactor watches:
//   /datum/pred_node/cmp   Threshold: property, op, value (op already negated).
//   /datum/pred_node/band  Band: property, lo, hi, outside.
//   /datum/pred_node/rel   Difference: prop_a on subject_a against prop_b on subject_b.

// ---- Predicates ----

/datum/predicate
	var/name
	/// The declaration: a list of clause specs, all of which must pass.
	var/list/spec
	/// Test fixtures set this so boot validation skips them.
	var/test_only = FALSE
	/// Compiled tree. Shared, never mutated after compile().
	var/datum/pred_node/root
	/// Compile errors, or null.
	var/list/errors
	/// Nodes P4 can turn into reactor watches.
	var/list/watchable

/// Compile `spec` against `registry` (default: the global one). Called once.
/datum/predicate/proc/compile(datum/property_registry/registry)
	var/datum/predicate_compiler/compiler = new(registry || dq_property_registry(), name || "[type]")
	root = compiler.compile_spec(spec)
	errors = length(compiler.errors) ? compiler.errors : null
	watchable = length(compiler.watchable) ? compiler.watchable : null
	if(errors)
		root = new /datum/pred_node/invalid
	return !errors

/// TRUE if every clause passes.
/datum/predicate/proc/check(mob/actor, atom/target, obj/item/held)
	return root.first_failure(actor, target, held) ? FALSE : TRUE

/// null if the predicate passes, else the reason from the first failing clause.
/datum/predicate/proc/why_not(mob/actor, atom/target, obj/item/held)
	var/datum/pred_node/failed = root.first_failure(actor, target, held)
	return failed?.reason(actor, target, held)

/// The compiled predicate for a /datum/predicate subtype: one shared instance.
/proc/dq_predicate(path)
	var/static/list/cache = list()
	. = cache[path]
	if(.)
		return .
	var/datum/predicate/P = new path
	if(!P.compile())
		stack_trace("predicate [path] failed to compile: [jointext(P.errors, "; ")]")
	cache[path] = P
	return P

/// The compiled predicate for an inline spec, compiled once per `key`. The
/// spec for a given key must not change.
/proc/dq_predicate_for(key, list/spec, name)
	var/static/list/cache = list()
	. = cache[key]
	if(.)
		return .
	var/datum/predicate/P = new
	P.spec = spec
	P.name = name || "[key]"
	if(!P.compile())
		stack_trace("predicate [key] failed to compile: [jointext(P.errors, "; ")]")
	cache[key] = P
	return P

/// Boot validation: compile every declared /datum/predicate subtype. Returns error strings.
/proc/dq_predicates_validate(datum/property_registry/registry)
	. = list()
	for(var/path in subtypesof(/datum/predicate))
		var/datum/predicate/P = new path
		if(P.test_only || isnull(P.spec))
			continue
		if(!P.compile(registry))
			for(var/error in P.errors)
				. += "[error]"

// ---- Compiler ----

/datum/predicate_compiler
	var/datum/property_registry/registry
	var/label
	var/list/errors = list()
	var/list/watchable = list()

/datum/predicate_compiler/New(datum/property_registry/registry, label)
	..()
	src.registry = registry
	src.label = label

/datum/predicate_compiler/proc/error(text)
	errors += "predicate [label]: [text]"

/// A whole spec: a list of clauses (implicit AND), or one clause.
/datum/predicate_compiler/proc/compile_spec(list/spec)
	if(!islist(spec) || !length(spec))
		error("has no clauses")
		return null
	if(istext(spec[1]))
		return compile_clause(spec, FALSE)
	return compile_group(spec, 1, FALSE, FALSE)

/// Clauses spec[start..] combined with AND (or OR when `any`), under `negate`.
/datum/predicate_compiler/proc/compile_group(list/spec, start, any, negate)
	// NOT(AND) = OR(NOT), NOT(OR) = AND(NOT).
	var/is_or = any != negate
	var/list/children = list()
	for(var/i in start to length(spec))
		var/datum/pred_node/child = compile_clause(spec[i], negate)
		if(child)
			children += child
	if(!length(children))
		error("has an empty [any ? "ANY" : "ALL"]")
		return null
	if(length(children) == 1)
		return children[1]
	var/datum/pred_node/group/node = is_or ? new /datum/pred_node/group/any : new /datum/pred_node/group/all
	node.children = children
	return node

/datum/predicate_compiler/proc/compile_clause(list/clause, negate)
	if(!islist(clause) || !length(clause) || !istext(clause[1]))
		error("[clause] is not a clause; build clauses with the REQ_* macros")
		return null
	var/op = clause[1]
	switch(op)
		if(PRED_OP_AND)
			return compile_group(clause, 2, FALSE, negate)
		if(PRED_OP_OR)
			return compile_group(clause, 2, TRUE, negate)
		if(PRED_OP_NOT)
			if(!arity(clause, 2))
				return null
			return compile_clause(clause[2], !negate)
		if(PRED_OP_BECAUSE)
			if(!arity(clause, 3))
				return null
			var/datum/pred_node/inner = compile_clause(clause[2], negate)
			if(!istext(clause[3]))
				error("REQ_BECAUSE needs reason text")
			if(inner)
				inner.reason_text = clause[3]
			return inner
		if(PRED_OP_TAG)
			return compile_tag(clause, negate)
		if(PRED_OP_CMP)
			return compile_cmp(clause, negate)
		if(PRED_OP_BAND)
			return compile_band(clause, negate)
		if(PRED_OP_REL)
			return compile_rel(clause, negate)
		if(PRED_OP_TOOL)
			if(!arity(clause, 3))
				return null
			if(!istext(clause[2]) || !isnum(clause[3]) || clause[3] < 1)
				error("REQ_TOOL needs a TOOL_* quality and a tier of 1 or more")
				return null
			var/datum/pred_node/tool/node = leaf(/datum/pred_node/tool, negate)
			node.quality = clause[2]
			node.tier = clause[3]
			return node
		if(PRED_OP_TYPE)
			if(!arity(clause, 3) || !valid_subject(clause[2]))
				return null
			if(!islist(clause[3]))
				error("REQ_TYPE needs a list of types")
				return null
			for(var/path in clause[3])
				if(!ispath(path))
					error("REQ_TYPE lists [path], which is not a type")
					return null
			var/datum/pred_node/type/node = leaf(/datum/pred_node/type, negate)
			node.subject = clause[2]
			node.types = typecacheof(clause[3])
			return node
		if(PRED_OP_FITS)
			if(!arity(clause, 2))
				return null
			if(!islist(clause[2]))
				error("REQ_FITS_BODYTYPES needs a list of body types")
				return null
			var/list/bodytypes = clause[2]
			var/datum/pred_node/fits/node = leaf(/datum/pred_node/fits, negate)
			node.bodytypes = bodytypes.Copy()
			node.exclusive = ("exclude" in bodytypes)
			return node
		if(PRED_OP_HAND_FREE)
			return leaf(/datum/pred_node/hand_free, negate)
		if(PRED_OP_HOLDING)
			return leaf(/datum/pred_node/holding, negate)
		if(PRED_OP_ADJACENT)
			return leaf(/datum/pred_node/adjacent, negate)
		if(PRED_OP_SELF)
			return leaf(/datum/pred_node/self, negate)
		if(PRED_OP_IN_HAND)
			return leaf(/datum/pred_node/in_hand, negate)
		if(PRED_OP_RANGE)
			if(!arity(clause, 2))
				return null
			if(!isnum(clause[2]) || clause[2] < 0)
				error("REQ_REACH needs a tile count")
				return null
			var/datum/pred_node/range/node = leaf(/datum/pred_node/range, negate)
			node.tiles = clause[2]
			return node
		if(PRED_OP_PROC)
			if(!arity(clause, 4))
				return null
			var/subject = clause[2]
			if(subject != PRED_GLOBAL && !valid_subject(subject))
				return null
			if(isnull(clause[3]))
				error("a proc clause has no proc")
				return null
			if(!isnull(clause[4]) && !istext(clause[4]))
				error("a proc clause's reason must be text")
			var/datum/pred_node/call_proc/node = leaf(/datum/pred_node/call_proc, negate)
			node.subject = subject
			node.proc_path = clause[3]
			node.fallback = clause[4]
			return node
	error("unknown clause [op]")
	return null

/datum/predicate_compiler/proc/leaf(path, negate)
	var/datum/pred_node/node = new path
	node.negate = negate
	return node

/datum/predicate_compiler/proc/arity(list/clause, count)
	if(length(clause) == count)
		return TRUE
	error("[clause[1]] clause has [length(clause)] parts, expected [count]")
	return FALSE

/datum/predicate_compiler/proc/valid_subject(subject)
	if(subject == PRED_ACTOR || subject == PRED_TARGET || subject == PRED_HELD)
		return TRUE
	error("unknown subject [subject]; use PRED_ACTOR, PRED_TARGET or PRED_HELD")
	return FALSE

/// The measure definition for `id`, or null after reporting why not.
/datum/predicate_compiler/proc/measure(id)
	var/datum/property_def/def = registry.defs[id]
	if(!def)
		error("unknown property [id]")
		return null
	if(def.kind != PROP_KIND_MEASURE)
		error("[id] is a tag; compare it with REQ_TAG")
		return null
	return def

/// Whether `value unit` is a valid literal for `def`, reporting why not.
/datum/predicate_compiler/proc/unit_matches(datum/property_def/def, value, unit)
	if(!isnum(value))
		error("compares [def.id] with [value], which is not a number")
		return FALSE
	if(unit != def.unit)
		error("compares [def.id] ([def.unit]) with [value] [isnull(unit) ? "(no unit)" : unit]")
		return FALSE
	return TRUE

/// Channel-backed properties can become reactor watches (P4).
/datum/predicate_compiler/proc/channel_backed(id)
	for(var/datum/property_provider/provider as anything in registry.base_providers[id])
		if(provider.source == PROP_SOURCE_DOMAIN)
			return TRUE
	return FALSE

/datum/predicate_compiler/proc/compile_tag(list/clause, negate)
	if(!arity(clause, 3) || !valid_subject(clause[2]))
		return null
	var/datum/property_def/def = registry.defs[clause[3]]
	if(!def)
		error("unknown tag [clause[3]]")
		return null
	if(def.kind != PROP_KIND_TAG)
		error("[def.id] is a measure; compare it with REQ_ABOVE, REQ_BELOW and friends")
		return null
	var/datum/pred_node/tag/node = leaf(/datum/pred_node/tag, negate)
	node.subject = clause[2]
	node.property = def.id
	node.def = def
	return node

/datum/predicate_compiler/proc/compile_cmp(list/clause, negate)
	// cmp, subject, property, op, value, unit
	if(length(clause) == 5)
		error("compares [clause[3]] with a bare number [clause[5]]; wrap it in a unit literal such as KG() or KELVIN()")
		return null
	if(!arity(clause, 6) || !valid_subject(clause[2]))
		return null
	var/datum/property_def/def = measure(clause[3])
	if(!def || !unit_matches(def, clause[5], clause[6]))
		return null
	var/op = clause[4]
	if(!dq_pred_valid_cmp(op))
		error("unknown comparison [op]")
		return null
	var/datum/pred_node/cmp/node = new
	node.subject = clause[2]
	node.property = def.id
	node.def = def
	node.op = negate ? dq_pred_invert_cmp(op) : op
	node.value = clause[5]
	if(node.op != PRED_CMP_EQ && node.op != PRED_CMP_NE && channel_backed(def.id))
		node.watch_kind = PRED_WATCH_THRESHOLD
		watchable += node
	return node

/datum/predicate_compiler/proc/compile_band(list/clause, negate)
	// band, subject, property, lo, lo unit, hi, hi unit
	if(!arity(clause, 7) || !valid_subject(clause[2]))
		return null
	var/datum/property_def/def = measure(clause[3])
	if(!def || !unit_matches(def, clause[4], clause[5]) || !unit_matches(def, clause[6], clause[7]))
		return null
	if(clause[4] > clause[6])
		error("REQ_BETWEEN on [def.id] has its bounds reversed")
		return null
	var/datum/pred_node/band/node = new
	node.subject = clause[2]
	node.property = def.id
	node.def = def
	node.lo = clause[4]
	node.hi = clause[6]
	node.outside = negate
	if(channel_backed(def.id))
		node.watch_kind = PRED_WATCH_BAND
		watchable += node
	return node

/datum/predicate_compiler/proc/compile_rel(list/clause, negate)
	// rel, subject a, property a, op, subject b, property b
	if(!arity(clause, 6) || !valid_subject(clause[2]) || !valid_subject(clause[5]))
		return null
	var/datum/property_def/def_a = measure(clause[3])
	var/datum/property_def/def_b = measure(clause[6])
	if(!def_a || !def_b)
		return null
	if(def_a.unit != def_b.unit)
		error("compares [def_a.id] ([def_a.unit]) with [def_b.id] ([def_b.unit])")
		return null
	var/op = clause[4]
	if(!dq_pred_valid_cmp(op))
		error("unknown comparison [op]")
		return null
	var/datum/pred_node/rel/node = new
	node.subject = clause[2]
	node.property = def_a.id
	node.def = def_a
	node.op = negate ? dq_pred_invert_cmp(op) : op
	node.subject_b = clause[5]
	node.property_b = def_b.id
	if(node.op != PRED_CMP_EQ && node.op != PRED_CMP_NE && channel_backed(def_a.id) && channel_backed(def_b.id))
		node.watch_kind = PRED_WATCH_DIFFERENCE
		watchable += node
	return node

/proc/dq_pred_valid_cmp(op)
	return op == PRED_CMP_GT || op == PRED_CMP_GTE || op == PRED_CMP_LT || op == PRED_CMP_LTE || op == PRED_CMP_EQ || op == PRED_CMP_NE

/proc/dq_pred_invert_cmp(op)
	switch(op)
		if(PRED_CMP_GT)
			return PRED_CMP_LTE
		if(PRED_CMP_GTE)
			return PRED_CMP_LT
		if(PRED_CMP_LT)
			return PRED_CMP_GTE
		if(PRED_CMP_LTE)
			return PRED_CMP_GT
		if(PRED_CMP_EQ)
			return PRED_CMP_NE
		if(PRED_CMP_NE)
			return PRED_CMP_EQ

/proc/dq_pred_compare(a, op, b)
	switch(op)
		if(PRED_CMP_GT)
			return a > b
		if(PRED_CMP_GTE)
			return a >= b
		if(PRED_CMP_LT)
			return a < b
		if(PRED_CMP_LTE)
			return a <= b
		if(PRED_CMP_EQ)
			return a == b
		if(PRED_CMP_NE)
			return a != b
	return FALSE

// ---- Reason helpers ----

/// "12 kg", "size 3", "373.15 K".
/proc/dq_format_measure(value, unit)
	if(isnull(value))
		return "unknown"
	var/text = "[round(value, 0.01)]"
	switch(unit)
		if(PROP_UNIT_SIZE_CLASS)
			return "size [text]"
		if(PROP_UNIT_RATIO, null)
			return text
	return "[text] [unit]"

/// "a welder", "an analyzer".
/proc/dq_pred_article(noun)
	return "[(copytext(noun, 1, 2) in list("a", "e", "i", "o", "u")) ? "an" : "a"] [noun]"

/proc/dq_pred_tool_name(quality)
	switch(quality)
		if(TOOL_CABLE_COIL)
			return "cable coil"
		if(TOOL_BLOODFILTER)
			return "blood filter"
		if(TOOL_ROLLINGPIN)
			return "rolling pin"
		if(TOOL_MINING)
			return "mining tool"
	return quality

/// "too heavy" / "mass too high", said of `subject`.
/proc/dq_pred_extreme_text(datum/property_def/def, subject, high)
	var/word = high ? def.high_word : def.low_word
	if(word)
		switch(subject)
			if(PRED_ACTOR)
				return "you are too [word]"
			if(PRED_HELD)
				return "the held item is too [word]"
		return "too [word]"
	var/what = lowertext(def.name || def.id)
	var/direction = high ? "high" : "low"
	switch(subject)
		if(PRED_ACTOR)
			return "your [what] is too [direction]"
		if(PRED_HELD)
			return "the held item's [what] is too [direction]"
	return "[what] too [direction]"

/proc/dq_pred_subject(subject, mob/actor, atom/target, obj/item/held)
	switch(subject)
		if(PRED_ACTOR)
			return actor
		if(PRED_TARGET)
			return target
		if(PRED_HELD)
			return held
	return null

// ---- Nodes ----

/datum/pred_node
	/// Leaves only: pass when the raw test is FALSE.
	var/negate = FALSE
	/// REQ_BECAUSE text, replacing the generated reason.
	var/reason_text
	/// PRED_WATCH_* when P4 can turn this node into a reactor watch.
	var/watch_kind

/// null if this node passes, else the node whose reason explains the failure.
/datum/pred_node/proc/first_failure(mob/actor, atom/target, obj/item/held)
	return (test(actor, target, held) ? TRUE : FALSE) != negate ? null : src

/// Leaves: the raw (un-negated) test.
/datum/pred_node/proc/test(mob/actor, atom/target, obj/item/held)
	return FALSE

/datum/pred_node/proc/reason(mob/actor, atom/target, obj/item/held)
	return reason_text || generate_reason(actor, target, held)

/// The generated reason for this node failing (with `negate` applied).
/datum/pred_node/proc/generate_reason(mob/actor, atom/target, obj/item/held)
	return "not possible"

/datum/pred_node/invalid/test()
	return FALSE

/datum/pred_node/invalid/generate_reason()
	return "misconfigured (see the property registry errors)"

// ---- Combinators ----

/datum/pred_node/group
	var/list/children

/datum/pred_node/group/all/first_failure(mob/actor, atom/target, obj/item/held)
	for(var/datum/pred_node/child as anything in children)
		var/datum/pred_node/failed = child.first_failure(actor, target, held)
		if(failed)
			return reason_text ? src : failed
	return null

/datum/pred_node/group/all/generate_reason(mob/actor, atom/target, obj/item/held)
	for(var/datum/pred_node/child as anything in children)
		var/datum/pred_node/failed = child.first_failure(actor, target, held)
		if(failed)
			return failed.reason(actor, target, held)
	return "not possible"

/datum/pred_node/group/any/first_failure(mob/actor, atom/target, obj/item/held)
	for(var/datum/pred_node/child as anything in children)
		if(!child.first_failure(actor, target, held))
			return null
	return src

/// "needs a welder or needs a free hand". Failure path only.
/datum/pred_node/group/any/generate_reason(mob/actor, atom/target, obj/item/held)
	var/list/reasons = list()
	for(var/datum/pred_node/child as anything in children)
		var/datum/pred_node/failed = child.first_failure(actor, target, held)
		if(failed)
			reasons |= failed.reason(actor, target, held)
	return jointext(reasons, " or ")

// ---- Properties ----

/datum/pred_node/tag
	var/subject
	var/property
	var/datum/property_def/def

/datum/pred_node/tag/test(mob/actor, atom/target, obj/item/held)
	var/datum/thing = dq_pred_subject(subject, actor, target, held)
	return thing ? dq_has_tag(thing, property) : FALSE

/datum/pred_node/tag/generate_reason(mob/actor, atom/target, obj/item/held)
	var/adjective = def.adjective || lowertext(def.name || def.id)
	switch(subject)
		if(PRED_ACTOR)
			return negate ? "you must not be [adjective]" : "you must be [adjective]"
		if(PRED_HELD)
			return negate ? "the held item must not be [adjective]" : "needs something [adjective] in hand"
	return negate ? "must not be [adjective]" : "must be [adjective]"

/datum/pred_node/cmp
	var/subject
	var/property
	var/datum/property_def/def
	/// Effective operator, with any NOT already applied.
	var/op
	var/value

/datum/pred_node/cmp/test(mob/actor, atom/target, obj/item/held)
	var/datum/thing = dq_pred_subject(subject, actor, target, held)
	if(!thing)
		return FALSE
	var/current = dq_property(thing, property)
	if(isnull(current))
		return FALSE
	return dq_pred_compare(current, op, value)

/datum/pred_node/cmp/generate_reason(mob/actor, atom/target, obj/item/held)
	var/datum/thing = dq_pred_subject(subject, actor, target, held)
	if(!thing)
		return "needs something in hand"
	return dq_pred_cmp_reason(def, subject, dq_property(thing, property), op, value)

/// Reason for `current op limit` having failed, e.g. "too heavy: 12 kg > 5 kg".
/proc/dq_pred_cmp_reason(datum/property_def/def, subject, current, op, limit)
	var/unit = def.unit
	var/shown_limit = dq_format_measure(limit, unit)
	if(isnull(current))
		return "[lowertext(def.name || def.id)] unknown"
	var/shown = dq_format_measure(current, unit)
	switch(op)
		if(PRED_CMP_EQ)
			return "[lowertext(def.name || def.id)] must be [shown_limit], is [shown]"
		if(PRED_CMP_NE)
			return "[lowertext(def.name || def.id)] must not be [shown_limit]"
	var/high = (op == PRED_CMP_LT || op == PRED_CMP_LTE)
	var/text = dq_pred_extreme_text(def, subject, high)
	if(current == limit)
		return "[text]: [shown], must be [high ? "below" : "above"] [shown_limit]"
	return "[text]: [shown] [current > limit ? ">" : "<"] [shown_limit]"

/datum/pred_node/band
	var/subject
	var/property
	var/datum/property_def/def
	var/lo
	var/hi
	/// Negated: pass outside lo..hi.
	var/outside = FALSE

/datum/pred_node/band/first_failure(mob/actor, atom/target, obj/item/held)
	return test(actor, target, held) ? null : src

/datum/pred_node/band/test(mob/actor, atom/target, obj/item/held)
	var/datum/thing = dq_pred_subject(subject, actor, target, held)
	if(!thing)
		return FALSE
	var/current = dq_property(thing, property)
	if(isnull(current))
		return FALSE
	return (current >= lo && current <= hi) != outside

/datum/pred_node/band/generate_reason(mob/actor, atom/target, obj/item/held)
	var/datum/thing = dq_pred_subject(subject, actor, target, held)
	if(!thing)
		return "needs something in hand"
	var/current = dq_property(thing, property)
	if(isnull(current))
		return "[lowertext(def.name || def.id)] unknown"
	var/range = "[dq_format_measure(lo, def.unit)] to [dq_format_measure(hi, def.unit)]"
	if(outside)
		return "[lowertext(def.name || def.id)] must be outside [range], is [dq_format_measure(current, def.unit)]"
	return "[dq_pred_extreme_text(def, subject, current > hi)]: [dq_format_measure(current, def.unit)], must be [range]"

/datum/pred_node/rel
	var/subject
	var/property
	var/datum/property_def/def
	var/op
	var/subject_b
	var/property_b

/datum/pred_node/rel/first_failure(mob/actor, atom/target, obj/item/held)
	return test(actor, target, held) ? null : src

/datum/pred_node/rel/test(mob/actor, atom/target, obj/item/held)
	var/datum/a = dq_pred_subject(subject, actor, target, held)
	var/datum/b = dq_pred_subject(subject_b, actor, target, held)
	if(!a || !b)
		return FALSE
	var/value_a = dq_property(a, property)
	var/value_b = dq_property(b, property_b)
	if(isnull(value_a) || isnull(value_b))
		return FALSE
	return dq_pred_compare(value_a, op, value_b)

/datum/pred_node/rel/generate_reason(mob/actor, atom/target, obj/item/held)
	var/datum/a = dq_pred_subject(subject, actor, target, held)
	var/datum/b = dq_pred_subject(subject_b, actor, target, held)
	if(!a || !b)
		return "needs something in hand"
	return dq_pred_cmp_reason(def, subject, dq_property(a, property), op, dq_property(b, property_b))

// ---- Types and fit (constraints, rules.md ง3) ----

/datum/pred_node/type
	var/subject
	/// typecacheof() the listed types.
	var/list/types

/datum/pred_node/type/test(mob/actor, atom/target, obj/item/held)
	var/datum/thing = dq_pred_subject(subject, actor, target, held)
	return thing ? (types[thing.type] ? TRUE : FALSE) : FALSE

/datum/pred_node/type/generate_reason()
	return negate ? "not that kind of thing" : "only takes certain things"

/// The legacy species_restricted rules, as a clause: `bodytypes` lists the
/// body types that fit, or starts with "exclude" and lists those that don't.
/datum/pred_node/fits
	var/list/bodytypes
	var/exclusive = FALSE

/datum/pred_node/fits/test(mob/actor, atom/target, obj/item/held)
	if(!ishuman(actor) || !isitem(target))
		return TRUE
	var/mob/living/carbon/human/H = actor
	if(!H.species)
		return TRUE
	var/obj/item/I = target
	return dq_fits_bodytype(bodytypes, exclusive, H.species.get_bodytype(H), I.sprite_sheets)

/datum/pred_node/fits/generate_reason(mob/actor, atom/target, obj/item/held)
	if(negate)
		return "it fits you"
	var/bodytype = "your body"
	if(ishuman(actor))
		var/mob/living/carbon/human/H = actor
		bodytype = H.species?.get_bodytype(H) || bodytype
	if(exclusive)
		return "it doesn't fit a [bodytype]"
	var/list/names = bodytypes.Copy()
	if(length(names) > 3)
		return "it isn't made for a [bodytype]"
	return "it only fits [english_list(names, and_text = " or ")]"

/// Whether clothing restricted to `bodytypes` fits `bodytype`. Custom-fitted
/// Vox, Werebeast and Teshari clothing fits only them, and Teshari and
/// Werebeasts need their own sprites for anything restricted.
/proc/dq_fits_bodytype(list/bodytypes, exclusive, bodytype, list/sprite_sheets)
	if(exclusive)
		return !(bodytype in bodytypes)
	if(bodytype in bodytypes)
		return TRUE
	if(((SPECIES_VOX in bodytypes) && bodytype != SPECIES_VOX) || ((SPECIES_WEREBEAST in bodytypes) && bodytype != SPECIES_WEREBEAST) || ((SPECIES_TESHARI in bodytypes) && bodytype != SPECIES_TESHARI))
		return FALSE
	if((bodytype == SPECIES_TESHARI || bodytype == SPECIES_WEREBEAST) && !LAZYACCESS(sprite_sheets, bodytype))
		return FALSE
	return TRUE

// ---- Relationships ----

/datum/pred_node/tool
	var/quality
	var/tier = 1

/datum/pred_node/tool/test(mob/actor, atom/target, obj/item/held)
	if(!held || !held.has_tool_quality(quality))
		return FALSE
	return tier <= 1 || dq_tool_tier(held, quality) >= tier

/datum/pred_node/tool/generate_reason()
	var/tool = dq_pred_article(dq_pred_tool_name(quality))
	if(negate)
		return "can't be done with [tool]"
	return tier > 1 ? "needs [tool] (tier [tier])" : "needs [tool]"

/// Tier of `quality` on `I`: its value in an associative tool_qualities list, else 1.
/proc/dq_tool_tier(obj/item/I, quality)
	if(!I.has_tool_quality(quality))
		return 0
	var/tier = I.tool_qualities[quality]
	return isnum(tier) ? tier : 1

/datum/pred_node/hand_free/test(mob/actor)
	return actor ? actor.dq_has_free_hand() : FALSE

/datum/pred_node/hand_free/generate_reason()
	return negate ? "needs your hands full" : "needs a free hand"

/datum/pred_node/holding/test(mob/actor, atom/target, obj/item/held)
	return held ? TRUE : FALSE

/datum/pred_node/holding/generate_reason()
	return negate ? "needs an empty hand" : "needs something in hand"

/datum/pred_node/adjacent/test(mob/actor, atom/target)
	return (actor && target) ? actor.Adjacent(target) : FALSE

/datum/pred_node/adjacent/generate_reason()
	return negate ? "too close" : "too far away"

/datum/pred_node/range
	var/tiles

/datum/pred_node/range/test(mob/actor, atom/target)
	if(!actor || !target)
		return FALSE
	var/turf/a = get_turf(actor)
	var/turf/b = get_turf(target)
	return a && b && a.z == b.z && get_dist(a, b) <= tiles

/datum/pred_node/range/generate_reason()
	return negate ? "too close (within [tiles] tiles)" : "too far away (more than [tiles] tiles)"

/datum/pred_node/self/test(mob/actor, atom/target)
	return actor && actor == target

/datum/pred_node/self/generate_reason()
	return negate ? "can't be done to yourself" : "can only be done to yourself"

/datum/pred_node/in_hand/test(mob/actor, atom/target)
	if(!actor || !target)
		return FALSE
	return actor.get_active_hand() == target || actor.get_inactive_hand() == target

/datum/pred_node/in_hand/generate_reason()
	return negate ? "can't be done while holding it" : "must be held in hand"

// ---- Procs ----

/datum/pred_node/call_proc
	var/subject
	var/proc_path
	/// Reason when the proc returns FALSE rather than text.
	var/fallback

/datum/pred_node/call_proc/test(mob/actor, atom/target, obj/item/held)
	var/result = invoke(actor, target, held)
	return result == TRUE

/datum/pred_node/call_proc/proc/invoke(mob/actor, atom/target, obj/item/held)
	if(subject == PRED_GLOBAL)
		return call(proc_path)(actor, target, held)
	var/datum/thing = dq_pred_subject(subject, actor, target, held)
	if(!thing || !hascall(thing, dq_pred_proc_name(proc_path)))
		return FALSE
	return call(thing, proc_path)(actor, target, held)

/datum/pred_node/call_proc/generate_reason(mob/actor, atom/target, obj/item/held)
	if(!negate)
		var/result = invoke(actor, target, held)
		if(istext(result))
			return result
	return fallback || "not possible right now"

/// "/obj/machinery/proc/can_toggle_power" -> "can_toggle_power".
/proc/dq_pred_proc_name(proc_path)
	var/text = "[proc_path]"
	var/slash = findlasttext(text, "/")
	return slash ? copytext(text, slash + 1) : text

// ---- Actor capabilities ----

/// Whether this mob has a usable hand with nothing in it.
/mob/proc/dq_has_free_hand()
	return FALSE

/mob/living/carbon/human/dq_has_free_hand()
	return !get_equipped_item(SLOT_ID_L_HAND) || !get_equipped_item(SLOT_ID_R_HAND)

/mob/living/simple_mob/dq_has_free_hand()
	return has_hands && (!get_equipped_item(SLOT_ID_L_HAND) || !get_equipped_item(SLOT_ID_R_HAND))
